from .base import *

DEBUG = True

# ── CORS: permitir cualquier origen en desarrollo ─────────────────────────
# Esto es lo que hace que el Flutter web pueda comunicarse con la API
# cuando se sirven desde puertos distintos (e.g. :3000 y :8000).
CORS_ALLOW_ALL_ORIGINS = True
CORS_ALLOW_CREDENTIALS = True

# Encabezados adicionales que usan Dio y los WebSockets con JWT
CORS_ALLOW_HEADERS = [
    'accept',
    'accept-encoding',
    'authorization',
    'content-type',
    'dnt',
    'origin',
    'user-agent',
    'x-csrftoken',
    'x-requested-with',
]

EMAIL_BACKEND = 'django.core.mail.backends.console.EmailBackend'

INSTALLED_APPS += ['debug_toolbar'] if False else []