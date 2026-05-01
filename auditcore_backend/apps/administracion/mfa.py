import pyotp
import qrcode
import io
import base64
from django.utils import timezone
from datetime import timedelta


MAX_INTENTOS = 5
BLOQUEO_MINUTOS = 30


def generar_secret_totp():

    return pyotp.random_base32()


def generar_qr_totp(usuario):


    totp = pyotp.TOTP(usuario.mfa_secret)
    uri = totp.provisioning_uri(
        name=usuario.email,
        issuer_name='AuditCore',
    )
    qr = qrcode.QRCode(version=1, box_size=6, border=2)
    qr.add_data(uri)
    qr.make(fit=True)
    img = qr.make_image(fill_color='black', back_color='white')
    buffer = io.BytesIO()
    img.save(buffer, format='PNG')
    return base64.b64encode(buffer.getvalue()).decode()


def verificar_totp(usuario, codigo):


    if not usuario.mfa_secret:
        return False
    totp = pyotp.TOTP(usuario.mfa_secret)
    return totp.verify(codigo, valid_window=1)


def registrar_intento_fallido(usuario):


    from django.db.models import F
    from django.db import transaction

    with transaction.atomic():

        type(usuario).objects.filter(pk=usuario.pk).update(
            intentos_fallidos=F('intentos_fallidos') + 1
        )

        usuario.refresh_from_db(fields=['intentos_fallidos'])

        if usuario.intentos_fallidos >= MAX_INTENTOS and usuario.estado != 'BLOQUEADO':
            type(usuario).objects.filter(pk=usuario.pk).update(
                estado='BLOQUEADO',
                fecha_bloqueo=timezone.now(),
            )
            usuario.estado = 'BLOQUEADO'
            usuario.fecha_bloqueo = timezone.now()
            _notificar_bloqueo(usuario)


def registrar_login_exitoso(usuario):

    usuario.intentos_fallidos = 0
    usuario.ultimo_acceso = timezone.now()
    usuario.save(update_fields=['intentos_fallidos', 'ultimo_acceso'])


def verificar_bloqueo(usuario):


    if usuario.estado != 'BLOQUEADO':
        return False
    if not usuario.fecha_bloqueo:

        type(usuario).objects.filter(pk=usuario.pk).update(
            estado='ACTIVO',
            intentos_fallidos=0,
        )
        usuario.estado = 'ACTIVO'
        usuario.intentos_fallidos = 0
        return False
    limite = usuario.fecha_bloqueo + timedelta(minutes=BLOQUEO_MINUTOS)
    if timezone.now() > limite:

        type(usuario).objects.filter(pk=usuario.pk).update(
            estado='ACTIVO',
            intentos_fallidos=0,
            fecha_bloqueo=None,
        )
        usuario.estado = 'ACTIVO'
        usuario.intentos_fallidos = 0
        usuario.fecha_bloqueo = None
        return False
    return True


def _notificar_bloqueo(usuario):

    try:
        from django.core.mail import send_mail
        from django.conf import settings
        send_mail(
            subject='[AuditCore] Tu cuenta ha sido bloqueada',
            message=(
                f'Hola {usuario.nombre_completo},\n\n'
                f'Tu cuenta fue bloqueada por {MAX_INTENTOS} intentos fallidos de login.\n'
                f'Se desbloqueará automáticamente en {BLOQUEO_MINUTOS} minutos.\n\n'
                f'Si no fuiste tú, contacta al administrador inmediatamente.'
            ),
            from_email=settings.DEFAULT_FROM_EMAIL,
            recipient_list=[usuario.email],
            fail_silently=True,
        )
    except Exception:
        pass