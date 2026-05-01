from django.db.models.signals import post_save, pre_save
from django.dispatch import receiver
import logging

logger = logging.getLogger(__name__)


def _invalidar_cache_expediente(expediente_id, usuario_id=None):


    try:
        from workers.chat_context import invalidar_expediente, invalidar_expedientes_usuario
        invalidar_expediente(str(expediente_id))
        if usuario_id:
            invalidar_expedientes_usuario(str(usuario_id))
    except Exception as e:
        logger.warning('Cache invalidation failed: %s', e)


def _broadcast_dashboard():


    try:
        from channels.layers import get_channel_layer
        from asgiref.sync import async_to_sync

        channel_layer = get_channel_layer()
        if channel_layer is None:
            return

        async_to_sync(channel_layer.group_send)(
            'dashboard_global',


            {'type': 'dashboard_update', 'data': {}},
        )
    except Exception as e:
        logger.warning(f'No se pudo emitir dashboard_update: {e}')


@receiver(post_save, sender='expedientes.Expediente')
def crear_estructura_expediente(sender, instance, created, **kwargs):


    if not created:
        return

    from apps.expedientes.models import FaseExpediente
    from apps.ejecucion.models import ChecklistEjecucion
    from apps.tipos_auditoria.models import FaseTipoAuditoria, ChecklistItem

    fases_count = 0
    tipo_nombre = ''
    try:
        fases_tipo = list(FaseTipoAuditoria.objects.filter(
            tipo_auditoria=instance.tipo_auditoria
        ).order_by('orden'))

        for fase_tipo in fases_tipo:
            FaseExpediente.objects.create(
                expediente=instance,
                fase_tipo=fase_tipo,
                estado='PENDIENTE',
            )
            items = ChecklistItem.objects.filter(fase=fase_tipo)
            checklist_bulk = [
                ChecklistEjecucion(
                    expediente=instance,
                    item=item,
                    estado='PENDIENTE',
                )
                for item in items
            ]
            if checklist_bulk:
                ChecklistEjecucion.objects.bulk_create(checklist_bulk)

        fases_count = len(fases_tipo)
        tipo_nombre = instance.tipo_auditoria.nombre
        logger.info(
            f'Expediente {instance.numero_expediente}: '
            f'creadas {fases_count} fases con checklist automático'
        )

    except Exception as e:
        logger.error(f'Error creando estructura expediente {instance.id}: {e}')


    try:
        from django.db import transaction as db_transaction
        _exp_pk  = instance.pk
        _exp_id  = str(instance.pk)
        _uid     = str(instance.auditor_lider_id) if getattr(instance, 'auditor_lider_id', None) else None
        _fases_n = fases_count
        _tipo_n  = tipo_nombre

        def _post_commit():
            try:
                from apps.expedientes.models import Expediente as Exp
                exp_obj = Exp.objects.get(pk=_exp_pk)
                bitacora_expediente_registrar(
                    expediente=exp_obj,
                    accion='EXPEDIENTE_CREADO',
                    descripcion=(
                        f'Expediente creado. '
                        f'Se generaron {_fases_n} fases automáticamente '
                        f'según el tipo de auditoría "{_tipo_n}".'
                    ),
                )
            except Exception as e:
                logger.error('_post_commit bitácora: %s', e)
            _broadcast_dashboard()
            _invalidar_cache_expediente(_exp_id, _uid)

        db_transaction.on_commit(_post_commit)
    except Exception as e:
        logger.warning(f'No se pudo programar on_commit post-creación: {e}')


@receiver(pre_save, sender='expedientes.Expediente')
def capturar_estado_anterior(sender, instance, raw=False, update_fields=None, **kwargs):


    if raw or not instance.pk:
        instance._estado_anterior = None
        return

    if update_fields is not None and 'estado' not in update_fields:
        instance._estado_anterior = None
        return
    try:
        from apps.expedientes.models import Expediente
        anterior = Expediente.objects.only('estado').get(pk=instance.pk)
        instance._estado_anterior = anterior.estado
    except Exception:
        instance._estado_anterior = None


@receiver(post_save, sender='expedientes.Expediente')
def registrar_cambio_estado(sender, instance, created, **kwargs):

    if created:
        return

    anterior = getattr(instance, '_estado_anterior', None)
    if anterior and anterior != instance.estado:
        bitacora_expediente_registrar(
            expediente=instance,
            accion='CAMBIO_ESTADO',
            descripcion=(
                f'Estado cambiado de "{anterior}" a "{instance.estado}".'
            ),
        )
        try:
            from django.db import transaction as db_transaction
            db_transaction.on_commit(_broadcast_dashboard)
        except Exception as e:
            logger.warning(f'No se pudo programar broadcast_dashboard: {e}')


def bitacora_expediente_registrar(expediente, accion, descripcion, usuario=None):

    try:
        from apps.expedientes.models import BitacoraExpediente
        BitacoraExpediente.registrar(
            expediente=expediente,
            accion=accion,
            descripcion=descripcion,
            usuario=usuario,
        )
    except Exception as e:
        logger.error(f'Error registrando bitácora: {e}')
