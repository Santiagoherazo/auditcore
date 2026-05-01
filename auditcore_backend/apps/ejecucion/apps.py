from django.apps import AppConfig


class EjecucionConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'apps.ejecucion'
    verbose_name = 'Ejecución'

    def ready(self):
        import apps.ejecucion.signals