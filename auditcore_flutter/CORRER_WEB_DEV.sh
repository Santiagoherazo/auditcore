#!/usr/bin/env bash
# AuditCore — Web con hot reload (dev server propio en :8080)
# Usar en terminal separada mientras CORRER_DUAL.sh o CORRER_ANDROID.sh corren.
#
# NO interfiere con Docker (:3000) ni con el emulador Android.

set -e
cd "$(dirname "$0")"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║   AuditCore — WEB Dev Server (hot reload :8080)      ║"
echo "║   Docker sigue sirviendo :3000 — sin conflicto ✓     ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

if ! command -v flutter &> /dev/null; then
    echo "[ERROR] Flutter no encontrado en el PATH."
    exit 1
fi

# Si CORRER_DUAL.sh o CORRER_ANDROID.sh están corriendo,
# el .env apunta a 10.0.2.2. Restauramos el de web temporalmente.
if [ -f ".env.web.bak" ]; then
    echo "[INFO] Detectado .env.web.bak — restaurando config web para Chrome..."
    cp .env.web.bak .env
fi

echo "[INFO] API en localhost:3000 (Docker Nginx)"
echo "[INFO] Dev server Chrome en localhost:8080"
echo ""
echo " Tip: 'r' hot reload | 'R' hot restart | 'q' salir"
echo ""

flutter run -d chrome --web-port 8080
