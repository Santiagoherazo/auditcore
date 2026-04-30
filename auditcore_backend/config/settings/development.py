from .base import *

DEBUG = True

# ── CORS: permitir cualquier origen en desarrollo ─────────────────────────
CORS_ALLOW_ALL_ORIGINS   = True
CORS_ALLOW_CREDENTIALS   = True
CORS_ALLOW_PRIVATE_NETWORK = True  # Para localhost en Chrome con flags de seguridad

# Headers que envía Dio (Flutter) y los WebSockets con JWT.
# Sin 'authorization' aquí → el browser bloquea el preflight → XMLHttpRequest onError.
CORS_ALLOW_HEADERS = [
    'accept',
    'accept-encoding',
    'authorization',       # JWT token — CRÍTICO para Flutter Web
    'content-type',
    'dnt',
    'origin',
    'user-agent',
    'x-csrftoken',
    'x-requested-with',
    'cache-control',
    'pragma',
]

# Asegurarse de que los métodos incluyen OPTIONS para preflight
CORS_ALLOW_METHODS = [
    'DELETE',
    'GET',
    'OPTIONS',
    'PATCH',
    'POST',
    'PUT',
]

EMAIL_BACKEND = 'django.core.mail.backends.console.EmailBackend'

INSTALLED_APPS += ['debug_toolbar'] if False else []