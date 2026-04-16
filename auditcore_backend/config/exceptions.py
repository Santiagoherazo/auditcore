from django.core.exceptions import ObjectDoesNotExist
from rest_framework.views import exception_handler
from rest_framework.response import Response
from rest_framework import status


def drf_exception_handler(exc, context):
    """
    Handler DRF personalizado.

    Convierte ObjectDoesNotExist (incluyendo UsuarioInterno.DoesNotExist)
    en HTTP 401 cuando ocurre en endpoints de autenticación JWT.
    Sin este handler, simplejwt en versiones antiguas deja que DoesNotExist
    propagule hasta Django y se convierte en 500, cuando el comportamiento
    correcto es 401 (token inválido porque el usuario ya no existe).
    """
    if isinstance(exc, ObjectDoesNotExist):
        request = context.get('request')
        path = getattr(request, 'path', '')
        if path and '/auth/' in path:
            return Response(
                {'detail': 'Token inválido o usuario no encontrado.'},
                status=status.HTTP_401_UNAUTHORIZED,
            )

    return exception_handler(exc, context)
