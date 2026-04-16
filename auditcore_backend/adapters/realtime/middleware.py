import logging
from channels.middleware import BaseMiddleware
from channels.db import database_sync_to_async
from django.contrib.auth.models import AnonymousUser
from rest_framework_simplejwt.tokens import AccessToken
from rest_framework_simplejwt.exceptions import InvalidToken, TokenError
from urllib.parse import parse_qs

logger = logging.getLogger('auditcore.chatbot.ids')

try:
    from adapters.realtime.chatbot_logger import ids_log, IDS
except ImportError:
    def ids_log(*a, **kw): pass  # type: ignore[misc]
    class IDS:
        AUTH='AUTH'


@database_sync_to_async
def get_user_from_token(token_str):
    """
    Resuelve el JWT a un UsuarioInterno.

    FIX: solo resuelve UsuarioInterno (usuarios internos con rol).
    Los UsuarioCliente (portal externo) tienen su propia autenticación
    por sesión HTTP y NO usan WebSocket — no necesitan JWTAuthMiddleware.
    Si en el futuro el portal de clientes necesita WS, se debe extender
    esta función para también buscar en UsuarioCliente, manteniendo la
    separación de modelos.

    El campo 'rol' queda disponible en scope['user'].rol para que
    los consumers puedan verificarlo sin tocar la BD de nuevo.
    """
    from apps.administracion.models import UsuarioInterno
    try:
        token   = AccessToken(token_str)
        user_id = token['user_id']
        user    = UsuarioInterno.objects.get(id=user_id)
        # Loguear resolución exitosa para diagnóstico IDS
        ids_log(IDS.AUTH, msg='jwt_resolved', user=user.id, rol=user.rol, estado=user.estado)
        # FIX: rechazar usuarios inactivos o bloqueados a nivel WS.
        # BUG ORIGINAL: un usuario BLOQUEADO con token aún válido (no expirado)
        # podía conectarse al WebSocket. La verificación de estado solo ocurría
        # en el login HTTP. El WS debe hacer la misma comprobación.
        if user.estado != 'ACTIVO':
            logger.warning(
                '[CHATBOT-IDS] [AUTH    ] msg=jwt_user_not_active user=%s estado=%s',
                user.id, user.estado,
            )
            return AnonymousUser()
        return user
    except (InvalidToken, TokenError):
        ids_log(IDS.AUTH, level='warning', msg='jwt_invalid_or_expired')
        return AnonymousUser()
    except UsuarioInterno.DoesNotExist:
        ids_log(IDS.AUTH, level='warning', msg='jwt_user_not_found')
        return AnonymousUser()
    except Exception as exc:
        ids_log(IDS.AUTH, level='error', msg='jwt_resolve_error', exc=str(exc))
        return AnonymousUser()


class JWTAuthMiddleware(BaseMiddleware):
    async def __call__(self, scope, receive, send):
        query_string = scope.get('query_string', b'').decode()
        params       = parse_qs(query_string)
        token_list   = params.get('token', [])

        if token_list:
            scope['user'] = await get_user_from_token(token_list[0])
        else:
            logger.debug(
                '[CHATBOT-IDS] [AUTH    ] msg=ws_no_token path=%s',
                scope.get('path', '?'),
            )
            scope['user'] = AnonymousUser()

        return await super().__call__(scope, receive, send)


def JWTAuthMiddlewareStack(inner):
    return JWTAuthMiddleware(inner)
