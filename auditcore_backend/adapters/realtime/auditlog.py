from __future__ import annotations

import json
import logging
import logging.handlers
import os
import sys
import time
import traceback
import uuid
from enum import Enum
from pathlib import Path
from typing import Any


_LOG_DIR = Path(os.environ.get('AUDITLOG_DIR', '/app/logs'))
try:
    _LOG_DIR.mkdir(parents=True, exist_ok=True)
    _LOG_FILE     = _LOG_DIR / 'auditcore.log'
    _LOG_FILE_ERR = _LOG_DIR / 'auditcore_err.log'
    _LOG_FILE.touch(exist_ok=True)
    _LOG_FILE_ERR.touch(exist_ok=True)
except OSError:
    _LOG_DIR      = Path('/tmp/auditcore_logs')
    _LOG_DIR.mkdir(parents=True, exist_ok=True)
    _LOG_FILE     = _LOG_DIR / 'auditcore.log'
    _LOG_FILE_ERR = _LOG_DIR / 'auditcore_err.log'


class AL(str, Enum):
    HTTP    = 'HTTP'
    AUTH    = 'AUTH'
    DB      = 'DB'
    CELERY  = 'CELERY'
    WS      = 'WS'
    SEC     = 'SEC'
    DOC     = 'DOC'
    AUDIT   = 'AUDIT'
    SYS     = 'SYS'
    ERROR   = 'ERROR'


_COLORS = {
    'DEBUG':    '\033[90m',
    'INFO':     '\033[0m',
    'WARNING':  '\033[33m',
    'ERROR':    '\033[31m',
    'CRITICAL': '\033[35;1m',
}
_CAT_COLORS = {
    'HTTP':   '\033[36m',
    'AUTH':   '\033[34m',
    'DB':     '\033[90m',
    'CELERY': '\033[32m',
    'WS':     '\033[35m',
    'SEC':    '\033[31;1m',
    'DOC':    '\033[33m',
    'AUDIT':  '\033[34;1m',
    'SYS':    '\033[37m',
    'ERROR':  '\033[31;1m',
}
_RESET = '\033[0m'


class _JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        p = getattr(record, '_al', None)
        if p is None:
            p = {
                'ts':    self.formatTime(record, '%Y-%m-%dT%H:%M:%S'),
                'ms':    int(record.created * 1000) % 1000,
                'level': record.levelname,
                'cat':   'SYS',
                'proc':  'unknown',
                'pid':   os.getpid(),
                'msg':   record.getMessage(),
            }
            if record.exc_info:
                p['traceback'] = self.formatException(record.exc_info)
        return json.dumps(p, ensure_ascii=False, default=str)


class _ConsoleFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        p     = getattr(record, '_al', {})
        ts    = p.get('ts', '')
        cat   = p.get('cat', 'SYS')
        proc  = p.get('proc', '?')
        level = p.get('level', record.levelname)
        op    = p.get('op', '')
        user  = f" user={p['user']}" if p.get('user') else ''
        ip    = f" ip={p['ip']}"     if p.get('ip')   else ''
        op_id = f" op={p['op_id']}"  if p.get('op_id') else ''


        _skip = {'ts', 'ms', 'level', 'cat', 'proc', 'pid', 'op', 'user',
                 'ip', 'op_id', 'traceback'}
        extras = ' '.join(f'{k}={v}' for k, v in p.items() if k not in _skip)

        cat_color   = _CAT_COLORS.get(cat, '')
        level_color = _COLORS.get(level, '')

        line = (
            f"{level_color}{ts}{_RESET} "
            f"[{cat_color}{cat:<6}{_RESET}] "
            f"[{proc:<12}] "
            f"{level_color}{op:<45}{_RESET}"
            f"{user}{ip}{op_id} {extras}"
        )
        return line.rstrip()


class _ErrFileFormatter(logging.Formatter):

    def format(self, record: logging.LogRecord) -> str:
        p = getattr(record, '_al', {})
        if record.exc_info and 'traceback' not in p:
            p = dict(p)
            p['traceback'] = self.formatException(record.exc_info)
        return json.dumps(p, ensure_ascii=False, default=str)


def _build_loggers():
    main_logger = logging.getLogger('auditcore.audit.main')
    main_logger.setLevel(logging.DEBUG)
    main_logger.propagate = False

    err_logger = logging.getLogger('auditcore.audit.err')
    err_logger.setLevel(logging.WARNING)
    err_logger.propagate = False

    if not main_logger.handlers:

        fh = logging.handlers.TimedRotatingFileHandler(
            str(_LOG_FILE), when='midnight', backupCount=30,
            encoding='utf-8', utc=True,
        )
        fh.setFormatter(_JsonFormatter())
        fh.setLevel(logging.DEBUG)
        main_logger.addHandler(fh)


        ch = logging.StreamHandler(sys.stdout)
        ch.setFormatter(_ConsoleFormatter())
        ch.setLevel(logging.DEBUG)
        main_logger.addHandler(ch)

    if not err_logger.handlers:

        eh = logging.handlers.TimedRotatingFileHandler(
            str(_LOG_FILE_ERR), when='midnight', backupCount=90,
            encoding='utf-8', utc=True,
        )
        eh.setFormatter(_ErrFileFormatter())
        eh.setLevel(logging.WARNING)
        err_logger.addHandler(eh)

    return main_logger, err_logger


_main_logger, _err_logger = _build_loggers()


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


_FIELD_MAX = 500


def _trunc(v: Any) -> str:
    s = str(v)
    return s if len(s) <= _FIELD_MAX else s[:_FIELD_MAX - 3] + '...'


def alog(
    category: AL,
    op:       str        = '',
    level:    str        = 'info',
    user:     str | None = None,
    ip:       str | None = None,
    op_id:    str | None = None,
    exc_info: bool       = False,
    **kwargs: Any,
) -> None:


    now = time.time()
    payload: dict[str, Any] = {
        'ts':    time.strftime('%Y-%m-%dT%H:%M:%S', time.gmtime(now)),
        'ms':    int(now * 1000) % 1000,
        'level': level.upper(),
        'cat':   category.value,
        'proc':  _PROC,
        'pid':   _PID,
        'op':    op,
    }
    if user:  payload['user']  = _trunc(user)
    if ip:    payload['ip']    = ip
    if op_id: payload['op_id'] = op_id

    for k, v in kwargs.items():
        payload[k] = _trunc(v)


    if exc_info:
        tb = traceback.format_exc()
        if tb and tb.strip() != 'NoneType: None':
            payload['traceback'] = tb[:3000]

    py_level = getattr(logging, level.upper(), logging.INFO)
    rec = logging.LogRecord(
        name='auditcore.audit.main', level=py_level,
        pathname='', lineno=0, msg='', args=(), exc_info=None,
    )
    rec._al     = payload
    rec.created = now
    _main_logger.handle(rec)


    if py_level >= logging.WARNING:
        err_rec = logging.LogRecord(
            name='auditcore.audit.err', level=py_level,
            pathname='', lineno=0, msg='', args=(), exc_info=None,
        )
        err_rec._al     = payload
        err_rec.created = now
        _err_logger.handle(err_rec)


def new_op_id() -> str:

    return uuid.uuid4().hex[:12]


class DeepAuditMiddleware:


    _SKIP_PATHS = frozenset([
        '/api/chatbot/status/',
        '/api/schema/',
        '/static/',
        '/media/',
        '/favicon.ico',
        '/health/',
    ])


    _MASK_HEADERS = frozenset([
        'authorization', 'cookie', 'x-api-key', 'x-auth-token',
    ])

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):

        path = request.path
        if any(path.startswith(s) for s in self._SKIP_PATHS):
            return self.get_response(request)

        op_id = new_op_id()
        request._auditlog_op_id = op_id
        t0    = time.monotonic()
        user  = self._get_user(request)
        ip    = self._get_ip(request)
        method = request.method


        alog(
            AL.HTTP, op=f'{method} {path}',
            level='debug',
            user=user, ip=ip, op_id=op_id,
            user_agent=request.META.get('HTTP_USER_AGENT', '')[:120],
            content_type=request.content_type or '',
            content_length=request.META.get('CONTENT_LENGTH', 0),
        )


        response = None
        try:
            response = self.get_response(request)
        except Exception as exc:
            latency = int((time.monotonic() - t0) * 1000)
            alog(
                AL.ERROR, op=f'{method} {path} → EXCEPTION',
                level='critical',
                user=user, ip=ip, op_id=op_id,
                exc_type=type(exc).__name__,
                detail=str(exc)[:300],
                latency_ms=latency,
                exc_info=True,
            )
            raise


        latency = int((time.monotonic() - t0) * 1000)
        status  = response.status_code


        if status >= 500:
            lvl = 'error'
        elif status in (401, 403):
            lvl = 'warning'
        elif status == 429:
            lvl = 'warning'
        elif latency > 2000:
            lvl = 'warning'
        else:
            lvl = 'info'

        cat = AL.SEC if status in (401, 403, 429) else AL.HTTP

        alog(
            cat, op=f'{method} {path} → {status}',
            level=lvl,
            user=user, ip=ip, op_id=op_id,
            status=status,
            latency_ms=latency,
            response_size=len(getattr(response, 'content', b'')),
        )


        if status == 401:
            alog(AL.SEC, op='unauthorized_access',
                 level='warning', user=user, ip=ip, op_id=op_id,
                 path=path, hint='Token inválido o expirado')
        elif status == 403:
            alog(AL.SEC, op='forbidden_access',
                 level='warning', user=user, ip=ip, op_id=op_id,
                 path=path, hint='Permisos insuficientes para este recurso')

        return response

    def _get_ip(self, request) -> str:
        xff = request.META.get('HTTP_X_FORWARDED_FOR', '')
        if xff:
            return xff.split(',')[0].strip()
        return request.META.get('REMOTE_ADDR', '?')

    def _get_user(self, request) -> str | None:
        try:
            u = getattr(request, 'user', None)
            if u and u.is_authenticated:
                return getattr(u, 'email', None) or getattr(u, 'username', None) or str(u.pk)
        except Exception:
            pass
        return None


class SlowQueryLogger:


    _installed = False

    @classmethod
    def install(cls, threshold_ms: int = 200) -> None:
        if cls._installed:
            return
        cls._installed = True

        from django.db import connection
        from django.db.backends.signals import connection_created

        def _on_connection_created(sender, connection, **kwargs):
            connection.execute_wrappers.append(
                cls._make_wrapper(threshold_ms)
            )

        connection_created.connect(_on_connection_created)

        alog(AL.DB, op='slow_query_logger_installed',
             level='info', threshold_ms=threshold_ms)

    @staticmethod
    def _make_wrapper(threshold_ms: int):
        def wrapper(execute, sql, params, many, context):
            t0     = time.monotonic()
            result = execute(sql, params, many, context)
            ms     = int((time.monotonic() - t0) * 1000)
            if ms >= threshold_ms:

                sql_clean = ' '.join(sql.split())
                alog(
                    AL.DB, op='slow_query',
                    level='warning' if ms < 1000 else 'error',
                    latency_ms=ms,
                    sql=sql_clean[:400],
                    threshold_ms=threshold_ms,
                    hint='Considera añadir índice o revisar N+1 queries',
                )
            return result
        return wrapper


def log_doc_upload(
    nombre: str,
    mime_type: str,
    size_bytes: int,
    conv_id: str,
    user: str | None = None,
    ip: str | None = None,
    op_id: str | None = None,
    seguro: bool = True,
    motivo_rechazo: str = '',
) -> None:

    alog(
        AL.DOC, op='doc_upload_received',
        level='info' if seguro else 'warning',
        user=user, ip=ip, op_id=op_id,
        nombre=nombre,
        mime_type=mime_type,
        size_kb=size_bytes // 1024,
        conv_id=conv_id,
        seguro=seguro,
        motivo_rechazo=motivo_rechazo or '',
    )


def log_doc_analysis_start(nombre: str, conv_id: str, op_id: str | None = None) -> None:
    alog(AL.DOC, op='doc_analysis_start', level='info',
         nombre=nombre, conv_id=conv_id, op_id=op_id)


def log_doc_analysis_done(
    nombre: str,
    conv_id: str,
    tokens: int,
    elapsed_s: float,
    op_id: str | None = None,
) -> None:
    alog(AL.DOC, op='doc_analysis_done', level='info',
         nombre=nombre, conv_id=conv_id,
         tokens=tokens, elapsed_s=f'{elapsed_s:.1f}',
         op_id=op_id)


def log_doc_review(
    nombre: str,
    expediente: str,
    nuevo_estado: str,
    user: str | None = None,
    observacion: str = '',
) -> None:

    alog(
        AL.DOC, op=f'doc_{nuevo_estado.lower()}',
        level='info',
        user=user,
        nombre=nombre,
        expediente=expediente,
        nuevo_estado=nuevo_estado,
        observacion=observacion[:200] if observacion else '',
    )


def log_login_ok(user: str, ip: str | None = None, mfa: bool = False) -> None:
    alog(AL.AUTH, op='login_ok', level='info', user=user, ip=ip, mfa=mfa)


def log_login_failed(identifier: str, ip: str | None = None, reason: str = '') -> None:
    alog(AL.AUTH, op='login_failed', level='warning',
         user=identifier, ip=ip, reason=reason,
         hint='Posible ataque de fuerza bruta si se repite')


def log_logout(user: str, ip: str | None = None) -> None:
    alog(AL.AUTH, op='logout', level='info', user=user, ip=ip)


def log_token_refresh(user: str, ip: str | None = None, ok: bool = True) -> None:
    alog(AL.AUTH, op='token_refresh', level='debug' if ok else 'warning',
         user=user, ip=ip, ok=ok)


def log_mfa_event(user: str, event: str, ip: str | None = None, ok: bool = True) -> None:

    alog(AL.AUTH, op=f'mfa_{event}',
         level='info' if ok else 'warning',
         user=user, ip=ip, ok=ok)


def log_task_enqueue(task_name: str, task_id: str, op_id: str | None = None, **kwargs) -> None:
    alog(AL.CELERY, op=f'task_enqueued:{task_name}',
         level='info', task_id=task_id, op_id=op_id, **kwargs)


def log_task_start(task_name: str, task_id: str, retries: int = 0, **kwargs) -> None:
    alog(AL.CELERY, op=f'task_start:{task_name}',
         level='info', task_id=task_id, retries=retries, **kwargs)


def log_task_done(task_name: str, task_id: str, elapsed_s: float, **kwargs) -> None:
    alog(AL.CELERY, op=f'task_done:{task_name}',
         level='info', task_id=task_id,
         elapsed_s=f'{elapsed_s:.1f}', **kwargs)


def log_task_error(task_name: str, task_id: str, exc: Exception,
                   retries: int = 0, max_retries: int = 0) -> None:
    alog(AL.CELERY, op=f'task_error:{task_name}',
         level='error',
         task_id=task_id,
         exc_type=type(exc).__name__,
         detail=str(exc)[:300],
         retries=retries,
         max_retries=max_retries,
         exc_info=True)


def log_system_boot() -> None:

    info: dict[str, Any] = {
        'python': sys.version.split()[0],
        'env':    os.environ.get('DJANGO_ENV', 'unknown'),
    }
    try:
        import psutil
        proc = psutil.Process()
        mem  = proc.memory_info()
        info['rss_mb']   = mem.rss  // (1024 * 1024)
        info['vms_mb']   = mem.vms  // (1024 * 1024)
        disk = psutil.disk_usage('/app')
        info['disk_free_gb'] = disk.free // (1024 ** 3)
        info['disk_pct']     = disk.percent
    except ImportError:
        info['psutil'] = 'not_installed'
    except Exception as e:
        info['psutil_err'] = str(e)

    alog(AL.SYS, op='system_boot', level='info', **info)


def log_system_stats() -> None:

    info: dict[str, Any] = {}
    try:
        import psutil
        proc = psutil.Process()
        mem  = proc.memory_info()
        info['rss_mb']       = mem.rss // (1024 * 1024)
        info['cpu_pct']      = proc.cpu_percent(interval=0.1)
        disk = psutil.disk_usage('/app')
        info['disk_free_gb'] = disk.free // (1024 ** 3)
        info['disk_pct']     = disk.percent
        info['open_files']   = len(proc.open_files())
        info['threads']      = proc.num_threads()
    except ImportError:
        info['psutil'] = 'not_installed'
    except Exception as e:
        info['psutil_err'] = str(e)

    level = 'warning' if info.get('disk_pct', 0) > 85 else 'info'
    alog(AL.SYS, op='system_stats', level=level, **info)


alog(
    AL.SYS, op='auditlog_ready', level='info',
    log_main=str(_LOG_FILE),
    log_err=str(_LOG_FILE_ERR),
    proc=_PROC,
    pid=_PID,
)
