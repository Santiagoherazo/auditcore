from django.core.exceptions import ObjectDoesNotExist
from rest_framework.views import exception_handler
from rest_framework.response import Response
from rest_framework import status
from rest_framework.exceptions import (
    PermissionDenied, NotAuthenticated, AuthenticationFailed,
    NotFound, MethodNotAllowed, Throttled,
)


# Traducciones de los mensajes estándar de DRF al español
_TRADUCCIONES = {
    'You do not have permission to perform this action.':
        'No tienes permisos para realizar esta acción.',
    'Authentication credentials were not provided.':
        'No se proporcionaron credenciales de autenticación.',
    'Invalid token.':
        'Token inválido.',
    'Token has expired.':
        'El token ha expirado.',
    'Token is invalid or expired':
        'El token es inválido o ha expirado.',
    'Not found.':
        'Recurso no encontrado.',
    'Method "{method}" not allowed.':
        'Método "{method}" no permitido.',
    'Request was throttled. Expected available in {wait} second.':
        'Demasiadas solicitudes. Intenta en {wait} segundo.',
    'Request was throttled. Expected available in {wait} seconds.':
        'Demasiadas solicitudes. Intenta en {wait} segundos.',
}


def _traducir(detail):
    """Traduce un mensaje de error DRF al español si existe traducción."""
    if isinstance(detail, str):
        return _TRADUCCIONES.get(detail, detail)
    return detail


def drf_exception_handler(exc, context):
    """
    Handler DRF personalizado:
    1. Convierte ObjectDoesNotExist en 401 en endpoints de auth (token con usuario borrado).
    2. Traduce mensajes de error estándar de DRF al español.
    """
    # Caso especial: usuario del token ya no existe
    if isinstance(exc, ObjectDoesNotExist):
        request = context.get('request')
        path = getattr(request, 'path', '')
        if path and '/auth/' in path:
            return Response(
                {'detail': 'Token inválido o usuario no encontrado.'},
                status=status.HTTP_401_UNAUTHORIZED,
            )

    # Dejar que DRF genere la respuesta estándar
    response = exception_handler(exc, context)

    if response is not None and isinstance(response.data, dict):
        # Traducir el campo 'detail' si existe
        if 'detail' in response.data:
            original = str(response.data['detail'])
            traducido = _TRADUCCIONES.get(original, original)
            if traducido != original:
                response.data['detail'] = traducido

    return response
