import json
import logging
import logging.handlers
import os
import sys
import time
import uuid
from enum import Enum
from pathlib import Path


_NOT_SET = '<NOT_SET>'
_MISSING = '<missing>'


_LOG_DIR = Path(os.environ.get('IDS_LOG_DIR', '/app/logs'))
try:
    _LOG_DIR.mkdir(parents=True, exist_ok=True)
    _LOG_FILE = _LOG_DIR / 'chatbot_ids.log'
    _LOG_FILE.touch(exist_ok=True)
except OSError:
    _LOG_DIR  = Path('/tmp/auditcore_logs')
    _LOG_DIR.mkdir(parents=True, exist_ok=True)
    _LOG_FILE = _LOG_DIR / 'chatbot_ids.log'


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


def ids_log(
    category: IDS,
    conv_id:  str | None = None,
    level:    str        = 'info',
    trace_id: str | None = None,
    **kwargs,
) -> None:


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
    rec._ids    = payload
    rec.created = now
    _logger.handle(rec)


def broker_diagnostic(
    conv_id:  str | None = None,
    trace_id: str | None = None,
) -> None:


    env_url = os.environ.get('RABBITMQ_URL', _NOT_SET)


    s_broker = s_rabbit = pool = failover = '<django_not_ready>'
    try:
        from django.conf import settings as _s
        s_broker = getattr(_s, 'CELERY_BROKER_URL', _MISSING)
        s_rabbit = getattr(_s, 'RABBITMQ_URL',      _MISSING)
        pool     = str(getattr(_s, 'CELERY_BROKER_POOL_LIMIT',        _MISSING))
        failover = str(getattr(_s, 'CELERY_BROKER_FAILOVER_STRATEGY', _MISSING))
    except Exception as e:
        s_broker = s_rabbit = f'<ERR:{e}>'


    app_url = app_pool = app_fo = '<celery_not_ready>'
    try:
        from config.celery import app as _app
        app_url  = str(_app.conf.broker_url)
        app_pool = str(_app.conf.broker_pool_limit)
        app_fo   = str(_app.conf.broker_failover_strategy)
    except Exception as e:
        app_url = f'<ERR:{e}>'


    kombu_result = '<skipped>'
    test_url = env_url if env_url != _NOT_SET else s_broker
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


    if env_url != _NOT_SET and '<' not in app_url:
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

    return uuid.uuid4().hex[:8]


ids_log(
    IDS.BOOT, level='info',
    msg='ids_logger_v2_ready',
    log_file=str(_LOG_FILE),
    writable=str(_LOG_FILE.exists()),
    env_RABBITMQ_URL=os.environ.get('RABBITMQ_URL', _NOT_SET),
)
