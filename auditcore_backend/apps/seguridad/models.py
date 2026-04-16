import uuid
from django.db import models
from django.conf import settings


class AuditLogSistema(models.Model):
    TIPO_USUARIO_CHOICES = [('INTERNO','Interno'),('CLIENTE','Cliente'),('SISTEMA','Sistema')]
    RESULTADO_CHOICES    = [('EXITOSO','Exitoso'),('FALLIDO','Fallido'),('DENEGADO','Denegado')]

    id           = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    usuario      = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True)
    tipo_usuario = models.CharField(max_length=10, choices=TIPO_USUARIO_CHOICES, default='INTERNO')
    ip_origen    = models.GenericIPAddressField(null=True, blank=True)
    user_agent   = models.CharField(max_length=500, blank=True)
    accion       = models.CharField(max_length=100)
    recurso      = models.CharField(max_length=100, blank=True)
    recurso_id   = models.CharField(max_length=100, blank=True)
    resultado    = models.CharField(max_length=10, choices=RESULTADO_CHOICES, default='EXITOSO')
    detalle      = models.JSONField(default=dict, blank=True)
    fecha        = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table  = 'audit_log_sistema'
        ordering  = ['-fecha']

    def save(self, *args, **kwargs):
        if self.pk:
            raise ValueError('AuditLog es inmutable. No se puede editar.')
        super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        raise ValueError('AuditLog es inmutable. No se puede eliminar.')

    @classmethod
    def registrar(cls, accion, usuario=None, ip=None, user_agent='',
                  recurso='', recurso_id='', resultado='EXITOSO', detalle=None):
        return cls.objects.create(
            usuario=usuario,
            tipo_usuario='INTERNO' if usuario else 'SISTEMA',
            ip_origen=ip,
            user_agent=user_agent,
            accion=accion,
            recurso=recurso,
            recurso_id=str(recurso_id),
            resultado=resultado,
            detalle=detalle or {},
        )