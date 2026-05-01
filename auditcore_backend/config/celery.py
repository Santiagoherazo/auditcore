import os
import django
from celery import Celery

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings.development')

app = Celery('auditcore')
app.config_from_object('django.conf:settings', namespace='CELERY')


_DEFAULT_BROKER = os.environ.get(
    'RABBITMQ_URL',
    'amqp://auditcore:auditcore_dev_CAMBIAR_EN_PROD@rabbitmq:5672/auditcore?heartbeat=120'
)
_broker_url = _DEFAULT_BROKER

app.conf.broker_url                    = _broker_url
app.conf.broker_failover_strategy      = 'round-robin'
app.conf.broker_pool_limit             = None
app.conf.broker_connection_retry       = True
app.conf.broker_connection_max_retries = 10


app.autodiscover_tasks([
    'workers.chatbot',
    'workers.chat_context',
    'workers.notificaciones',
    'workers.reportes',
])


try:
    django.setup()
except RuntimeError:
    pass

try:
    from adapters.realtime.chatbot_logger import ids_log, IDS
    ids_log(
        IDS.BOOT, level='info',
        msg='celery_app_initialized',
        broker_url=_broker_url,
        pool_limit=str(app.conf.broker_pool_limit),
        failover=app.conf.broker_failover_strategy,
        env_present=str(bool(os.environ.get('RABBITMQ_URL'))),
        urls_match=str(os.environ.get('RABBITMQ_URL', '') == _broker_url),
    )
except Exception as e:
    print(f'[CELERY-BOOT] IDS logger no disponible: {e}', file=__import__('sys').stderr)
