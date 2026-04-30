import uuid
import secrets
from django.db import models, transaction
from django.conf import settings
from django.utils import timezone
from django.contrib.auth.hashers import make_password, check_password as django_check_password


class Cliente(models.Model):
    ESTADO_CHOICES = [
        ('PROSPECTO',      'Prospecto'),
        ('EN_EVALUACION',  'En evaluación'),
        ('ACTIVO',         'Activo'),
        ('INACTIVO',       'Inactivo'),
        ('SUSPENDIDO',     'Suspendido'),
    ]
    TIPO_PERSONA_CHOICES = [
        ('JURIDICA',  'Persona Jurídica (Empresa)'),
        ('NATURAL',   'Persona Natural'),
    ]
    SECTOR_CHOICES = [
        ('TECNOLOGIA',    'Tecnología'),
        ('SALUD',         'Salud'),
        ('FINANCIERO',    'Financiero / Fintech'),
        ('MANUFACTURA',   'Manufactura / Industrial'),
        ('SERVICIOS',     'Servicios'),
        ('GOBIERNO',      'Gobierno / Sector Público'),
        ('EDUCACION',     'Educación'),
        ('ENERGIA',       'Energía y Recursos'),
        ('TRANSPORTE',    'Transporte y Logística'),
        ('CONSTRUCCION',  'Construcción e Inmobiliario'),
        ('COMERCIO',      'Comercio y Retail'),
        ('AGROPECUARIO',  'Agropecuario'),
        ('TELECOMUNICACIONES', 'Telecomunicaciones'),
        ('SEGUROS',       'Seguros'),
        ('OTRO',          'Otro'),
    ]
    TAMANO_CHOICES = [
        ('MICRO',    'Microempresa (1-10 empleados)'),
        ('PEQUENA',  'Pequeña (11-50 empleados)'),
        ('MEDIANA',  'Mediana (51-250 empleados)'),
        ('GRANDE',   'Grande (251-1000 empleados)'),
        ('CORP',     'Corporación (>1000 empleados)'),
    ]
    REGIMEN_CHOICES = [
        ('SIMPLIFICADO', 'Régimen Simplificado'),
        ('COMUN',        'Régimen Común'),
        ('ESPECIAL',     'Régimen Especial'),
        ('NO_RESPONSABLE', 'No Responsable de IVA'),
    ]
    NECESIDAD_CHOICES = [
        ('REQUERIMIENTO_LEGAL',   'Requerimiento legal / regulatorio'),
        ('REQUERIMIENTO_CLIENTE', 'Exigencia de clientes o socios'),
        ('MEJORA_CONTINUA',       'Mejora continua interna'),
        ('FALLA_INTERNA',         'Falla o incidente interno detectado'),
        ('EXPANSION',             'Expansión de mercado o certificación nueva'),
        ('RENOVACION',            'Renovación de certificación existente'),
        ('OTRO',                  'Otro'),
    ]

    id           = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    tipo_persona = models.CharField(
        max_length=10, choices=TIPO_PERSONA_CHOICES, default='JURIDICA')

    # ── Perfil Legal ───────────────────────────────────────────────────────
    razon_social        = models.CharField(max_length=255, help_text='Nombre legal completo')
    nit                 = models.CharField(max_length=30, unique=True, help_text='NIT, RUT o documento tributario')
    digito_verificacion = models.CharField(max_length=2, blank=True, help_text='Dígito de verificación del NIT')
    matricula_mercantil = models.CharField(max_length=50, blank=True)
    fecha_constitucion  = models.DateField(null=True, blank=True)
    duracion_empresa    = models.CharField(max_length=100, blank=True, help_text='Duración estimada (ej: Indefinida)')
    objeto_social       = models.TextField(blank=True, help_text='Actividad económica principal')
    codigo_ciiu         = models.CharField(max_length=10, blank=True, help_text='Código CIIU de la actividad')
    regimen_tributario  = models.CharField(
        max_length=20, choices=REGIMEN_CHOICES, blank=True)
    responsable_iva     = models.BooleanField(default=True)

    # ── Representante Legal ────────────────────────────────────────────────
    rep_legal_nombre      = models.CharField(max_length=200, blank=True)
    rep_legal_documento   = models.CharField(max_length=30, blank=True)
    rep_legal_tipo_doc    = models.CharField(max_length=10, blank=True,
                                              help_text='CC, CE, Pasaporte, NIT')
    rep_legal_cargo       = models.CharField(max_length=100, blank=True)
    rep_legal_email       = models.EmailField(blank=True)
    rep_legal_telefono    = models.CharField(max_length=20, blank=True)

    # ── Sedes y Ubicación ──────────────────────────────────────────────────
    pais            = models.CharField(max_length=100, default='Colombia')
    departamento    = models.CharField(max_length=100, blank=True)
    ciudad          = models.CharField(max_length=100, blank=True)
    direccion_principal = models.CharField(max_length=300, blank=True)
    codigo_postal   = models.CharField(max_length=10, blank=True)
    sedes_adicionales = models.JSONField(
        default=list, blank=True,
        help_text='Lista de sedes: [{nombre, ciudad, direccion, telefono}]')

    # ── Contacto General ──────────────────────────────────────────────────
    telefono        = models.CharField(max_length=20, blank=True)
    telefono_alt    = models.CharField(max_length=20, blank=True)
    email           = models.EmailField(blank=True)
    sitio_web       = models.URLField(blank=True)
    linkedin        = models.URLField(blank=True)

    # ── Segmentación ───────────────────────────────────────────────────────
    sector          = models.CharField(max_length=20, choices=SECTOR_CHOICES, default='OTRO')
    subsector       = models.CharField(max_length=100, blank=True)
    tamano          = models.CharField(max_length=10, choices=TAMANO_CHOICES, blank=True)
    num_empleados   = models.PositiveIntegerField(null=True, blank=True)
    ingresos_anuales = models.CharField(max_length=50, blank=True,
                                         help_text='Rango de ingresos anuales estimados')

    # ── Alcance del Servicio ───────────────────────────────────────────────
    tipos_auditoria_solicitados = models.JSONField(
        default=list, blank=True,
        help_text='IDs de tipos de auditoría de interés')
    alcance_descripcion = models.TextField(
        blank=True, help_text='Descripción del alcance del servicio de auditoría')
    normas_interes      = models.JSONField(
        default=list, blank=True,
        help_text='Normas de interés: ISO 27001, ISO 9001, NIIF, etc.')
    tiene_certificacion_previa = models.BooleanField(default=False)
    certificacion_previa_detalle = models.TextField(blank=True)

    # ── Declaración de Necesidad ───────────────────────────────────────────
    motivo_auditoria    = models.CharField(
        max_length=25, choices=NECESIDAD_CHOICES, blank=True)
    declaracion_necesidad = models.TextField(
        blank=True, help_text='Descripción del por qué busca la auditoría')
    urgencia            = models.CharField(
        max_length=10,
        choices=[('BAJA', 'Baja'), ('MEDIA', 'Media'), ('ALTA', 'Alta'), ('CRITICA', 'Crítica')],
        default='MEDIA', blank=True)
    fecha_limite_deseada = models.DateField(null=True, blank=True)

    # ── Estado y Flujo ─────────────────────────────────────────────────────
    estado              = models.CharField(max_length=15, choices=ESTADO_CHOICES, default='PROSPECTO')
    caracterizacion_completada = models.BooleanField(default=False)
    fecha_caracterizacion      = models.DateTimeField(null=True, blank=True)
    asesor_responsable  = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name='clientes_asesorados')

    notas               = models.TextField(blank=True)
    metadata            = models.JSONField(default=dict, blank=True)
    fecha_creacion      = models.DateTimeField(auto_now_add=True)
    fecha_actualizacion = models.DateTimeField(auto_now=True)
    creado_por          = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT,
        related_name='clientes_creados', null=True)

    class Meta:
        db_table = 'clientes'
        ordering = ['razon_social']

    def __str__(self):
        return f'{self.razon_social} ({self.nit})'


class SedeCliente(models.Model):
    id        = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    cliente   = models.ForeignKey(Cliente, on_delete=models.CASCADE, related_name='sedes')
    nombre    = models.CharField(max_length=150, help_text='Ej: Sede Bogotá, Bodega Norte')
    es_principal = models.BooleanField(default=False)
    pais      = models.CharField(max_length=100, default='Colombia')
    departamento = models.CharField(max_length=100, blank=True)
    ciudad    = models.CharField(max_length=100, blank=True)
    direccion = models.CharField(max_length=300, blank=True)
    codigo_postal = models.CharField(max_length=10, blank=True)
    telefono  = models.CharField(max_length=20, blank=True)
    email_sede = models.EmailField(blank=True)
    num_empleados = models.PositiveIntegerField(null=True, blank=True)
    responsable_nombre = models.CharField(max_length=200, blank=True)
    responsable_cargo  = models.CharField(max_length=100, blank=True)
    responsable_email  = models.EmailField(blank=True)
    responsable_telefono = models.CharField(max_length=20, blank=True)
    activa    = models.BooleanField(default=True)

    class Meta:
        db_table = 'sedes_cliente'
        ordering = ['-es_principal', 'nombre']

    def __str__(self):
        return f'{self.nombre} — {self.cliente.razon_social}'


class ContactoCliente(models.Model):
    TIPO_CHOICES = [
        ('OPERATIVO',    'Contacto Operativo / Punto de Enlace'),
        ('GERENCIAL',    'Gerencial / Directivo'),
        ('TECNICO',      'Técnico'),
        ('ADMINISTRATIVO', 'Administrativo'),
        ('JURIDICO',     'Jurídico'),
        ('FINANCIERO',   'Financiero'),
    ]

    id           = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    cliente      = models.ForeignKey(Cliente, on_delete=models.CASCADE, related_name='contactos')
    sede         = models.ForeignKey(
        SedeCliente, on_delete=models.SET_NULL, null=True, blank=True, related_name='contactos')
    tipo         = models.CharField(max_length=15, choices=TIPO_CHOICES, default='OPERATIVO')
    nombre       = models.CharField(max_length=150)
    apellido     = models.CharField(max_length=150)
    cargo        = models.CharField(max_length=100, blank=True)
    departamento = models.CharField(max_length=100, blank=True)
    email        = models.EmailField()
    telefono     = models.CharField(max_length=20, blank=True)
    telefono_ext = models.CharField(max_length=10, blank=True)
    celular      = models.CharField(max_length=20, blank=True)
    es_principal     = models.BooleanField(default=False)
    recibe_informes  = models.BooleanField(default=True,
                        help_text='Recibirá los formularios e informes de auditoría')
    recibe_notificaciones = models.BooleanField(default=True)
    notas        = models.TextField(blank=True)

    class Meta:
        db_table = 'contactos_cliente'
        ordering = ['-es_principal', 'nombre']

    def save(self, *args, **kwargs):
        if self.es_principal:
            with transaction.atomic():
                ContactoCliente.objects.filter(
                    cliente=self.cliente, es_principal=True
                ).exclude(pk=self.pk).update(es_principal=False)
                super().save(*args, **kwargs)
        else:
            super().save(*args, **kwargs)

    def __str__(self):
        return f'{self.nombre} {self.apellido} ({self.tipo}) — {self.cliente.razon_social}'

    @property
    def nombre_completo(self):
        return f'{self.nombre} {self.apellido}'


class AccesoTemporalCaracterizacion(models.Model):
    """
    Token de acceso temporal que se envía al cliente para que complete
    el formulario de caracterización sin necesidad de crear una cuenta.
    Expira en 7 días. Solo puede usarse una vez.
    """
    id         = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    cliente    = models.ForeignKey(Cliente, on_delete=models.CASCADE, related_name='accesos_temporales')
    contacto   = models.ForeignKey(
        ContactoCliente, on_delete=models.SET_NULL, null=True, blank=True)
    token      = models.CharField(max_length=64, unique=True, db_index=True)
    email_destino = models.EmailField()
    creado_por = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name='accesos_generados')
    creado_en  = models.DateTimeField(auto_now_add=True)
    expira_en  = models.DateTimeField()
    usado      = models.BooleanField(default=False)
    usado_en   = models.DateTimeField(null=True, blank=True)
    ip_uso     = models.GenericIPAddressField(null=True, blank=True)

    class Meta:
        db_table = 'accesos_temporales_caracterizacion'

    def save(self, *args, **kwargs):
        if not self.token:
            self.token = secrets.token_urlsafe(48)
        if not self.expira_en:
            self.expira_en = timezone.now() + timezone.timedelta(days=7)
        super().save(*args, **kwargs)

    @property
    def esta_vigente(self):
        return not self.usado and timezone.now() < self.expira_en

    def usar(self, ip=None):
        self.usado    = True
        self.usado_en = timezone.now()
        self.ip_uso   = ip
        self.save(update_fields=['usado', 'usado_en', 'ip_uso'])

    def __str__(self):
        return f'Acceso {self.cliente.razon_social} → {self.email_destino}'


class UsuarioCliente(models.Model):
    """
    Cuenta de portal para el cliente. Se crea automáticamente cuando
    se activa el cliente y se vincula a su contacto principal.
    """
    id        = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    contacto  = models.OneToOneField(
        ContactoCliente, on_delete=models.CASCADE, related_name='usuario')
    email     = models.EmailField(unique=True)
    password  = models.CharField(max_length=128)
    activo    = models.BooleanField(default=True)
    ultimo_acceso = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = 'usuarios_cliente'

    def __str__(self):
        return f'Portal: {self.email}'

    def set_password(self, raw_password: str) -> None:
        self.password = make_password(raw_password)

    def check_password(self, raw_password: str) -> bool:
        return django_check_password(raw_password, self.password)
