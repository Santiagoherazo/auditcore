import logging

from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status

from adapters.api.permissions import CanCreateClientes

logger = logging.getLogger(__name__)


class ClienteDraftCreateView(APIView):


    permission_classes = [CanCreateClientes]

    def post(self, request):
        from apps.clientes.draft_service import create_draft
        data = request.data.copy()
        if not data.get('razon_social') or not data.get('nit'):
            return Response(
                {'error': 'Los campos razon_social y nit son obligatorios.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        draft_id = create_draft(request.user.pk, data)
        return Response({'draft_id': draft_id}, status=status.HTTP_201_CREATED)


class ClienteDraftUpdateView(APIView):


    permission_classes = [CanCreateClientes]

    def patch(self, request, draft_id):
        from apps.clientes.draft_service import update_draft
        draft = update_draft(draft_id, request.user.pk, request.data.copy())
        if draft is None:
            return Response(
                {'error': 'Draft no encontrado o expirado. Por favor reinicia el formulario.'},
                status=status.HTTP_404_NOT_FOUND,
            )
        return Response({'draft_id': draft_id}, status=status.HTTP_200_OK)


class ClienteDraftCommitView(APIView):


    permission_classes = [CanCreateClientes]

    def post(self, request, draft_id):
        from apps.clientes.draft_service import commit_draft
        try:
            result = commit_draft(draft_id, request.user.pk)
        except ValueError as exc:
            return Response({'error': str(exc)}, status=status.HTTP_404_NOT_FOUND)
        except Exception as exc:

            exc_str = str(exc).lower()
            if 'unique' in exc_str and 'nit' in exc_str:
                return Response(
                    {'error': 'Ya existe un cliente con ese NIT. Verifica el número ingresado.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            if 'unique' in exc_str:
                return Response(
                    {'error': f'Ya existe un registro con ese valor. Detalle: {exc}'},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            logger.exception('Error en commit_draft %s', draft_id)
            return Response(
                {'error': f'Error al guardar el cliente: {exc}'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )

        cliente  = result['cliente']
        warnings = result['warnings']


        contacto = result.get('contacto')
        if contacto and contacto.email:
            try:
                from apps.clientes.models import AccesoTemporalCaracterizacion
                AccesoTemporalCaracterizacion.objects.create(
                    cliente       = cliente,
                    contacto      = contacto,
                    email_destino = contacto.email,
                    creado_por    = request.user,
                )
            except Exception as exc:
                warnings.append(f'Acceso de caracterización no creado: {exc}')

        from adapters.api.serializers import ClienteSerializer
        return Response({
            'cliente':  ClienteSerializer(cliente, context={'request': request}).data,
            'warnings': warnings,
        }, status=status.HTTP_201_CREATED)
