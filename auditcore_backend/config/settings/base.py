import os
from pathlib import Path
from decouple import config
from datetime import timedelta

BASE_DIR = Path(__file__).resolve().parent.parent.parent

SECRET_KEY    = config('SECRET_KEY')
DEBUG         = config('DEBUG', default=False, cast=bool)
ALLOWED_HOSTS = config('ALLOWED_HOSTS', default='localhost').split(',')

DJANGO_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
]

THIRD_PARTY_APPS = [
    'rest_framework',
    'rest_framework_simplejwt',
    'rest_framework_simplejwt.token_blacklist',
    'corsheaders',
    'channels',
    'django_filters',
    'drf_spectacular',
    'django_celery_beat',
]

LOCAL_APPS = [
    'apps.administracion',
    'apps.clientes',
    'apps.tipos_auditoria',
    'apps.formularios',
    'apps.expedientes',
    'apps.ejecucion',
    'apps.documentos',
    'apps.certificaciones',
    'apps.chatbot',
    'apps.seguridad',
]

INSTALLED_APPS = DJANGO_APPS + THIRD_PARTY_APPS + LOCAL_APPS

MIDDLEWARE = [
    'corsheaders.middleware.CorsMiddleware',
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',


    'adapters.realtime.auditlog.DeepAuditMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
    'apps.seguridad.middleware.AuditLogMiddleware',
]

ROOT_URLCONF     = 'config.urls'
ASGI_APPLICATION = 'config.asgi.application'
WSGI_APPLICATION = 'config.wsgi.application'

TEMPLATES = [{
    'BACKEND': 'django.template.backends.django.DjangoTemplates',
    'DIRS': [BASE_DIR / 'templates'],
    'APP_DIRS': True,
    'OPTIONS': {'context_processors': [
        'django.template.context_processors.debug',
        'django.template.context_processors.request',
        'django.contrib.auth.context_processors.auth',
        'django.contrib.messages.context_processors.messages',
    ]},
}]

import dj_database_url
DATABASES = {
    'default': dj_database_url.config(
        default=config('DATABASE_URL'),
        conn_max_age=600,
    )
}

REDIS_URL = config('REDIS_URL', default='redis://localhost:6379/0')

CHANNEL_LAYERS = {
    'default': {
        'BACKEND': 'channels_redis.core.RedisChannelLayer',
        'CONFIG': {'hosts': [REDIS_URL]},
    }
}

CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.redis.RedisCache',
        'LOCATION': REDIS_URL,
    }
}

AUTH_USER_MODEL = 'administracion.UsuarioInterno'

AUTHENTICATION_BACKENDS = ['django.contrib.auth.backends.ModelBackend']

AUTH_PASSWORD_VALIDATORS = [
    {'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator'},
    {'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator',
     'OPTIONS': {'min_length': 8}},
    {'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator'},
    {'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator'},
]

SIMPLE_JWT = {
    'ACCESS_TOKEN_LIFETIME':    timedelta(minutes=60),
    'REFRESH_TOKEN_LIFETIME':   timedelta(days=7),
    'ROTATE_REFRESH_TOKENS':    True,
    'BLACKLIST_AFTER_ROTATION': True,
    'AUTH_HEADER_TYPES':        ('Bearer',),
    'ALGORITHM':                'HS256',
}

REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': [
        'rest_framework_simplejwt.authentication.JWTAuthentication',
    ],
    'DEFAULT_PERMISSION_CLASSES': [
        'rest_framework.permissions.IsAuthenticated',
    ],
    'DEFAULT_FILTER_BACKENDS': [
        'django_filters.rest_framework.DjangoFilterBackend',
        'rest_framework.filters.SearchFilter',
        'rest_framework.filters.OrderingFilter',
    ],
    'DEFAULT_PAGINATION_CLASS': 'rest_framework.pagination.PageNumberPagination',
    'PAGE_SIZE': 25,
    'DEFAULT_SCHEMA_CLASS': 'drf_spectacular.openapi.AutoSchema',


    'EXCEPTION_HANDLER': 'config.exceptions.drf_exception_handler',
}

SPECTACULAR_SETTINGS = {
    'TITLE': 'AuditCore API',
    'DESCRIPTION': 'API REST para la plataforma de gestión de auditorías y certificaciones.',
    'VERSION': '1.0.0',


    'ENUM_NAME_OVERRIDES': {
        'RolUsuarioEnum':         'apps.administracion.models.UsuarioInterno.ROL_CHOICES',
        'EstadoUsuarioEnum':      'apps.administracion.models.UsuarioInterno.ESTADO_CHOICES',
        'EstadoExpedienteEnum':   'apps.expedientes.models.Expediente.ESTADO_CHOICES',
        'EstadoCertificacionEnum':'apps.certificaciones.models.Certificacion.ESTADO_CHOICES',
        'EstadoHallazgoEnum':     'apps.ejecucion.models.Hallazgo.ESTADO_CHOICES',
        'EstadoDocumentoEnum':    'apps.documentos.models.DocumentoExpediente.ESTADO_CHOICES',
        'EstadoConversacionEnum': 'apps.chatbot.models.Conversacion.ESTADO_CHOICES',
    },

    'SERVE_INCLUDE_SCHEMA': False,
}


_RABBITMQ_DEFAULT = 'amqp://auditcore:auditcore2026@rabbitmq:5672/auditcore?heartbeat=120'
RABBITMQ_URL      = os.environ.get('RABBITMQ_URL') or config('RABBITMQ_URL', default=_RABBITMQ_DEFAULT)
CELERY_BROKER_URL = RABBITMQ_URL
CELERY_RESULT_BACKEND     = REDIS_URL
CELERY_ACCEPT_CONTENT     = ['json']
CELERY_TASK_SERIALIZER    = 'json'
CELERY_RESULT_SERIALIZER  = 'json'
CELERY_TIMEZONE           = 'America/Bogota'
CELERY_BEAT_SCHEDULER     = 'django_celery_beat.schedulers:DatabaseScheduler'


CELERY_BROKER_CONNECTION_RETRY_ON_STARTUP = True


CELERY_BROKER_CONNECTION_RETRY           = True
CELERY_BROKER_CONNECTION_MAX_RETRIES     = 10


CELERY_BROKER_TRANSPORT_OPTIONS = {
    'connect_timeout':  10,
    'max_retries':       5,
    'interval_start':    0.5,
    'interval_step':     0.5,
    'interval_max':      3.0,
}


CELERY_BROKER_POOL_LIMIT          = None
CELERY_BROKER_FAILOVER_STRATEGY   = 'round-robin'
CELERY_BROKER_USE_SSL             = False


CELERY_BROKER_HEARTBEAT = 60


CELERY_TASK_PUBLISH_RETRY        = True
CELERY_TASK_PUBLISH_RETRY_POLICY = {
    'max_retries': 3,
    'interval_start': 0.5,
    'interval_step':  0.5,
    'interval_max':   2.0,
}

CELERY_TASK_TIME_LIMIT      = 480
CELERY_TASK_SOFT_TIME_LIMIT = 420
CELERY_TASK_ACKS_LATE             = True
CELERY_WORKER_PREFETCH_MULTIPLIER = 1

CELERY_WORKER_PREFETCH_COUNT      = 1
CELERY_WORKER_MAX_MEMORY_PER_CHILD = 1500000


from kombu import Exchange, Queue
CELERY_TASK_QUEUES = (
    Queue('default',        Exchange('default',        type='direct'), routing_key='default',        durable=True),
    Queue('notificaciones', Exchange('notificaciones', type='direct'), routing_key='notificaciones', durable=True),
    Queue('reportes',       Exchange('reportes',       type='direct'), routing_key='reportes',       durable=True),
)
CELERY_TASK_DEFAULT_QUEUE    = 'default'
CELERY_TASK_DEFAULT_EXCHANGE = 'default'
CELERY_TASK_DEFAULT_ROUTING_KEY = 'default'

CELERY_TASK_ROUTES = {
    'workers.notificaciones.*': {'queue': 'notificaciones'},
    'workers.reportes.*':       {'queue': 'reportes'},
    'workers.chatbot.*':        {'queue': 'default'},
}

EMAIL_BACKEND       = 'django.core.mail.backends.smtp.EmailBackend'
EMAIL_HOST          = config('EMAIL_HOST',          default='smtp.gmail.com')
EMAIL_PORT          = config('EMAIL_PORT',          default=587, cast=int)
EMAIL_USE_TLS       = config('EMAIL_USE_TLS',       default=True, cast=bool)
EMAIL_HOST_USER     = config('EMAIL_HOST_USER',     default='')
EMAIL_HOST_PASSWORD = config('EMAIL_HOST_PASSWORD', default='')
DEFAULT_FROM_EMAIL  = config('DEFAULT_FROM_EMAIL',  default=f'AuditCore <{EMAIL_HOST_USER}>')

OLLAMA_BASE_URL  = config('OLLAMA_BASE_URL',  default='https://santiagoherazo.ddns.net:11435')
OLLAMA_MODEL     = config('OLLAMA_MODEL',     default='llama3.1:8b')
OLLAMA_SSL_VERIFY = config('OLLAMA_SSL_VERIFY', default=False, cast=bool)

MEDIA_URL   = '/media/'
MEDIA_ROOT  = BASE_DIR / config('MEDIA_ROOT', default='media')
STATIC_URL  = '/static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'

LANGUAGE_CODE = 'es-co'
TIME_ZONE     = 'America/Bogota'
USE_I18N      = True
USE_TZ        = True

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'


SECURE_CONTENT_TYPE_NOSNIFF = True
SECURE_BROWSER_XSS_FILTER   = True
X_FRAME_OPTIONS              = 'DENY'
REFERRER_POLICY              = 'strict-origin-when-cross-origin'


DATA_UPLOAD_MAX_MEMORY_SIZE  = 57_671_680
FILE_UPLOAD_MAX_MEMORY_SIZE  = 57_671_680

from celery.schedules import crontab
CELERY_BEAT_SCHEDULE = {
    'verificar-estados-certificaciones': {
        'task':     'workers.notificaciones.verificar_estados_certificaciones',
        'schedule': crontab(hour=0, minute=0),
    },
    'alertas-vencimiento-certificaciones': {
        'task':     'workers.notificaciones.alertas_vencimiento_certificaciones',
        'schedule': crontab(hour=8, minute=0),
    },
}


LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'verbose': {
            'format': '{asctime} [{levelname}] {name}: {message}',
            'style': '{',
        },
        'ids': {

            'format': '{asctime} {message}',
            'style': '{',
        },
    },
    'handlers': {
        'console': {
            'class': 'logging.StreamHandler',
            'formatter': 'verbose',
        },
        'console_ids': {
            'class': 'logging.StreamHandler',
            'formatter': 'ids',
        },
    },
    'loggers': {


        'auditcore.chatbot.ids': {
            'handlers': [],
            'level': 'DEBUG',
            'propagate': False,
        },


        'kombu': {
            'handlers': ['console'],
            'level': 'WARNING',
            'propagate': False,
        },
        'amqp': {
            'handlers': ['console'],
            'level': 'WARNING',
            'propagate': False,
        },

        'django.channels': {
            'handlers': ['console'],
            'level': 'INFO',
            'propagate': False,
        },

        'celery': {
            'handlers': ['console'],
            'level': 'INFO',
            'propagate': False,
        },
        'django': {
            'handlers': ['console'],
            'level': 'INFO',
            'propagate': False,
        },
    },
    'root': {
        'handlers': ['console'],
        'level': 'WARNING',
    },
}
