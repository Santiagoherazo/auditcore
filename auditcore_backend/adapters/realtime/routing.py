from django.urls import re_path
from adapters.realtime.consumers import (
    ExpedienteConsumer, DashboardConsumer, ChatbotConsumer, NotificacionesConsumer
)


websocket_urlpatterns = [
    re_path(r'^ws/expediente/(?P<expediente_id>[^/]+)/$', ExpedienteConsumer.as_asgi()),
    re_path(r'^ws/dashboard/$',                            DashboardConsumer.as_asgi()),
    re_path(r'^ws/chatbot/(?P<conversacion_id>[^/]+)/$',  ChatbotConsumer.as_asgi()),
    re_path(r'^ws/notificaciones/$',                       NotificacionesConsumer.as_asgi()),
]
