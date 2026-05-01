import json
import logging
import time
from channels.generic.websocket import AsyncWebsocketConsumer

from adapters.realtime.chatbot_logger import ids_log, IDS

logger = logging.getLogger(__name__)


class BaseAuthConsumer(AsyncWebsocketConsumer):


    group_name: str | None = None

    async def connect(self):
        user = self.scope.get('user')
        token_present = bool(self.scope.get('query_string', b'') and b'token=' in self.scope.get('query_string', b''))

        ids_log(IDS.AUTH, conv_id=getattr(self, '_conv_id_log', None),
                msg='ws_connect_attempt',
                user=getattr(user, 'id', 'anonymous'),
                authenticated=bool(user and getattr(user, 'is_authenticated', False)),
                token_present=token_present,
                path=self.scope.get('path', '?'))

        if not user or not user.is_authenticated:
            ids_log(IDS.AUTH, conv_id=getattr(self, '_conv_id_log', None),
                    level='warning',
                    msg='ws_auth_rejected',
                    reason='no_valid_jwt_token_present=' + str(token_present),
                    path=self.scope.get('path', '?'))


            await self.accept()
            await self.close(code=4001)
            return
        await self._on_connect()

    async def _on_connect(self):
        raise NotImplementedError

    async def disconnect(self, code):
        ids_log(IDS.WS_IN, conv_id=getattr(self, '_conv_id_log', None),
                msg='ws_disconnect',
                close_code=code,
                group=self.group_name or 'none')
        await self._on_disconnect(code)

    async def _on_disconnect(self, code):
        if self.group_name and self.channel_layer:
            try:
                await self.channel_layer.group_discard(
                    self.group_name, self.channel_name
                )
                ids_log(IDS.CHANNEL, conv_id=getattr(self, '_conv_id_log', None),
                        msg='group_discard_ok', group=self.group_name)
            except Exception as e:
                ids_log(IDS.CHANNEL, conv_id=getattr(self, '_conv_id_log', None),
                        level='warning',
                        msg='group_discard_failed', group=self.group_name, error=e)

    async def receive(self, text_data):
        try:
            data = json.loads(text_data)
            ids_log(IDS.WS_IN, conv_id=getattr(self, '_conv_id_log', None),
                    msg='ws_message_received', type=data.get('type', '?'))
            await self._on_receive(data)
        except json.JSONDecodeError:
            ids_log(IDS.WS_IN, conv_id=getattr(self, '_conv_id_log', None),
                    level='warning', msg='ws_bad_json')

    async def _on_receive(self, data):


        pass


class ExpedienteConsumer(BaseAuthConsumer):
    async def _on_connect(self):
        self.expediente_id = self.scope['url_route']['kwargs']['expediente_id']
        self.group_name    = f'expediente_{self.expediente_id}'
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()
        ids_log(IDS.WS_IN, msg='expediente_ws_connected',
                expediente=self.expediente_id, group=self.group_name)

    async def expediente_update(self, event):
        await self.send(text_data=json.dumps({
            'type': 'expediente_update', 'data': event.get('data', {}),
        }))

    async def hallazgo_creado(self, event):
        await self.send(text_data=json.dumps({
            'type': 'hallazgo_creado', 'hallazgo': event.get('hallazgo', {}),
        }))

    async def documento_actualizado(self, event):
        await self.send(text_data=json.dumps({
            'type': 'documento_actualizado', 'documento': event.get('documento', {}),
        }))

    async def fase_actualizada(self, event):
        await self.send(text_data=json.dumps({
            'type': 'fase_actualizada', 'fase': event.get('fase', {}),
        }))


class DashboardConsumer(BaseAuthConsumer):


    _GROUP_NAME = 'dashboard_global'
    _ROLES_PERMITIDOS = frozenset(['SUPERVISOR', 'ASESOR', 'AUDITOR', 'AUXILIAR', 'REVISOR'])

    async def _on_connect(self):
        user = self.scope['user']
        rol  = getattr(user, 'rol', None)

        if rol not in self._ROLES_PERMITIDOS:
            ids_log(IDS.AUTH, msg='dashboard_ws_forbidden',
                    level='warning',
                    user=getattr(user, 'id', '?'),
                    rol=rol or 'none',
                    roles_permitidos=','.join(sorted(self._ROLES_PERMITIDOS)))


            await self.accept()
            await self.close(code=4003)
            return

        self.group_name = self._GROUP_NAME
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()
        ids_log(IDS.WS_IN, msg='dashboard_ws_connected',
                user=user.id, rol=rol)
        await self._enviar_snapshot()

    async def _enviar_snapshot(self):


        await self.send(text_data=json.dumps({'type': 'dashboard_update', 'data': {}}))

    async def dashboard_update(self, event):
        await self.send(text_data=json.dumps({
            'type': 'dashboard_update', 'data': event.get('data', {}),
        }))


class NotificacionesConsumer(BaseAuthConsumer):
    async def _on_connect(self):
        user_id         = str(self.scope['user'].id)
        self.group_name = f'notificaciones_{user_id}'
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()
        ids_log(IDS.WS_IN, msg='notificaciones_ws_connected',
                user=user_id, group=self.group_name)

    async def notificacion(self, event):
        await self.send(text_data=json.dumps({
            'type':    'notificacion',
            'tipo':    event.get('tipo', 'INFO'),
            'titulo':  event.get('titulo', ''),
            'mensaje': event.get('mensaje', ''),
        }))


class ChatbotConsumer(BaseAuthConsumer):


    async def _on_connect(self):
        self.conv_id       = self.scope['url_route']['kwargs']['conversacion_id']
        self._conv_id_log  = self.conv_id
        self.group_name    = f'chatbot_{self.conv_id}'
        self._stream_buffer: list = []
        self._connect_time = time.monotonic()

        user = self.scope.get('user')
        rol  = getattr(user, 'rol', None)


        from adapters.api.permissions import ROLES_CHATBOT
        if rol not in ROLES_CHATBOT:
            ids_log(IDS.AUTH, conv_id=self.conv_id, level='warning',
                    msg='chatbot_ws_role_forbidden',
                    user=getattr(user, 'id', '?'),
                    rol=rol or 'none',
                    hint='Usuario autenticado pero sin rol chatbot válido — '
                         'usar código 4003 para que Flutter no reintente')
            await self.accept()
            await self.close(code=4003)
            return


        cl = self.channel_layer
        ids_log(IDS.CHANNEL, conv_id=self.conv_id,
                msg='channel_layer_check',
                backend=type(cl).__name__ if cl else 'NONE',
                channel_name=self.channel_name)

        if cl is None:
            ids_log(IDS.ERROR, conv_id=self.conv_id, level='error',
                    msg='channel_layer_none',
                    hint='CHANNEL_LAYERS en settings no apunta a Redis válido')
            await self.accept()
            await self.close(code=4500)
            return

        try:
            await cl.group_add(self.group_name, self.channel_name)
            ids_log(IDS.CHANNEL, conv_id=self.conv_id,
                    msg='group_add_ok',
                    group=self.group_name,
                    channel=self.channel_name)
        except Exception as exc:
            ids_log(IDS.ERROR, conv_id=self.conv_id, level='error',
                    msg='group_add_failed',
                    group=self.group_name,
                    error=type(exc).__name__,
                    detail=str(exc),
                    hint='Redis caído o CHANNEL_LAYERS["CONFIG"]["hosts"] incorrecto')
            await self.accept()
            await self.close(code=4500)
            return

        await self.accept()
        ids_log(IDS.WS_IN, conv_id=self.conv_id,
                msg='chatbot_ws_connected',
                group=self.group_name,
                user_id=getattr(user, 'id', 'anonymous'),
                rol=rol,
                channel=self.channel_name)

    async def _on_disconnect(self, code):
        elapsed = time.monotonic() - getattr(self, '_connect_time', time.monotonic())
        ids_log(IDS.WS_IN, conv_id=getattr(self, 'conv_id', None),
                msg='chatbot_ws_disconnected',
                close_code=code,
                session_seconds=f'{elapsed:.1f}',
                group=self.group_name or 'none')

        if self.group_name and self.channel_layer:
            try:
                await self.channel_layer.group_discard(
                    self.group_name, self.channel_name
                )
                ids_log(IDS.CHANNEL, conv_id=getattr(self, 'conv_id', None),
                        msg='group_discard_ok', group=self.group_name)
            except Exception as e:
                ids_log(IDS.CHANNEL, conv_id=getattr(self, 'conv_id', None),
                        level='warning',
                        msg='group_discard_failed', group=self.group_name,
                        error=type(e).__name__)

    async def _on_receive(self, data):
        if data.get('type') == 'ping':
            ids_log(IDS.WS_IN, conv_id=getattr(self, 'conv_id', None),
                    msg='ping_received')
            await self.send(text_data=json.dumps({'type': 'pong'}))


    async def chatbot_token(self, event):

        chunk = event.get('contenido', '')
        self._stream_buffer.append(chunk)
        ids_log(IDS.WS_OUT, conv_id=getattr(self, 'conv_id', None),
                msg='chatbot_token_sent',
                chunk_len=len(chunk),
                total_buffered=sum(len(c) for c in self._stream_buffer))
        await self.send(text_data=json.dumps({
            'type':  'chatbot_token',
            'chunk': chunk,
        }))

    async def chatbot_done(self, event):

        contenido = event.get('contenido', '')
        self._stream_buffer = []
        ids_log(IDS.WS_OUT, conv_id=getattr(self, 'conv_id', None),
                msg='chatbot_done_sent',
                contenido_len=len(contenido))
        await self.send(text_data=json.dumps({
            'type':      'chatbot_done',
            'contenido': contenido,
        }))

    async def chatbot_error(self, event):

        self._stream_buffer = []
        mensaje = event.get('contenido', 'Error del asistente.')
        ids_log(IDS.WS_OUT, conv_id=getattr(self, 'conv_id', None),
                level='warning',
                msg='chatbot_error_sent',
                mensaje=mensaje)

        await self.send(text_data=json.dumps({
            'type':    'chatbot_error',
            'mensaje': mensaje,
        }))

    async def chatbot_typing(self, event):
        ids_log(IDS.WS_OUT, conv_id=getattr(self, 'conv_id', None),
                msg='chatbot_typing_received_from_worker')
        await self.send(text_data=json.dumps({'type': 'chatbot_typing'}))
