import uuid
from django.db import models
from django.conf import settings


class Conversacion(models.Model):
    CANAL_CHOICES  = [('WEB','Web'),('MOVIL','Móvil'),('INTERNO','Interno')]
    ESTADO_CHOICES = [('ACTIVA','Activa'),('ARCHIVADA','Archivada'),('CERRADA','Cerrada')]

    id             = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    cliente        = models.ForeignKey('clientes.Cliente', on_delete=models.CASCADE, null=True, blank=True, related_name='conversaciones')
    usuario_interno = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, null=True, blank=True, related_name='conversaciones')
    expediente     = models.ForeignKey('expedientes.Expediente', on_delete=models.SET_NULL, null=True, blank=True, related_name='conversaciones')
    canal          = models.CharField(max_length=8, choices=CANAL_CHOICES, default='WEB')
    estado         = models.CharField(max_length=10, choices=ESTADO_CHOICES, default='ACTIVA')
    fecha_creacion = models.DateTimeField(auto_now_add=True)
    fecha_actualizacion = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'conversaciones'
        ordering = ['-fecha_actualizacion']


class MensajeConversacion(models.Model):
    ROL_CHOICES = [('USUARIO','Usuario'),('ASISTENTE','Asistente'),('SISTEMA','Sistema')]

    id           = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    conversacion = models.ForeignKey(Conversacion, on_delete=models.CASCADE, related_name='mensajes')
    rol          = models.CharField(max_length=10, choices=ROL_CHOICES)
    contenido    = models.TextField()
    tokens_usados = models.PositiveIntegerField(default=0)
    metadata     = models.JSONField(default=dict, blank=True)
    fecha        = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'mensajes_conversacion'
        ordering = ['conversacion', 'fecha']