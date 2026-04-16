from django.apps import AppConfig


class ExpedientesConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'apps.expedientes'
    verbose_name = 'Expedientes'

    def ready(self):
        import apps.expedientes.signals  # noqa: F401 — registra señales