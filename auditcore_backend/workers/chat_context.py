"""
workers/chat_context.py — Caché de contexto del chatbot en Redis.

PROBLEMA ORIGINAL:
  _construir_sistema() en workers/chatbot.py hacía 6 queries directas a
  Postgres por cada mensaje: hallazgos críticos, mayores, documentos pendientes,
  fases completadas, total de fases, datos del cliente. En cargas altas esto
  acumulaba decenas de queries por minuto innecesarias.

SOLUCIÓN — sistema híbrido Postgres + Redis:
  - Redis almacena snapshots JSON de los datos clave con TTL de 5 minutos.
  - Las señales de Django (post_save en Expediente, Hallazgo, etc.) invalidan
    el cache inmediatamente cuando hay cambios reales.
  - El chatbot lee de Redis en O(1) en lugar de N queries a Postgres.
  - Si Redis falla, cae silenciosamente a Postgres (modo degradado sin crash).

Flujo de datos:
  Postgres (fuente de verdad)
      ↓ señales Django (post_save)
  Redis (cache, TTL 5min)          ← chatbot worker lee de aquí
      ↓ miss o TTL expirado
  Postgres (fallback)

Claves Redis (prefijo auditcore:ctx:):
  auditcore:ctx:exp:<id>           → contexto de un expediente específico
  auditcore:ctx:user:<id>:exps     → expedientes activos de un usuario
  auditcore:ctx:global:stats       → KPIs globales para ADMIN
  auditcore:ctx:certs:por_vencer   → certificaciones que vencen en ≤30 días
"""
import json
import logging

logger = logging.getLogger(__name__)

# TTL en segundos para cada tipo de dato
_TTL_EXPEDIENTE  = 300   # 5 min — se invalida por señal en cambios reales
_TTL_USER_EXPS   = 180   # 3 min — lista de expedientes del usuario
_TTL_GLOBAL      = 600   # 10 min — stats globales (menos volátiles)
_TTL_CERTS       = 900   # 15 min — certificaciones por vencer


def _cache():
    """Devuelve el cliente de cache de Django. Nunca lanza excepción."""
    try:
        from django.core.cache import cache
        return cache
    except Exception:
        return None


# ── Expediente ─────────────────────────────────────────────────────────────────

def get_contexto_expediente(expediente_id: str) -> dict | None:
    """
    Devuelve el contexto de un expediente desde Redis.
    Si no está en cache, lo construye desde Postgres y lo guarda.
    Devuelve None si el expediente no existe.
    """
    key = f'auditcore:ctx:exp:{expediente_id}'
    c   = _cache()

    if c:
        cached = c.get(key)
        if cached:
            try:
                return json.loads(cached)
            except (json.JSONDecodeError, TypeError):
                pass

    # Cache miss — construir desde Postgres
    ctx = _build_contexto_expediente(expediente_id)
    if ctx and c:
        try:
            c.set(key, json.dumps(ctx, default=str), timeout=_TTL_EXPEDIENTE)
        except Exception as e:
            logger.warning('Redis set exp context failed: %s', e)
    return ctx


def invalidar_expediente(expediente_id: str) -> None:
    """Invalida el cache de un expediente (llamado desde señales Django)."""
    key = f'auditcore:ctx:exp:{expediente_id}'
    c   = _cache()
    if c:
        try:
            c.delete(key)
        except Exception as e:
            logger.warning('Redis delete exp context failed: %s', e)


def _build_contexto_expediente(expediente_id: str) -> dict | None:
    """Construye el contexto desde Postgres. Todas las queries en una sola función."""
    try:
        from apps.expedientes.models import Expediente
        exp = Expediente.objects.select_related(
            'cliente', 'tipo_auditoria', 'auditor_lider'
        ).get(id=expediente_id)

        criticos  = exp.hallazgos.filter(nivel_criticidad='CRITICO', estado='ABIERTO').count()
        mayores   = exp.hallazgos.filter(nivel_criticidad='MAYOR',   estado='ABIERTO').count()
        menores   = exp.hallazgos.filter(nivel_criticidad='MENOR',   estado='ABIERTO').count()
        docs_pend = exp.documentos.filter(estado='PENDIENTE').count()
        fases_ok  = exp.fases.filter(estado='COMPLETADA').count()
        fases_tot = exp.fases.count()

        return {
            'id':                str(exp.id),
            'numero':            exp.numero_expediente,
            'cliente':           exp.cliente.razon_social,
            'nit':               exp.cliente.nit,
            'tipo':              exp.tipo_auditoria.nombre,
            'estado':            exp.get_estado_display(),
            'avance':            float(exp.porcentaje_avance),
            'fases_completadas': fases_ok,
            'fases_total':       fases_tot,
            'hallazgos_criticos':criticos,
            'hallazgos_mayores': mayores,
            'hallazgos_menores': menores,
            'docs_pendientes':   docs_pend,
            'auditor_lider':     exp.auditor_lider.nombre_completo if exp.auditor_lider else None,
        }
    except Exception as e:
        logger.warning('_build_contexto_expediente %s: %s', expediente_id, e)
        return None


# ── Expedientes activos de un usuario ─────────────────────────────────────────

def get_expedientes_usuario(usuario_id: str, rol: str) -> list[dict]:
    """
    Expedientes activos visibles para un usuario según su rol.
    Cached en Redis por usuario_id.
    """
    key = f'auditcore:ctx:user:{usuario_id}:exps'
    c   = _cache()

    if c:
        cached = c.get(key)
        if cached:
            try:
                return json.loads(cached)
            except (json.JSONDecodeError, TypeError):
                pass

    data = _build_expedientes_usuario(usuario_id, rol)
    if c:
        try:
            c.set(key, json.dumps(data, default=str), timeout=_TTL_USER_EXPS)
        except Exception as e:
            logger.warning('Redis set user exps failed: %s', e)
    return data


def invalidar_expedientes_usuario(usuario_id: str) -> None:
    key = f'auditcore:ctx:user:{usuario_id}:exps'
    c   = _cache()
    if c:
        try:
            c.delete(key)
        except Exception as e:
            logger.warning('Redis delete user exps failed: %s', e)


def _build_expedientes_usuario(usuario_id: str, rol: str) -> list[dict]:
    try:
        from apps.expedientes.models import Expediente
        qs = Expediente.objects.select_related('cliente', 'tipo_auditoria')

        if rol == 'SUPERVISOR':
            qs = qs.filter(estado__in=['ACTIVO', 'EN_EJECUCION'])
        elif rol in ('SUPERVISOR', 'AUDITOR'):
            qs = qs.filter(auditor_lider_id=usuario_id,
                           estado__in=['ACTIVO', 'EN_EJECUCION'])
        elif rol == 'AUDITOR':
            qs = qs.filter(equipo__usuario_id=usuario_id,
                           estado__in=['ACTIVO', 'EN_EJECUCION']).distinct()
        elif rol == 'ASESOR':
            qs = qs.filter(ejecutivo_id=usuario_id,
                           estado__in=['ACTIVO', 'EN_EJECUCION'])
        else:
            return []

        return [
            {
                'id':      str(e.id),
                'numero':  e.numero_expediente,
                'cliente': e.cliente.razon_social,
                'tipo':    e.tipo_auditoria.nombre,
                'estado':  e.get_estado_display(),
                'avance':  float(e.porcentaje_avance),
            }
            for e in qs.order_by('-fecha_creacion')[:10]
        ]
    except Exception as e:
        logger.warning('_build_expedientes_usuario %s: %s', usuario_id, e)
        return []


# ── Stats globales (ADMIN) ────────────────────────────────────────────────────

def get_stats_globales() -> dict:
    key = 'auditcore:ctx:global:stats'
    c   = _cache()

    if c:
        cached = c.get(key)
        if cached:
            try:
                return json.loads(cached)
            except (json.JSONDecodeError, TypeError):
                pass

    data = _build_stats_globales()
    if c:
        try:
            c.set(key, json.dumps(data, default=str), timeout=_TTL_GLOBAL)
        except Exception as e:
            logger.warning('Redis set global stats failed: %s', e)
    return data


def _build_stats_globales() -> dict:
    try:
        from apps.expedientes.models import Expediente
        from apps.ejecucion.models   import Hallazgo
        from apps.clientes.models    import Cliente
        from django.db.models        import Count

        exps_activos  = Expediente.objects.filter(
            estado__in=['ACTIVO', 'EN_EJECUCION']).count()
        hallazgos_crit = Hallazgo.objects.filter(
            nivel_criticidad='CRITICO', estado='ABIERTO').count()
        clientes_act  = Cliente.objects.filter(estado='ACTIVO').count()

        return {
            'expedientes_activos':   exps_activos,
            'hallazgos_criticos':    hallazgos_crit,
            'clientes_activos':      clientes_act,
        }
    except Exception as e:
        logger.warning('_build_stats_globales: %s', e)
        return {}


# ── Certificaciones por vencer ────────────────────────────────────────────────

def get_certs_por_vencer(usuario_id: str | None = None) -> list[dict]:
    key = f'auditcore:ctx:certs:por_vencer:{usuario_id or "all"}'
    c   = _cache()

    if c:
        cached = c.get(key)
        if cached:
            try:
                return json.loads(cached)
            except (json.JSONDecodeError, TypeError):
                pass

    data = _build_certs_por_vencer(usuario_id)
    if c:
        try:
            c.set(key, json.dumps(data, default=str), timeout=_TTL_CERTS)
        except Exception as e:
            logger.warning('Redis set certs failed: %s', e)
    return data


def _build_certs_por_vencer(usuario_id: str | None) -> list[dict]:
    try:
        from apps.certificaciones.models import Certificacion
        from django.utils import timezone
        from datetime import timedelta

        hoy    = timezone.now().date()
        limite = hoy + timedelta(days=30)

        qs = Certificacion.objects.select_related(
            'expediente__cliente', 'expediente__tipo_auditoria'
        ).filter(
            fecha_vencimiento__lte=limite,
            fecha_vencimiento__gte=hoy,
            estado__in=['VIGENTE', 'POR_VENCER'],
        )
        if usuario_id:
            qs = qs.filter(expediente__ejecutivo_id=usuario_id)

        return [
            {
                'numero':          c.numero,
                'cliente':         c.expediente.cliente.razon_social,
                'tipo':            c.expediente.tipo_auditoria.nombre,
                'vence':           c.fecha_vencimiento.isoformat(),
                'dias_restantes':  (c.fecha_vencimiento - hoy).days,
            }
            for c in qs.order_by('fecha_vencimiento')[:5]
        ]
    except Exception as e:
        logger.warning('_build_certs_por_vencer: %s', e)
        return []
