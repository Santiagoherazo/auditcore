#!/bin/sh
set -e

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║           AuditCore — Backend Django                 ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# Crear directorio de logs IDS antes de que Django arranque.
# chatbot_logger.py escribe a /app/logs/chatbot_ids.log desde el primer import.
mkdir -p /app/logs && chmod 755 /app/logs
echo "  [IDS] Logs en /app/logs/chatbot_ids.log"

echo "[1/6] Esperando a PostgreSQL..."
until python -c "
import os, sys, psycopg2
try:
    conn = psycopg2.connect(os.environ.get('DATABASE_URL', ''))
    conn.close()
    sys.exit(0)
except Exception:
    sys.exit(1)
" 2>/dev/null; do
  echo "      PostgreSQL no disponible, reintentando en 2s..."
  sleep 2
done
echo "      PostgreSQL listo."

echo "[2/6] Esperando a RabbitMQ (conexión AMQP al vhost)..."
until python -c "
import os, sys
url = os.environ.get('RABBITMQ_URL', 'amqp://auditcore:${RABBITMQ_PASSWORD:-auditcore_dev_CAMBIAR_EN_PROD}@rabbitmq:5672/auditcore?heartbeat=120')
try:
    from kombu import Connection
    with Connection(url, connect_timeout=5) as conn:
        conn.ensure_connection(max_retries=1, timeout=5)
        channel = conn.channel()
        channel.close()
    sys.exit(0)
except Exception:
    sys.exit(1)
" 2>/dev/null; do
  echo "      RabbitMQ vhost no disponible, reintentando en 3s..."
  sleep 3
done
echo "      RabbitMQ listo."

# Diagnóstico de broker: compara las 3 fuentes de URL al arrancar.
# Si las URLs no coinciden → confirma bug de decouple (ya resuelto en base.py).
# Resultado visible en consola Y en /app/logs/chatbot_ids.log con cat=BOOT.
echo "[2b/6] Diagnóstico de broker URL..."
python -c "
import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings.development')
django.setup()
from django.conf import settings
from config.celery import app

env_url      = os.environ.get('RABBITMQ_URL', '<NOT_SET>')
settings_url = getattr(settings, 'CELERY_BROKER_URL', '<NOT_SET>')
app_url      = app.conf.broker_url
match        = env_url == app_url

print(f'  env RABBITMQ_URL     : {env_url}')
print(f'  settings BROKER_URL  : {settings_url}')
print(f'  celery app.broker_url: {app_url}')
print(f'  URLs coinciden       : {match}  {\"✓ OK\" if match else \"✗ BUG — aplicar fix de base.py\"}')
" 2>&1 | sed 's/^/      /'

echo "[3/6] Aplicando migraciones..."
python manage.py migrate --noinput

echo "[4/6] Recopilando archivos estáticos..."
python manage.py collectstatic --noinput --clear 2>/dev/null || true

echo ""
echo "  ┌─────────────────────────────────────────────────────┐"
echo "  │  Primera vez? Accede al wizard de instalación:     │"
echo "  │  http://localhost:3000/setup                        │"
echo "  └─────────────────────────────────────────────────────┘"

echo "[5/6] Arrancando servidor ASGI en 0.0.0.0:8000..."
echo ""
echo "  API REST:   http://localhost:8000/api/"
echo "  Swagger:    http://localhost:8000/api/docs/"
echo "  Admin:      http://localhost:3000/admin/  (via Nginx)"
echo "  Logs IDS:   /app/logs/chatbot_ids.log"
echo ""

exec daphne -b 0.0.0.0 -p 8000 config.asgi:application
