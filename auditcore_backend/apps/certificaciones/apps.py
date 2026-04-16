from django.apps import AppConfig


class CertificacionesConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'apps.certificaciones'

    def ready(self):
        # FIX: importar models para garantizar que el @receiver(post_save, sender=Certificacion)
        # definido en models.py quede registrado antes de que cualquier señal se dispare.
        # Sin ready(), la señal solo se registra si models.py es importado casualmente,
        # lo que en producción con múltiples workers puede no ocurrir a tiempo.
        import apps.certificaciones.models  # noqa: F401
