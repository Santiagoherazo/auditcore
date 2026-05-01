import json
import logging

logger = logging.getLogger(__name__)


_TTL_EXPEDIENTE  = 300
_TTL_USER_EXPS   = 180
_TTL_GLOBAL      = 600
_TTL_CERTS       = 900


def _cache():

    try:
        from django.core.cache import cache
        return cache
    except Exception:
        return None


def get_contexto_expediente(expediente_id: str) -> dict | None:


    key = f'auditcore:ctx:exp:{expediente_id}'
    c   = _cache()

    if c:
        cached = c.get(key)
        if cached:
            try:
                return json.loads(cached)
            except (json.JSONDecodeError, TypeError):
                pass


    ctx = _build_contexto_expediente(expediente_id)
    if ctx and c:
        try:
            c.set(key, json.dumps(ctx, default=str), timeout=_TTL_EXPEDIENTE)
        except Exception as e:
            logger.warning('Redis set exp context failed: %s', e)
    return ctx


def invalidar_expediente(expediente_id: str) -> None:

    key = f'auditcore:ctx:exp:{expediente_id}'
    c   = _cache()
    if c:
        try:
            c.delete(key)
        except Exception as e:
            logger.warning('Redis delete exp context failed: %s', e)


def _build_contexto_expediente(expediente_id: str) -> dict | None:

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


def get_expedientes_usuario(usuario_id: str, rol: str) -> list[dict]:


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
        from django.db.models import Q
        qs = Expediente.objects.select_related('cliente', 'tipo_auditoria')

        if rol == 'SUPERVISOR':

            qs = qs.filter(estado__in=['ACTIVO', 'EN_EJECUCION'])
        elif rol == 'AUDITOR':

            qs = qs.filter(
                Q(auditor_lider_id=usuario_id) |
                Q(equipo__usuario_id=usuario_id, equipo__activo=True),
                estado__in=['ACTIVO', 'EN_EJECUCION'],
            ).distinct()
        elif rol == 'ASESOR':
            qs = qs.filter(
                ejecutivo_id=usuario_id,
                estado__in=['ACTIVO', 'EN_EJECUCION'],
            )
        elif rol in ('AUXILIAR', 'REVISOR'):

            qs = qs.filter(
                equipo__usuario_id=usuario_id,
                equipo__activo=True,
                estado__in=['ACTIVO', 'EN_EJECUCION'],
            ).distinct()
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
