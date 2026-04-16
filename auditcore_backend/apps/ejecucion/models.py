import uuid, hashlib
from django.db import models
from django.conf import settings


class Hallazgo(models.Model):
    TIPO_CHOICES = [
        ('HALLAZGO','Hallazgo'),('OBSERVACION','Observación'),
        ('NO_CONFORMIDAD','No Conformidad'),('OPORTUNIDAD','Oportunidad de Mejora'),
    ]
    CRITICIDAD_CHOICES = [
        ('CRITICO','Crítico'),('MAYOR','Mayor'),('MENOR','Menor'),('INFORMATIVO','Informativo'),
    ]
    ESTADO_CHOICES = [
        ('ABIERTO','Abierto'),('EN_REVISION','En Revisión'),
        ('CERRADO','Cerrado'),('ACEPTADO_CON_RIESGO','Aceptado con Riesgo'),
    ]

    id             = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    expediente     = models.ForeignKey('expedientes.Expediente', on_delete=models.CASCADE, related_name='hallazgos')
    tipo           = models.CharField(max_length=20, choices=TIPO_CHOICES, default='HALLAZGO')
    nivel_criticidad = models.CharField(max_length=15, choices=CRITICIDAD_CHOICES, default='MENOR')
    titulo         = models.CharField(max_length=300)
    descripcion    = models.TextField()
    estado         = models.CharField(max_length=20, choices=ESTADO_CHOICES, default='ABIERTO')
    fecha_limite_cierre = models.DateField(null=True, blank=True)
    reportado_por  = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name='hallazgos_reportados')
    asignado_a     = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='hallazgos_asignados')
    metadata       = models.JSONField(default=dict, blank=True)
    fecha_creacion = models.DateTimeField(auto_now_add=True)
    fecha_actualizacion = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'hallazgos'
        ordering = ['-fecha_creacion']

    def __str__(self):
        return f'[{self.nivel_criticidad}] {self.titulo}'


def evidencia_upload_path(instance, filename):
    return f'evidencias/{instance.expediente.numero_expediente}/{filename}'


class Evidencia(models.Model):
    id           = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    expediente   = models.ForeignKey('expedientes.Expediente', on_delete=models.CASCADE, related_name='evidencias')
    hallazgo     = models.ForeignKey(Hallazgo, on_delete=models.SET_NULL, null=True, blank=True, related_name='evidencias')
    archivo      = models.FileField(upload_to=evidencia_upload_path)
    nombre_original = models.CharField(max_length=255)
    tipo_archivo = models.CharField(max_length=50, blank=True)
    tamanio_bytes = models.BigIntegerField(default=0)
    hash_sha256  = models.CharField(max_length=64, blank=True)
    descripcion  = models.TextField(blank=True)
    subido_por   = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT)
    fecha_subida = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'evidencias'

    def save(self, *args, **kwargs):
        # InMemoryUploadedFile may not be seekable in all contexts
        # (e.g. after the request cycle ends or in some test environments).
        # DocumentoExpediente already had this protection — Evidencia didn't.
        if self.archivo and not self.hash_sha256:
            try:
                self.archivo.seek(0)
                sha256 = hashlib.sha256()
                for chunk in iter(lambda: self.archivo.read(8192), b''):
                    sha256.update(chunk)
                self.hash_sha256 = sha256.hexdigest()
                self.archivo.seek(0)
            except Exception:
                pass  # Si el archivo no es seekable, ignorar el hash
        super().save(*args, **kwargs)


class ChecklistEjecucion(models.Model):
    ESTADO_CHOICES = [
        ('PENDIENTE','Pendiente'),('CUMPLE','Cumple'),
        ('NO_CUMPLE','No Cumple'),('NO_APLICA','No Aplica'),
    ]

    id           = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    expediente   = models.ForeignKey('expedientes.Expediente', on_delete=models.CASCADE, related_name='checklist')
    item         = models.ForeignKey('tipos_auditoria.ChecklistItem', on_delete=models.PROTECT)
    estado       = models.CharField(max_length=10, choices=ESTADO_CHOICES, default='PENDIENTE')
    evidencia    = models.ForeignKey(Evidencia, on_delete=models.SET_NULL, null=True, blank=True)
    observacion  = models.TextField(blank=True)
    verificado_por = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True)
    fecha_verificacion = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = 'checklist_ejecucion'
        unique_together = [['expediente', 'item']]


