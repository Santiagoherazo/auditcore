@echo off
title AuditCore Flutter Web
color 0B

echo.
echo  ╔══════════════════════════════════════════╗
echo  ║      AUDITCORE — APP FLUTTER WEB         ║
echo  ║   Panel interno + Portal del cliente     ║
echo  ╚══════════════════════════════════════════╝
echo.

echo Verificando Flutter...
flutter --version 2>nul || (
  echo ERROR: Flutter no está instalado o no está en el PATH.
  echo Instala Flutter desde https://flutter.dev y agrega al PATH.
  pause
  exit
)

echo Descargando dependencias...
flutter pub get

echo.
echo  ══════════════════════════════════════════════
echo    Iniciando app en Chrome: http://localhost:3000
echo    (La API debe estar corriendo en localhost:8000)
echo  ══════════════════════════════════════════════
echo.

flutter run -d chrome --web-port 3000