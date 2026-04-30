# AuditCore v2

Sistema de gestión de auditorías con backend Django y frontend Flutter (Web + Android).

## Estructura del repositorio

```
auditcore/
├── auditcore_backend/      # API REST + WebSockets (Django + DRF + Channels)
├── auditcore_flutter/      # App multiplataforma (Flutter Web + Android)
├── docker-compose.yml      # Orquestación completa (backend, Nginx, Postgres, Redis, RabbitMQ)
├── nginx.conf              # Proxy reverso (Web en :3000, API en :8000)
└── .gitignore
```

## Requisitos previos

- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (para desarrollo local)
- [Android Studio](https://developer.android.com/studio) (para Android)

## Configuración inicial

### 1. Variables de entorno

```bash
# Backend
cp auditcore_backend/.env.example auditcore_backend/.env
# Edita auditcore_backend/.env con tus valores reales

# Flutter (Web con Docker)
cp auditcore_flutter/.env.example auditcore_flutter/.env

# Flutter (Android — emulador)
cp auditcore_flutter/.env.android.example auditcore_flutter/.env.android
```

> ⚠️ **Nunca subas los archivos `.env` reales al repositorio.**

### 2. Levantar el stack con Docker

```bash
docker compose up -d
```

Servicios disponibles:
| Servicio   | URL                    |
|------------|------------------------|
| App Web    | http://localhost:3000  |
| API        | http://localhost:8000  |
| Admin Django | http://localhost:8000/admin |

### 3. Correr Flutter en desarrollo

```bash
cd auditcore_flutter
flutter pub get

# Web (hot reload en Chrome)
./CORRER_WEB_DEV.sh      # Linux/Mac
# o
flutter run -d chrome --web-port 8080

# Android (emulador)
./CORRER_ANDROID.sh      # Linux/Mac
CORRER_ANDROID.bat       # Windows
```

Para correr **Android + Web simultáneamente**:
```bash
./CORRER_DUAL.sh
```

## Credenciales por defecto (desarrollo)

| Campo    | Valor               |
|----------|---------------------|
| Email    | admin@auditcore.com |
| Password | Admin1234!          |

## Compilar para producción

| Plataforma | Comando                   | Output                                         |
|------------|---------------------------|------------------------------------------------|
| Web        | `flutter build web`       | `build/web/`                                   |
| Android APK| `flutter build apk`       | `build/app/outputs/flutter-apk/app-release.apk`|
| Android AAB| `flutter build appbundle` | Para Google Play Store                         |

## Cambios recientes

Ver [`auditcore_flutter/CAMBIOS_v33_fixes.md`](auditcore_flutter/CAMBIOS_v33_fixes.md) para el detalle de los fixes de SonarQube y actualizaciones de dependencias Android.

## Stack tecnológico

**Backend**
- Django 4.x + Django REST Framework
- Django Channels (WebSockets)
- Celery + RabbitMQ (tareas asíncronas)
- PostgreSQL + Redis
- Ollama (LLM local para chatbot)

**Frontend**
- Flutter 3.27+ (Web + Android)
- Riverpod (gestión de estado)
- Dio (HTTP)
- go_router (navegación)
