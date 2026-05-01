from django.apps import AppConfig


class CertificacionesConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'apps.certificaciones'

    def ready(self):


        import apps.certificaciones.models
