#!/bin/sh
set -e

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║           AuditCore — Celery Worker/Beat             ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# Crear directorio de logs IDS para el worker.
mkdir -p /app/logs && chmod 755 /app/logs
echo "  [IDS] Logs en /app/logs/chatbot_ids.log"

echo "[1/2] Esperando a RabbitMQ..."
until python -c "
import os, sys
url = os.environ.get('RABBITMQ_URL', 'amqp://auditcore:${RABBITMQ_PASSWORD:-auditcore_dev_CAMBIAR_EN_PROD}@rabbitmq:5672/auditcore?heartbeat=120')
try:
    from kombu import Connection
    with Connection(url, connect_timeout=5) as conn:
        conn.ensure_connection(max_retries=1, timeout=5)
        conn.channel().close()
    sys.exit(0)
except Exception:
    sys.exit(1)
" 2>/dev/null; do
  echo "      RabbitMQ no disponible, reintentando en 3s..."
  sleep 3
done
echo "      RabbitMQ listo."

echo "[2/2] Iniciando $@"
exec "$@"
