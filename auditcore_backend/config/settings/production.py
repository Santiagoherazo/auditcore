from .base import *

DEBUG = False

# FIX: definir explícitamente los orígenes permitidos.
# Sin esto, django-cors-headers bloquea TODAS las peticiones del frontend
# aunque CORS_ALLOW_ALL_ORIGINS=False esté configurado.
CORS_ALLOW_ALL_ORIGINS = False
CORS_ALLOW_CREDENTIALS = True
CORS_ALLOWED_ORIGINS = [
    # Reemplaza con el dominio real en producción, por ejemplo:
    # 'https://auditcore.tuempresa.com',
    'http://localhost:3000',
]

# FIX: ALLOWED_HOSTS lee de variable de entorno para no hardcodear el dominio.
# Ejemplo .env producción: ALLOWED_HOSTS=auditcore.tuempresa.com,backend,localhost
import os as _os
_extra_hosts = _os.environ.get('ALLOWED_HOSTS', '')
ALLOWED_HOSTS = ['localhost', 'backend'] + [
    h.strip() for h in _extra_hosts.split(',') if h.strip()
]

# HTTPS
# FIX: SECURE_SSL_REDIRECT=True detrás de Nginx HTTP causa bucle infinito de redirecciones.
# Django ve la petición como HTTP (Nginx → backend es HTTP interno) y redirige a HTTPS
# sin fin. Solución: deshabilitar la redirección de Django y dejar que Nginx gestione
# el HTTPS. Django debe confiar en el header X-Forwarded-Proto que Nginx envía.
SECURE_SSL_REDIRECT         = False   # Nginx gestiona HTTPS, no Django
SECURE_PROXY_SSL_HEADER     = ('HTTP_X_FORWARDED_PROTO', 'https')
SESSION_COOKIE_SECURE       = True
CSRF_COOKIE_SECURE          = True
SECURE_HSTS_SECONDS         = 31536000
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_PRELOAD         = True

# FIX: leer CORS_ALLOWED_ORIGINS desde variable de entorno en producción real:
# import os
# _origins = os.environ.get('CORS_ALLOWED_ORIGINS', '')
# if _origins:
#     CORS_ALLOWED_ORIGINS = [o.strip() for o in _origins.split(',')]
