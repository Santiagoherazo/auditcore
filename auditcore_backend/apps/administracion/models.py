import uuid
from django.contrib.auth.models import AbstractBaseUser, BaseUserManager, PermissionsMixin
from django.db import models


PERM_CLIENTES_VER          = 'clientes.ver'
PERM_CLIENTES_CREAR        = 'clientes.crear'
PERM_CLIENTES_EDITAR       = 'clientes.editar'
PERM_EXPEDIENTES_VER       = 'expedientes.ver'
PERM_EXPEDIENTES_CREAR     = 'expedientes.crear'
PERM_EXPEDIENTES_EDITAR    = 'expedientes.editar'
PERM_HALLAZGOS_VER         = 'hallazgos.ver'
PERM_HALLAZGOS_CREAR       = 'hallazgos.crear'
PERM_HALLAZGOS_EDITAR      = 'hallazgos.editar'
PERM_DOCUMENTOS_VER        = 'documentos.ver'
PERM_DOCUMENTOS_APROBAR    = 'documentos.aprobar'
PERM_CERTIFICACIONES_VER   = 'certificaciones.ver'
PERM_CERTIFICACIONES_EMITIR = 'certificaciones.emitir'
PERM_FORMULARIOS_VER       = 'formularios.ver'
PERM_FORMULARIOS_CREAR     = 'formularios.crear'
PERM_FORMULARIOS_EDITAR    = 'formularios.editar'
PERM_REPORTES_VER          = 'reportes.ver'
PERM_REPORTES_EXPORTAR     = 'reportes.exportar'
PERM_PROCEDIMIENTOS_VER    = 'procedimientos.ver'
PERM_PROCEDIMIENTOS_CREAR  = 'procedimientos.crear'


PERMISOS_POR_ROL = {
    'SUPERVISOR': [
        'usuarios.ver', 'usuarios.crear', 'usuarios.editar', 'usuarios.eliminar',
        PERM_CLIENTES_VER, PERM_CLIENTES_CREAR, PERM_CLIENTES_EDITAR,
        PERM_EXPEDIENTES_VER, PERM_EXPEDIENTES_CREAR, PERM_EXPEDIENTES_EDITAR,
        PERM_HALLAZGOS_VER, PERM_HALLAZGOS_CREAR, PERM_HALLAZGOS_EDITAR,
        PERM_DOCUMENTOS_VER, PERM_DOCUMENTOS_APROBAR,
        PERM_CERTIFICACIONES_VER, PERM_CERTIFICACIONES_EMITIR,
        PERM_FORMULARIOS_VER, PERM_FORMULARIOS_CREAR, PERM_FORMULARIOS_EDITAR,
        PERM_REPORTES_VER, PERM_REPORTES_EXPORTAR,
        PERM_PROCEDIMIENTOS_VER, PERM_PROCEDIMIENTOS_CREAR,
        'caracterizacion.ver', 'caracterizacion.aprobar',
        'acceso_temporal.crear',
    ],
    'ASESOR': [
        PERM_CLIENTES_VER, PERM_CLIENTES_CREAR, PERM_CLIENTES_EDITAR,
        PERM_EXPEDIENTES_VER,
        PERM_CERTIFICACIONES_VER,
        PERM_FORMULARIOS_VER,
        PERM_REPORTES_VER,
        'caracterizacion.ver',
        'acceso_temporal.crear',
    ],
    'AUDITOR': [
        PERM_CLIENTES_VER,
        PERM_EXPEDIENTES_VER, PERM_EXPEDIENTES_CREAR, PERM_EXPEDIENTES_EDITAR,
        PERM_HALLAZGOS_VER, PERM_HALLAZGOS_CREAR, PERM_HALLAZGOS_EDITAR,
        PERM_DOCUMENTOS_VER, PERM_DOCUMENTOS_APROBAR,
        PERM_CERTIFICACIONES_VER, PERM_CERTIFICACIONES_EMITIR,
        PERM_FORMULARIOS_VER,
        PERM_PROCEDIMIENTOS_VER, PERM_PROCEDIMIENTOS_CREAR,
        PERM_REPORTES_VER,
    ],
    'AUXILIAR': [
        PERM_EXPEDIENTES_VER,
        PERM_HALLAZGOS_VER,
        PERM_DOCUMENTOS_VER,
        PERM_FORMULARIOS_VER,
        PERM_PROCEDIMIENTOS_VER, PERM_PROCEDIMIENTOS_CREAR,
        PERM_REPORTES_VER,
    ],
    'REVISOR': [
        PERM_CLIENTES_VER,
        PERM_EXPEDIENTES_VER,
        PERM_HALLAZGOS_VER,
        PERM_DOCUMENTOS_VER,
        PERM_CERTIFICACIONES_VER,
        PERM_FORMULARIOS_VER,
        PERM_PROCEDIMIENTOS_VER,
        PERM_REPORTES_VER, PERM_REPORTES_EXPORTAR,
    ],
    'CLIENTE': [
        'expedientes.ver_propio',
        'certificaciones.ver_propio',
        'documentos.ver_propio',
        'reportes.ver_propio',
        'caracterizacion.llenar',
    ],
}


class UsuarioInternoManager(BaseUserManager):
    def create_user(self, email, password=None, **extra):
        if not email:
            raise ValueError('El email es obligatorio')
        email = self.normalize_email(email)
        user = self.model(email=email, **extra)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, email, password=None, **extra):
        extra.setdefault('rol', 'SUPERVISOR')
        extra.setdefault('is_staff', True)
        extra.setdefault('is_superuser', True)
        return self.create_user(email, password, **extra)


class UsuarioInterno(AbstractBaseUser, PermissionsMixin):
    ROL_CHOICES = [
        ('SUPERVISOR', 'Supervisor'),
        ('ASESOR',     'Asesor'),
        ('AUDITOR',    'Auditor'),
        ('AUXILIAR',   'Auxiliar'),
        ('REVISOR',    'Revisor'),
        ('CLIENTE',    'Cliente'),
    ]
    ESTADO_CHOICES = [
        ('ACTIVO',    'Activo'),
        ('INACTIVO',  'Inactivo'),
        ('BLOQUEADO', 'Bloqueado'),
    ]
    TIPO_CONTRATACION_CHOICES = [
        ('PLANTA',    'Planta'),
        ('CONTRATO',  'Contrato'),
        ('EXTERNO',   'Externo / Freelance'),
    ]

    id                = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    email             = models.EmailField(unique=True)
    nombre            = models.CharField(max_length=150)
    apellido          = models.CharField(max_length=150)
    telefono          = models.CharField(max_length=20, blank=True)
    documento_id      = models.CharField(max_length=30, blank=True)
    especialidad      = models.CharField(max_length=200, blank=True)
    tipo_contratacion = models.CharField(
        max_length=10, choices=TIPO_CONTRATACION_CHOICES, default='PLANTA', blank=True)
    rol               = models.CharField(max_length=12, choices=ROL_CHOICES, default='AUDITOR')
    estado            = models.CharField(max_length=10, choices=ESTADO_CHOICES, default='ACTIVO')
    permisos_extra    = models.JSONField(default=list, blank=True)

    mfa_habilitado     = models.BooleanField(default=False)
    mfa_secret         = models.CharField(max_length=64, blank=True)
    intentos_fallidos  = models.PositiveSmallIntegerField(default=0)
    fecha_bloqueo      = models.DateTimeField(null=True, blank=True)
    reset_token        = models.CharField(max_length=128, blank=True)
    reset_token_expira = models.DateTimeField(null=True, blank=True)
    ultimo_acceso      = models.DateTimeField(null=True, blank=True)
    fecha_creacion     = models.DateTimeField(auto_now_add=True)
    is_active          = models.BooleanField(default=True)
    is_staff           = models.BooleanField(default=False)

    objects = UsuarioInternoManager()

    USERNAME_FIELD  = 'email'
    REQUIRED_FIELDS = ['nombre', 'apellido']

    class Meta:
        db_table         = 'usuarios_internos'
        verbose_name     = 'Usuario'
        verbose_name_plural = 'Usuarios'

    def __str__(self):
        return f'{self.nombre} {self.apellido} ({self.get_rol_display()})'

    @property
    def nombre_completo(self):
        return f'{self.nombre} {self.apellido}'

    @property
    def es_personal_interno(self):
        return self.rol in ('SUPERVISOR', 'ASESOR', 'AUDITOR', 'AUXILIAR', 'REVISOR')

    def tiene_permiso(self, permiso: str) -> bool:
        base = PERMISOS_POR_ROL.get(self.rol, [])
        return permiso in base or permiso in (self.permisos_extra or [])

    def permisos_efectivos(self) -> list:
        base  = PERMISOS_POR_ROL.get(self.rol, [])
        extra = self.permisos_extra or []
        return sorted(set(base) | set(extra))
