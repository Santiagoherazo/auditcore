from django.db.models.signals import post_save
from django.dispatch import receiver
import logging

logger = logging.getLogger(__name__)

def _invalidar_ctx_expediente(expediente_id):
    try:
        from workers.chat_context import invalidar_expediente
        invalidar_expediente(str(expediente_id))
    except Exception as e:
        logger.warning('Cache invalidation hallazgo: %s', e)


try:
    from kombu.exceptions import OperationalError as KombuOperationalError
except ImportError:
    KombuOperationalError = OSError

_BROKER_ERRORS = (KombuOperationalError, OSError, ConnectionError, TimeoutError)


@receiver(post_save, sender='ejecucion.Hallazgo')
def notificar_hallazgo_critico(sender, instance, created, **kwargs):


    if instance.expediente_id:
        try:
            from django.db import transaction as db_transaction
            _eid = str(instance.expediente_id)
            db_transaction.on_commit(lambda eid=_eid: _invalidar_ctx_expediente(eid))
        except Exception as e:
            logger.warning('on_commit hallazgo cache invalidation: %s', e)

    if not created:
        return
    if instance.nivel_criticidad != 'CRITICO':
        return

    from workers.notificaciones import notificar_hallazgo_critico_task
    try:
        notificar_hallazgo_critico_task.delay(str(instance.id))
        logger.info('Hallazgo crítico %s encolado para notificación', instance.id)
    except _BROKER_ERRORS as e:


        logger.warning(
            'Broker no disponible al notificar hallazgo crítico %s (intento 1): %s — reintentando en 30s',
            instance.id, e,
        )
        try:
            notificar_hallazgo_critico_task.apply_async(
                args=[str(instance.id)],
                countdown=30,
            )
        except Exception as e2:
            logger.error(
                'Broker definitivamente no disponible para hallazgo crítico %s: %s',
                instance.id, e2,
            )


@receiver(post_save, sender='ejecucion.ChecklistEjecucion')
def actualizar_avance_expediente(sender, instance, **kwargs):


    try:
        instance.expediente.calcular_avance()
    except Exception as e:
        logger.error(f'Error recalculando avance expediente: {e}')