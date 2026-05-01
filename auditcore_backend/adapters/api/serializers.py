from __future__ import annotations
from typing import Optional
from rest_framework import serializers
from drf_spectacular.utils import extend_schema_field
from apps.administracion.models import UsuarioInterno, PERMISOS_POR_ROL
from apps.clientes.models import (
    Cliente, SedeCliente, ContactoCliente,
    AccesoTemporalCaracterizacion, UsuarioCliente,
)
from apps.tipos_auditoria.models import TipoAuditoria, FaseTipoAuditoria, ChecklistItem, DocumentoRequerido
from apps.formularios.models import EsquemaFormulario, CampoFormulario, ValorFormulario
from apps.expedientes.models import Expediente, FaseExpediente, AsignacionEquipo, BitacoraExpediente
from apps.ejecucion.models import Hallazgo, Evidencia, ChecklistEjecucion
from apps.documentos.models import DocumentoExpediente
from apps.certificaciones.models import Certificacion
from apps.chatbot.models import Conversacion, MensajeConversacion
from apps.expedientes.models import VisitaAgendada


CLIENTE_RAZON_SOCIAL = 'cliente.razon_social'
TIPO_AUDITORIA_NOMBRE = 'tipo_auditoria.nombre'


class UsuarioInternoSerializer(serializers.ModelSerializer):
    nombre_completo    = serializers.ReadOnlyField()
    permisos_efectivos = serializers.SerializerMethodField()

    class Meta:
        model  = UsuarioInterno
        fields = [
            'id', 'email', 'nombre', 'apellido', 'nombre_completo',
            'telefono', 'documento_id', 'especialidad', 'tipo_contratacion',
            'rol', 'estado', 'mfa_habilitado', 'ultimo_acceso',
            'permisos_extra', 'permisos_efectivos',
        ]
        read_only_fields = ['id', 'ultimo_acceso']

    @extend_schema_field(serializers.ListField(child=serializers.CharField()))
    def get_permisos_efectivos(self, obj) -> list:
        return obj.permisos_efectivos()


class UsuarioInternoCreateSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, min_length=8)

    class Meta:
        model  = UsuarioInterno
        fields = [
            'email', 'nombre', 'apellido', 'telefono',
            'documento_id', 'especialidad', 'tipo_contratacion',
            'rol', 'password', 'permisos_extra',
        ]

    def create(self, validated_data):
        return UsuarioInterno.objects.create_user(**validated_data)

    def validate_email(self, value):
        value = value.strip().lower()
        if UsuarioInterno.objects.filter(email=value).exists():
            raise serializers.ValidationError('Ya existe un usuario con este email.')
        return value


class UsuarioUpdateSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, required=False, min_length=8)

    class Meta:
        model  = UsuarioInterno
        fields = [
            'nombre', 'apellido', 'telefono', 'documento_id',
            'especialidad', 'tipo_contratacion',
            'rol', 'estado', 'password', 'permisos_extra',
        ]

    def update(self, instance, validated_data):
        password = validated_data.pop('password', None)
        for attr, value in validated_data.items():
            setattr(instance, attr, value)
        if password:
            instance.set_password(password)
        instance.save()
        return instance


class SedeClienteSerializer(serializers.ModelSerializer):
    class Meta:
        model  = SedeCliente
        fields = [
            'id', 'nombre', 'es_principal', 'pais', 'departamento', 'ciudad',
            'direccion', 'codigo_postal', 'telefono', 'email_sede', 'num_empleados',
            'responsable_nombre', 'responsable_cargo', 'responsable_email',
            'responsable_telefono', 'activa',
        ]
        read_only_fields = ['id']


class ContactoClienteSerializer(serializers.ModelSerializer):
    nombre_completo = serializers.ReadOnlyField()

    class Meta:
        model  = ContactoCliente
        fields = [
            'id', 'tipo', 'nombre', 'apellido', 'nombre_completo', 'cargo',
            'departamento', 'email', 'telefono', 'telefono_ext', 'celular',
            'es_principal', 'recibe_informes', 'recibe_notificaciones',
            'sede', 'notas',
        ]
        read_only_fields = ['id']


class AccesoTemporalSerializer(serializers.ModelSerializer):
    cliente_nombre = serializers.ReadOnlyField(source=CLIENTE_RAZON_SOCIAL)
    esta_vigente   = serializers.ReadOnlyField()

    class Meta:
        model  = AccesoTemporalCaracterizacion
        fields = [
            'id', 'cliente', 'cliente_nombre', 'contacto', 'email_destino',
            'creado_en', 'expira_en', 'usado', 'usado_en', 'esta_vigente',
        ]
        read_only_fields = ['id', 'token', 'creado_en', 'usado', 'usado_en']


class ClienteListSerializer(serializers.ModelSerializer):
    asesor_nombre = serializers.SerializerMethodField()

    class Meta:
        model  = Cliente
        fields = [
            'id', 'tipo_persona', 'razon_social', 'nit', 'sector', 'tamano',
            'estado', 'pais', 'ciudad', 'email', 'urgencia',
            'caracterizacion_completada', 'asesor_nombre', 'fecha_creacion',
        ]

    @extend_schema_field(serializers.CharField(allow_null=True))
    def get_asesor_nombre(self, obj) -> Optional[str]:
        if obj.asesor_responsable:
            return obj.asesor_responsable.nombre_completo
        return None


class ClienteSerializer(serializers.ModelSerializer):
    contactos     = ContactoClienteSerializer(many=True, read_only=True)
    sedes         = SedeClienteSerializer(many=True, read_only=True)
    asesor_nombre = serializers.SerializerMethodField()


    rep_legal_email    = serializers.EmailField(allow_blank=True, required=False, default='')
    email              = serializers.EmailField(allow_blank=True, required=False, default='')
    sitio_web          = serializers.URLField(allow_blank=True, required=False, default='')
    linkedin           = serializers.URLField(allow_blank=True, required=False, default='')
    num_empleados      = serializers.IntegerField(allow_null=True, required=False, default=None)
    asesor_responsable = serializers.PrimaryKeyRelatedField(
        allow_null=True, required=False, default=None,
        queryset=UsuarioInterno.objects.all(),
    )

    class Meta:
        model  = Cliente
        fields = [
            'id', 'tipo_persona',

            'razon_social', 'nit', 'digito_verificacion', 'matricula_mercantil',
            'fecha_constitucion', 'duracion_empresa', 'objeto_social',
            'codigo_ciiu', 'regimen_tributario', 'responsable_iva',

            'rep_legal_nombre', 'rep_legal_documento', 'rep_legal_tipo_doc',
            'rep_legal_cargo', 'rep_legal_email', 'rep_legal_telefono',

            'pais', 'departamento', 'ciudad', 'direccion_principal',
            'codigo_postal', 'sedes_adicionales',

            'telefono', 'telefono_alt', 'email', 'sitio_web', 'linkedin',

            'sector', 'subsector', 'tamano', 'num_empleados', 'ingresos_anuales',

            'tipos_auditoria_solicitados', 'alcance_descripcion',
            'normas_interes', 'tiene_certificacion_previa',
            'certificacion_previa_detalle',

            'motivo_auditoria', 'declaracion_necesidad',
            'urgencia', 'fecha_limite_deseada',

            'estado', 'caracterizacion_completada', 'fecha_caracterizacion',
            'asesor_responsable', 'asesor_nombre',
            'notas', 'fecha_creacion', 'fecha_actualizacion',

            'contactos', 'sedes',
        ]
        read_only_fields = [
            'id', 'fecha_creacion', 'fecha_actualizacion',
            'caracterizacion_completada', 'fecha_caracterizacion',
            'estado',
        ]

    @extend_schema_field(serializers.CharField(allow_null=True))
    def get_asesor_nombre(self, obj) -> Optional[str]:
        if obj.asesor_responsable:
            return obj.asesor_responsable.nombre_completo
        return None

    def validate_nit(self, value):
        qs = Cliente.objects.filter(nit=value)
        if self.instance:
            qs = qs.exclude(pk=self.instance.pk)
        if qs.exists():
            raise serializers.ValidationError('Ya existe un cliente con este NIT.')
        return value


class FaseTipoSerializer(serializers.ModelSerializer):
    tipo_auditoria = serializers.PrimaryKeyRelatedField(
        queryset=TipoAuditoria.objects.all(), write_only=True, required=False)

    class Meta:
        model  = FaseTipoAuditoria
        fields = ['id', 'tipo_auditoria', 'nombre', 'descripcion', 'orden',
                  'duracion_estimada_dias', 'es_fase_final']
        read_only_fields = ['id']


class ChecklistItemSerializer(serializers.ModelSerializer):
    tipo_auditoria = serializers.PrimaryKeyRelatedField(
        queryset=TipoAuditoria.objects.all(), write_only=True, required=False)
    fase = serializers.PrimaryKeyRelatedField(
        queryset=FaseTipoAuditoria.objects.all(),
        allow_null=True, required=False, default=None)

    class Meta:
        model  = ChecklistItem
        fields = ['id', 'tipo_auditoria', 'fase', 'codigo', 'descripcion',
                  'categoria', 'obligatorio', 'orden']
        read_only_fields = ['id']


class DocumentoRequeridoSerializer(serializers.ModelSerializer):
    tipo_auditoria = serializers.PrimaryKeyRelatedField(
        queryset=TipoAuditoria.objects.all(), write_only=True, required=False)

    class Meta:
        model  = DocumentoRequerido
        fields = ['id', 'tipo_auditoria', 'nombre', 'descripcion', 'obligatorio', 'orden']
        read_only_fields = ['id']


class TipoAuditoriaSerializer(serializers.ModelSerializer):
    fases                 = FaseTipoSerializer(many=True, read_only=True)
    checklist_items       = ChecklistItemSerializer(many=True, read_only=True)
    documentos_requeridos = DocumentoRequeridoSerializer(many=True, read_only=True)

    class Meta:
        model  = TipoAuditoria
        fields = [
            'id', 'codigo', 'nombre', 'descripcion', 'categoria', 'nivel',
            'certificacion_tipo', 'duracion_estimada_dias', 'version', 'activo',
            'fecha_creacion', 'fases', 'checklist_items', 'documentos_requeridos',
        ]
        read_only_fields = ['id', 'fecha_creacion']


class CampoFormularioSerializer(serializers.ModelSerializer):
    class Meta:
        model  = CampoFormulario
        fields = [
            'id', 'nombre', 'etiqueta', 'tipo', 'obligatorio',
            'orden', 'opciones', 'validaciones', 'ayuda', 'activo',
        ]


class EsquemaFormularioSerializer(serializers.ModelSerializer):
    campos            = CampoFormularioSerializer(many=True, read_only=True)
    creado_por_nombre = serializers.SerializerMethodField()

    class Meta:
        model  = EsquemaFormulario
        fields = [
            'id', 'nombre', 'descripcion', 'contexto', 'tipo_auditoria',
            'version', 'activo', 'origen', 'creado_por', 'creado_por_nombre',
            'fecha_creacion', 'fecha_actualizacion', 'campos',
        ]
        read_only_fields = ['id', 'fecha_creacion', 'fecha_actualizacion', 'creado_por']

    @extend_schema_field(serializers.CharField(allow_null=True))
    def get_creado_por_nombre(self, obj) -> Optional[str]:
        if obj.creado_por:
            return obj.creado_por.nombre_completo
        return None


class ValorFormularioSerializer(serializers.ModelSerializer):
    class Meta:
        model  = ValorFormulario
        fields = ['id', 'esquema', 'entidad_tipo', 'entidad_id', 'valores', 'fecha_creacion']
        read_only_fields = ['id', 'fecha_creacion']


class BitacoraSerializer(serializers.ModelSerializer):
    usuario_nombre = serializers.SerializerMethodField()

    class Meta:
        model  = BitacoraExpediente
        fields = ['id', 'tipo_usuario', 'usuario_nombre', 'accion', 'descripcion', 'entidad_afectada', 'fecha']

    @extend_schema_field(serializers.CharField())
    def get_usuario_nombre(self, obj) -> str:
        if obj.usuario_interno:
            return obj.usuario_interno.nombre_completo
        return 'Sistema'


class FaseExpedienteSerializer(serializers.ModelSerializer):
    fase_nombre = serializers.ReadOnlyField(source='fase_tipo.nombre')
    orden       = serializers.ReadOnlyField(source='fase_tipo.orden')

    class Meta:
        model  = FaseExpediente
        fields = ['id', 'fase_nombre', 'orden', 'estado', 'fecha_inicio', 'fecha_fin', 'observaciones']


class AsignacionSerializer(serializers.ModelSerializer):
    usuario_nombre = serializers.ReadOnlyField(source='usuario.nombre_completo')
    usuario_rol    = serializers.ReadOnlyField(source='usuario.rol')

    class Meta:
        model  = AsignacionEquipo
        fields = ['id', 'usuario', 'usuario_nombre', 'usuario_rol', 'rol', 'fecha_asignacion', 'activo']


class ExpedienteListSerializer(serializers.ModelSerializer):
    cliente_nombre = serializers.ReadOnlyField(source=CLIENTE_RAZON_SOCIAL)
    tipo_nombre    = serializers.ReadOnlyField(source=TIPO_AUDITORIA_NOMBRE)
    auditor_nombre = serializers.ReadOnlyField(source='auditor_lider.nombre_completo')

    class Meta:
        model  = Expediente
        fields = [
            'id', 'numero_expediente', 'cliente', 'cliente_nombre',
            'tipo_auditoria', 'tipo_nombre', 'estado',
            'porcentaje_avance', 'auditor_nombre', 'fecha_apertura', 'fecha_estimada_cierre',
        ]


class ExpedienteSerializer(serializers.ModelSerializer):
    cliente_nombre = serializers.ReadOnlyField(source=CLIENTE_RAZON_SOCIAL)
    tipo_nombre    = serializers.ReadOnlyField(source=TIPO_AUDITORIA_NOMBRE)
    auditor_nombre = serializers.ReadOnlyField(source='auditor_lider.nombre_completo')
    fases          = FaseExpedienteSerializer(many=True, read_only=True)
    equipo         = AsignacionSerializer(many=True, read_only=True)

    class Meta:
        model  = Expediente
        fields = [
            'id', 'numero_expediente', 'cliente', 'cliente_nombre',
            'tipo_auditoria', 'tipo_nombre', 'estado', 'tipo_origen',
            'auditor_lider', 'auditor_nombre', 'ejecutivo',
            'fecha_apertura', 'fecha_estimada_cierre',
            'porcentaje_avance', 'notas', 'fases', 'equipo',
        ]
        read_only_fields = ['id', 'numero_expediente', 'porcentaje_avance']

    def validate(self, data):
        auditor = data.get('auditor_lider')
        if auditor and auditor.rol not in ('SUPERVISOR', 'AUDITOR'):
            raise serializers.ValidationError(
                {'auditor_lider': 'El auditor líder debe tener rol Supervisor o Auditor.'})
        return data


class HallazgoSerializer(serializers.ModelSerializer):
    reportado_nombre = serializers.ReadOnlyField(source='reportado_por.nombre_completo')

    class Meta:
        model  = Hallazgo
        fields = [
            'id', 'expediente', 'tipo', 'nivel_criticidad', 'titulo',
            'descripcion', 'estado', 'fecha_limite_cierre',
            'reportado_por', 'reportado_nombre', 'asignado_a', 'fecha_creacion',
        ]
        read_only_fields = ['id', 'fecha_creacion', 'reportado_por']


class EvidenciaSerializer(serializers.ModelSerializer):
    class Meta:
        model  = Evidencia
        fields = [
            'id', 'expediente', 'hallazgo', 'archivo', 'nombre_original',
            'tipo_archivo', 'tamanio_bytes', 'hash_sha256',
            'descripcion', 'subido_por', 'fecha_subida',
        ]
        read_only_fields = [
            'id', 'hash_sha256', 'fecha_subida', 'nombre_original',
            'tipo_archivo', 'tamanio_bytes', 'subido_por',
        ]


class ChecklistEjecucionSerializer(serializers.ModelSerializer):
    item_descripcion = serializers.ReadOnlyField(source='item.descripcion')
    item_codigo      = serializers.ReadOnlyField(source='item.codigo')

    class Meta:
        model  = ChecklistEjecucion
        fields = [
            'id', 'expediente', 'item', 'item_codigo', 'item_descripcion',
            'estado', 'evidencia', 'observacion', 'verificado_por', 'fecha_verificacion',
        ]


class DocumentoExpedienteSerializer(serializers.ModelSerializer):
    revisado_por_nombre = serializers.SerializerMethodField()

    class Meta:
        model  = DocumentoExpediente
        fields = [
            'id', 'expediente', 'documento_requerido', 'nombre', 'archivo',
            'hash_sha256', 'estado', 'version', 'revisado_por',
            'revisado_por_nombre', 'fecha_revision',
            'observacion_revision', 'subido_por', 'fecha_subida',
        ]
        read_only_fields = [
            'id', 'hash_sha256', 'version', 'fecha_subida',
            'subido_por', 'revisado_por', 'fecha_revision',
        ]

    @extend_schema_field(serializers.CharField(allow_null=True))
    def get_revisado_por_nombre(self, obj) -> Optional[str]:
        if obj.revisado_por:
            return obj.revisado_por.nombre_completo
        return None


class CertificacionSerializer(serializers.ModelSerializer):
    cliente_nombre   = serializers.ReadOnlyField(source=CLIENTE_RAZON_SOCIAL)
    tipo_nombre      = serializers.ReadOnlyField(source=TIPO_AUDITORIA_NOMBRE)
    dias_para_vencer = serializers.IntegerField(read_only=True, allow_null=True)

    class Meta:
        model  = Certificacion
        fields = [
            'id', 'numero', 'expediente', 'cliente', 'cliente_nombre',
            'tipo_auditoria', 'tipo_nombre', 'codigo_verificacion',
            'tipo_emision', 'ente_certificador', 'fecha_emision',
            'fecha_vencimiento', 'estado', 'certificado_pdf',
            'emitido_por', 'dias_para_vencer',
        ]
        read_only_fields = ['id', 'numero', 'codigo_verificacion', 'dias_para_vencer', 'emitido_por']

    def validate(self, data):
        emision     = data.get('fecha_emision')
        vencimiento = data.get('fecha_vencimiento')
        if emision and vencimiento and emision >= vencimiento:
            raise serializers.ValidationError(
                {'fecha_vencimiento': 'La fecha de vencimiento debe ser posterior a la de emisión.'})
        return data


class MensajeSerializer(serializers.ModelSerializer):
    class Meta:
        model  = MensajeConversacion
        fields = ['id', 'rol', 'contenido', 'tokens_usados', 'fecha']


class ConversacionSerializer(serializers.ModelSerializer):
    class Meta:
        model  = Conversacion
        fields = ['id', 'cliente', 'usuario_interno', 'expediente', 'canal', 'estado', 'fecha_creacion']
        read_only_fields = ['id', 'fecha_creacion', 'usuario_interno']


class VisitaAgendadaSerializer(serializers.ModelSerializer):
    creado_por_nombre  = serializers.CharField(source='creado_por.nombre_completo', read_only=True)
    expediente_numero  = serializers.CharField(source='expediente.numero_expediente', read_only=True)
    fase_nombre        = serializers.SerializerMethodField()
    participantes_data = UsuarioInternoSerializer(source='participantes', many=True, read_only=True)
    duracion_horas     = serializers.FloatField(read_only=True)

    class Meta:
        model  = VisitaAgendada
        fields = [
            'id', 'expediente', 'expediente_numero', 'fase', 'fase_nombre',
            'tipo', 'titulo', 'descripcion', 'fecha_inicio', 'fecha_fin',
            'lugar', 'estado', 'creado_por', 'creado_por_nombre',
            'participantes', 'participantes_data', 'notas_resultado',
            'duracion_horas', 'fecha_creacion',
        ]
        read_only_fields = ['id', 'creado_por', 'fecha_creacion']

    @extend_schema_field(serializers.CharField(allow_null=True))
    def get_fase_nombre(self, obj) -> Optional[str]:

        if obj.fase and obj.fase.fase_tipo:
            return obj.fase.fase_tipo.nombre
        return None

    def validate(self, data):
        fecha_inicio = data.get('fecha_inicio')
        fecha_fin    = data.get('fecha_fin')
        if fecha_inicio and fecha_fin and fecha_fin <= fecha_inicio:
            raise serializers.ValidationError({
                'fecha_fin': 'La fecha de fin debe ser posterior a la fecha de inicio.'
            })
        return data
