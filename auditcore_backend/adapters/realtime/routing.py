from django.urls import re_path
from adapters.realtime.consumers import (
    ExpedienteConsumer, DashboardConsumer, ChatbotConsumer, NotificacionesConsumer
)

# FIX: Los patrones WebSocket deben comenzar con ^ para que URLRouter de
# Django Channels los ancle correctamente al inicio del path.
# Sin el ^, el router puede hacer match parcial o emitir el warning de SonarQube
# "pattern should match a full path". El $ al final ya estaba correcto.
websocket_urlpatterns = [
    re_path(r'^ws/expediente/(?P<expediente_id>[^/]+)/$', ExpedienteConsumer.as_asgi()),
    re_path(r'^ws/dashboard/$',                            DashboardConsumer.as_asgi()),
    re_path(r'^ws/chatbot/(?P<conversacion_id>[^/]+)/$',  ChatbotConsumer.as_asgi()),
    re_path(r'^ws/notificaciones/$',                       NotificacionesConsumer.as_asgi()),
]
