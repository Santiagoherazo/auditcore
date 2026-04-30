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
    NOTA: el secret en texto plano solo se expone aquí durante la
    configuración inicial. Una vez mfa_habilitado=True, el endpoint
    de setup no debe volver a devolverlo.
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
    AC-04: Incrementa el contador de intentos fallidos de forma atómica.
    Bloquea la cuenta si supera MAX_INTENTOS.
    Usa F() + update() para evitar race condition cuando dos requests
    simultáneos leen el mismo valor y ambos escriben el mismo incremento.
    """
    from django.db.models import F
    from django.db import transaction

    with transaction.atomic():
        # Incremento atómico en la BD — evita lost-update entre requests concurrentes
        type(usuario).objects.filter(pk=usuario.pk).update(
            intentos_fallidos=F('intentos_fallidos') + 1
        )
        # Refrescar desde BD para obtener el valor real post-incremento
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
    """Resetea el contador de intentos al hacer login exitoso."""
    usuario.intentos_fallidos = 0
    usuario.ultimo_acceso = timezone.now()
    usuario.save(update_fields=['intentos_fallidos', 'ultimo_acceso'])


def verificar_bloqueo(usuario):
    """
    Retorna True si la cuenta está bloqueada.
    Desbloqueo automático después de BLOQUEO_MINUTOS.
    Si fecha_bloqueo es None pero estado es BLOQUEADO (estado inconsistente),
    fuerza el desbloqueo para evitar un bloqueo permanente sin causa raíz.
    """
    if usuario.estado != 'BLOQUEADO':
        return False
    if not usuario.fecha_bloqueo:
        # Estado inconsistente: bloqueado sin fecha de bloqueo — desbloquear
        type(usuario).objects.filter(pk=usuario.pk).update(
            estado='ACTIVO',
            intentos_fallidos=0,
        )
        usuario.estado = 'ACTIVO'
        usuario.intentos_fallidos = 0
        return False
    limite = usuario.fecha_bloqueo + timedelta(minutes=BLOQUEO_MINUTOS)
    if timezone.now() > limite:
        # Auto-desbloqueo atómico
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