import uuid, hashlib
from django.db import models
from django.conf import settings


def doc_upload_path(instance, filename):
    return f'documentos/{instance.expediente.numero_expediente}/{filename}'


class DocumentoExpediente(models.Model):
    ESTADO_CHOICES = [
        ('PENDIENTE','Pendiente'), ('RECIBIDO','Recibido'),
        ('APROBADO','Aprobado'), ('RECHAZADO','Rechazado'), ('VENCIDO','Vencido'),
    ]

    id                   = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    expediente           = models.ForeignKey('expedientes.Expediente', on_delete=models.CASCADE, related_name='documentos')
    documento_requerido  = models.ForeignKey('tipos_auditoria.DocumentoRequerido', on_delete=models.PROTECT, null=True, blank=True)
    nombre               = models.CharField(max_length=255)
    archivo              = models.FileField(upload_to=doc_upload_path, null=True, blank=True)
    hash_sha256          = models.CharField(max_length=64, blank=True)
    estado               = models.CharField(max_length=10, choices=ESTADO_CHOICES, default='PENDIENTE')
    version              = models.PositiveIntegerField(default=1)
    revisado_por         = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='documentos_revisados')
    fecha_revision       = models.DateTimeField(null=True, blank=True)
    observacion_revision = models.TextField(blank=True)
    subido_por           = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name='documentos_subidos')
    fecha_subida         = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'documentos_expediente'
        ordering = ['expediente', 'nombre', '-version']

    def save(self, *args, **kwargs):


        if not self.pk and self.documento_requerido:
            existente = DocumentoExpediente.objects.filter(
                expediente=self.expediente,
                documento_requerido=self.documento_requerido,
            ).order_by('-version').first()
            if existente:
                self.version = existente.version + 1


        if self.archivo and not self.hash_sha256:
            try:
                self.archivo.seek(0)
                sha256 = hashlib.sha256()
                for chunk in iter(lambda: self.archivo.read(8192), b''):
                    sha256.update(chunk)
                self.hash_sha256 = sha256.hexdigest()
                self.archivo.seek(0)
            except Exception:
                pass

        super().save(*args, **kwargs)
