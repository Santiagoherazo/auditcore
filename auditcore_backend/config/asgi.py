import os

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings.development')

# Django setup MUST happen before importing channels or any app modules
import django
django.setup()

from django.conf import settings
from django.core.asgi import get_asgi_application
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.security.websocket import AllowedHostsOriginValidator
from adapters.realtime.middleware import JWTAuthMiddlewareStack
from adapters.realtime.routing import websocket_urlpatterns

# En desarrollo eliminamos AllowedHostsOriginValidator para que Flutter web
# (servido en un puerto distinto) pueda abrir conexiones WebSocket.
# En producción se vuelve a habilitar.
if settings.DEBUG:
    ws_application = JWTAuthMiddlewareStack(URLRouter(websocket_urlpatterns))
else:
    ws_application = AllowedHostsOriginValidator(
        JWTAuthMiddlewareStack(URLRouter(websocket_urlpatterns))
    )

application = ProtocolTypeRouter({
    'http': get_asgi_application(),
    'websocket': ws_application,
})
