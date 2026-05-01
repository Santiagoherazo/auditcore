from apps.seguridad.models import AuditLogSistema

RUTAS_SENSIBLES = ['/api/auth/', '/api/clientes/', '/api/expedientes/', '/api/certificaciones/']


_IGNORAR_CODES = {404, 405}


class AuditLogMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        response = self.get_response(request)
        try:
            if any(request.path.startswith(r) for r in RUTAS_SENSIBLES):
                if response.status_code in _IGNORAR_CODES:
                    return response

                usuario = request.user if request.user.is_authenticated else None

                if response.status_code < 400:
                    resultado = 'EXITOSO'
                elif response.status_code in (401, 403):
                    resultado = 'DENEGADO'
                else:
                    resultado = 'FALLIDO'

                AuditLogSistema.registrar(
                    accion=f'{request.method} {request.path}',
                    usuario=usuario,
                    ip=self.get_ip(request),
                    user_agent=request.META.get('HTTP_USER_AGENT', '')[:500],
                    resultado=resultado,
                )
        except Exception:
            pass
        return response

    def get_ip(self, request):
        xff = request.META.get('HTTP_X_FORWARDED_FOR')
        return xff.split(',')[0].strip() if xff else request.META.get('REMOTE_ADDR')
