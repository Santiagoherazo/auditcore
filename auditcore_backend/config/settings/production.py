from .base import *
import os as _os

DEBUG = False

CORS_ALLOW_ALL_ORIGINS = False
CORS_ALLOW_CREDENTIALS = True


_cors_origins = _os.environ.get('CORS_ALLOWED_ORIGINS', '')
CORS_ALLOWED_ORIGINS = [o.strip() for o in _cors_origins.split(',') if o.strip()]
if not CORS_ALLOWED_ORIGINS:

    import warnings
    warnings.warn(
        'CORS_ALLOWED_ORIGINS no está configurado. '
        'Define la variable de entorno CORS_ALLOWED_ORIGINS en producción.',
        RuntimeWarning,
        stacklevel=2,
    )
    CORS_ALLOWED_ORIGINS = ['http://localhost:3000']


_extra_hosts = _os.environ.get('ALLOWED_HOSTS', '')
ALLOWED_HOSTS = ['backend'] + [h.strip() for h in _extra_hosts.split(',') if h.strip()]


SECURE_SSL_REDIRECT             = False
SECURE_PROXY_SSL_HEADER         = ('HTTP_X_FORWARDED_PROTO', 'https')
SESSION_COOKIE_SECURE           = True
SESSION_COOKIE_SAMESITE         = 'Lax'
CSRF_COOKIE_SECURE              = True
CSRF_COOKIE_SAMESITE            = 'Lax'
SECURE_HSTS_SECONDS             = 31536000
SECURE_HSTS_INCLUDE_SUBDOMAINS  = True
SECURE_HSTS_PRELOAD             = True
