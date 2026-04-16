import uuid, secrets
from django.db import models
from django.conf import settings
from django.db.models.signals import post_save
from django.dispatch import receiver
from django.utils import timezone


def cert_upload_path(instance, filename):
    return f'certificados/{instance.cliente.nit}/{filename}'


class Certificacion(models.Model):
    ESTADO_CHOICES = [
        ('VIGENTE','Vigente'),('POR_VENCER','Por Vencer'),
        ('VENCIDA','Vencida'),('REVOCADA','Revocada'),
    ]
    EMISION_CHOICES = [('PROPIA','Propia'),('EXTERNA','Externa')]

    id                 = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    numero             = models.CharField(max_length=20, unique=True, editable=False)
    expediente         = models.OneToOneField('expedientes.Expediente', on_delete=models.PROTECT, related_name='certificacion')
    cliente            = models.ForeignKey('clientes.Cliente', on_delete=models.PROTECT, related_name='certificaciones')
    tipo_auditoria     = models.ForeignKey('tipos_auditoria.TipoAuditoria', on_delete=models.PROTECT)
    codigo_verificacion = models.CharField(max_length=64, unique=True, editable=False)
    tipo_emision       = models.CharField(max_length=8, choices=EMISION_CHOICES, default='PROPIA')
    ente_certificador  = models.CharField(max_length=200, blank=True)
    fecha_emision      = models.DateField()
    fecha_vencimiento  = models.DateField()
    estado             = models.CharField(max_length=12, choices=ESTADO_CHOICES, default='VIGENTE')
    certificado_pdf    = models.FileField(upload_to=cert_upload_path, null=True, blank=True)
    hash_documento     = models.CharField(max_length=64, blank=True)
    emitido_por        = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT)
    metadata           = models.JSONField(default=dict, blank=True)
    fecha_creacion     = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'certificaciones'
        ordering = ['-fecha_emision']

    def save(self, *args, **kwargs):
        if not self.numero:
            # FIX: usar MAX sobre el string para evitar race conditions,
            # igual que en Expediente. count() puede dar duplicados concurrentes.
            from django.db import transaction as db_transaction
            from django.db.models import Max
            with db_transaction.atomic():
                year = timezone.now().year
                prefix = f'CERT-{year}-'
                last = (
                    Certificacion.objects
                    .filter(numero__startswith=prefix)
                    .aggregate(last=Max('numero'))['last']
                )
                if last:
                    try:
                        last_num = int(last.split('-')[-1])
                    except (ValueError, IndexError):
                        last_num = 0
                    count = last_num + 1
                else:
                    count = 1
                self.numero = f'{prefix}{count:04d}'
        if not self.codigo_verificacion:
            self.codigo_verificacion = secrets.token_urlsafe(32)
        super().save(*args, **kwargs)

    @property
    def dias_para_vencer(self):
        # FIX: proteger contra fecha_vencimiento None (datos corruptos o migración parcial).
        # Sin esta guarda, cualquier endpoint que serialice la certificación lanza TypeError → 500.
        if not self.fecha_vencimiento:
            return None
        return (self.fecha_vencimiento - timezone.now().date()).days

    def __str__(self):
        return f'{self.numero} — {self.cliente.razon_social}'


# AlertaCertificacion must be defined BEFORE the signal that references it
class AlertaCertificacion(models.Model):
    TIPO_CHOICES = [('90_DIAS','90 días'),('60_DIAS','60 días'),('30_DIAS','30 días'),('VENCIDA','Vencida')]
    CANAL_CHOICES = [('EMAIL','Email'),('PUSH','Push'),('SISTEMA','Sistema'),('TODOS','Todos')]

    id               = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    certificacion    = models.ForeignKey(Certificacion, on_delete=models.CASCADE, related_name='alertas')
    tipo_alerta      = models.CharField(max_length=10, choices=TIPO_CHOICES)
    fecha_programada = models.DateField()
    enviada          = models.BooleanField(default=False)
    fecha_enviada    = models.DateTimeField(null=True, blank=True)
    canal            = models.CharField(max_length=8, choices=CANAL_CHOICES, default='TODOS')

    class Meta:
        db_table = 'alertas_certificacion'


# Signal defined AFTER AlertaCertificacion so the class is available
@receiver(post_save, sender=Certificacion)
def crear_alertas_automaticas(sender, instance, created, **kwargs):
    if created:
        from datetime import timedelta
        alertas = [
            ('90_DIAS', instance.fecha_vencimiento - timedelta(days=90)),
            ('60_DIAS', instance.fecha_vencimiento - timedelta(days=60)),
            ('30_DIAS', instance.fecha_vencimiento - timedelta(days=30)),
            ('VENCIDA', instance.fecha_vencimiento),
        ]
        for tipo, fecha in alertas:
            AlertaCertificacion.objects.create(
                certificacion=instance,
                tipo_alerta=tipo,
                fecha_programada=fecha,
            )
