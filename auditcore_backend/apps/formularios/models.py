import uuid
from django.db import models
from django.conf import settings


class EsquemaFormulario(models.Model):
    CONTEXTO_CHOICES = [
        ('EXPEDIENTE', 'Expediente'),
        ('HALLAZGO',   'Hallazgo'),
        ('DOCUMENTO',  'Documento'),
        ('CLIENTE',    'Cliente'),
    ]
    ORIGEN_CHOICES = [
        ('MANUAL',    'Creado manualmente'),
        ('BOT_PDF',   'Importado desde PDF via bot'),
        ('BOT_WORD',  'Importado desde Word via bot'),
        ('BOT_EXCEL', 'Importado desde Excel via bot'),
    ]

    id             = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    nombre         = models.CharField(max_length=200)
    descripcion    = models.TextField(blank=True)
    contexto       = models.CharField(max_length=15, choices=CONTEXTO_CHOICES)
    tipo_auditoria = models.ForeignKey(
        'tipos_auditoria.TipoAuditoria',
        on_delete=models.SET_NULL, null=True, blank=True,
        related_name='formularios',
    )
    version        = models.PositiveIntegerField(default=1)
    activo         = models.BooleanField(default=True)
    origen         = models.CharField(max_length=10, choices=ORIGEN_CHOICES, default='MANUAL')
    creado_por     = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name='formularios_creados',
    )
    fecha_creacion = models.DateTimeField(auto_now_add=True)
    fecha_actualizacion = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'esquemas_formulario'
        ordering = ['-fecha_creacion']

    def __str__(self):
        return f'{self.nombre} v{self.version}'


class CampoFormulario(models.Model):
    TIPO_CHOICES = [
        ('TEXTO',    'Texto libre'),
        ('NUMERO',   'Número'),
        ('FECHA',    'Fecha'),
        ('LISTA',    'Lista de opciones'),
        ('BOOLEANO', 'Sí / No'),
        ('ARCHIVO',  'Archivo adjunto'),
        ('FIRMA',    'Firma'),
        ('TABLA',    'Tabla de datos'),
    ]

    id           = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    esquema      = models.ForeignKey(EsquemaFormulario, on_delete=models.CASCADE, related_name='campos')
    nombre       = models.CharField(max_length=100)
    etiqueta     = models.CharField(max_length=200)
    tipo         = models.CharField(max_length=10, choices=TIPO_CHOICES)
    obligatorio  = models.BooleanField(default=False)
    orden        = models.PositiveIntegerField(default=0)
    opciones     = models.JSONField(default=list, blank=True)
    validaciones = models.JSONField(default=dict, blank=True)
    activo       = models.BooleanField(default=True)
    ayuda        = models.CharField(max_length=300, blank=True, help_text='Texto de ayuda visible al auditor')

    class Meta:
        db_table = 'campos_formulario'
        ordering = ['esquema', 'orden']

    def __str__(self):
        return f'{self.etiqueta} ({self.tipo})'


class ValorFormulario(models.Model):
    id           = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    esquema      = models.ForeignKey(EsquemaFormulario, on_delete=models.PROTECT)
    entidad_tipo = models.CharField(max_length=50)
    entidad_id   = models.UUIDField()
    valores      = models.JSONField(default=dict)
    creado_por   = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, null=True)
    fecha_creacion      = models.DateTimeField(auto_now_add=True)
    fecha_actualizacion = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'valores_formulario'
        indexes  = [models.Index(fields=['entidad_tipo', 'entidad_id'])]

    def __str__(self):
        return f'{self.esquema.nombre} → {self.entidad_tipo}:{self.entidad_id}'
