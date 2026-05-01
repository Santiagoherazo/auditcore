import json
import uuid
import logging
from typing import Optional

from django.core.cache import cache
from django.db import transaction

logger = logging.getLogger(__name__)


DRAFT_TTL_SECONDS = 86_400
DRAFT_KEY_PREFIX  = 'cliente_draft'
USER_DRAFTS_PREFIX = 'cliente_draft_user'


CONTACTO_FIELDS = {
    'contacto_tipo', 'contacto_nombre', 'contacto_apellido', 'contacto_cargo',
    'contacto_email', 'contacto_telefono', 'contacto_departamento',
}


def _draft_key(draft_id: str) -> str:
    return f'{DRAFT_KEY_PREFIX}:{draft_id}'


def _user_set_key(user_id) -> str:
    return f'{USER_DRAFTS_PREFIX}:{user_id}'


def create_draft(user_id, initial_data: dict) -> str:


    draft_id = str(uuid.uuid4())
    draft = {
        'draft_id': draft_id,
        'user_id':  str(user_id),
        'data':     initial_data,
    }
    cache.set(_draft_key(draft_id), json.dumps(draft), timeout=DRAFT_TTL_SECONDS)


    user_key = _user_set_key(user_id)
    existing = cache.get(user_key)
    draft_ids = json.loads(existing) if existing else []
    draft_ids.append(draft_id)
    cache.set(user_key, json.dumps(draft_ids), timeout=DRAFT_TTL_SECONDS)

    logger.info('Draft creado: %s por usuario %s', draft_id, user_id)
    return draft_id


def get_draft(draft_id: str, user_id=None) -> Optional[dict]:


    raw = cache.get(_draft_key(draft_id))
    if not raw:
        return None
    draft = json.loads(raw)
    if user_id and str(draft.get('user_id')) != str(user_id):
        logger.warning('Acceso denegado al draft %s por usuario %s', draft_id, user_id)
        return None
    return draft


def update_draft(draft_id: str, user_id, partial_data: dict) -> Optional[dict]:


    draft = get_draft(draft_id, user_id)
    if draft is None:
        return None

    draft['data'].update(partial_data)
    cache.set(_draft_key(draft_id), json.dumps(draft), timeout=DRAFT_TTL_SECONDS)
    logger.debug('Draft actualizado: %s', draft_id)
    return draft


def delete_draft(draft_id: str, user_id=None) -> bool:


    if not get_draft(draft_id, user_id):
        return False
    cache.delete(_draft_key(draft_id))
    logger.info('Draft eliminado: %s', draft_id)
    return True


_STR_BLANK_FIELDS = [
    'digito_verificacion', 'matricula_mercantil', 'objeto_social',
    'codigo_ciiu', 'regimen_tributario', 'rep_legal_nombre',
    'rep_legal_documento', 'rep_legal_tipo_doc', 'rep_legal_cargo',
    'rep_legal_email', 'rep_legal_telefono', 'pais', 'departamento',
    'ciudad', 'direccion_principal', 'codigo_postal', 'telefono',
    'telefono_alt', 'email', 'sitio_web', 'linkedin', 'subsector',
    'ingresos_anuales', 'alcance_descripcion', 'declaracion_necesidad',
    'certificacion_previa_detalle', 'motivo_auditoria', 'urgencia',
    'tamano', 'notas', 'duracion_empresa',
]

_CAMPOS_EXCLUIDOS = {'creado_por', 'asesor_responsable'}


def _normalizar_data(data: dict) -> None:

    for field in _STR_BLANK_FIELDS:
        if field not in data or data[field] is None:
            data[field] = ''
    for jfield in ('normas_interes', 'tipos_auditoria_solicitados', 'sedes_adicionales'):
        if jfield not in data:
            data[jfield] = []
    data.setdefault('responsable_iva', True)
    data.setdefault('tiene_certificacion_previa', False)
    if 'num_empleados' in data and data['num_empleados'] == '':
        data['num_empleados'] = None
    for dfield in ('fecha_constitucion', 'fecha_limite_deseada'):
        if data.get(dfield) == '':
            data[dfield] = None


def _limpiar_data_para_cliente(data: dict, cliente_model) -> dict:

    cliente_field_names = (
        {f.name for f in cliente_model._meta.concrete_fields}
        | {f.name for f in cliente_model._meta.many_to_many}
    )
    return {
        k: v for k, v in data.items()
        if k in cliente_field_names and k not in _CAMPOS_EXCLUIDOS
    }


def commit_draft(draft_id: str, user_id) -> dict:


    from apps.clientes.models import Cliente, ContactoCliente

    draft = get_draft(draft_id, user_id)
    if draft is None:
        raise ValueError(f'Draft {draft_id} no encontrado o acceso denegado.')

    data = draft['data'].copy()
    warnings = []


    contacto_data = {}
    for field in tuple(data):
        if field in CONTACTO_FIELDS:
            contacto_data[field] = data.pop(field)

    with transaction.atomic():

        _normalizar_data(data)
        data_clean = _limpiar_data_para_cliente(data, Cliente)

        from django.contrib.auth import get_user_model
        user_model = get_user_model()
        try:
            creado_por = user_model.objects.get(pk=user_id)
        except user_model.DoesNotExist:
            creado_por = None

        cliente = Cliente.objects.create(creado_por=creado_por, **data_clean)
        logger.info('Cliente creado desde draft %s → id=%s', draft_id, cliente.pk)


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


    delete_draft(draft_id, user_id)

    return {
        'cliente':  cliente,
        'contacto': contacto,
        'warnings': warnings,
    }
