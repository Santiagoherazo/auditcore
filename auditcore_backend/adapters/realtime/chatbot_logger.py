"""
chatbot_logger.py — Sistema IDS v2 para el pipeline del chatbot AuditCore.

Escribe a DOS destinos en paralelo:
  1. /app/logs/chatbot_ids.log  — JSON-Lines, rotación diaria, 7 días
  2. stdout                     — líneas legibles para docker logs

Categorías (una por capa del sistema):
  BOOT    arranque del proceso — qué PID, qué broker URL
  AUTH    autenticación JWT en el middleware WS
  WS_IN   eventos entrantes al consumer (connect, disconnect, ping)
  WS_OUT  eventos salientes al cliente (token, done, error, typing)
  CHANNEL operaciones channel layer (group_add, group_send, group_discard)
  API     endpoint HTTP enviar_mensaje y similares
  CELERY  publicación de tarea — .apply_async() en el proceso Daphne
  BROKER  diagnóstico RabbitMQ/kombu — snapshot completo al fallar
  TASK    ciclo de vida de la tarea dentro del worker Celery
  OLLAMA  preflight, streaming, tokens, errores HTTP
  ERROR   cualquier fallo en cualquier capa

Uso rápido:
  from adapters.realtime.chatbot_logger import ids_log, IDS, broker_diagnostic, new_trace_id

  ids_log(IDS.API, conv_id='abc', trace_id='a3f7c901', msg='enviar_mensaje_request', user='xyz')

Comandos de análisis:
  # Seguimiento en tiempo real
  docker compose exec backend tail -f /app/logs/chatbot_ids.log | python3 -c "
  import sys,json
  for l in sys.stdin:
    try:
      d=json.loads(l)
      ex={k:v for k,v in d.items() if k not in('ts','ms','level','cat','conv','msg','proc','pid','trace')}
      conv=' conv='+d['conv'] if d.get('conv') else ''
      print(f'[{d[\"ts\"]}][{d[\"proc\"]:<14}][{d[\"cat\"]:<7}]{conv} {d.get(\"msg\",\"\")} {ex}')
    except: print(l,end='')
  "

  # Sólo errores
  docker compose exec backend grep '"level":"ERROR"' /app/logs/chatbot_ids.log | tail -20

  # Diagnóstico completo del broker tras un fallo 503
  docker compose exec backend grep 'broker_diagnostic_snapshot' /app/logs/chatbot_ids.log | tail -1 | python3 -m json.tool

  # Seguir un mensaje de punta a punta (trace_id de 8 chars)
  docker compose exec backend grep '"trace":"<8chars>"' /app/logs/chatbot_ids.log

  # Ver con qué URL arrancó cada proceso
  docker compose exec backend grep '"cat":"BOOT"' /app/logs/chatbot_ids.log | python3 -m json.tool
"""
import json
import logging
import logging.handlers
import os
import sys
import time
import uuid
from enum import Enum
from pathlib import Path


# ── Directorio de logs ────────────────────────────────────────────────────────
_LOG_DIR = Path(os.environ.get('IDS_LOG_DIR', '/app/logs'))
try:
    _LOG_DIR.mkdir(parents=True, exist_ok=True)
    _LOG_FILE = _LOG_DIR / 'chatbot_ids.log'
    _LOG_FILE.touch(exist_ok=True)
except (OSError, PermissionError):
    _LOG_DIR  = Path('/tmp/auditcore_logs')
    _LOG_DIR.mkdir(parents=True, exist_ok=True)
    _LOG_FILE = _LOG_DIR / 'chatbot_ids.log'


# ── Formatters ────────────────────────────────────────────────────────────────
class _JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = getattr(record, '_ids', None)
        if payload is None:
            payload = {
                'ts': self.formatTime(record, '%Y-%m-%dT%H:%M:%S'),
                'ms': int(record.created * 1000) % 1000,
                'level': record.levelname,
                'cat': 'SYSTEM',
                'proc': 'unknown',
                'pid': os.getpid(),
                'msg': record.getMessage(),
            }
            if record.exc_info:
                payload['exc'] = self.formatException(record.exc_info)
        return json.dumps(payload, ensure_ascii=False, default=str)


class _ConsoleFormatter(logging.Formatter):
    _C = {'DEBUG': '\033[37m', 'INFO': '', 'WARNING': '\033[33m',
          'ERROR': '\033[31m', 'CRITICAL': '\033[35m'}
    _R = '\033[0m'

    def format(self, record: logging.LogRecord) -> str:
        p     = getattr(record, '_ids', {})
        ts    = p.get('ts', '')
        cat   = p.get('cat', 'SYSTEM')
        proc  = p.get('proc', '?')
        conv  = f" conv={p['conv']}" if p.get('conv') else ''
        trace = f" trace={p['trace']}" if p.get('trace') else ''
        msg   = p.get('msg', record.getMessage())
        level = p.get('level', record.levelname)
        extras = ' '.join(
            f'{k}={v}' for k, v in p.items()
            if k not in ('ts', 'ms', 'level', 'cat', 'conv', 'msg', 'proc', 'pid', 'trace')
        )
        c = self._C.get(level, '')
        return f'{c}{ts} [IDS][{proc:<14}][{cat:<7}]{conv}{trace} {msg} {extras}{self._R}'.rstrip()


# ── Logger (singleton) ────────────────────────────────────────────────────────
_logger = logging.getLogger('auditcore.chatbot.ids')
_logger.setLevel(logging.DEBUG)
_logger.propagate = False

if not _logger.handlers:
    _fh = logging.handlers.TimedRotatingFileHandler(
        str(_LOG_FILE), when='midnight', backupCount=7, encoding='utf-8', utc=True,
    )
    _fh.setFormatter(_JsonFormatter())
    _fh.setLevel(logging.DEBUG)

    _ch = logging.StreamHandler(sys.stdout)
    _ch.setFormatter(_ConsoleFormatter())
    _ch.setLevel(logging.DEBUG)

    _logger.addHandler(_fh)
    _logger.addHandler(_ch)


# ── Categorías ────────────────────────────────────────────────────────────────
class IDS(str, Enum):
    BOOT    = 'BOOT'
    AUTH    = 'AUTH'
    WS_IN   = 'WS_IN'
    WS_OUT  = 'WS_OUT'
    CHANNEL = 'CHANNEL'
    API     = 'API'
    CELERY  = 'CELERY'
    BROKER  = 'BROKER'
    TASK    = 'TASK'
    OLLAMA  = 'OLLAMA'
    ERROR   = 'ERROR'


# ── Contexto de proceso (cacheado al primer import) ───────────────────────────
def _detect_proc() -> str:
    argv = ' '.join(sys.argv)
    if 'daphne'   in argv: return 'daphne'
    if 'beat'     in argv: return 'celery-beat'
    if 'celery'   in argv: return 'celery-worker'
    if 'manage'   in argv: return 'manage.py'
    if 'gunicorn' in argv: return 'gunicorn'
    return (sys.argv[0] if sys.argv else 'unknown')[:20]


_PROC = _detect_proc()
_PID  = os.getpid()


# ── API pública ───────────────────────────────────────────────────────────────
def ids_log(
    category: IDS,
    conv_id:  str | None = None,
    level:    str        = 'info',
    trace_id: str | None = None,
    **kwargs,
) -> None:
    """
    Emite un evento IDS al archivo JSON-Lines y a consola.

    Args:
        category  Categoría IDS que identifica la capa del sistema
        conv_id   UUID de conversación — correlaciona toda la cadena de un mensaje
        level     'debug' | 'info' | 'warning' | 'error' | 'critical'
        trace_id  ID corto por mensaje (new_trace_id()) — correlaciona Daphne↔Worker
        **kwargs  Campos extra: msg=, exc_type=, detail=, etc.
    """
    now = time.time()
    payload: dict = {
        'ts':    time.strftime('%Y-%m-%dT%H:%M:%S', time.gmtime(now)),
        'ms':    int(now * 1000) % 1000,
        'level': level.upper(),
        'cat':   category.value,
        'proc':  _PROC,
        'pid':   _PID,
    }
    if conv_id:  payload['conv']  = conv_id
    if trace_id: payload['trace'] = trace_id

    for k, v in kwargs.items():
        s = str(v)
        payload[k] = s if len(s) <= 300 else s[:297] + '...'

    py_level = getattr(logging, level.upper(), logging.INFO)
    rec = logging.LogRecord(
        name='auditcore.chatbot.ids', level=py_level,
        pathname='', lineno=0, msg='', args=(), exc_info=None,
    )
    rec._ids    = payload  # type: ignore[attr-defined]
    rec.created = now
    _logger.handle(rec)


def broker_diagnostic(
    conv_id:  str | None = None,
    trace_id: str | None = None,
) -> None:
    """
    Snapshot completo del estado del broker al momento de un fallo.
    Llama esto dentro del bloque except _BROKER_ERRORS en views.py.

    Captura y compara tres fuentes de la broker URL:
      A) os.environ.get('RABBITMQ_URL')     — lo que Docker inyecta
      B) django.conf.settings.CELERY_BROKER_URL — lo que base.py leyó
      C) config.celery.app.conf.broker_url  — lo que el objeto Celery tiene

    Si A != C → bug de decouple confirmado (fix de base.py lo resuelve).
    Si A == C pero kombu_test falla → RabbitMQ realmente caído.
    Si A == C y kombu_test == OK   → problema de pool de conexiones.
    """
    env_url = os.environ.get('RABBITMQ_URL', '<NOT_SET>')

    # Django settings
    s_broker = s_rabbit = pool = failover = '<django_not_ready>'
    try:
        from django.conf import settings as _s
        s_broker = getattr(_s, 'CELERY_BROKER_URL', '<missing>')
        s_rabbit = getattr(_s, 'RABBITMQ_URL',      '<missing>')
        pool     = str(getattr(_s, 'CELERY_BROKER_POOL_LIMIT',        '<missing>'))
        failover = str(getattr(_s, 'CELERY_BROKER_FAILOVER_STRATEGY', '<missing>'))
    except Exception as e:
        s_broker = s_rabbit = f'<ERR:{e}>'

    # Celery app.conf
    app_url = app_pool = app_fo = '<celery_not_ready>'
    try:
        from config.celery import app as _app
        app_url  = str(_app.conf.broker_url)
        app_pool = str(_app.conf.broker_pool_limit)
        app_fo   = str(_app.conf.broker_failover_strategy)
    except Exception as e:
        app_url = f'<ERR:{e}>'

    # Test real de conexión kombu
    kombu_result = '<skipped>'
    test_url = env_url if env_url != '<NOT_SET>' else s_broker
    if test_url and '<' not in test_url:
        try:
            from kombu import Connection
            with Connection(test_url, connect_timeout=4) as c:
                c.ensure_connection(max_retries=1, timeout=4)
                c.channel()
            kombu_result = 'OK'
        except Exception as e:
            kombu_result = f'FAIL:{type(e).__name__}:{e}'

    ids_log(
        IDS.BROKER, conv_id=conv_id, trace_id=trace_id, level='error',
        msg='broker_diagnostic_snapshot',
        env_RABBITMQ_URL=env_url,
        settings_CELERY_BROKER_URL=s_broker,
        settings_RABBITMQ_URL=s_rabbit,
        settings_POOL_LIMIT=pool,
        settings_FAILOVER=failover,
        celery_app_broker_url=app_url,
        celery_app_pool_limit=app_pool,
        celery_app_failover=app_fo,
        kombu_direct_test=kombu_result,
    )

    # Diagnóstico automático: ¿las URLs coinciden?
    if env_url != '<NOT_SET>' and '<' not in app_url:
        if env_url != app_url:
            ids_log(
                IDS.BROKER, conv_id=conv_id, trace_id=trace_id, level='error',
                msg='DIAGNOSIS_url_mismatch',
                cause='python-decouple capturó RABBITMQ_URL antes de que el entorno Docker estuviera listo',
                fix='settings/base.py ya usa os.environ.get() — asegúrate de desplegar ese fix',
                env_url=env_url, app_url=app_url,
            )
        elif kombu_result == 'OK':
            ids_log(
                IDS.BROKER, conv_id=conv_id, trace_id=trace_id, level='error',
                msg='DIAGNOSIS_pool_corruption',
                cause='URLs coinciden y kombu conecta bien — pool de conexiones corrompido',
                fix='CELERY_BROKER_POOL_LIMIT=None ya desactiva el pool — reiniciar el proceso Daphne',
            )
        else:
            ids_log(
                IDS.BROKER, conv_id=conv_id, trace_id=trace_id, level='error',
                msg='DIAGNOSIS_rabbitmq_down',
                cause='URLs coinciden pero kombu no puede conectar',
                fix='docker compose ps rabbitmq — verificar que el contenedor esté healthy',
            )


def new_trace_id() -> str:
    """ID corto de 8 hex chars para correlacionar un mensaje de punta a punta."""
    return uuid.uuid4().hex[:8]


# ── Boot log (ejecutado una vez al importar) ──────────────────────────────────
ids_log(
    IDS.BOOT, level='info',
    msg='ids_logger_v2_ready',
    log_file=str(_LOG_FILE),
    writable=str(_LOG_FILE.exists()),
    env_RABBITMQ_URL=os.environ.get('RABBITMQ_URL', '<NOT_SET>'),
)
