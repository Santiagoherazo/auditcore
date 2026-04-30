import os
import django
from celery import Celery

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings.development')

app = Celery('auditcore')
app.config_from_object('django.conf:settings', namespace='CELERY')

# FIX v2: asignar broker_url directamente desde os.environ sobre el objeto app.
# config_from_object() ya lee CELERY_BROKER_URL desde settings (que a su vez
# usa os.environ.get en base.py), pero esta asignación explícita actúa como
# segunda capa: si en cualquier edge case de orden de importación el valor
# llegó vacío a settings, aquí lo corregimos antes de que cualquier tarea
# intente usar el pool de conexiones.
# SEGURIDAD: No hardcodear credenciales en código fuente.
# En producción RABBITMQ_URL debe estar en las variables de entorno del sistema.
# El fallback aquí es solo para desarrollo local con docker-compose.
_DEFAULT_BROKER = os.environ.get(
    'RABBITMQ_URL',
    'amqp://auditcore:auditcore_dev_CAMBIAR_EN_PROD@rabbitmq:5672/auditcore?heartbeat=120'
)
_broker_url = _DEFAULT_BROKER

app.conf.broker_url                    = _broker_url
app.conf.broker_failover_strategy      = 'round-robin'
app.conf.broker_pool_limit             = None   # sin pool: cada .apply_async() abre conexión fresca
app.conf.broker_connection_retry       = True
app.conf.broker_connection_max_retries = 10

# FIX: listar módulos explícitamente — workers/ no tiene tasks.py, así que
# autodiscover_tasks(['workers']) no encontraba nada y las tareas nunca se
# registraban → KeyError al intentar ejecutarlas.
app.autodiscover_tasks([
    'workers.chatbot',
    'workers.chat_context',
    'workers.notificaciones',
    'workers.reportes',
])

# Boot log IDS: registrar con qué URL y en qué proceso arrancó el objeto Celery.
# Visible en /app/logs/chatbot_ids.log con cat=BOOT.
# Si urls_match=False → el fix de base.py aún no está desplegado.
try:
    django.setup()
except RuntimeError:
    pass  # Ya inicializado (proceso Daphne)

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
