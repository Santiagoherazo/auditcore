@echo off
title AuditCore — Compilar APK Android
echo.
echo Compilando APK para Android...
echo (Requiere Android Studio instalado)
flutter build apk --release
echo.
echo APK generado en: build\app\outputs\flutter-apk\app-release.apk
pause