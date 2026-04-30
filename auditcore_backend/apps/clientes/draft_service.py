"""
apps/clientes/draft_service.py
===============================
Servicio de borrador (draft) para el formulario multi-paso de creación de clientes.

Flujo
-----
  Paso 1 → POST  /api/clientes/draft/           → crea draft en Redis, devuelve draft_id (UUID)
  Paso 2 → PATCH /api/clientes/draft/{id}/      → actualiza draft en Redis
  ...
  Paso 6 → PATCH /api/clientes/draft/{id}/      → último parcial (contacto operativo incluido)
           POST  /api/clientes/draft/{id}/commit/ → persiste en PostgreSQL y borra el draft

¿Por qué Redis?
---------------
El formulario tiene 6 pasos. Cada "Siguiente" antes enviaba un POST/PATCH real a PostgreSQL,
lo que causaba IntegrityError porque la columna `direccion` (de la migración 0001 huérfana)
era NOT NULL y el Paso 1 no la incluía. Ahora, ningún paso escribe en Postgres hasta que
el usuario confirma el formulario completo. Redis actúa como buffer transaccional con TTL.

Claves Redis
------------
  cliente_draft:{draft_id}        → dict JSON con los datos acumulados
  cliente_draft_user:{user_id}    → set de draft_ids activos del usuario (para limpieza)

TTL
---
  DRAFT_TTL_SECONDS = 86400 (24 horas) — el draft expira si el usuario abandona el formulario.
"""
import json
import uuid
import logging
from typing import Optional

from django.core.cache import cache
from django.db import transaction

logger = logging.getLogger(__name__)

# ── Constantes ────────────────────────────────────────────────────────────────
DRAFT_TTL_SECONDS = 86_400          # 24 horas
DRAFT_KEY_PREFIX  = 'cliente_draft'
USER_DRAFTS_PREFIX = 'cliente_draft_user'

# Campos que al hacer commit crean objetos relacionados (no van en Cliente directamente)
CONTACTO_FIELDS = {
    'contacto_tipo', 'contacto_nombre', 'contacto_apellido', 'contacto_cargo',
    'contacto_email', 'contacto_telefono', 'contacto_departamento',
}


def _draft_key(draft_id: str) -> str:
    return f'{DRAFT_KEY_PREFIX}:{draft_id}'


def _user_set_key(user_id) -> str:
    return f'{USER_DRAFTS_PREFIX}:{user_id}'


# ── Operaciones de draft ──────────────────────────────────────────────────────

def create_draft(user_id, initial_data: dict) -> str:
    """
    Crea un nuevo draft en Redis con los datos del Paso 1.
    Retorna el draft_id (UUID string).
    """
    draft_id = str(uuid.uuid4())
    draft = {
        'draft_id': draft_id,
        'user_id':  str(user_id),
        'data':     initial_data,
    }
    cache.set(_draft_key(draft_id), json.dumps(draft), timeout=DRAFT_TTL_SECONDS)

    # Registrar el draft en el set del usuario (para poder listar/limpiar)
    user_key = _user_set_key(user_id)
    existing = cache.get(user_key)
    draft_ids = json.loads(existing) if existing else []
    draft_ids.append(draft_id)
    cache.set(user_key, json.dumps(draft_ids), timeout=DRAFT_TTL_SECONDS)

    logger.info('Draft creado: %s por usuario %s', draft_id, user_id)
    return draft_id


def get_draft(draft_id: str, user_id=None) -> Optional[dict]:
    """
    Recupera el draft. Retorna None si no existe o si el user_id no coincide.
    """
    raw = cache.get(_draft_key(draft_id))
    if not raw:
        return None
    draft = json.loads(raw)
    if user_id and str(draft.get('user_id')) != str(user_id):
        logger.warning('Acceso denegado al draft %s por usuario %s', draft_id, user_id)
        return None
    return draft


def update_draft(draft_id: str, user_id, partial_data: dict) -> Optional[dict]:
    """
    Hace un merge del partial_data sobre los datos existentes del draft.
    Renueva el TTL. Retorna el draft actualizado o None si no existe / acceso denegado.
    """
    draft = get_draft(draft_id, user_id)
    if draft is None:
        return None

    draft['data'].update(partial_data)
    cache.set(_draft_key(draft_id), json.dumps(draft), timeout=DRAFT_TTL_SECONDS)
    logger.debug('Draft actualizado: %s', draft_id)
    return draft


def delete_draft(draft_id: str, user_id=None) -> bool:
    """
    Elimina el draft de Redis. Retorna True si existía.
    """
    if not get_draft(draft_id, user_id):
        return False
    cache.delete(_draft_key(draft_id))
    logger.info('Draft eliminado: %s', draft_id)
    return True


# ── Commit a PostgreSQL ───────────────────────────────────────────────────────

def commit_draft(draft_id: str, user_id) -> dict:
    """
    Persiste el draft en PostgreSQL dentro de una transacción atómica.
    Elimina el draft de Redis si el commit es exitoso.

    Retorna un dict con:
      - 'cliente': instancia del Cliente creado
      - 'contacto': instancia del ContactoCliente (o None)
      - 'warnings': lista de advertencias no fatales

    Lanza ValueError si el draft no existe o no pertenece al usuario.
    Lanza cualquier excepción de Django/DRF en caso de error de validación o BD.
    """
    from apps.clientes.models import Cliente, ContactoCliente

    draft = get_draft(draft_id, user_id)
    if draft is None:
        raise ValueError(f'Draft {draft_id} no encontrado o acceso denegado.')

    data = draft['data'].copy()
    warnings = []

    # ── Separar campos de contacto operativo ─────────────────────────────────
    contacto_data = {}
    for field in list(data.keys()):
        if field in CONTACTO_FIELDS:
            contacto_data[field] = data.pop(field)

    with transaction.atomic():
        # ── Crear el Cliente ──────────────────────────────────────────────────
        # Campos que podrían llegar vacíos desde el formulario y que el modelo
        # acepta como blank pero PostgreSQL espera cadena vacía (no None).
        str_blank_fields = [
            'digito_verificacion', 'matricula_mercantil', 'objeto_social',
            'codigo_ciiu', 'regimen_tributario', 'rep_legal_nombre',
            'rep_legal_documento', 'rep_legal_tipo_doc', 'rep_legal_cargo',
            'rep_legal_email', 'rep_legal_telefono', 'pais', 'departamento',
            'ciudad', 'direccion_principal', 'codigo_postal', 'telefono',
            'telefono_alt', 'email', 'sitio_web', 'linkedin', 'subsector',
            'ingresos_anuales', 'alcance_descripcion', 'declaracion_necesidad',
            'certificacion_previa_detalle', 'motivo_auditoria', 'urgencia',
            'tamano', 'notas',
        ]
        for field in str_blank_fields:
            if field not in data:
                data[field] = ''

        # Campos JSON con default de lista
        for jfield in ('normas_interes', 'tipos_auditoria_solicitados', 'sedes_adicionales'):
            if jfield not in data:
                data[jfield] = []

        # Campos booleanos
        data.setdefault('responsable_iva', True)
        data.setdefault('tiene_certificacion_previa', False)

        # Campos numéricos
        if 'num_empleados' in data and data['num_empleados'] == '':
            data['num_empleados'] = None

        # Campos de fecha
        for dfield in ('fecha_constitucion', 'fecha_limite_deseada'):
            if data.get(dfield) == '':
                data[dfield] = None

        # Eliminar campos que no pertenecen al modelo Cliente
        cliente_field_names = {f.name for f in Cliente._meta.get_fields()}
        data_clean = {k: v for k, v in data.items() if k in cliente_field_names}

        from django.contrib.auth import get_user_model
        User = get_user_model()
        try:
            creado_por = User.objects.get(pk=user_id)
        except User.DoesNotExist:
            creado_por = None

        cliente = Cliente.objects.create(creado_por=creado_por, **data_clean)
        logger.info('Cliente creado desde draft %s → id=%s', draft_id, cliente.pk)

        # ── Crear ContactoCliente (si hay datos) ──────────────────────────────
        contacto = None
        nombre   = contacto_data.get('contacto_nombre', '').strip()
        email_c  = contacto_data.get('contacto_email', '').strip()

        if nombre and email_c:
            try:
                contacto = ContactoCliente.objects.create(
                    cliente    = cliente,
                    tipo       = contacto_data.get('contacto_tipo', 'OPERATIVO'),
                    nombre     = nombre,
                    apellido   = contacto_data.get('contacto_apellido', ''),
                    cargo      = contacto_data.get('contacto_cargo', ''),
                    departamento = contacto_data.get('contacto_departamento', ''),
                    email      = email_c,
                    telefono   = contacto_data.get('contacto_telefono', ''),
                    es_principal          = True,
                    recibe_informes       = True,
                    recibe_notificaciones = True,
                )
                logger.info('ContactoCliente creado para cliente %s', cliente.pk)
            except Exception as exc:
                warnings.append(f'Contacto operativo no guardado: {exc}')
                logger.warning('Error creando ContactoCliente: %s', exc)
        else:
            warnings.append('Contacto operativo omitido (nombre o email vacíos).')

    # ── Limpiar draft de Redis (fuera de la transacción atómica) ─────────────
    delete_draft(draft_id, user_id)

    return {
        'cliente':  cliente,
        'contacto': contacto,
        'warnings': warnings,
    }
