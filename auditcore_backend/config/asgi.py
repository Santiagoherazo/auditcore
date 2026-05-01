import os

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings.development')


import django
django.setup()

from django.conf import settings
from django.core.asgi import get_asgi_application
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.security.websocket import AllowedHostsOriginValidator
from adapters.realtime.middleware import JWTAuthMiddlewareStack
from adapters.realtime.routing import websocket_urlpatterns


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
