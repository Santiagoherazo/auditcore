# AuditCore Flutter — Arranque Rápido

## Requisito previo
**La API backend debe estar corriendo en http://localhost:8000**
(Ejecuta INICIAR.bat en la carpeta auditcore_backend primero)

## Arrancar la app web

### Opción 1 — Doble clic
- Doble clic en `INICIAR_WEB.bat`

### Opción 2 — PowerShell
```powershell
cd auditcore_flutter
flutter pub get
flutter run -d chrome --web-port 3000
```

La app abre en: http://localhost:3000

## Compilar para producción

| Plataforma | Comando | Resultado |
|---|---|---|
| Web | `flutter build web` | `build/web/` (subir al servidor) |
| Android | `flutter build apk` | `build/app/outputs/flutter-apk/app-release.apk` |
| iOS | `flutter build ios` | Requiere Mac con Xcode |

## Credenciales por defecto
- **Email:** admin@auditcore.com
- **Password:** Admin1234!