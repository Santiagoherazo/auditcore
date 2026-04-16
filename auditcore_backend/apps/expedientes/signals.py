"""
apps/expedientes/signals.py
AC-28: Auto-crear FaseExpediente y ChecklistEjecucion al crear un expediente.
AC-31: Registrar en BitacoraExpediente automáticamente en cambios de estado.
AC-40: Emitir evento dashboard_update al grupo WS cuando cambia un expediente.
"""
from django.db.models.signals import post_save, pre_save
from django.dispatch import receiver
import logging

logger = logging.getLogger(__name__)


def _invalidar_cache_expediente(expediente_id, usuario_id=None):
    """
    Invalida el cache de Redis para un expediente y sus participantes.
    Llamado desde señales post_save para mantener el contexto del chatbot fresco.
    """
    try:
        from workers.chat_context import invalidar_expediente, invalidar_expedientes_usuario
        invalidar_expediente(str(expediente_id))
        if usuario_id:
            invalidar_expedientes_usuario(str(usuario_id))
    except Exception as e:
        logger.warning('Cache invalidation failed: %s', e)


def _broadcast_dashboard():
    """
    Emite dashboard_update al grupo WebSocket para refrescar KPIs en tiempo real.
    Se llama via transaction.on_commit() para no causar 500 si Redis falla.

    FIX: en lugar de calcular y enviar los KPIs completos desde aquí
    (lo que enviaba clientes_activos a TODOS los suscriptores incluyendo
    AUDITOR_LIDER que no debería ver esa métrica), ahora enviamos solo
    una señal de 'refresh'. Cada cliente Flutter reacciona invalidando
    el dashboardProvider, que hace GET /api/dashboard/ con su propio
    token — y ese endpoint ya filtra los KPIs por rol correctamente.
    Esto elimina la inconsistencia entre los datos del WS y los del HTTP.
    """
    try:
        from channels.layers import get_channel_layer
        from asgiref.sync import async_to_sync

        channel_layer = get_channel_layer()
        if channel_layer is None:
            return

        async_to_sync(channel_layer.group_send)(
            'dashboard_global',
            # 'type': 'dashboard_update' dispara ChatbotConsumer.dashboard_update()
            # en el DashboardConsumer. 'data': {} vacío le indica al Flutter que
            # debe recargar los datos via HTTP (ref.invalidate(dashboardProvider)).
            {'type': 'dashboard_update', 'data': {}},
        )
    except Exception as e:
        logger.warning(f'No se pudo emitir dashboard_update: {e}')


@receiver(post_save, sender='expedientes.Expediente')
def crear_estructura_expediente(sender, instance, created, **kwargs):
    """
    AC-28: Al crear un expediente nuevo, auto-genera:
    - Una FaseExpediente por cada FaseTipoAuditoria del tipo seleccionado
    - Un ChecklistEjecucion por cada ChecklistItem de esas fases

    FIX: BitacoraExpediente_registrar y el broadcast se mueven a on_commit.
    Antes, cualquier fallo en la bitácora (ej: Redis/Channels no disponible)
    causaba un 500 DESPUÉS de que el expediente ya estaba guardado en DB,
    lo que hacía que Flutter mostrara error pero el objeto existía → duplicados
    al reintentar. Con on_commit, los efectos secundarios nunca bloquean la
    respuesta HTTP 201 al cliente.
    """
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

    # FIX: todos los efectos secundarios post-creación van en on_commit.
    # Si Redis/Channels/bitácora fallan, NO propagan el error al HTTP 201.
    try:
        from django.db import transaction as db_transaction
        _exp_id     = str(instance.pk)
        _uid        = str(instance.auditor_lider_id) if getattr(instance, 'auditor_lider_id', None) else None
        _fases_n    = fases_count
        _tipo_n     = tipo_nombre

        def _post_commit():
            BitacoraExpediente_registrar(
                expediente=instance,
                accion='EXPEDIENTE_CREADO',
                descripcion=(
                    f'Expediente creado. '
                    f'Se generaron {_fases_n} fases automáticamente '
                    f'según el tipo de auditoría "{_tipo_n}".'
                ),
            )
            _broadcast_dashboard()
            _invalidar_cache_expediente(_exp_id, _uid)

        db_transaction.on_commit(_post_commit)
    except Exception as e:
        logger.warning(f'No se pudo programar on_commit post-creación: {e}')


@receiver(pre_save, sender='expedientes.Expediente')
def capturar_estado_anterior(sender, instance, raw=False, update_fields=None, **kwargs):
    """Guarda el estado anterior para detectar cambios de estado.

    FIX: evitar la query extra cuando update_fields no incluye 'estado'.
    Antes se hacía Expediente.objects.get() en CADA save() incluyendo los de
    porcentaje_avance (disparados por cada item de checklist actualizado), generando
    una query N+1 por cada verificación de checklist. Con este guard solo se hace
    la query cuando el guardado realmente podría cambiar el estado.
    """
    if raw or not instance.pk:
        instance._estado_anterior = None
        return
    # Si update_fields está definido y 'estado' no está en él, el estado no cambió
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
    """AC-31: Registra en bitácora cada cambio de estado del expediente."""
    if created:
        return

    anterior = getattr(instance, '_estado_anterior', None)
    if anterior and anterior != instance.estado:
        BitacoraExpediente_registrar(
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


def BitacoraExpediente_registrar(expediente, accion, descripcion, usuario=None):
    """Helper para registrar en bitácora sin importar el modelo en circular."""
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
