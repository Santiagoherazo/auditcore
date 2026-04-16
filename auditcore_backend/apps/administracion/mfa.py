"""
apps/administracion/mfa.py
AC-03: MFA TOTP con django_otp
AC-04: Bloqueo tras 5 intentos fallidos
"""
import pyotp
import qrcode
import io
import base64
from django.utils import timezone
from datetime import timedelta


MAX_INTENTOS = 5
BLOQUEO_MINUTOS = 30


def generar_secret_totp():
    """Genera una clave secreta TOTP de 32 caracteres."""
    return pyotp.random_base32()


def generar_qr_totp(usuario):
    """
    Genera un QR code en base64 para configurar la app autenticadora.
    El usuario debe tener mfa_secret configurado.
    """
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
    """
    Verifica el código TOTP del usuario.
    Acepta ventana de ±1 período (30s) para tolerar desfase de reloj.
    """
    if not usuario.mfa_secret:
        return False
    totp = pyotp.TOTP(usuario.mfa_secret)
    return totp.verify(codigo, valid_window=1)


def registrar_intento_fallido(usuario):
    """
    AC-04: Incrementa el contador de intentos fallidos.
    Bloquea la cuenta si supera MAX_INTENTOS.
    """
    usuario.intentos_fallidos = (usuario.intentos_fallidos or 0) + 1
    if usuario.intentos_fallidos >= MAX_INTENTOS:
        usuario.estado = 'BLOQUEADO'
        usuario.fecha_bloqueo = timezone.now()
        _notificar_bloqueo(usuario)
    usuario.save(update_fields=['intentos_fallidos', 'estado', 'fecha_bloqueo'])


def registrar_login_exitoso(usuario):
    """Resetea el contador de intentos al hacer login exitoso."""
    usuario.intentos_fallidos = 0
    usuario.ultimo_acceso = timezone.now()
    usuario.save(update_fields=['intentos_fallidos', 'ultimo_acceso'])


def verificar_bloqueo(usuario):
    """
    Retorna True si la cuenta está bloqueada.
    Desbloqueo automático después de BLOQUEO_MINUTOS.
    """
    if usuario.estado != 'BLOQUEADO':
        return False
    if usuario.fecha_bloqueo:
        limite = usuario.fecha_bloqueo + timedelta(minutes=BLOQUEO_MINUTOS)
        if timezone.now() > limite:
            # Auto-desbloqueo
            usuario.estado = 'ACTIVO'
            usuario.intentos_fallidos = 0
            usuario.fecha_bloqueo = None
            usuario.save(update_fields=['estado', 'intentos_fallidos', 'fecha_bloqueo'])
            return False
    return True


def _notificar_bloqueo(usuario):
    """Envía email al usuario y al ADMIN cuando se bloquea la cuenta."""
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