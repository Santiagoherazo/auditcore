# AuditCore — Guía de configuración Android Studio

## Requisitos previos

| Herramienta | Versión mínima | Dónde obtenerla |
|---|---|---|
| Android Studio | Hedgehog 2023.1+ | https://developer.android.com/studio |
| Flutter SDK | 3.27+ | https://docs.flutter.dev/get-started/install |
| Java (JDK) | 17 | Incluido en Android Studio |
| Android SDK | **API 35** | SDK Manager en Android Studio |
| Docker Desktop | cualquiera | https://www.docker.com/products/docker-desktop |

---

## Paso 1 — Instalar Flutter y configurar Android Studio

1. Descarga e instala **Flutter SDK** en una ruta sin espacios (ej: `C:\src\flutter`).
2. Agrega `C:\src\flutter\bin` al PATH del sistema.
3. En Android Studio instala los plugins **Flutter** y **Dart**:
   - `File → Settings → Plugins → Marketplace → "Flutter"` → Install.
4. Verifica que todo esté bien:
   ```bash
   flutter doctor
   ```
   Todos los ítems deben estar en ✓ verde (excepto Xcode en Windows/Linux).

---

## Paso 2 — Levantar el backend con Docker

Desde la raíz del proyecto (donde está `docker-compose.yml`):

```bash
docker compose up -d
```

Verifica los servicios:
```bash
docker compose ps
```

Todos deben aparecer `running`. URLs disponibles:
- **API:** `http://localhost:8000`
- **Frontend Nginx:** `http://localhost:3000`

---

## Paso 3 — Abrir el proyecto Flutter en Android Studio

1. `File → Open` → selecciona la carpeta `auditcore_flutter/`.
2. Android Studio detectará automáticamente el proyecto Flutter.
3. Espera a que Gradle sincronice (`Build → Sync Project with Gradle Files`).

---

## Paso 4 — Editar `android/local.properties`

**Windows:**
```properties
sdk.dir=C\:\\Users\\TuUsuario\\AppData\\Local\\Android\\Sdk
flutter.sdk=C\:\\src\\flutter
```

**macOS / Linux:**
```properties
sdk.dir=/Users/TuUsuario/Library/Android/sdk
flutter.sdk=/Users/TuUsuario/flutter
```

---

## Paso 5 — Variables de entorno para Android

El emulador **no puede usar `localhost`** — ese hostname apunta al emulador mismo.

```bash
# macOS / Linux
cp .env.android .env

# Windows
copy .env.android .env
```

El `.env.android` usa `10.0.2.2` — la IP especial que mapea al `localhost` de tu PC.

### Dispositivo físico (USB o WiFi):

1. Encuentra la IP LAN de tu PC:
   - Windows: `ipconfig` → IPv4 del adaptador WiFi/Ethernet
   - macOS/Linux: `ip addr` o `ifconfig`
2. Edita `.env`:
   ```
   API_BASE_URL=http://192.168.1.X:3000
   WS_BASE_URL=ws://192.168.1.X:3000
   ```
3. Asegúrate de que el firewall permita el puerto 3000.

---

## Paso 6 — Crear el emulador

1. `Tools → Device Manager → Create Device`
2. Selecciona **Pixel 7** con imagen **API 35 (VanillaIceCream) — x86_64**
3. Haz clic en ▶ para iniciarlo.

---

## Paso 7 — Correr la app

### Desde Android Studio:
Selecciona el emulador en el dropdown y haz clic en ▶ Run (`Shift+F10`).

### Desde terminal:
```bash
cd auditcore_flutter
flutter run -d android
```

---

## 🔥 Correr WEB y Android al mismo tiempo

Los tres procesos usan puertos distintos y no se interfieren:

```
Docker Nginx       :3000   build web estático + proxy API   (siempre)
flutter run chrome :8080   dev server web con hot reload     (Terminal 2)
flutter run android emulador → conecta a 10.0.2.2:3000     (Terminal 1)
```

**Terminal 1:**
```bash
cd auditcore_flutter
./CORRER_DUAL.sh        # configura Android y muestra instrucciones
```

**Terminal 2 (mientras Terminal 1 corre):**
```bash
cd auditcore_flutter
./CORRER_WEB_DEV.sh     # Chrome en :8080, hot reload
```

---

## Solución de problemas

### `SocketException: Connection refused`
- Verifica Docker: `docker compose ps`
- En emulador: `.env` debe tener `API_BASE_URL=http://10.0.2.2:3000`

### `flutter_secure_storage` — error en emulador API < 24
- Recrea el AVD con API 35.

### `Gradle sync failed` o `AGP requires compileSdk 35`
- Descarga Android SDK API 35 desde SDK Manager.
- `Build → Clean Project` → `Sync Project with Gradle Files`.

### `Could not resolve com.android.tools.build:gradle:8.7.3`
- Requiere conexión a internet para descargar AGP.
- En redes corporativas, configura proxy en `gradle.properties`.

### `HTTP cleartext traffic not permitted`
- El `network_security_config.xml` ya permite HTTP a `10.0.2.2` en debug.
- Verifica que el build type sea `debug`.

### La app no hace login
- Verifica que el backend esté inicializado: `http://localhost:8000/api/auth/setup/status/`
- Si no se configuró, ve a `http://localhost:3000` y completa el wizard de setup.

---

## Compilar APK release

```bash
cd auditcore_flutter
# Asegúrate de que .env apunte a tu URL de producción
flutter build apk --release
# APK en: build/app/outputs/flutter-apk/app-release.apk
```
