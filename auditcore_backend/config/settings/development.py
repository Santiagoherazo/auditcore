from .base import *

DEBUG = True


CORS_ALLOW_ALL_ORIGINS   = True
CORS_ALLOW_CREDENTIALS   = True
CORS_ALLOW_PRIVATE_NETWORK = True


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
    'cache-control',
    'pragma',
]


CORS_ALLOW_METHODS = [
    'DELETE',
    'GET',
    'OPTIONS',
    'PATCH',
    'POST',
    'PUT',
]

EMAIL_BACKEND = 'django.core.mail.backends.console.EmailBackend'

