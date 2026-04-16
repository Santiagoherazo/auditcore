import uuid
from django.db import models, transaction
from django.conf import settings


class Expediente(models.Model):
    ESTADO_CHOICES = [
        ('BORRADOR','Borrador'), ('ACTIVO','Activo'), ('EN_EJECUCION','En Ejecución'),
        ('COMPLETADO','Completado'), ('CANCELADO','Cancelado'), ('SUSPENDIDO','Suspendido'),
    ]
    ORIGEN_CHOICES = [('NUEVO','Nuevo'), ('RENOVACION','Renovación'), ('SEGUIMIENTO','Seguimiento')]

    id                    = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    numero_expediente     = models.CharField(max_length=20, unique=True, editable=False)
    cliente               = models.ForeignKey('clientes.Cliente', on_delete=models.PROTECT, related_name='expedientes')
    tipo_auditoria        = models.ForeignKey('tipos_auditoria.TipoAuditoria', on_delete=models.PROTECT)
    estado                = models.CharField(max_length=15, choices=ESTADO_CHOICES, default='BORRADOR')
    tipo_origen           = models.CharField(max_length=15, choices=ORIGEN_CHOICES, default='NUEVO')
    expediente_origen     = models.ForeignKey('self', on_delete=models.SET_NULL, null=True, blank=True, related_name='renovaciones')
    auditor_lider         = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name='expedientes_lider')
    ejecutivo             = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='expedientes_ejecutivo')
    fecha_apertura        = models.DateField(auto_now_add=True)
    fecha_estimada_cierre = models.DateField(null=True, blank=True)
    fecha_cierre_real     = models.DateField(null=True, blank=True)
    porcentaje_avance     = models.DecimalField(max_digits=5, decimal_places=2, default=0)
    notas                 = models.TextField(blank=True)
    metadata              = models.JSONField(default=dict, blank=True)
    fecha_creacion        = models.DateTimeField(auto_now_add=True)
    fecha_actualizacion   = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'expedientes'
        ordering = ['-fecha_creacion']

    def save(self, *args, **kwargs):
        if not self.numero_expediente:
            # Generar número de expediente de forma segura.
            # NO usamos select_for_update sobre fecha_creacion porque ese campo
            # aún no existe cuando el objeto es nuevo (auto_now_add, pre-INSERT).
            # Usamos MAX sobre el string numero_expediente — funciona correctamente
            # antes del INSERT y dentro de un atomic block evita duplicados.
            with transaction.atomic():
                from django.utils import timezone
                from django.db.models import Max
                year = timezone.now().year
                prefix = f'EXP-{year}-'
                last = (
                    Expediente.objects
                    .filter(numero_expediente__startswith=prefix)
                    .aggregate(last=Max('numero_expediente'))['last']
                )
                if last:
                    try:
                        last_num = int(last.split('-')[-1])
                    except (ValueError, IndexError):
                        last_num = 0
                    count = last_num + 1
                else:
                    count = 1
                self.numero_expediente = f'{prefix}{count:04d}'
        super().save(*args, **kwargs)

    def __str__(self):
        return f'{self.numero_expediente} — {self.cliente.razon_social}'

    def calcular_avance(self):
        from apps.ejecucion.models import ChecklistEjecucion
        from decimal import Decimal
        items = ChecklistEjecucion.objects.filter(expediente=self)
        total = items.count()
        if total == 0:
            return 0
        completados = items.exclude(estado='PENDIENTE').count()
        nuevo_avance = round((completados / total) * 100, 2)
        # self.porcentaje_avance viene de la BD como Decimal (DecimalField).
        # nuevo_avance es un float. Decimal('33.33') != 33.33 (float) en Python,
        # lo que causaba que la comparación siempre devolviera False y se escribiera
        # a la BD en cada llamada, incluso cuando el valor no había cambiado.
        if self.porcentaje_avance != Decimal(str(nuevo_avance)):
            self.porcentaje_avance = nuevo_avance
            Expediente.objects.filter(pk=self.pk).update(porcentaje_avance=nuevo_avance)
        return nuevo_avance


class FaseExpediente(models.Model):
    ESTADO_CHOICES = [
        ('PENDIENTE','Pendiente'), ('EN_CURSO','En Curso'),
        ('COMPLETADA','Completada'), ('OMITIDA','Omitida'),
    ]

    id           = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    expediente   = models.ForeignKey(Expediente, on_delete=models.CASCADE, related_name='fases')
    fase_tipo    = models.ForeignKey('tipos_auditoria.FaseTipoAuditoria', on_delete=models.PROTECT)
    estado       = models.CharField(max_length=12, choices=ESTADO_CHOICES, default='PENDIENTE')
    fecha_inicio = models.DateField(null=True, blank=True)
    fecha_fin    = models.DateField(null=True, blank=True)
    observaciones = models.TextField(blank=True)

    class Meta:
        db_table = 'fases_expediente'
        ordering = ['expediente', 'fase_tipo__orden']


class AsignacionEquipo(models.Model):
    ROL_CHOICES = [('LIDER','Líder'), ('AUDITOR','Auditor'), ('APOYO','Apoyo'), ('REVISOR','Revisor')]

    id               = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    expediente       = models.ForeignKey(Expediente, on_delete=models.CASCADE, related_name='equipo')
    usuario          = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT)
    rol              = models.CharField(max_length=10, choices=ROL_CHOICES)
    fecha_asignacion = models.DateField(auto_now_add=True)
    activo           = models.BooleanField(default=True)

    class Meta:
        db_table = 'asignaciones_equipo'
        unique_together = [['expediente', 'usuario']]


class BitacoraExpediente(models.Model):
    TIPO_USUARIO_CHOICES = [
        ('INTERNO','Interno'), ('CLIENTE','Cliente'), ('SISTEMA','Sistema'),
    ]

    id               = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    expediente       = models.ForeignKey(Expediente, on_delete=models.CASCADE, related_name='bitacora')
    tipo_usuario     = models.CharField(max_length=10, choices=TIPO_USUARIO_CHOICES)
    usuario_interno  = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, null=True, blank=True)
    accion           = models.CharField(max_length=100)
    descripcion      = models.TextField()
    entidad_afectada = models.CharField(max_length=50, blank=True)
    metadata         = models.JSONField(default=dict, blank=True)
    fecha            = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'bitacora_expediente'
        ordering = ['-fecha']

    def save(self, *args, **kwargs):
        if self.pk:
            raise ValueError('La bitácora es inmutable. No se puede editar.')
        super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        raise ValueError('La bitácora es inmutable. No se puede eliminar.')

    @classmethod
    def registrar(cls, expediente, accion, descripcion, usuario=None, entidad='', metadata=None):
        return cls.objects.create(
            expediente=expediente,
            tipo_usuario='INTERNO' if usuario else 'SISTEMA',
            usuario_interno=usuario,
            accion=accion,
            descripcion=descripcion,
            entidad_afectada=entidad,
            metadata=metadata or {},
        )


class VisitaAgendada(models.Model):
    """
    Visita de auditoría agendada — conectada con FaseExpediente.

    Punto 5: El calendario muestra las visitas agendadas por expediente/fase.
    Una visita corresponde a una fase o sub-actividad planificada.
    Eliminación virtual: estado = CANCELADA.
    """
    TIPO_CHOICES = [
        ('APERTURA',     'Reunión de apertura'),
        ('CAMPO',        'Visita en campo'),
        ('DOCUMENTACION','Revisión de documentación'),
        ('SEGUIMIENTO',  'Seguimiento de hallazgos'),
        ('CIERRE',       'Reunión de cierre'),
        ('OTRO',         'Otro'),
    ]
    ESTADO_CHOICES = [
        ('PROGRAMADA',  'Programada'),
        ('CONFIRMADA',  'Confirmada'),
        ('REALIZADA',   'Realizada'),
        ('REPROGRAMADA','Reprogramada'),
        ('CANCELADA',   'Cancelada'),
    ]

    id               = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    expediente       = models.ForeignKey(
        Expediente, on_delete=models.CASCADE, related_name='visitas'
    )
    fase             = models.ForeignKey(
        FaseExpediente, on_delete=models.SET_NULL,
        null=True, blank=True, related_name='visitas',
        help_text='Fase del cronograma a la que corresponde esta visita',
    )
    tipo             = models.CharField(max_length=15, choices=TIPO_CHOICES, default='CAMPO')
    titulo           = models.CharField(max_length=200)
    descripcion      = models.TextField(blank=True)
    fecha_inicio     = models.DateTimeField()
    fecha_fin        = models.DateTimeField()
    lugar            = models.CharField(max_length=300, blank=True)
    estado           = models.CharField(max_length=12, choices=ESTADO_CHOICES, default='PROGRAMADA')
    creado_por       = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, related_name='visitas_creadas',
    )
    participantes    = models.ManyToManyField(
        settings.AUTH_USER_MODEL, blank=True, related_name='visitas_asignadas',
        help_text='Auditores que participan en esta visita',
    )
    notas_resultado  = models.TextField(blank=True, help_text='Notas post-visita')
    fecha_creacion   = models.DateTimeField(auto_now_add=True)
    fecha_actualizacion = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'visitas_agendadas'
        ordering = ['fecha_inicio']

    def __str__(self):
        return f'{self.titulo} — {self.expediente.numero_expediente} ({self.fecha_inicio.date()})'

    @property
    def duracion_horas(self):
        delta = self.fecha_fin - self.fecha_inicio
        return round(delta.total_seconds() / 3600, 1)
