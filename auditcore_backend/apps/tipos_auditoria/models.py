import uuid
from django.db import models


class TipoAuditoria(models.Model):
    CATEGORIA_CHOICES = [('SEGURIDAD','Seguridad'),('CALIDAD','Calidad'),('AMBIENTAL','Ambiental'),('FINANCIERO','Financiero'),('OTRO','Otro')]
    CERT_CHOICES      = [('PROPIA','Propia'),('EXTERNA','Externa'),('AMBAS','Ambas')]
    NIVEL_CHOICES     = [('BASICO','Básico'),('INTERMEDIO','Intermedio'),('AVANZADO','Avanzado')]

    id                  = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    codigo              = models.CharField(max_length=20, unique=True)
    nombre              = models.CharField(max_length=200)
    descripcion         = models.TextField(blank=True)
    categoria           = models.CharField(max_length=20, choices=CATEGORIA_CHOICES, default='OTRO')
    nivel               = models.CharField(max_length=15, choices=NIVEL_CHOICES, default='BASICO')
    certificacion_tipo  = models.CharField(max_length=10, choices=CERT_CHOICES, default='PROPIA')
    duracion_estimada_dias = models.PositiveIntegerField(default=30)
    version             = models.CharField(max_length=10, default='1.0')
    activo              = models.BooleanField(default=True)
    fecha_creacion      = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'tipos_auditoria'
        ordering = ['nombre']

    def __str__(self):
        return f'{self.codigo} — {self.nombre}'


class FaseTipoAuditoria(models.Model):
    id               = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    tipo_auditoria   = models.ForeignKey(TipoAuditoria, on_delete=models.CASCADE, related_name='fases')
    nombre           = models.CharField(max_length=100)
    descripcion      = models.TextField(blank=True)
    orden            = models.PositiveIntegerField()
    duracion_estimada_dias = models.PositiveIntegerField(default=7)
    es_fase_final    = models.BooleanField(default=False)

    class Meta:
        db_table = 'fases_tipo_auditoria'
        ordering = ['tipo_auditoria', 'orden']

    def __str__(self):
        return f'{self.tipo_auditoria.codigo} — Fase {self.orden}: {self.nombre}'


class ChecklistItem(models.Model):
    CATEGORIA_CHOICES = [('DOCUMENTAL','Documental'),('TECNICO','Técnico'),('LEGAL','Legal'),('OPERACIONAL','Operacional')]

    id             = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    tipo_auditoria = models.ForeignKey(TipoAuditoria, on_delete=models.CASCADE, related_name='checklist_items')
    fase           = models.ForeignKey(FaseTipoAuditoria, on_delete=models.SET_NULL, null=True, blank=True, related_name='items')
    codigo         = models.CharField(max_length=20)
    descripcion    = models.TextField()
    categoria      = models.CharField(max_length=15, choices=CATEGORIA_CHOICES, default='DOCUMENTAL')
    obligatorio    = models.BooleanField(default=True)
    orden          = models.PositiveIntegerField(default=0)

    class Meta:
        db_table = 'checklist_items'
        ordering = ['tipo_auditoria', 'orden']


class DocumentoRequerido(models.Model):
    id             = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    tipo_auditoria = models.ForeignKey(TipoAuditoria, on_delete=models.CASCADE, related_name='documentos_requeridos')
    nombre         = models.CharField(max_length=200)
    descripcion    = models.TextField(blank=True)
    obligatorio    = models.BooleanField(default=True)
    orden          = models.PositiveIntegerField(default=0)

    class Meta:
        db_table = 'documentos_requeridos'
        ordering = ['tipo_auditoria', 'orden']