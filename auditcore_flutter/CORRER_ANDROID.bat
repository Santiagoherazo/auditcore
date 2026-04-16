@echo off
title AuditCore — Correr en Android (Emulador)
color 0A

echo.
echo  ╔══════════════════════════════════════════════════════╗
echo  ║         AUDITCORE — APP ANDROID (Emulador)           ║
echo  ║   Requiere: Docker corriendo + Emulador iniciado     ║
echo  ╚══════════════════════════════════════════════════════╝
echo.

:: Verificar Flutter
flutter --version >nul 2>&1 || (
    echo [ERROR] Flutter no encontrado en el PATH.
    echo Instala Flutter desde https://flutter.dev y agrega al PATH.
    pause
    exit /b 1
)

:: Copiar .env para Android (usa 10.0.2.2 en vez de localhost)
echo [1/4] Configurando variables de entorno para Android...
copy /Y .env.android .env >nul
echo       .env configurado con IP del emulador (10.0.2.2)

:: Instalar dependencias
echo [2/4] Descargando dependencias Flutter...
flutter pub get

:: Verificar dispositivos
echo [3/4] Dispositivos disponibles:
flutter devices

echo.
echo [4/4] Iniciando app en Android...
echo       (La API debe estar corriendo: docker compose up -d)
echo.
echo  Tip: usa 'r' para hot reload, 'R' para hot restart, 'q' para salir
echo.

flutter run -d android

:: Restaurar .env de web al salir
echo.
echo Restaurando .env para web...
copy /Y .env.web .env >nul 2>&1 || echo (No se encontro .env.web — mantiene config Android)

echo.
echo App cerrada.
pause
