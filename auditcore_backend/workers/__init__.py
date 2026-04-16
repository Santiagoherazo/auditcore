# FIX: importar todos los módulos de tareas explícitamente.
# Garantiza que los @shared_task queden registrados en cualquier contexto
# (worker Celery, proceso Django/Daphne, tests) independientemente de cómo
# se inicialice la app de Celery.
from workers import chatbot, chat_context, notificaciones, reportes  # noqa: F401
