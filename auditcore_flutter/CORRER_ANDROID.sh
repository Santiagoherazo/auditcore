#!/usr/bin/env bash
# AuditCore — Correr en Android (Emulador o dispositivo físico)
# macOS / Linux

set -e
cd "$(dirname "$0")"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║         AUDITCORE — APP ANDROID (Emulador)           ║"
echo "║   Requiere: Docker corriendo + Emulador iniciado     ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

if ! command -v flutter &> /dev/null; then
    echo "[ERROR] Flutter no encontrado en el PATH."
    echo "Instala Flutter desde https://flutter.dev y agrega al PATH."
    exit 1
fi

echo "[1/4] Configurando variables de entorno para Android..."
cp .env .env.web.bak 2>/dev/null || true
cp .env.android .env
echo "      .env configurado con IP del emulador (10.0.2.2)"

restore_env() {
    echo ""
    echo "Restaurando .env original..."
    mv .env.web.bak .env 2>/dev/null || true
}
trap restore_env EXIT

echo "[2/4] Descargando dependencias Flutter..."
flutter pub get

echo "[3/4] Dispositivos disponibles:"
flutter devices
echo ""

echo "[4/4] Iniciando app en Android..."
echo "      (La API debe estar corriendo: docker compose up -d)"
echo ""
echo " Tip: 'r' hot reload | 'R' hot restart | 'q' salir"
echo " Para correr WEB al mismo tiempo: abre otra terminal y ejecuta CORRER_WEB_DEV.sh"
echo ""

flutter run -d android
