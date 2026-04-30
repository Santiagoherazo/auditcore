"""
apps/administracion/views_auth.py
AC-02: Login con JWT
AC-03: MFA TOTP
AC-04: Bloqueo automático tras 5 intentos
AC-05: Recuperación de contraseña
"""
import logging
import secrets
from datetime import timedelta
from django.utils import timezone
from django.core.mail import send_mail
from django.conf import settings
from rest_framework.views import APIView
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework import status
from rest_framework_simplejwt.tokens import RefreshToken

logger = logging.getLogger(__name__)


try:
    from adapters.realtime.auditlog import (
        alog, AL, log_login_ok, log_login_failed,
        log_logout, log_mfa_event,
    )
except ImportError:
    def alog(*a, **kw): pass
    def log_login_ok(*a, **kw): pass
    def log_login_failed(*a, **kw): pass
    def log_logout(*a, **kw): pass
    def log_mfa_event(*a, **kw): pass


def _get_ip(request) -> str:
    xff = request.META.get('HTTP_X_FORWARDED_FOR', '')
    return xff.split(',')[0].strip() if xff else request.META.get('REMOTE_ADDR', '?')


class LoginView(APIView):
    """AC-02 + AC-04: Login con control de bloqueo tras 5 intentos fallidos."""
    permission_classes = [AllowAny]

    def post(self, request):
        from apps.administracion.models import UsuarioInterno
        from apps.administracion.mfa import (
            verificar_bloqueo, registrar_intento_fallido,
            registrar_login_exitoso, verificar_totp,
        )

        email      = request.data.get('email', '').strip().lower()
        password   = request.data.get('password', '')
        codigo_mfa = request.data.get('codigo_mfa', '').strip()

        if not email or not password:
            return Response({'detail': 'Email y contraseña son requeridos.'}, status=400)

        try:
            usuario = UsuarioInterno.objects.get(email=email)
        except UsuarioInterno.DoesNotExist:
            # No revelar si el email existe o no
            return Response({'detail': 'Credenciales inválidas.'}, status=401)

        # Esto permitía que un usuario BLOQUEADO probara contraseñas y distinguiera
        # "contraseña correcta pero bloqueado" (403) de "contraseña incorrecta" (401),
        # filtrando información útil para un atacante.
        # Orden correcto: bloqueo temporal → estado permanente → contraseña → MFA.

        _ip = _get_ip(request)

        # 1. Bloqueo temporal por intentos fallidos (AC-04)
        if verificar_bloqueo(usuario):
            log_login_failed(email, ip=_ip, reason='account_locked')
            return Response(
                {'detail': 'Cuenta bloqueada por múltiples intentos fallidos. '
                           'Intenta en 30 minutos o contacta al administrador.'},
                status=403,
            )

        # 2. Estado de la cuenta (INACTIVO o BLOQUEADO permanente)
        if usuario.estado != 'ACTIVO':
            log_login_failed(email, ip=_ip, reason='account_inactive')
            return Response({'detail': 'Usuario inactivo. Contacta al administrador.'}, status=403)

        # 3. Verificar contraseña
        if not usuario.check_password(password):
            registrar_intento_fallido(usuario)
            restantes = max(0, 5 - (usuario.intentos_fallidos or 0))
            log_login_failed(email, ip=_ip, reason='wrong_password', attempts_left=restantes)
            return Response(
                {'detail': f'Credenciales inválidas. {restantes} intento(s) restantes.'},
                status=401,
            )

        # AC-03: MFA
        if usuario.mfa_habilitado:
            if not codigo_mfa:
                return Response(
                    {'detail': 'Se requiere código MFA.', 'mfa_required': True},
                    status=202,
                )
            if not verificar_totp(usuario, codigo_mfa):
                log_mfa_event(email, 'verify_failed', ip=_ip, ok=False)
                return Response({'detail': 'Código MFA inválido o expirado.'}, status=401)
            log_mfa_event(email, 'verify_ok', ip=_ip, ok=True)

        registrar_login_exitoso(usuario)
        log_login_ok(email, ip=_ip, mfa=usuario.mfa_habilitado)
        refresh = RefreshToken.for_user(usuario)
        return Response({
            'access':  str(refresh.access_token),
            'refresh': str(refresh),
            'usuario': {
                'id':     str(usuario.id),
                'email':  usuario.email,
                'nombre': usuario.nombre_completo,
                'rol':    usuario.rol,
            },
        })


class MFASetupView(APIView):
    """AC-03: Genera QR y activa/desactiva MFA para el usuario autenticado."""
    permission_classes = [IsAuthenticated]

    def get(self, request):
        from apps.administracion.mfa import generar_secret_totp, generar_qr_totp
        usuario = request.user
        # Si MFA ya está habilitado, no devolver el secret (ya fue configurado y
        # confirmado). Solo devolver el QR para re-escaneo si el usuario lo pide
        # explícitamente, pero NUNCA el secret en texto plano.
        if usuario.mfa_habilitado:
            return Response({
                'mfa_activo': True,
                'detail': 'MFA ya está activado. Para reconfigurarlo, desactívalo primero.',
            })
        if not usuario.mfa_secret:
            usuario.mfa_secret = generar_secret_totp()
            usuario.save(update_fields=['mfa_secret'])
        qr_b64 = generar_qr_totp(usuario)
        # El secret solo se expone una vez, durante la configuración inicial
        return Response({'qr_base64': qr_b64, 'secret': usuario.mfa_secret, 'mfa_activo': False})

    def post(self, request):
        from apps.administracion.mfa import verificar_totp
        codigo = request.data.get('codigo', '').strip()
        if not codigo:
            return Response({'detail': 'Código requerido.'}, status=400)
        usuario = request.user
        if not verificar_totp(usuario, codigo):
            return Response({'detail': 'Código inválido o expirado.'}, status=400)
        usuario.mfa_habilitado = True
        usuario.save(update_fields=['mfa_habilitado'])
        return Response({'detail': 'MFA activado correctamente.'})

    def delete(self, request):
        password = request.data.get('password', '')
        usuario = request.user
        if not usuario.check_password(password):
            return Response({'detail': 'Contraseña incorrecta.'}, status=400)
        usuario.mfa_habilitado = False
        usuario.mfa_secret = ''
        usuario.save(update_fields=['mfa_habilitado', 'mfa_secret'])
        return Response({'detail': 'MFA desactivado.'})


class PasswordResetRequestView(APIView):
    """AC-05: Solicitar reset de contraseña por email."""
    permission_classes = [AllowAny]

    def post(self, request):
        from apps.administracion.models import UsuarioInterno
        email = request.data.get('email', '').strip().lower()
        if not email:
            return Response({'detail': 'Email requerido.'}, status=400)

        # Responder igual independientemente de si el email existe (seguridad)
        try:
            usuario = UsuarioInterno.objects.get(email=email, estado='ACTIVO')
            token = secrets.token_urlsafe(48)
            usuario.reset_token = token
            usuario.reset_token_expira = timezone.now() + timedelta(minutes=15)
            usuario.save(update_fields=['reset_token', 'reset_token_expira'])
            reset_url = (
                f"{getattr(settings, 'FRONTEND_URL', 'http://localhost:3000')}"
                f"/reset-password?token={token}"
            )
            send_mail(
                subject='[AuditCore] Recuperación de contraseña',
                message=(
                    f'Hola {usuario.nombre_completo},\n\n'
                    f'Para restablecer tu contraseña accede al siguiente enlace '
                    f'(válido por 15 minutos):\n\n{reset_url}\n\n'
                    f'Si no solicitaste esto, ignora este mensaje.'
                ),
                from_email=settings.DEFAULT_FROM_EMAIL,
                recipient_list=[email],
                fail_silently=True,
            )
        except UsuarioInterno.DoesNotExist:
            pass  # No revelar si el email existe

        return Response(
            {'detail': 'Si el email está registrado, recibirás las instrucciones en breve.'}
        )


class PasswordResetConfirmView(APIView):
    """AC-05: Confirmar reset con el token recibido por email."""
    permission_classes = [AllowAny]

    def post(self, request):
        from apps.administracion.models import UsuarioInterno
        token    = request.data.get('token', '').strip()
        password = request.data.get('password', '')

        if not token:
            return Response({'detail': 'Token requerido.'}, status=400)
        if len(password) < 8:
            return Response(
                {'detail': 'La contraseña debe tener al menos 8 caracteres.'}, status=400
            )
        # Validación adicional: la contraseña no debe ser solo numérica
        if password.isdigit():
            return Response(
                {'detail': 'La contraseña no puede ser completamente numérica.'}, status=400
            )

        try:
            usuario = UsuarioInterno.objects.get(
                reset_token=token,
                reset_token_expira__gt=timezone.now(),
            )
            usuario.set_password(password)
            usuario.reset_token = ''
            usuario.reset_token_expira = None
            usuario.intentos_fallidos = 0
            if usuario.estado == 'BLOQUEADO':
                usuario.estado = 'ACTIVO'
            # (ultimo_acceso, mfa_secret, etc.) en caso de actualización concurrente.
            usuario.save(update_fields=[
                'password', 'reset_token', 'reset_token_expira',
                'intentos_fallidos', 'estado',
            ])
            return Response({'detail': 'Contraseña restablecida correctamente.'})
        except UsuarioInterno.DoesNotExist:
            return Response({'detail': 'Token inválido o expirado.'}, status=400)


class SetupStatusView(APIView):
    """
    GET /api/auth/setup/status/
    Devuelve si la plataforma ya fue configurada.
    Endpoint público — usado por el wizard del frontend.
    """
    permission_classes = [AllowAny]

    def get(self, request):
        from apps.administracion.models import UsuarioInterno
        tiene_admin = UsuarioInterno.objects.filter(
            rol='SUPERVISOR', is_superuser=True
        ).exists()
        return Response({'configured': tiene_admin})


class SetupView(APIView):
    """
    POST /api/auth/setup/
    Crea el primer superadministrador.
    Se bloquea automáticamente después del primer uso.
    """
    permission_classes = [AllowAny]

    # antes de la configuración inicial, potencialmente como DoS o para
    # observar tiempos de respuesta durante el primer setup.
    # Limitamos a 5 intentos por IP en una ventana de 10 minutos.
    _MAX_INTENTOS = 5
    _VENTANA_SEGUNDOS = 600

    def _verificar_rate_limit(self, request) -> bool:
        """Devuelve True si la IP está dentro del límite, False si excedió."""
        try:
            from django.core.cache import cache
            xff = request.META.get('HTTP_X_FORWARDED_FOR')
            ip  = xff.split(',')[0].strip() if xff else request.META.get('REMOTE_ADDR', '0.0.0.0')
            key = f'setup_attempts:{ip}'
            intentos = cache.get(key, 0)
            if intentos >= self._MAX_INTENTOS:
                return False
            cache.set(key, intentos + 1, self._VENTANA_SEGUNDOS)
            return True
        except Exception:
            return True  # Si el cache falla, no bloquear

    def post(self, request):
        from apps.administracion.models import UsuarioInterno
        from django.db import transaction

        # Double-checked locking: primera comprobación rápida (sin lock)
        if UsuarioInterno.objects.filter(rol='SUPERVISOR', is_superuser=True).exists():
            return Response(
                {'detail': 'La plataforma ya fue configurada. Este endpoint está deshabilitado.'},
                status=403,
            )

        if not self._verificar_rate_limit(request):
            return Response(
                {'detail': 'Demasiados intentos. Espera 10 minutos.'},
                status=429,
            )

        nombre            = request.data.get('nombre', '').strip()
        apellido          = request.data.get('apellido', '').strip()
        email             = request.data.get('email', '').strip().lower()
        password          = request.data.get('password', '')
        nombre_plataforma = request.data.get('nombre_plataforma', 'AuditCore').strip()

        # Validaciones
        errores = {}
        if not nombre:   errores['nombre']   = 'Requerido.'
        if not apellido: errores['apellido'] = 'Requerido.'
        if not email:    errores['email']    = 'Requerido.'
        elif '@' not in email: errores['email'] = 'Email inválido.'
        if len(password) < 8:
            errores['password'] = 'Mínimo 8 caracteres.'
        if errores:
            return Response(errores, status=400)

        try:
            with transaction.atomic():
                # Segunda comprobación dentro del bloque atómico para evitar race condition
                if UsuarioInterno.objects.select_for_update().filter(rol='SUPERVISOR', is_superuser=True).exists():
                    return Response(
                        {'detail': 'La plataforma ya fue configurada. Este endpoint está deshabilitado.'},
                        status=403,
                    )

                if UsuarioInterno.objects.filter(email=email).exists():
                    return Response({'email': 'Ya existe un usuario con ese email.'}, status=400)

                usuario = UsuarioInterno.objects.create_superuser(
                    email=email,
                    password=password,
                    nombre=nombre,
                    apellido=apellido,
                    rol='SUPERVISOR',
                )
                if usuario.estado != 'ACTIVO':
                    usuario.estado = 'ACTIVO'
                    usuario.save(update_fields=['estado'])
        except Exception as exc:
            logger.exception('Error al crear superusuario en setup: %s', exc)
            return Response(
                {'detail': 'Error interno al crear el usuario. Revisa los logs del servidor.'},
                status=500,
            )

        return Response({
            'detail': f'Plataforma "{nombre_plataforma}" configurada correctamente.',
            'usuario': {
                'email':  usuario.email,
                'nombre': usuario.nombre_completo,
                'rol':    usuario.rol,
            },
        }, status=201)
