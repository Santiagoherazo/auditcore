import logging
import os

from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework.exceptions import ValidationError
from django.utils import timezone
from django.db.models import Count, Q

logger = logging.getLogger(__name__)

try:
    from adapters.realtime.chatbot_logger import (
        ids_log, IDS as _IDS, broker_diagnostic, new_trace_id,
    )
    _ids_log      = ids_log
    _broker_diag  = broker_diagnostic
    _new_trace_id = new_trace_id
    _IDS_API    = _IDS.API
    _IDS_CELERY = _IDS.CELERY
    _IDS_ERROR  = _IDS.ERROR
except ImportError:
    def _ids_log(*a, **kw): pass
    def _broker_diag(*a, **kw): pass
    def _new_trace_id(): return 'na'
    _IDS_API    = 'API'
    _IDS_CELERY = 'CELERY'
    _IDS_ERROR  = 'ERROR'


try:
    from kombu.exceptions import OperationalError as KombuOperationalError
except ImportError:
    KombuOperationalError = OSError

_BROKER_ERRORS = (KombuOperationalError, OSError, ConnectionError, TimeoutError)

_MSG_BROKER_NO_DISPONIBLE = (
    'El servicio de mensajería no está disponible en este momento. '
    'Espera unos segundos y vuelve a intentarlo.'
)

from apps.administracion.models import UsuarioInterno
from apps.clientes.models import Cliente, SedeCliente, ContactoCliente, AccesoTemporalCaracterizacion
from apps.tipos_auditoria.models import TipoAuditoria, FaseTipoAuditoria, ChecklistItem, DocumentoRequerido
from apps.formularios.models import EsquemaFormulario, ValorFormulario
from apps.expedientes.models import Expediente, BitacoraExpediente
from apps.ejecucion.models import Hallazgo, Evidencia, ChecklistEjecucion
from apps.documentos.models import DocumentoExpediente
from apps.certificaciones.models import Certificacion
from apps.chatbot.models import Conversacion, MensajeConversacion

from adapters.api.serializers import (
    UsuarioInternoSerializer, UsuarioInternoCreateSerializer,
    ClienteSerializer, ClienteListSerializer, SedeClienteSerializer,
    ContactoClienteSerializer, AccesoTemporalSerializer,
    TipoAuditoriaSerializer, FaseTipoSerializer, ChecklistItemSerializer, DocumentoRequeridoSerializer,
    EsquemaFormularioSerializer, ValorFormularioSerializer,
    ExpedienteSerializer, ExpedienteListSerializer, BitacoraSerializer,
    FaseExpedienteSerializer, AsignacionSerializer,
    HallazgoSerializer, EvidenciaSerializer, ChecklistEjecucionSerializer,
    DocumentoExpedienteSerializer,
    CertificacionSerializer,
    ConversacionSerializer, MensajeSerializer,
)
try:
    from adapters.realtime.auditlog import (
        alog, AL, new_op_id,
        log_doc_upload, log_doc_review,
        log_task_enqueue,
    )
except ImportError:
    def alog(*a, **kw):
        pass
    def new_op_id():
        return ''
    def log_doc_upload(*a, **kw):
        pass
    def log_doc_review(*a, **kw):
        pass
    def log_task_enqueue(*a, **kw):
        pass

from adapters.api.permissions import (
    IsSupervisor, IsSupervisorOrAsesor, IsSupervisorOrAuditor,
    IsAuditTeam, IsPersonalInterno, IsRevisorOrAbove,
    CanCreateClientes, CanAudit, CanCreateProcedimientos,
    CanUseChatbot, IsClientePortal, HasPermission,
    IsAdmin, IsAdminOrLider, IsInternalUser, IsExecutivoOrAdmin,
)


def _blacklist_user_tokens(user) -> None:


    try:
        from rest_framework_simplejwt.token_blacklist.models import (
            OutstandingToken, BlacklistedToken,
        )
        for token in OutstandingToken.objects.filter(user=user):
            BlacklistedToken.objects.get_or_create(token=token)
    except Exception:
        pass


class SoftDeleteMixin:


    def destroy(self, *args, **kwargs):
        instance = self.get_object()
        self._soft_delete(instance)
        return Response(status=status.HTTP_204_NO_CONTENT)

    def _soft_delete(self, instance):
        raise NotImplementedError(
            f'{self.__class__.__name__} debe implementar _soft_delete()'
        )

class UsuarioInternoViewSet(SoftDeleteMixin, viewsets.ModelViewSet):
    queryset = UsuarioInterno.objects.all()
    permission_classes = [IsSupervisor]

    def _soft_delete(self, instance):
        if instance == self.request.user:
            raise ValidationError({"detail": "No puedes desactivarte a ti mismo."})
        instance.estado    = 'INACTIVO'
        instance.is_active = False
        instance.save(update_fields=['estado', 'is_active'])
        _blacklist_user_tokens(instance)

    def get_serializer_class(self):
        if self.action == 'create':
            return UsuarioInternoCreateSerializer
        if self.action in ('update', 'partial_update'):
            from adapters.api.serializers import UsuarioUpdateSerializer
            return UsuarioUpdateSerializer
        return UsuarioInternoSerializer

    def perform_update(self, serializer):

        instance = serializer.save()
        if not instance.is_active:
            _blacklist_user_tokens(instance)

    @action(detail=True, methods=['post'], url_path='activar')
    def activar(self, request, pk=None):

        usuario = self.get_object()
        usuario.estado    = 'ACTIVO'
        usuario.is_active = True
        usuario.intentos_fallidos = 0
        usuario.fecha_bloqueo = None
        usuario.save(update_fields=['estado', 'is_active', 'intentos_fallidos', 'fecha_bloqueo'])
        return Response({'detail': 'Usuario activado.'})

    @action(detail=False, methods=['get'], permission_classes=[IsAuthenticated])
    def me(self, request):


        if request.user.estado != 'ACTIVO':
            return Response(
                {'detail': 'Cuenta inactiva o bloqueada. Contacta al administrador.'},
                status=403,
            )
        return Response(UsuarioInternoSerializer(request.user).data)

    @action(detail=False, methods=['get'], permission_classes=[IsAuthenticated])
    def auditores(self, request):


        qs = UsuarioInterno.objects.filter(
            rol__in=['SUPERVISOR', 'AUDITOR'],
            estado='ACTIVO',
        ).order_by('nombre', 'apellido')
        return Response(UsuarioInternoSerializer(qs, many=True).data)

    @action(detail=True, methods=['post'])
    def desactivar(self, request, pk=None):
        usuario = self.get_object()
        if usuario == request.user:
            return Response({'detail': 'No puedes desactivarte a ti mismo.'}, status=400)
        usuario.estado    = 'INACTIVO'
        usuario.is_active = False
        usuario.save(update_fields=['estado', 'is_active'])


        _blacklist_user_tokens(usuario)
        return Response({'detail': 'Usuario desactivado.'})


class ClienteViewSet(SoftDeleteMixin, viewsets.ModelViewSet):
    queryset = Cliente.objects.prefetch_related('contactos').select_related('creado_por').all()

    def _soft_delete(self, instance):
        instance.estado = 'INACTIVO'
        instance.save(update_fields=['estado'])

    def get_serializer_class(self):
        if self.action == 'list':
            return ClienteListSerializer
        return ClienteSerializer

    def get_permissions(self):
        if self.action in ('list', 'retrieve', 'dashboard'):
            return [IsPersonalInterno()]
        if self.action == 'cambiar_estado':
            return [IsSupervisorOrAsesor()]

        return [CanCreateClientes()]

    def get_queryset(self):
        qs     = super().get_queryset()
        estado = self.request.query_params.get('estado')
        sector = self.request.query_params.get('sector')
        search = self.request.query_params.get('search')
        if estado:
            qs = qs.filter(estado=estado)
        if sector:
            qs = qs.filter(sector=sector)
        if search:
            qs = qs.filter(
                Q(razon_social__icontains=search) | Q(nit__icontains=search)
            )
        return qs

    def perform_create(self, serializer):
        serializer.save(creado_por=self.request.user)

    @action(detail=True, methods=['get'])
    def dashboard(self, request, pk=None):
        cliente              = self.get_object()
        expedientes_activos  = Expediente.objects.filter(
            cliente=cliente, estado__in=['ACTIVO', 'EN_EJECUCION']
        ).count()
        certificaciones = Certificacion.objects.filter(cliente=cliente)
        return Response({
            'cliente':                    ClienteListSerializer(cliente).data,
            'expedientes_activos':        expedientes_activos,
            'certificaciones_vigentes':   certificaciones.filter(estado='VIGENTE').count(),
            'certificaciones_por_vencer': certificaciones.filter(estado='POR_VENCER').count(),
            'certificaciones_vencidas':   certificaciones.filter(estado='VENCIDA').count(),
        })

    _TRANSICIONES_CLIENTE = {
        'PROSPECTO':     ['EN_EVALUACION', 'INACTIVO'],
        'EN_EVALUACION': ['ACTIVO', 'PROSPECTO', 'INACTIVO'],
        'ACTIVO':        ['SUSPENDIDO', 'INACTIVO'],
        'SUSPENDIDO':    ['ACTIVO', 'INACTIVO'],
        'INACTIVO':      ['ACTIVO'],
    }

    @action(detail=True, methods=['post'], url_path='cambiar-estado',
            permission_classes=[IsSupervisorOrAsesor])
    def cambiar_estado(self, request, pk=None):


        cliente      = self.get_object()
        nuevo_estado = request.data.get('estado', '').strip()
        motivo       = request.data.get('motivo', '').strip()

        estados_validos = [s[0] for s in cliente.ESTADO_CHOICES]
        if nuevo_estado not in estados_validos:
            return Response(
                {'error': f'Estado inválido. Opciones: {estados_validos}'},
                status=400,
            )

        permitidos = self._TRANSICIONES_CLIENTE.get(cliente.estado, [])
        if nuevo_estado not in permitidos:
            return Response({
                'error': (
                    f'Transición inválida: {cliente.estado} → {nuevo_estado}. '
                    f'Transiciones permitidas: {permitidos if permitidos else "ninguna"}'
                )
            }, status=400)

        estado_anterior  = cliente.estado
        cliente.estado   = nuevo_estado
        cliente.save(update_fields=['estado'])
        return Response({
            'detail':          f'Estado cambiado de {estado_anterior} a {nuevo_estado}.',
            'estado_anterior': estado_anterior,
            'estado_nuevo':    nuevo_estado,
            'motivo':          motivo,
        })


class SedeClienteViewSet(viewsets.ModelViewSet):
    serializer_class   = SedeClienteSerializer
    permission_classes = [IsPersonalInterno]

    def get_queryset(self):
        if getattr(self, 'swagger_fake_view', False):
            return SedeCliente.objects.none()
        cliente_id = self.request.query_params.get('cliente')
        qs = SedeCliente.objects.select_related('cliente')
        if cliente_id:
            qs = qs.filter(cliente_id=cliente_id)
        return qs


class ContactoClienteViewSet(viewsets.ModelViewSet):
    serializer_class   = ContactoClienteSerializer
    permission_classes = [IsPersonalInterno]

    def get_queryset(self):
        if getattr(self, 'swagger_fake_view', False):
            return ContactoCliente.objects.none()
        cliente_id = self.request.query_params.get('cliente')
        qs = ContactoCliente.objects.select_related('cliente', 'sede')
        if cliente_id:
            qs = qs.filter(cliente_id=cliente_id)
        return qs


class AccesoTemporalView(APIView):
    permission_classes = [IsSupervisorOrAsesor]

    def post(self, request):
        from apps.clientes.models import AccesoTemporalCaracterizacion
        from django.core.validators import validate_email
        from django.core.exceptions import ValidationError as DjangoValidationError

        cliente_id   = request.data.get('cliente_id')
        contacto_id  = request.data.get('contacto_id')
        email_destino = request.data.get('email_destino', '').strip()

        if not cliente_id or not email_destino:
            return Response({'error': 'cliente_id y email_destino son requeridos.'}, status=400)

        try:
            validate_email(email_destino)
        except DjangoValidationError:
            return Response({'error': 'El email de destino no tiene un formato válido.'}, status=400)

        try:
            cliente = Cliente.objects.get(id=cliente_id)
        except Cliente.DoesNotExist:
            return Response({'error': 'Cliente no encontrado.'}, status=404)

        acceso = AccesoTemporalCaracterizacion.objects.create(
            cliente=cliente,
            contacto_id=contacto_id if contacto_id else None,
            email_destino=email_destino,
            creado_por=request.user,
        )
        from adapters.api.serializers import AccesoTemporalSerializer
        return Response(AccesoTemporalSerializer(acceso).data, status=201)


class CaracterizacionPublicaView(APIView):
    permission_classes = []
    authentication_classes = []

    def get(self, request, token):
        from apps.clientes.models import AccesoTemporalCaracterizacion
        try:
            acceso = AccesoTemporalCaracterizacion.objects.select_related(
                'cliente', 'contacto'
            ).get(token=token)
        except AccesoTemporalCaracterizacion.DoesNotExist:
            return Response({'error': 'Enlace inválido.'}, status=404)
        if not acceso.esta_vigente:
            return Response({'error': 'Este enlace ha expirado o ya fue utilizado.'}, status=410)
        from adapters.api.serializers import ClienteSerializer
        return Response({
            'cliente': ClienteSerializer(acceso.cliente).data,
            'contacto_nombre': acceso.contacto.nombre_completo if acceso.contacto else '',
            'expira_en': acceso.expira_en,
        })

    def post(self, request, token):
        from apps.clientes.models import AccesoTemporalCaracterizacion
        from django.utils import timezone
        from django.db import transaction
        try:
            with transaction.atomic():
                acceso = AccesoTemporalCaracterizacion.objects.select_for_update().select_related('cliente').get(token=token)
                if not acceso.esta_vigente:
                    return Response({'error': 'Este enlace ha expirado o ya fue utilizado.'}, status=410)

                cliente = acceso.cliente
                campos_permitidos = [
                    'objeto_social', 'codigo_ciiu', 'num_empleados', 'tamano',
                    'declaracion_necesidad', 'motivo_auditoria', 'urgencia',
                    'fecha_limite_deseada', 'alcance_descripcion', 'normas_interes',
                    'tiene_certificacion_previa', 'certificacion_previa_detalle',
                    'sedes_adicionales',
                    'rep_legal_nombre', 'rep_legal_documento', 'rep_legal_tipo_doc',
                    'rep_legal_cargo', 'rep_legal_email', 'rep_legal_telefono',
                    'telefono', 'telefono_alt', 'sitio_web', 'direccion_principal',
                    'departamento', 'codigo_postal',
                ]
                for campo in campos_permitidos:
                    if campo in request.data:
                        setattr(cliente, campo, request.data[campo])

                cliente.caracterizacion_completada = True
                cliente.fecha_caracterizacion      = timezone.now()
                cliente.estado = 'EN_EVALUACION'
                cliente.save()

                ip = (
                    request.META.get('HTTP_X_FORWARDED_FOR', '').split(',')[0].strip()
                    or request.META.get('REMOTE_ADDR')
                )
                acceso.usar(ip=ip)
        except AccesoTemporalCaracterizacion.DoesNotExist:
            return Response({'error': 'Enlace inválido.'}, status=404)

        return Response({'detail': 'Caracterización enviada correctamente. El equipo se pondrá en contacto.'})

class TipoAuditoriaViewSet(SoftDeleteMixin, viewsets.ModelViewSet):
    serializer_class = TipoAuditoriaSerializer

    def _soft_delete(self, instance):
        instance.activo = False
        instance.save(update_fields=['activo'])

    def get_queryset(self):
        qs = TipoAuditoria.objects.prefetch_related(
            'fases', 'checklist_items', 'documentos_requeridos'
        )
        if self.action == 'list':

            user = getattr(self.request, 'user', None)
            es_admin = user and getattr(user, 'rol', None) == 'SUPERVISOR'
            if not es_admin:
                qs = qs.filter(activo=True)

            activo_param = self.request.query_params.get('activo')
            if activo_param is not None:
                qs = qs.filter(activo=activo_param.lower() == 'true')
        return qs

    def get_permissions(self):
        if self.action in ('list', 'retrieve'):
            return [IsAuthenticated()]
        return [IsAdmin()]


class FaseTipoAuditoriaViewSet(viewsets.ModelViewSet):
    serializer_class = FaseTipoSerializer

    def get_queryset(self):
        qs = FaseTipoAuditoria.objects.select_related('tipo_auditoria').order_by('tipo_auditoria', 'orden')
        tipo_id = self.request.query_params.get('tipo_auditoria')
        if tipo_id:
            qs = qs.filter(tipo_auditoria_id=tipo_id)
        return qs

    def get_permissions(self):
        if self.action in ('list', 'retrieve'):
            return [IsAuthenticated()]
        return [IsAdmin()]


class ChecklistItemViewSet(viewsets.ModelViewSet):
    serializer_class = ChecklistItemSerializer

    def get_queryset(self):
        qs = ChecklistItem.objects.select_related('tipo_auditoria', 'fase').order_by('tipo_auditoria', 'orden')
        tipo_id = self.request.query_params.get('tipo_auditoria')
        if tipo_id:
            qs = qs.filter(tipo_auditoria_id=tipo_id)
        return qs

    def get_permissions(self):
        if self.action in ('list', 'retrieve'):
            return [IsAuthenticated()]
        return [IsAdmin()]


class DocumentoRequeridoViewSet(viewsets.ModelViewSet):
    serializer_class = DocumentoRequeridoSerializer

    def get_queryset(self):
        qs = DocumentoRequerido.objects.select_related('tipo_auditoria').order_by('tipo_auditoria', 'orden')
        tipo_id = self.request.query_params.get('tipo_auditoria')
        if tipo_id:
            qs = qs.filter(tipo_auditoria_id=tipo_id)
        return qs

    def get_permissions(self):
        if self.action in ('list', 'retrieve'):
            return [IsAuthenticated()]
        return [IsAdmin()]


class EsquemaFormularioViewSet(viewsets.ModelViewSet):
    serializer_class = EsquemaFormularioSerializer

    def get_queryset(self):
        if getattr(self, 'swagger_fake_view', False):
            return EsquemaFormulario.objects.none()
        qs = EsquemaFormulario.objects.prefetch_related('campos').select_related('tipo_auditoria', 'creado_por')
        tipo = self.request.query_params.get('tipo_auditoria')
        contexto = self.request.query_params.get('contexto')
        if tipo:
            qs = qs.filter(tipo_auditoria_id=tipo)
        if contexto:
            qs = qs.filter(contexto=contexto)
        user = self.request.user
        rol = getattr(user, 'rol', None) if user and user.is_authenticated else None
        if rol == 'SUPERVISOR':
            return qs.all()
        return qs.filter(activo=True)

    def get_permissions(self):
        if self.action in ('list', 'retrieve'):
            return [IsAuthenticated()]
        return [IsAdminOrLider()]

    def perform_create(self, serializer):
        serializer.save(creado_por=self.request.user, origen='MANUAL')

    @staticmethod
    def _resolver_origen(ext, mime):

        if ext == 'pdf' or 'pdf' in mime:
            return 'BOT_PDF'
        if ext in ('docx', 'doc') or 'word' in mime:
            return 'BOT_WORD'
        if ext in ('xlsx', 'xls') or 'excel' in mime or 'spreadsheet' in mime:
            return 'BOT_EXCEL'
        return None

    def _encolar_analisis(self, esquema, tmp_path, mime, origen):

        import os
        from workers.chatbot import analizar_formulario_bot
        try:
            analizar_formulario_bot.delay(
                esquema_id=str(esquema.id),
                ruta_archivo=tmp_path,
                mime_type=mime,
                origen=origen,
            )
        except _BROKER_ERRORS:
            esquema.delete()
            os.remove(tmp_path)
            return Response({'error': _MSG_BROKER_NO_DISPONIBLE}, status=503)
        return None

    @action(detail=False, methods=['post'], url_path='importar-bot',
            permission_classes=[IsAdminOrLider])
    def importar_bot(self, request):
        from rest_framework.parsers import MultiPartParser, FormParser
        archivo  = request.FILES.get('archivo')
        nombre   = request.data.get('nombre', '').strip()
        contexto = request.data.get('contexto', 'EXPEDIENTE')
        tipo_id  = request.data.get('tipo_auditoria')

        if not archivo:
            return Response({'error': 'Se requiere un archivo.'}, status=400)
        if not nombre:
            return Response({'error': 'El nombre del formulario es requerido.'}, status=400)

        mime = archivo.content_type or ''
        ext  = archivo.name.rsplit('.', 1)[-1].lower() if '.' in archivo.name else ''

        origen = self._resolver_origen(ext, mime)
        if origen is None:
            return Response({'error': f'Tipo de archivo no soportado: {ext}. Use PDF, Word o Excel.'}, status=400)

        import os, uuid as _uuid
        from django.conf import settings as djsettings
        tmp_dir  = os.path.join(getattr(djsettings, 'MEDIA_ROOT', '/app/media'), 'formularios_tmp')
        os.makedirs(tmp_dir, exist_ok=True)
        nombre_seguro_bot = os.path.basename(archivo.name)
        tmp_path = os.path.join(tmp_dir, f'{_uuid.uuid4().hex}_{nombre_seguro_bot}')
        with open(tmp_path, 'wb') as f:
            for chunk in archivo.chunks():
                f.write(chunk)

        try:
            esquema = EsquemaFormulario.objects.create(
                nombre=nombre,
                contexto=contexto,
                tipo_auditoria_id=tipo_id if tipo_id else None,
                origen=origen,
                creado_por=request.user,
                activo=False,
            )
            error_resp = self._encolar_analisis(esquema, tmp_path, mime, origen)
            if error_resp is not None:
                return error_resp
            return Response({
                'detail': 'Formulario en procesamiento. El bot extraerá los campos automáticamente.',
                'esquema_id': str(esquema.id),
                'estado': 'PROCESANDO',
            }, status=202)
        except Exception as e:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)
            return Response({'error': f'Error al procesar el formulario: {e}'}, status=500)


class ValorFormularioViewSet(viewsets.ModelViewSet):
    queryset         = ValorFormulario.objects.all()
    serializer_class = ValorFormularioSerializer
    permission_classes = [IsPersonalInterno]

    def perform_create(self, serializer):
        serializer.save(creado_por=self.request.user)


class ExpedienteViewSet(SoftDeleteMixin, viewsets.ModelViewSet):

    def _soft_delete(self, instance):
        if instance.estado in ('COMPLETADO', 'CANCELADO'):
            raise ValidationError({"detail": f'El expediente ya está {instance.get_estado_display()}.'})
        instance.estado = 'CANCELADO'
        instance.save(update_fields=['estado'])
        BitacoraExpediente.registrar(
            expediente=instance, accion='EXPEDIENTE_CANCELADO',
            descripcion='Expediente cancelado (eliminación virtual).',
            usuario=self.request.user, entidad='expediente',
        )
    permission_classes = [IsAuthenticated]

    def get_serializer_class(self):
        if self.action == 'list':
            return ExpedienteListSerializer
        return ExpedienteSerializer

    def get_queryset(self):

        if getattr(self, 'swagger_fake_view', False):
            return Expediente.objects.none()
        user = self.request.user
        qs   = Expediente.objects.select_related(
            'cliente', 'tipo_auditoria', 'auditor_lider', 'ejecutivo'
        ).prefetch_related('fases__fase_tipo', 'equipo__usuario')

        cliente_id = self.request.query_params.get('cliente')
        estado     = self.request.query_params.get('estado')
        if cliente_id:
            qs = qs.filter(cliente_id=cliente_id)
        if estado:
            qs = qs.filter(estado=estado)

        if user.rol in ('SUPERVISOR', 'ASESOR', 'REVISOR'):
            return qs.all()
        if user.rol == 'CLIENTE':


            return qs.filter(
                cliente__contactos__email__iexact=user.email
            ).distinct()
        return qs.filter(
            Q(auditor_lider=user) | Q(equipo__usuario=user)
        ).distinct()

    @action(detail=True, methods=['get', 'post'], url_path='equipo', permission_classes=[IsAdminOrLider])
    def equipo(self, request, pk=None):
        expediente = self.get_object()
        if request.method == 'GET':
            from apps.expedientes.models import AsignacionEquipo
            asignaciones = expediente.equipo.select_related('usuario').filter(activo=True)
            return Response(AsignacionSerializer(asignaciones, many=True).data)
        usuario_id = request.data.get('usuario_id')
        rol        = request.data.get('rol', 'AUDITOR')
        if not usuario_id:
            return Response({'error': 'usuario_id requerido.'}, status=400)
        try:
            usuario = UsuarioInterno.objects.get(id=usuario_id)
        except UsuarioInterno.DoesNotExist:
            return Response({'error': 'Usuario no encontrado.'}, status=404)
        from apps.expedientes.models import AsignacionEquipo
        asig, created = AsignacionEquipo.objects.get_or_create(
            expediente=expediente, usuario=usuario,
            defaults={'rol': rol, 'activo': True},
        )
        if not created:
            asig.rol    = rol
            asig.activo = True
            asig.save(update_fields=['rol', 'activo'])
        BitacoraExpediente.registrar(
            expediente=expediente,
            accion='EQUIPO_ACTUALIZADO',
            descripcion=f'{usuario.nombre_completo} asignado como {rol} al equipo.',
            usuario=request.user,
        )
        return Response(AsignacionSerializer(asig).data, status=201 if created else 200)

    @action(detail=True, methods=['delete'], url_path=r'equipo/(?P<usuario_id>[^/.]+)',
            permission_classes=[IsAdminOrLider])
    def equipo_remover(self, request, pk=None, usuario_id=None):
        expediente = self.get_object()
        from apps.expedientes.models import AsignacionEquipo
        try:
            asig = AsignacionEquipo.objects.get(expediente=expediente, usuario_id=usuario_id)
        except AsignacionEquipo.DoesNotExist:
            return Response({'error': 'Asignación no encontrada.'}, status=404)
        asig.activo = False
        asig.save(update_fields=['activo'])
        BitacoraExpediente.registrar(
            expediente=expediente,
            accion='EQUIPO_REMOVIDO',
            descripcion=f'Usuario {asig.usuario.nombre_completo} removido del equipo.',
            usuario=request.user,
        )
        return Response({'detail': 'Miembro removido del equipo.'})

    @action(detail=True, methods=['get', 'patch'], url_path=r'fases/(?P<fase_id>[^/.]+)',
            permission_classes=[IsAuditTeam])
    def fase_detalle(self, request, pk=None, fase_id=None):
        from apps.expedientes.models import FaseExpediente
        expediente = self.get_object()
        try:
            fase = expediente.fases.get(id=fase_id)
        except FaseExpediente.DoesNotExist:
            return Response({'error': 'Fase no encontrada.'}, status=404)
        if request.method == 'GET':
            return Response(FaseExpedienteSerializer(fase).data)
        serializer = FaseExpedienteSerializer(fase, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        BitacoraExpediente.registrar(
            expediente=expediente,
            accion='FASE_ACTUALIZADA',
            descripcion=f'Fase "{fase.fase_tipo.nombre}" actualizada a {request.data.get("estado", "")}.',
            usuario=request.user,
        )
        return Response(serializer.data)

    @action(detail=True, methods=['get'], url_path='fases', permission_classes=[IsAuthenticated])
    def fases_list(self, request, pk=None):
        expediente = self.get_object()
        fases = expediente.fases.select_related('fase_tipo').order_by('fase_tipo__orden')
        return Response(FaseExpedienteSerializer(fases, many=True).data)

    @action(detail=True, methods=['get'], url_path='checklist', permission_classes=[IsAuthenticated])
    def checklist_list(self, request, pk=None):
        expediente = self.get_object()
        items = expediente.checklist.select_related('item', 'verificado_por', 'evidencia')
        return Response(ChecklistEjecucionSerializer(items, many=True).data)

    @action(detail=True, methods=['patch'], url_path=r'checklist/(?P<item_id>[^/.]+)',
            permission_classes=[IsAuditTeam])
    def checklist_actualizar(self, request, pk=None, item_id=None):
        expediente = self.get_object()
        try:
            item = expediente.checklist.get(id=item_id)
        except Exception:
            return Response({'error': 'Item no encontrado.'}, status=404)
        estado_anterior = item.estado
        serializer = ChecklistEjecucionSerializer(item, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        if 'estado' in request.data and request.data['estado'] != 'PENDIENTE':
            serializer.save(
                verificado_por=request.user,
                fecha_verificacion=timezone.now(),
            )
        else:
            serializer.save()
        expediente.calcular_avance()
        if estado_anterior != item.estado:
            BitacoraExpediente.registrar(
                expediente=expediente,
                accion='CHECKLIST_ACTUALIZADO',
                descripcion=f'Item "{item.item.codigo}" cambiado de {estado_anterior} a {item.estado}.',
                usuario=request.user,
            )
        return Response(serializer.data)

    def perform_create(self, serializer):
        expediente = serializer.save()
        BitacoraExpediente.registrar(
            expediente=expediente,
            accion='EXPEDIENTE_CREADO',
            descripcion=f'Expediente creado por {self.request.user.nombre_completo}',
            usuario=self.request.user,
        )

    @action(detail=True, methods=['get'])
    def bitacora(self, request, pk=None):
        expediente = self.get_object()
        entradas   = expediente.bitacora.select_related('usuario_interno').all()
        return Response(BitacoraSerializer(entradas, many=True).data)

    @action(detail=True, methods=['post'], url_path='bitacora_nota')
    def bitacora_nota(self, request, pk=None):


        expediente  = self.get_object()
        descripcion = request.data.get('descripcion', '').strip()
        if not descripcion:
            return Response({'error': 'La descripción no puede estar vacía.'}, status=400)
        if len(descripcion) > 2000:
            return Response({'error': 'Máximo 2000 caracteres.'}, status=400)
        BitacoraExpediente.registrar(
            expediente=expediente,
            accion='NOTA_MANUAL',
            descripcion=descripcion,
            usuario=request.user,
            entidad='expediente',
        )
        return Response({'detail': 'Nota registrada en bitácora.'}, status=201)

    @action(detail=True, methods=['get'])
    def dashboard(self, request, pk=None):
        exp = self.get_object()
        hallazgos_por_criticidad = dict(
            exp.hallazgos.values('nivel_criticidad')
            .annotate(total=Count('id'))
            .values_list('nivel_criticidad', 'total')
        )
        checklist  = exp.checklist.values('estado').annotate(total=Count('id'))
        documentos = exp.documentos.values('estado').annotate(total=Count('id'))
        return Response({
            'numero':                    exp.numero_expediente,
            'estado':                    exp.estado,
            'porcentaje_avance':         float(exp.porcentaje_avance),
            'hallazgos_por_criticidad':  hallazgos_por_criticidad,
            'checklist':                 list(checklist),
            'documentos':                list(documentos),
        })


    _TRANSICIONES_VALIDAS = {
        'BORRADOR':     ['ACTIVO', 'CANCELADO'],
        'ACTIVO':       ['EN_EJECUCION', 'SUSPENDIDO', 'CANCELADO'],
        'EN_EJECUCION': ['COMPLETADO', 'SUSPENDIDO', 'CANCELADO'],
        'SUSPENDIDO':   ['ACTIVO', 'CANCELADO'],
        'COMPLETADO':   [],
        'CANCELADO':    [],
    }

    @action(detail=True, methods=['post'])
    def cambiar_estado(self, request, pk=None):
        expediente    = self.get_object()
        nuevo_estado  = request.data.get('estado')
        motivo        = request.data.get('motivo', '')

        estados_validos = [s[0] for s in Expediente.ESTADO_CHOICES]
        if nuevo_estado not in estados_validos:
            return Response({'error': f'Estado no válido. Opciones: {estados_validos}'}, status=400)

        estado_anterior = expediente.estado
        permitidos = self._TRANSICIONES_VALIDAS.get(estado_anterior, [])
        if nuevo_estado not in permitidos:
            return Response({
                'error': (
                    f'Transición inválida: {estado_anterior} → {nuevo_estado}. '
                    f'Transiciones permitidas desde {estado_anterior}: '
                    f'{permitidos if permitidos else "ninguna (estado terminal)"}'
                )
            }, status=400)

        expediente.estado = nuevo_estado
        if nuevo_estado == 'COMPLETADO':
            expediente.fecha_cierre_real = timezone.now().date()
        update_fields = ['estado', 'fecha_cierre_real'] if nuevo_estado == 'COMPLETADO' else ['estado']
        expediente.save(update_fields=update_fields)
        BitacoraExpediente.registrar(
            expediente=expediente,
            accion='CAMBIO_ESTADO',
            descripcion=f'Estado cambiado de {estado_anterior} a {nuevo_estado}. Motivo: {motivo}',
            usuario=request.user,
        )
        return Response(ExpedienteSerializer(expediente).data)


class HallazgoViewSet(SoftDeleteMixin, viewsets.ModelViewSet):
    queryset = Hallazgo.objects.select_related(
        'expediente', 'reportado_por', 'asignado_a'
    ).all()

    def _soft_delete(self, instance):
        instance.estado = 'CERRADO'
        instance.save(update_fields=['estado'])
    serializer_class   = HallazgoSerializer
    permission_classes = [IsAuditTeam]
    filterset_fields   = ['expediente', 'tipo', 'nivel_criticidad', 'estado', 'asignado_a']

    def perform_create(self, serializer):
        hallazgo = serializer.save(reportado_por=self.request.user)
        BitacoraExpediente.registrar(
            expediente=hallazgo.expediente,
            accion='HALLAZGO_CREADO',
            descripcion=f'Hallazgo [{hallazgo.nivel_criticidad}]: {hallazgo.titulo}',
            usuario=self.request.user,
            entidad='hallazgo',
        )


class EvidenciaViewSet(SoftDeleteMixin, viewsets.ModelViewSet):
    queryset = Evidencia.objects.select_related('expediente', 'hallazgo', 'subido_por').all()

    def _soft_delete(self, instance):


        if not instance.nombre.startswith('[INACTIVA]'):
            instance.nombre = '[INACTIVA] ' + instance.nombre
            instance.save(update_fields=['nombre'])

        if not instance.descripcion.startswith('[INACTIVA]'):
            instance.descripcion = '[INACTIVA] ' + instance.descripcion
            instance.save(update_fields=['nombre', 'descripcion'])
    serializer_class   = EvidenciaSerializer
    permission_classes = [IsAuditTeam]
    filterset_fields   = ['expediente', 'hallazgo']

    def perform_create(self, serializer):
        archivo = self.request.FILES.get('archivo')
        if not archivo:
            raise ValidationError({'archivo': 'Se requiere un archivo adjunto para crear una evidencia.'})
        evidencia = serializer.save(
            subido_por=self.request.user,
            nombre_original=archivo.name,
            tipo_archivo=archivo.content_type,
            tamanio_bytes=archivo.size,
        )
        BitacoraExpediente.registrar(
            expediente=evidencia.expediente,
            accion='EVIDENCIA_SUBIDA',
            descripcion=f'Evidencia subida: {evidencia.nombre_original} ({evidencia.tamanio_bytes:,} bytes)',
            usuario=self.request.user,
            entidad='evidencia',
        )


class ChecklistEjecucionViewSet(SoftDeleteMixin, viewsets.ModelViewSet):
    def _soft_delete(self, instance):


        instance.estado = 'NO_APLICA'
        instance.save(update_fields=['estado'])

    serializer_class   = ChecklistEjecucionSerializer
    permission_classes = [IsAuditTeam]
    filterset_fields   = ['expediente', 'estado']

    def get_queryset(self):
        if getattr(self, 'swagger_fake_view', False):
            return ChecklistEjecucion.objects.none()

        qs = ChecklistEjecucion.objects.select_related(
            'item', 'verificado_por', 'expediente'
        )


        expediente_id = self.request.query_params.get('expediente')
        if expediente_id:
            qs = qs.filter(expediente_id=expediente_id)
        elif self.action == 'list':

            return ChecklistEjecucion.objects.none()


        user = self.request.user
        rol  = getattr(user, 'rol', None)
        if rol == 'SUPERVISOR':
            return qs

        return qs.filter(
            Q(expediente__auditor_lider=user) |
            Q(expediente__equipo__usuario=user)
        ).distinct()

    def perform_update(self, serializer):


        from django.utils import timezone
        estado_nuevo = serializer.validated_data.get('estado', serializer.instance.estado)
        if estado_nuevo != 'PENDIENTE':
            serializer.save(
                verificado_por=self.request.user,
                fecha_verificacion=timezone.now(),
            )
        else:

            serializer.save(
                verificado_por=None,
                fecha_verificacion=None,
            )


        from django.utils import timezone
        estado_nuevo = serializer.validated_data.get('estado', serializer.instance.estado)
        if estado_nuevo != 'PENDIENTE':
            serializer.save(
                verificado_por=self.request.user,
                fecha_verificacion=timezone.now(),
            )
        else:

            serializer.save(
                verificado_por=None,
                fecha_verificacion=None,
            )


class DocumentoExpedienteViewSet(SoftDeleteMixin, viewsets.ModelViewSet):
    queryset = DocumentoExpediente.objects.select_related(
        'expediente', 'subido_por', 'revisado_por', 'documento_requerido'
    ).all()

    def _soft_delete(self, instance):
        instance.estado = 'RECHAZADO'
        instance.save(update_fields=['estado'])
    serializer_class   = DocumentoExpedienteSerializer
    permission_classes = [IsAuthenticated]
    filterset_fields   = ['expediente', 'estado']

    def perform_create(self, serializer):
        serializer.save(subido_por=self.request.user)

    @action(detail=True, methods=['post'], permission_classes=[IsAdminOrLider])
    def revisar(self, request, pk=None):
        documento     = self.get_object()
        nuevo_estado  = request.data.get('estado')
        observacion   = request.data.get('observacion', '')
        if nuevo_estado not in ('APROBADO', 'RECHAZADO'):
            return Response({'error': 'Estado debe ser APROBADO o RECHAZADO.'}, status=400)
        documento.estado              = nuevo_estado
        documento.revisado_por        = request.user
        documento.fecha_revision      = timezone.now()
        documento.observacion_revision = observacion
        documento.save(update_fields=['estado', 'revisado_por', 'fecha_revision', 'observacion_revision'])
        BitacoraExpediente.registrar(
            expediente=documento.expediente,
            accion=f'DOCUMENTO_{nuevo_estado}',
            descripcion=f'Documento "{documento.nombre}" {nuevo_estado.lower()}. {observacion}',
            usuario=request.user,
            entidad='documento',
        )
        log_doc_review(
            nombre=documento.nombre,
            expediente=str(documento.expediente.numero_expediente),
            nuevo_estado=nuevo_estado,
            user=getattr(request.user, 'email', str(request.user)),
            observacion=observacion,
        )
        return Response(DocumentoExpedienteSerializer(documento).data)


class CertificacionViewSet(SoftDeleteMixin, viewsets.ModelViewSet):
    queryset = Certificacion.objects.select_related(
        'cliente', 'tipo_auditoria', 'expediente', 'emitido_por'
    ).all()

    def _soft_delete(self, instance):
        instance.estado = 'REVOCADA'
        instance.save(update_fields=['estado'])
    serializer_class = CertificacionSerializer
    filterset_fields = ['estado', 'cliente', 'tipo_auditoria', 'tipo_emision']

    def get_permissions(self):


        if self.action in ('list', 'retrieve', 'verificar'):
            return [IsAuthenticated()]
        return [IsAdminOrLider()]

    def perform_create(self, serializer):
        expediente = serializer.validated_data.get('expediente')
        cliente    = serializer.validated_data.get('cliente')
        if expediente and cliente and str(expediente.cliente_id) != str(cliente.id):
            raise ValidationError({
                'expediente': (
                    'El expediente no pertenece al cliente indicado. '
                    'Asegúrate de que expediente y cliente correspondan al mismo contrato.'
                )
            })
        serializer.save(emitido_por=self.request.user)

    @action(detail=False, methods=['get'], permission_classes=[AllowAny], url_path='verificar')
    def verificar(self, request):
        codigo = request.query_params.get('codigo', '').strip()
        if not codigo:
            return Response({'error': 'Parámetro "codigo" requerido.'}, status=400)
        try:
            cert = Certificacion.objects.select_related(
                'cliente', 'tipo_auditoria'
            ).get(codigo_verificacion=codigo)
            return Response({
                'valido':          True,
                'numero':          cert.numero,
                'cliente':         cert.cliente.razon_social,
                'tipo_auditoria':  cert.tipo_auditoria.nombre,
                'fecha_emision':   cert.fecha_emision,
                'fecha_vencimiento': cert.fecha_vencimiento,
                'estado':          cert.estado,
                'dias_para_vencer': cert.dias_para_vencer,
            })
        except Certificacion.DoesNotExist:
            return Response({'valido': False, 'error': 'Certificado no encontrado.'}, status=200)

    @action(detail=True, methods=['get'])
    def generar_pdf(self, request, pk=None):
        certificacion = self.get_object()
        from workers.reportes import generar_informe_pdf
        try:
            task = generar_informe_pdf.delay(str(certificacion.id))
        except _BROKER_ERRORS as exc:
            logger.error('Broker no disponible para PDF: %s', exc)
            return Response(
                {'error': 'El servicio de generación de PDFs no está disponible. Intenta en unos segundos.'},
                status=503,
            )
        return Response({
            'task_id': task.id,
            'detail':  'Generación de PDF iniciada. Recibirás una notificación cuando esté listo.',
        })


class ConversacionViewSet(SoftDeleteMixin, viewsets.ModelViewSet):
    serializer_class   = ConversacionSerializer

    def _soft_delete(self, instance):
        instance.estado = 'CERRADA'
        instance.save(update_fields=['estado'])


    permission_classes = [CanUseChatbot]

    def get_queryset(self):
        if getattr(self, 'swagger_fake_view', False):
            return Conversacion.objects.none()

        user = self.request.user
        rol  = getattr(user, 'rol', None)


        if rol == 'SUPERVISOR':
            qs = Conversacion.objects.all()
        else:
            qs = Conversacion.objects.filter(usuario_interno=user)

        qs = qs.order_by('-fecha_actualizacion')

        expediente_id = self.request.query_params.get('expediente')
        if expediente_id:
            qs = qs.filter(expediente_id=expediente_id)


        limit = self.request.query_params.get('limit')
        if limit:
            try:
                return list(qs[:int(limit)])
            except (ValueError, TypeError):
                pass

        return qs

    def perform_create(self, serializer):


        canal = self.request.data.get('canal', '').upper()
        if canal not in ('WEB', 'MOVIL', 'INTERNO'):
            ua = self.request.META.get('HTTP_USER_AGENT', '').lower()
            canal = 'MOVIL' if ('okhttp' in ua or 'dart' in ua) else 'WEB'

        serializer.save(usuario_interno=self.request.user, canal=canal)

    @action(detail=True, methods=['post'])
    def enviar_mensaje(self, request, pk=None):
        conversacion = self.get_object()
        contenido    = request.data.get('contenido', '').strip()


        trace = _new_trace_id()

        _ids_log(_IDS_API,
                 conv_id=str(conversacion.id),
                 trace_id=trace,
                 msg='enviar_mensaje_request',
                 user=str(request.user.id),
                 contenido_len=len(contenido))

        if not contenido:
            _ids_log(_IDS_ERROR, conv_id=str(conversacion.id), trace_id=trace,
                     level='warning', msg='enviar_mensaje_rejected', reason='empty_content')
            return Response({'error': 'El mensaje no puede estar vacío.'}, status=400)
        if len(contenido) > 4000:
            _ids_log(_IDS_ERROR, conv_id=str(conversacion.id), trace_id=trace,
                     level='warning', msg='enviar_mensaje_rejected', reason='content_too_long')
            return Response({'error': 'El mensaje excede el límite de 4000 caracteres.'}, status=400)


        msg_usuario = MensajeConversacion.objects.create(
            conversacion=conversacion,
            rol='USUARIO',
            contenido=contenido,
        )
        _ids_log(_IDS_API, conv_id=str(conversacion.id), trace_id=trace,
                 msg='mensaje_guardado', msg_id=str(msg_usuario.id))


        from config.celery import app as _celery_app
        _ids_log(_IDS_CELERY,
                 conv_id=str(conversacion.id),
                 trace_id=trace,
                 msg='pre_publish_broker_state',
                 celery_app_broker_url=str(_celery_app.conf.broker_url),
                 env_RABBITMQ_URL=os.environ.get('RABBITMQ_URL', '<NOT_SET>'),
                 pool_limit=str(_celery_app.conf.broker_pool_limit),
                 failover=str(_celery_app.conf.broker_failover_strategy))

        from workers.chatbot import procesar_mensaje_chatbot
        try:


            task = procesar_mensaje_chatbot.apply_async(
                args=[str(conversacion.id), contenido, str(msg_usuario.id)],
                headers={'trace_id': trace},
            )
            _ids_log(_IDS_CELERY, conv_id=str(conversacion.id), trace_id=trace,
                     msg='task_published_ok',
                     celery_task_id=str(task.id),
                     msg_id=str(msg_usuario.id),
                     queue='default')
        except _BROKER_ERRORS as exc:


            msg_usuario.delete()
            _ids_log(_IDS_ERROR, conv_id=str(conversacion.id), trace_id=trace,
                     level='error',
                     msg='broker_unavailable',
                     exc_type=type(exc).__name__,
                     detail=str(exc))


            _broker_diag(conv_id=str(conversacion.id), trace_id=trace)
            logger.error(
                '[IDS][BROKER] Broker no disponible conv=%s trace=%s exc=%s: %s',
                conversacion.id, trace, type(exc).__name__, exc,
            )
            return Response(
                {'error': _MSG_BROKER_NO_DISPONIBLE},
                status=503,
            )
        return Response({'detail': 'Mensaje recibido. El asistente está procesando tu consulta.'})

    @action(detail=True, methods=['get'])
    def mensajes(self, request, pk=None):
        conversacion = self.get_object()
        msgs         = conversacion.mensajes.order_by('fecha')
        return Response(MensajeSerializer(msgs, many=True).data)

    def destroy(self, request, *args, **kwargs):


        conversacion = self.get_object()
        conversacion.delete()
        return Response(status=204)


class ChatbotStatusView(APIView):


    permission_classes = [IsAuthenticated]

    def get(self, request):
        import requests as req
        from django.conf import settings
        modelo   = getattr(settings, 'OLLAMA_MODEL',    'llama3.1:8b')
        base_url = getattr(settings, 'OLLAMA_BASE_URL', 'http://localhost:11434')

        disponible   = False
        modelo_listo = False

        try:
            r = req.get(f'{base_url}/', timeout=3)
            disponible = r.status_code == 200

            if disponible:
                r2 = req.get(f'{base_url}/api/tags', timeout=3)
                if r2.status_code == 200:
                    modelos     = r2.json().get('models', [])
                    nombres     = [m.get('name', '').split(':')[0] for m in modelos]
                    modelo_base = modelo.split(':')[0]
                    modelo_listo = any(modelo_base in n for n in nombres)
        except Exception:
            pass

        return Response({
            'disponible':        disponible and modelo_listo,
            'ollama_activo':     disponible,
            'modelo_descargado': modelo_listo,
            'modelo':            modelo,

            'mensaje': (
                'Listo' if (disponible and modelo_listo) else
                ('Descargando modelo...' if disponible else 'Ollama no disponible')
            ),
        })


class VisitaAgendadaViewSet(SoftDeleteMixin, viewsets.ModelViewSet):


    from adapters.api.serializers import VisitaAgendadaSerializer
    from apps.expedientes.models import VisitaAgendada

    queryset           = VisitaAgendada.objects.select_related(
        'expediente', 'fase', 'creado_por'
    ).prefetch_related('participantes').all()
    serializer_class   = VisitaAgendadaSerializer
    permission_classes = [IsAuditTeam]
    filterset_fields   = ['expediente', 'estado', 'tipo', 'fase']

    def get_queryset(self):
        qs  = super().get_queryset()

        desde = self.request.query_params.get('desde')
        hasta = self.request.query_params.get('hasta')
        if desde:
            qs = qs.filter(fecha_inicio__date__gte=desde)
        if hasta:
            qs = qs.filter(fecha_inicio__date__lte=hasta)
        return qs.order_by('fecha_inicio')

    def perform_create(self, serializer):
        serializer.save(creado_por=self.request.user)

    def _soft_delete(self, instance):
        instance.estado = 'CANCELADA'
        instance.save(update_fields=['estado'])


class DashboardGlobalView(APIView):

    permission_classes = [IsInternalUser]

    def get(self, request):
        user = request.user
        rol  = getattr(user, 'rol', None)


        if rol in ('SUPERVISOR', 'ASESOR', 'REVISOR'):
            exp_qs = Expediente.objects.all()
        else:

            exp_qs = Expediente.objects.filter(
                Q(auditor_lider=user) | Q(equipo__usuario=user)
            ).distinct()

        data = {
            'expedientes_activos':        exp_qs.filter(estado__in=['ACTIVO', 'EN_EJECUCION']).count(),
            'expedientes_completados':    exp_qs.filter(estado='COMPLETADO').count(),
            'certificaciones_vigentes':   Certificacion.objects.filter(estado='VIGENTE').count(),
            'certificaciones_por_vencer': Certificacion.objects.filter(estado='POR_VENCER').count(),
            'hallazgos_criticos_abiertos': Hallazgo.objects.filter(
                nivel_criticidad='CRITICO', estado='ABIERTO'
            ).count(),
            'expedientes_por_estado': list(
                exp_qs.values('estado').annotate(total=Count('id'))
            ),
        }


        if rol in ('SUPERVISOR', 'ASESOR', 'REVISOR'):
            data['clientes_activos'] = Cliente.objects.filter(estado='ACTIVO').count()
        else:
            data['clientes_activos'] = None

        return Response(data)


DashboardView = DashboardGlobalView


class BitacoraGlobalView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        from apps.seguridad.models import AuditLogSistema
        qs          = AuditLogSistema.objects.select_related('usuario').order_by('-fecha')
        fecha_desde = request.query_params.get('desde')
        if fecha_desde:
            qs = qs.filter(fecha__date__gte=fecha_desde)
        logs = qs[:500]
        data = [{
            'id':        str(log.id),
            'fecha':     log.fecha.isoformat(),
            'usuario':   log.usuario.email if log.usuario else None,
            'accion':    log.accion,
            'recurso':   log.recurso,
            'resultado': log.resultado,
            'ip':        log.ip_origen,
        } for log in logs]
        return Response({'bitacora': data, 'total': len(data)})


class ExportarReporteView(APIView):
    permission_classes = [IsAdminOrLider]

    def post(self, request):
        tipo        = request.data.get('tipo', 'expedientes')
        filtros     = request.data.get('filtros', {})
        valid_tipos = ['expedientes', 'hallazgos', 'certificaciones', 'clientes']
        if tipo not in valid_tipos:
            return Response(
                {'error': f'Tipo inválido. Opciones: {valid_tipos}'},
                status=400,
            )


        filtros['_user_id'] = str(request.user.id)
        from workers.reportes import generar_reporte_excel
        try:
            task = generar_reporte_excel.delay(tipo, filtros)
        except _BROKER_ERRORS as exc:
            logger.error('Broker no disponible para reporte Excel: %s', exc)
            return Response(
                {'error': 'El servicio de reportes no está disponible. Intenta en unos segundos.'},
                status=503,
            )
        return Response({
            'task_id': task.id,
            'mensaje': f'Generando reporte de {tipo}. Recibirás una notificación cuando esté listo.',
        }, status=202)


DocumentoViewSet = DocumentoExpedienteViewSet


class SeedDemoView(APIView):


    permission_classes = [IsAdmin]

    def post(self, request):
        from apps.tipos_auditoria.models import (
            TipoAuditoria, FaseTipoAuditoria, ChecklistItem, DocumentoRequerido
        )
        TIPOS = [
            {
                'codigo': 'ISO27001', 'nombre': 'ISO 27001 — Seguridad de la Información',
                'categoria': 'SEGURIDAD', 'nivel': 'AVANZADO', 'duracion': 60,
                'fases': ['Inicio y Planificación','Análisis de Riesgos','Evaluación de Controles','Informe y Certificación'],
                'checklist': ['Política de seguridad documentada','Inventario de activos actualizado','Análisis de riesgos realizado','Controles de acceso implementados','Plan de continuidad documentado'],
                'docs': ['Política de Seguridad','Inventario de Activos','Registro de Riesgos','Plan de Continuidad'],
            },
            {
                'codigo': 'ISO9001', 'nombre': 'ISO 9001 — Gestión de Calidad',
                'categoria': 'CALIDAD', 'nivel': 'INTERMEDIO', 'duracion': 45,
                'fases': ['Revisión Documental','Auditoría en Campo','Verificación de Hallazgos','Certificación'],
                'checklist': ['Manual de calidad documentado','Procesos de proveedores definidos','Indicadores establecidos','Acciones correctivas documentadas','Revisión por dirección realizada'],
                'docs': ['Manual de Calidad','Mapa de Procesos','Registros de No Conformidades','Informes de Auditoría'],
            },
            {
                'codigo': 'SOC2', 'nombre': 'SOC 2 Tipo II — Controles de Servicio',
                'categoria': 'SEGURIDAD', 'nivel': 'AVANZADO', 'duracion': 90,
                'fases': ['Definición de Alcance','Período de Observación','Pruebas de Controles','Informe Final'],
                'checklist': ['Controles de disponibilidad documentados','Controles de confidencialidad implementados','Monitoreo activo','Gestión de acceso privilegiado','Pruebas de penetración realizadas'],
                'docs': ['Descripción del Sistema','Políticas de Seguridad','Evidencias de Controles','Resultados de Pruebas'],
            },
            {
                'codigo': 'ISO45001', 'nombre': 'ISO 45001 — Seguridad Ocupacional',
                'categoria': 'AMBIENTAL', 'nivel': 'INTERMEDIO', 'duracion': 30,
                'fases': ['Revisión Inicial','Evaluación de Riesgos','Verificación de Cumplimiento','Certificación'],
                'checklist': ['Política SSO aprobada','Identificación de peligros','Programa de capacitación','Registros de accidentes actualizados','Comité paritario activo'],
                'docs': ['Política SSO','Matriz de Riesgos','Registros de Capacitación','Estadísticas de Accidentalidad'],
            },
        ]
        creados = 0
        for t in TIPOS:
            tipo, created = TipoAuditoria.objects.get_or_create(
                codigo=t['codigo'],
                defaults={
                    'nombre': t['nombre'], 'categoria': t['categoria'],
                    'nivel': t['nivel'], 'duracion_estimada_dias': t['duracion'],
                    'activo': True,
                }
            )
            if created:
                creados += 1
                for i, nombre_fase in enumerate(t['fases'], 1):
                    fase = FaseTipoAuditoria.objects.create(
                        tipo_auditoria=tipo, nombre=nombre_fase, orden=i,
                        duracion_estimada_dias=7,
                        es_fase_final=(i == len(t['fases'])),
                    )
                    if i <= len(t['checklist']):
                        ChecklistItem.objects.create(
                            tipo_auditoria=tipo, fase=fase,
                            codigo=f"{tipo.codigo}-{i:02d}",
                            descripcion=t['checklist'][i-1],
                            categoria='DOCUMENTAL', obligatorio=True, orden=i,
                        )
                for j, nombre_doc in enumerate(t['docs'], 1):
                    DocumentoRequerido.objects.create(
                        tipo_auditoria=tipo, nombre=nombre_doc,
                        obligatorio=True, orden=j,
                    )
        return Response({
            'detail': f'{creados} tipo(s) creado(s). {len(TIPOS)-creados} ya existían.',
            'creados': creados,
        }, status=201 if creados > 0 else 200)


class AnalizarDocumentoChatbotView(APIView):


    permission_classes = [IsAuthenticated, CanUseChatbot]


    from rest_framework.parsers import MultiPartParser, FormParser
    parser_classes = [MultiPartParser, FormParser]

    _EXTENSIONES_PELIGROSAS = {
        '.exe', '.bat', '.sh', '.ps1', '.cmd', '.com', '.msi', '.dll',
        '.vbs', '.jar', '.py', '.rb', '.php', '.pl', '.scr',
        '.pif', '.reg', '.lnk', '.hta', '.wsf', '.inf', '.iso',
    }
    _MAX_BYTES = 50 * 1024 * 1024

    def post(self, request):
        import os, uuid
        from django.conf import settings
        from apps.chatbot.models import Conversacion, MensajeConversacion


        conversacion_id = request.data.get('conversacion_id', '').strip()
        if not conversacion_id:
            return Response({'error': 'conversacion_id requerido.'}, status=400)

        archivo = request.FILES.get('archivo')
        if not archivo:
            return Response({'error': 'Se requiere un archivo adjunto.'}, status=400)

        pregunta = request.data.get('pregunta', '').strip()


        nombre   = archivo.name
        ext      = os.path.splitext(nombre.lower())[1]
        if ext in self._EXTENSIONES_PELIGROSAS:
            return Response(
                {'error': f'Extensión bloqueada por seguridad: {ext}. '
                          f'No se permiten archivos ejecutables o scripts.'},
                status=400,
            )


        if archivo.size > self._MAX_BYTES:
            return Response(
                {'error': f'Archivo demasiado grande ({archivo.size // (1024*1024)} MB). '
                          f'Máximo permitido: 50 MB.'},
                status=400,
            )


        try:
            conv = Conversacion.objects.select_related('usuario_interno').get(
                id=conversacion_id
            )
        except (Conversacion.DoesNotExist, Exception):
            return Response({'error': 'Conversación no encontrada.'}, status=404)


        usuario = request.user
        es_admin = getattr(usuario, 'rol', '') == 'SUPERVISOR'
        if not es_admin and str(getattr(conv, 'usuario_interno_id', '')) != str(usuario.id):
            return Response({'error': 'No tienes acceso a esta conversación.'}, status=403)


        media_root  = getattr(settings, 'MEDIA_ROOT', '/app/media')
        conv_id_seguro = os.path.basename(str(conversacion_id))
        carpeta     = os.path.join(media_root, 'analisis_temp', conv_id_seguro)
        os.makedirs(carpeta, exist_ok=True)

        nombre_base   = os.path.basename(nombre)
        nombre_seguro = f'{uuid.uuid4().hex}_{nombre_base}'
        ruta_archivo  = os.path.join(carpeta, nombre_seguro)

        try:
            with open(ruta_archivo, 'wb') as f:
                for chunk in archivo.chunks():
                    f.write(chunk)
        except Exception as e:
            return Response({'error': f'Error guardando archivo: {e}'}, status=500)


        cuerpo_pregunta = f'\n{pregunta}' if pregunta else '\n*Analiza este documento.*'
        contenido_usuario = f'📎 **Documento adjunto:** `{nombre}`\n' + cuerpo_pregunta
        msg_usuario = MensajeConversacion.objects.create(
            conversacion=conv,
            rol='USUARIO',
            contenido=contenido_usuario,
            tokens_usados=0,
        )


        mime_type = archivo.content_type or 'application/octet-stream'
        trace_id  = _new_trace_id()
        _op_id    = new_op_id()
        _user_str = getattr(usuario, 'email', str(usuario))
        _ip_str = (
            request.META.get('HTTP_X_FORWARDED_FOR', '').split(',')[0].strip()
            or request.META.get('REMOTE_ADDR', '?')
        )

        log_doc_upload(
            nombre=nombre, mime_type=mime_type, size_bytes=archivo.size,
            conv_id=str(conversacion_id), user=_user_str, ip=_ip_str,
            op_id=_op_id, seguro=True,
        )

        try:
            from workers.chatbot import analizar_documento_chatbot
            task = analizar_documento_chatbot.apply_async(
                kwargs={
                    'conversacion_id': str(conversacion_id),
                    'documento_id':    str(msg_usuario.id),
                    'nombre_archivo':  nombre,
                    'mime_type':       mime_type,
                    'tamanio_bytes':   archivo.size,
                    'ruta_archivo':    ruta_archivo,
                    'pregunta_usuario': pregunta,
                },
                headers={'trace_id': trace_id},
            )
            _ids_log(_IDS_CELERY,
                     msg='analizar_documento_task_enqueued',
                     conv_id=str(conversacion_id),
                     nombre=nombre,
                     tamanio_bytes=archivo.size,
                     trace_id=trace_id)
            log_task_enqueue(
                'analizar_documento_chatbot',
                task_id=str(task.id),
                op_id=_op_id,
                nombre=nombre,
                conv_id=str(conversacion_id),
            )
        except _BROKER_ERRORS as e:

            os.remove(ruta_archivo)
            msg_usuario.delete()
            _ids_log(_IDS_ERROR,
                     msg='broker_unavailable_for_doc_analysis',
                     detail=str(e))
            return Response({'error': _MSG_BROKER_NO_DISPONIBLE}, status=503)

        return Response({
            'detail':   'Documento recibido. El análisis llegará en breve al chat.',
            'msg_id':   str(msg_usuario.id),
            'trace_id': trace_id,
        }, status=202)


class MisPermisosView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response({
            'rol':               request.user.rol,
            'tipo_contratacion': getattr(request.user, 'tipo_contratacion', ''),
            'permisos':          request.user.permisos_efectivos(),
        })


DocumentoViewSet = DocumentoExpedienteViewSet
