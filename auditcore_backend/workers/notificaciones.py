from celery import shared_task
from django.conf import settings
from django.core.mail import send_mail
from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
import logging

logger = logging.getLogger(__name__)

try:
    from adapters.realtime.chatbot_logger import ids_log, IDS
except ImportError:
    def ids_log(*a, **kw): pass  # type: ignore[misc]
    class IDS:
        TASK='TASK'; ERROR='ERROR'; BOOT='BOOT'


@shared_task(
    queue='notificaciones',
    bind=True,
    max_retries=3,              # FIX: sin max_retries, un fallo SMTP reintentaba infinitamente
    default_retry_delay=60,     # 1 minuto entre reintentos
)
def notificar_hallazgo_critico_task(self, hallazgo_id):
    """Notifica al auditor líder cuando se registra un hallazgo CRÍTICO."""
    from apps.ejecucion.models import Hallazgo
    ids_log(IDS.TASK, msg='notificar_hallazgo_critico_start', hallazgo_id=str(hallazgo_id))
    try:
        hallazgo = Hallazgo.objects.select_related(
            'expediente__auditor_lider',
            'expediente__cliente',
        ).get(id=hallazgo_id)

        exp   = hallazgo.expediente
        lider = exp.auditor_lider

        if not lider or not lider.email:
            logger.warning('Hallazgo crítico %s sin auditor líder con email', hallazgo_id)
            return

        # FIX: fail_silently=False para poder capturar y reintentar con backoff
        # exponencial. Antes fail_silently=True silenciaba el fallo de SMTP y
        # la notificación se perdía sin registro ni reintento.
        try:
            send_mail(
                subject=f'🔴 [AuditCore] Hallazgo CRÍTICO — {exp.numero_expediente}',
                message=(
                    f'Se registró un hallazgo CRÍTICO en el expediente {exp.numero_expediente}.\n\n'
                    f'Cliente: {exp.cliente.razon_social}\n'
                    f'Hallazgo: {hallazgo.titulo}\n'
                    f'Descripción: {hallazgo.descripcion[:300]}\n\n'
                    f'Accede al sistema para revisar y tomar acción inmediata.'
                ),
                from_email=settings.DEFAULT_FROM_EMAIL,
                recipient_list=[lider.email],
                fail_silently=False,
            )
        except Exception as mail_exc:
            logger.error('Error enviando email hallazgo crítico %s: %s', hallazgo_id, mail_exc)
            # FIX: countdown exponencial para no saturar el servidor SMTP.
            # Sin countdown, el reintento era inmediato, generando ráfagas de
            # conexiones SMTP que podían resultar en rate-limiting o bloqueo.
            countdown = 60 * (2 ** self.request.retries)  # 60s, 120s, 240s
            raise self.retry(exc=mail_exc, countdown=countdown)

        _push_notificacion(
            user_id=str(lider.id),
            tipo='CRITICO',
            titulo=f'Hallazgo CRÍTICO — {exp.numero_expediente}',
            mensaje=hallazgo.titulo,
        )

        from apps.expedientes.models import BitacoraExpediente
        BitacoraExpediente.registrar(
            expediente=exp,
            accion='HALLAZGO_CRITICO',
            descripcion=f'Hallazgo crítico registrado: {hallazgo.titulo}',
        )
        ids_log(IDS.TASK, msg='notificar_hallazgo_critico_ok',
                hallazgo_id=str(hallazgo_id), email=lider.email)
        logger.info('Notificación hallazgo crítico enviada a %s', lider.email)

    except Exception as e:
        logger.error('Error notificando hallazgo crítico %s: %s', hallazgo_id, e)
        raise


@shared_task(queue='notificaciones')
def alertas_vencimiento_certificaciones():
    """
    Ejecuta diariamente via Celery Beat.
    Envía emails a 90, 60 y 30 días antes del vencimiento.
    """
    from apps.certificaciones.models import Certificacion
    from django.utils import timezone
    from datetime import timedelta

    hoy         = timezone.now().date()
    DIAS_ALERTA = [90, 60, 30]

    for dias in DIAS_ALERTA:
        fecha_objetivo = hoy + timedelta(days=dias)
        certs = Certificacion.objects.filter(
            fecha_vencimiento=fecha_objetivo,
            estado__in=['VIGENTE', 'POR_VENCER'],
        ).select_related('expediente__cliente', 'expediente__ejecutivo', 'expediente__tipo_auditoria')

        for cert in certs:
            _enviar_alerta_vencimiento(cert, dias)

    logger.info('Alertas de vencimiento procesadas para %s', hoy)


def _enviar_alerta_vencimiento(cert, dias_restantes):
    exp     = cert.expediente
    cliente = exp.cliente

    destinatarios = []
    contacto = cliente.contactos.filter(es_principal=True).first()
    if contacto and contacto.email:
        destinatarios.append(contacto.email)
    if exp.ejecutivo and exp.ejecutivo.email:
        destinatarios.append(exp.ejecutivo.email)
    if dias_restantes <= 30:
        from apps.administracion.models import UsuarioInterno
        admins = list(
            UsuarioInterno.objects.filter(rol='SUPERVISOR', estado='ACTIVO')
            .values_list('email', flat=True)
        )
        destinatarios.extend(admins)

    destinatarios = list(set(d for d in destinatarios if d))
    if not destinatarios:
        logger.warning('Alerta vencimiento %s: sin destinatarios', cert.numero)
        return

    urgencia = '🔴' if dias_restantes <= 30 else '🟠' if dias_restantes <= 60 else '🟡'
    send_mail(
        subject=f'{urgencia} [AuditCore] Certificación vence en {dias_restantes} días — {cert.numero}',
        message=(
            f'La certificación {cert.numero} del cliente {cliente.razon_social} '
            f'vence el {cert.fecha_vencimiento} ({dias_restantes} días restantes).\n\n'
            f'Expediente: {exp.numero_expediente}\n'
            f'Tipo: {exp.tipo_auditoria.nombre}\n\n'
            f'Inicia el proceso de renovación para mantener la certificación vigente.'
        ),
        from_email=settings.DEFAULT_FROM_EMAIL,
        recipient_list=destinatarios,
        fail_silently=True,
    )
    logger.info('Alerta vencimiento %sd enviada: %s', dias_restantes, cert.numero)


@shared_task(queue='notificaciones')
def verificar_estados_certificaciones():
    """
    Celery Beat diario a medianoche.
    Actualiza VIGENTE → POR_VENCER → VENCIDA según fecha.
    """
    from apps.certificaciones.models import Certificacion
    from django.utils import timezone
    from datetime import timedelta

    hoy         = timezone.now().date()
    actualizadas = 0

    count = Certificacion.objects.filter(
        fecha_vencimiento__lt=hoy,
        estado__in=['VIGENTE', 'POR_VENCER'],
    ).update(estado='VENCIDA')
    actualizadas += count

    limite = hoy + timedelta(days=30)
    count = Certificacion.objects.filter(
        fecha_vencimiento__lte=limite,
        fecha_vencimiento__gte=hoy,
        estado='VIGENTE',
    ).update(estado='POR_VENCER')
    actualizadas += count

    logger.info('Estados certificaciones actualizados: %d registros', actualizadas)
    return actualizadas


def _push_notificacion(user_id, tipo, titulo, mensaje):
    """Envía notificación en tiempo real al canal personal del usuario."""
    try:
        channel_layer = get_channel_layer()
        async_to_sync(channel_layer.group_send)(
            f'notificaciones_{user_id}',
            {
                'type':    'notificacion',
                'tipo':    tipo,
                'titulo':  titulo,
                'mensaje': mensaje,
            },
        )
    except Exception as e:
        logger.error('Error push WS notificación: %s', e)
