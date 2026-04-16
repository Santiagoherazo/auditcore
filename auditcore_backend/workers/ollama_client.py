"""
ollama_client.py — Cliente unificado para Ollama (local Docker o servidor remoto HTTPS).

Soporta dos modos según OLLAMA_BASE_URL:
  · http://ollama:11434  — contenedor Docker local (sin SSL)
  · https://host:puerto  — servidor remoto con HTTPS (SSL verificado o con verify=False configurable)

Uso:
    from workers.ollama_client import OllamaClient
    client = OllamaClient()
    ok, err = client.verificar()
    respuesta, tokens = client.chat_stream(sistema, historial, mensaje, conv_id_for_ws)
"""
import json
import logging
import time
import requests
from django.conf import settings

logger = logging.getLogger(__name__)

try:
    from adapters.realtime.chatbot_logger import ids_log, IDS, new_trace_id
except ImportError:
    import enum
    class IDS(str, enum.Enum):
        OLLAMA = 'OLLAMA'; ERROR = 'ERROR'; TASK = 'TASK'
    def ids_log(cat, **kw): logger.info('[OLLAMA-FALLBACK] %s', kw)
    def new_trace_id(): return 'na'


def _get_config():
    base_url = getattr(settings, 'OLLAMA_BASE_URL', 'https://santiagoherazo.ddns.net:11435').rstrip('/')
    model    = getattr(settings, 'OLLAMA_MODEL',    'llama3.1:8b')
    ssl_verify = getattr(settings, 'OLLAMA_SSL_VERIFY', True)
    return base_url, model, ssl_verify


def _session(base_url: str, ssl_verify):
    """Crea una sesión requests con la configuración SSL correcta."""
    s = requests.Session()
    if base_url.startswith('https://'):
        s.verify = ssl_verify
        if not ssl_verify:
            import urllib3
            urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    return s


def verificar_ollama(conv_id=None) -> tuple[bool, str]:
    """Verifica que el servidor Ollama esté disponible. Devuelve (ok, error_msg)."""
    base_url, _, ssl_verify = _get_config()
    t0 = time.monotonic()
    ids_log(IDS.OLLAMA, conv_id=conv_id, msg='preflight_check', url=f'{base_url}/api/tags')
    try:
        sess = _session(base_url, ssl_verify)
        r = sess.get(f'{base_url}/api/tags', timeout=10)
        r.raise_for_status()
        try:
            modelos = [m.get('name', '?') for m in r.json().get('models', [])]
        except Exception:
            modelos = ['(no parseable)']
        ids_log(IDS.OLLAMA, conv_id=conv_id, msg='preflight_ok',
                latency_ms=f'{(time.monotonic()-t0)*1000:.0f}',
                url=base_url, modelos=','.join(modelos) or 'ninguno')
        return True, ''
    except requests.exceptions.SSLError as e:
        ids_log(IDS.OLLAMA, conv_id=conv_id, level='error', msg='preflight_ssl_error',
                detail=str(e), hint='Verifica el certificado o configura OLLAMA_SSL_VERIFY=False')
        return False, f'Error SSL al conectar con el servidor Ollama. Detalle: {e}'
    except requests.exceptions.ConnectionError:
        ids_log(IDS.OLLAMA, conv_id=conv_id, level='error', msg='preflight_connection_error',
                url=base_url, hint='Verifica que el servidor esté activo y la URL sea correcta')
        return False, f'No se puede conectar con el servidor Ollama en {base_url}. Verifica que esté activo.'
    except requests.exceptions.Timeout:
        ids_log(IDS.OLLAMA, conv_id=conv_id, level='error', msg='preflight_timeout',
                url=base_url)
        return False, 'Ollama no responde (timeout 10s). Puede estar iniciando o sobrecargado.'
    except Exception as e:
        ids_log(IDS.OLLAMA, conv_id=conv_id, level='error', msg='preflight_error',
                exc=type(e).__name__, detail=str(e))
        return False, f'Error al contactar Ollama: {e}'


def chat_stream(sistema: str, historial: list, mensaje: str, conv_id: str,
                on_token=None) -> tuple[str, int]:
    """
    Llamada streaming a Ollama /api/chat.

    Args:
        sistema:   Prompt de sistema.
        historial: Lista de {rol, contenido}.
        mensaje:   Mensaje del usuario.
        conv_id:   UUID de conversación (para logs).
        on_token:  Callable(str) llamado por cada chunk recibido.

    Returns:
        (texto_completo, total_tokens)
    """
    base_url, model, ssl_verify = _get_config()

    ok, err = verificar_ollama(conv_id)
    if not ok:
        return err, 0

    messages = [{'role': 'system', 'content': sistema}]
    for m in historial:
        rol = 'assistant' if m['rol'] == 'ASISTENTE' else 'user'
        messages.append({'role': rol, 'content': m['contenido']})
    messages.append({'role': 'user', 'content': mensaje})

    ids_log(IDS.OLLAMA, conv_id=conv_id, msg='stream_start',
            model=model, messages=len(messages), url=f'{base_url}/api/chat')
    t0 = time.monotonic()

    try:
        sess = _session(base_url, ssl_verify)
        with sess.post(
            f'{base_url}/api/chat',
            json={
                'model':      model,
                'messages':   messages,
                'stream':     True,
                'keep_alive': -1,
                'options': {
                    'temperature':    0.7,
                    'num_predict':    768,
                    'num_ctx':        2048,
                    'num_gpu':        99,
                    'num_thread':     0,
                    'repeat_penalty': 1.1,
                },
            },
            stream=True,
            timeout=390,
        ) as response:
            response.raise_for_status()

            texto, buffer, tokens = [], [], 0

            for line in response.iter_lines():
                if not line:
                    continue
                try:
                    data = json.loads(line.decode('utf-8'))
                except (json.JSONDecodeError, UnicodeDecodeError):
                    continue

                chunk = data.get('message', {}).get('content', '')
                if chunk:
                    texto.append(chunk)
                    buffer.append(chunk)
                    buf_str = ''.join(buffer)
                    if len(buf_str) >= 15 or any(c in buf_str for c in '.!?;\n'):
                        if on_token:
                            on_token(buf_str)
                        buffer = []

                if data.get('done', False):
                    if buffer and on_token:
                        on_token(''.join(buffer))
                    tokens = data.get('eval_count', 0) + data.get('prompt_eval_count', 0)
                    break

            respuesta = ''.join(texto).strip()
            ids_log(IDS.OLLAMA, conv_id=conv_id, msg='stream_done',
                    tokens=tokens, chars=len(respuesta),
                    elapsed=f'{time.monotonic()-t0:.1f}s')
            return respuesta or 'El asistente no pudo generar una respuesta.', tokens

    except requests.exceptions.SSLError as e:
        ids_log(IDS.OLLAMA, conv_id=conv_id, level='error', msg='stream_ssl_error', detail=str(e))
        return 'Error de seguridad SSL al comunicarse con el servidor de IA. Contacta al administrador.', 0
    except requests.exceptions.ConnectionError:
        ids_log(IDS.OLLAMA, conv_id=conv_id, level='error', msg='stream_connection_error', url=base_url)
        return 'El servidor de IA no está disponible. Verifica la conexión.', 0
    except requests.exceptions.Timeout:
        ids_log(IDS.OLLAMA, conv_id=conv_id, level='error', msg='stream_timeout',
                elapsed=f'{time.monotonic()-t0:.1f}s')
        return 'El servidor de IA tardó demasiado. Intenta de nuevo.', 0
    except requests.exceptions.HTTPError as e:
        status = e.response.status_code if e.response else '?'
        ids_log(IDS.OLLAMA, conv_id=conv_id, level='error', msg='stream_http_error', status=status)
        if status == 404:
            return f'Modelo "{model}" no encontrado. Ejecuta: ollama pull {model}', 0
        return f'Error del servidor de IA (HTTP {status}). Intenta de nuevo.', 0
    except Exception as e:
        ids_log(IDS.OLLAMA, conv_id=conv_id, level='error', msg='stream_unexpected',
                exc=type(e).__name__, detail=str(e))
        return 'Error inesperado. Intenta de nuevo.', 0


def chat_complete(sistema: str, prompt: str, conv_id: str = '',
                  temperature: float = 0.3, max_tokens: int = 1200) -> tuple[str, int]:
    """Llamada no-streaming para análisis de documentos y formularios."""
    base_url, model, ssl_verify = _get_config()

    ok, err = verificar_ollama(conv_id or None)
    if not ok:
        return err, 0

    try:
        sess = _session(base_url, ssl_verify)
        r = sess.post(
            f'{base_url}/api/chat',
            json={
                'model':    model,
                'messages': [
                    {'role': 'system', 'content': sistema},
                    {'role': 'user',   'content': prompt},
                ],
                'stream':  False,
                'options': {
                    'temperature':  temperature,
                    'num_predict':  max_tokens,
                    'num_ctx':      4096,
                    'num_gpu':      99,
                    'repeat_penalty': 1.1,
                },
            },
            timeout=230,
        )
        r.raise_for_status()
        data = r.json()
        texto  = data.get('message', {}).get('content', '').strip()
        tokens = data.get('eval_count', 0) + data.get('prompt_eval_count', 0)
        return texto or 'Sin respuesta.', tokens
    except Exception as e:
        logger.error('chat_complete error: %s', e, exc_info=True)
        return f'Error: {e}', 0
