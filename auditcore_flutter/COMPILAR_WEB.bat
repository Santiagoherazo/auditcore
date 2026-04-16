@echo off
title AuditCore — Compilar para Producción
echo.
echo Compilando Flutter Web para producción...
flutter build web --release --no-wasm-dry-run
echo.
echo Listo. Los archivos estan en: build\web\
echo Sube esa carpeta a tu servidor web.
pause
