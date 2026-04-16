# AuditCore v33 — Cambios aplicados

## Dependencias Android

### `android/build.gradle`
- `kotlin_version`: `1.9.23` → `2.0.21`
- AGP: `8.3.1` → `8.7.3`

### `android/gradle/wrapper/gradle-wrapper.properties`
- Gradle: `8.4-all` → `8.11.1-all`

### `android/app/build.gradle`
- `compileSdkVersion`: `34` → `35`
- `targetSdkVersion`: `34` → `35`
- `kotlin-stdlib-jdk8` (deprecado) → `kotlin-stdlib`
- Se agrega `androidx.window:window:1.3.0`

### `pubspec.yaml`
| Paquete | Antes | Después | Razón |
|---|---|---|---|
| `dio` | `^5.4.3` | `^5.7.0` | Fixes interceptors Android |
| `flutter_riverpod` | `^2.5.1` | `^2.6.1` | Mejoras rendimiento |
| `go_router` | `^14.2.7` | `^14.6.3` | Fix navegación Android 14+ |
| `web_socket_channel` | `^2.4.5` | `^3.0.1` | Requerida por Flutter 3.27+ |
| `file_picker` | `^8.0.7` | `^9.0.0` | Crash Android 14 con SAF |
| `flutter_dotenv` | `^5.1.0` | `^5.2.1` | Fix assets Android release |
| `flutter_secure_storage` | `^9.2.2` | `^9.2.4` | Patch Android KeyStore |
| `flutter_svg` | `^2.0.10+1` | `^2.0.17` | Fixes render |
| `fl_chart` | `^0.68.0` | `^0.69.0` | Fix render Android |

---

## Bugs de botones corregidos

### `expediente_form_screen.dart`
**Race condition auditor líder (rol EJECUTIVO):** El `addPostFrameCallback`
podía ejecutarse después de que el usuario tocara "Crear expediente",
dejando `_auditorLiderId` en `null` y fallando la validación con el loader
ya visible. Se reemplazó por inicialización síncrona con flag `_auditorInicializado`.

### `hallazgo_form_screen.dart`
**Guardia para `expedienteId` vacío:** Si la pantalla se abría por URL
malformada sin parámetros, la API retornaba un 400 confuso. Ahora se
verifica antes del POST y se muestra un mensaje claro al usuario.

---

## Scripts nuevos

| Script | Descripción |
|---|---|
| `CORRER_DUAL.sh` | Android + instrucciones para Web simultáneo |
| `CORRER_WEB_DEV.sh` | `flutter run -d chrome` en puerto :8080 |
| `CORRER_ANDROID.sh` | Actualizado con referencia al modo dual |

---

## Cómo usar Web + Android al mismo tiempo

```
Terminal 1:  ./CORRER_DUAL.sh      → emulador Android
Terminal 2:  ./CORRER_WEB_DEV.sh   → Chrome en :8080 (hot reload)
Docker:      siempre corriendo     → Nginx :3000 + API :8000
```
