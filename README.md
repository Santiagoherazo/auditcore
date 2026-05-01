# AuditCore

Plataforma digital de gestión de auditorías y certificaciones. Arquitectura monorepo con backend Django y frontend Flutter.

---

## Estructura del repositorio

```
auditcore_merged/
├── auditcore_backend/      # API REST + WebSockets (Django 5.2)
├── auditcore_flutter/      # App multiplataforma (Flutter 3.27+)
├── docker-compose.yml      # Orquestación de servicios
└── nginx.conf              # Reverse proxy para producción
```

---

## Stack tecnológico

### Backend
| Tecnología | Versión | Rol |
|---|---|---|
| Django | 5.2 | Framework principal |
| Django REST Framework | 3.15 | API REST |
| Daphne / Channels | 4.x | WebSockets / ASGI |
| Celery + RabbitMQ | 5.3 | Tareas asíncronas |
| PostgreSQL | 16 | Base de datos principal |
| Redis | 7 | Cache y result backend |
| SimpleJWT | 5.3 | Autenticación JWT |
| drf-spectacular | 0.27 | Documentación OpenAPI |
| WeasyPrint | 62 | Generación de PDFs |

### Frontend
| Tecnología | Versión | Rol |
|---|---|---|
| Flutter | 3.27+ | Framework multiplataforma |
| Dart SDK | ≥3.3.0 | Lenguaje |
| flutter_riverpod | 2.6 | Gestión de estado |
| go_router | 14.6 | Navegación |
| Dio | 5.7 | Cliente HTTP |
| web_socket_channel | 3.0 | WebSockets |
| flutter_secure_storage | 9.2 | Almacenamiento seguro de tokens |

---

## Módulos de la aplicación

| Módulo | Descripción |
|---|---|
| `auth` | Login con JWT y MFA TOTP |
| `dashboard` | Panel principal con métricas |
| `clientes` | Gestión de clientes |
| `expedientes` | Expedientes de auditoría |
| `hallazgos` | Registro de hallazgos |
| `calendario` | Planificación de visitas |
| `documentos` | Gestión documental |
| `certificaciones` | Emisión y verificación de certificados |
| `chatbot` | Asistente IA (Ollama) |
| `admin` | Panel de administración |
| `perfil` | Configuración de cuenta y MFA |
| `portal_cliente` | Portal de acceso para clientes |
| `setup` | Configuración inicial del sistema |

---

## Apps del backend

| App | Descripción |
|---|---|
| `administracion` | Usuarios, roles, permisos, MFA |
| `clientes` | Modelos y lógica de clientes |
| `expedientes` | Expedientes y visitas agendadas |
| `ejecucion` | Ejecución de auditorías |
| `hallazgos` | Hallazgos y evidencias |
| `documentos` | Documentos adjuntos |
| `certificaciones` | Certificados digitales |
| `formularios` | Formularios dinámicos |
| `tipos_auditoria` | Catálogo de tipos de auditoría |
| `seguridad` | Middleware de auditoría y logs |
| `chatbot` | Contexto y conversaciones del chatbot |

---

## Requisitos previos

- Docker y Docker Compose v2
- Flutter SDK ≥ 3.27 (para desarrollo local del frontend)
- Python 3.11+ (para desarrollo local del backend)

---

## Inicio rápido con Docker

```bash
# Clonar el repositorio
git clone <url-del-repositorio>
cd auditcore_merged

# Copiar variables de entorno
cp auditcore_backend/.env.example auditcore_backend/.env
# Editar .env con los valores correctos

# Levantar todos los servicios
docker compose up -d

# Aplicar migraciones
docker compose exec backend python manage.py migrate

# Crear superusuario
docker compose exec backend python manage.py createsuperuser
```

La API queda disponible en `http://localhost:8000`
La app web queda disponible en `http://localhost:3000`

---

## Desarrollo local — Backend

```bash
cd auditcore_backend

# Crear entorno virtual
python -m venv .venv
source .venv/bin/activate        # Linux/Mac
.venv\Scripts\activate           # Windows

# Instalar dependencias
pip install -r requirements.txt

# Variables de entorno
cp .env.example .env
# Editar .env

# Migraciones
python manage.py migrate

# Seed de datos iniciales (opcional)
python scripts/seed_data.py

# Correr servidor de desarrollo
python manage.py runserver
```

### Servicios de soporte necesarios en desarrollo

```bash
# PostgreSQL, Redis y RabbitMQ con Docker
docker compose up -d postgres redis rabbitmq

# Worker de Celery (en otra terminal)
celery -A config worker -l info

# Celery Beat — tareas programadas (en otra terminal)
celery -A config beat -l info
```

---

## Desarrollo local — Flutter

```bash
cd auditcore_flutter

# Instalar dependencias
flutter pub get

# Correr en Chrome (web)
flutter run -d chrome --web-port 3000

# Correr en Android
flutter run -d android

# Correr en emulador
flutter emulators --launch <emulator-id>
flutter run
```

### Scripts disponibles

| Script | Plataforma | Descripción |
|---|---|---|
| `INICIAR_WEB.bat` | Windows | Inicia app web en Chrome |
| `COMPILAR_WEB.bat` | Windows | Compila para producción web |
| `COMPILAR_WEB.sh` | Linux/Mac | Compila para producción web |
| `CORRER_ANDROID.bat` | Windows | Lanza en dispositivo Android |
| `CORRER_ANDROID.sh` | Linux/Mac | Lanza en dispositivo Android |
| `COMPILAR_APK.bat` | Windows | Genera APK release |
| `CORRER_DUAL.sh` | Linux/Mac | Backend + Flutter simultáneos |

---

## Compilar para producción

### Web
```bash
cd auditcore_flutter
flutter build web
# Output: build/web/ — subir al servidor o a un bucket S3/GCS
```

### Android APK
```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### Android App Bundle (Google Play)
```bash
flutter build appbundle --release
```

---

## Variables de entorno

### Backend (`.env`)

| Variable | Descripción |
|---|---|
| `SECRET_KEY` | Clave secreta de Django |
| `DEBUG` | `True` en desarrollo, `False` en producción |
| `ALLOWED_HOSTS` | Hosts permitidos separados por coma |
| `DATABASE_URL` | URL de conexión PostgreSQL |
| `REDIS_URL` | URL de conexión Redis |
| `RABBITMQ_URL` | URL de conexión RabbitMQ |
| `OLLAMA_BASE_URL` | URL del servidor Ollama (IA) |
| `OLLAMA_MODEL` | Modelo a usar (default: `llama3.1:8b`) |
| `EMAIL_HOST` | Servidor SMTP para correos |
| `DJANGO_SETTINGS_MODULE` | Módulo de settings a usar |

### Flutter (`.env`)

| Variable | Descripción |
|---|---|
| `API_BASE_URL` | URL base de la API REST |
| `WS_BASE_URL` | URL base para WebSockets |

---

## Documentación de la API

Con el backend corriendo, la documentación OpenAPI está disponible en:

- Swagger UI: `http://localhost:8000/api/schema/swagger-ui/`
- ReDoc: `http://localhost:8000/api/schema/redoc/`
- Schema YAML: `http://localhost:8000/api/schema/`

---

## Tests

### Backend
```bash
cd auditcore_backend

# Todos los tests
pytest

# Con cobertura
pytest --cov=. --cov-report=html

# Tests específicos
pytest tests/test_api.py
pytest tests/test_mfa.py
pytest tests/test_mfa_totp.py
pytest tests/test_modelos.py
```

### Flutter
```bash
cd auditcore_flutter
flutter test
```

---

## Despliegue en producción

```bash
# Usar el settings de producción
export DJANGO_SETTINGS_MODULE=config.settings.production

# Colectar archivos estáticos
python manage.py collectstatic --noinput

# Con Docker Compose en producción
docker compose -f docker-compose.yml up -d
```

El `nginx.conf` incluido actúa como reverse proxy, sirve los estáticos del frontend compilado y redirige `/api/` y `/ws/` al backend.

---

## Credenciales por defecto (desarrollo)

> **Estas credenciales son solo para desarrollo local. Cambiarlas antes de cualquier despliegue.**

- **Email:** `admin@auditcore.com`
- **Contraseña:** `Admin1234!`

---

## Seguridad

- Autenticación JWT con refresh token y blacklist
- MFA opcional con TOTP (compatible con Google Authenticator, Authy)
- Bloqueo automático tras 5 intentos de login fallidos
- Middleware de auditoría que registra todas las acciones
- Contraseñas nunca expuestas en logs ni respuestas de API
- Las variables sensibles se gestionan exclusivamente por variables de entorno

---

## Licencia

Propietario — todos los derechos reservados.
