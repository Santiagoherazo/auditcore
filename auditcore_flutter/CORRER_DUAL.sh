#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║   AuditCore — Correr WEB + ANDROID al mismo tiempo              ║
# ║   macOS / Linux                                                  ║
# ╠══════════════════════════════════════════════════════════════════╣
# ║  Requisitos:                                                     ║
# ║    • Docker corriendo  →  cd .. && docker compose up -d         ║
# ║    • Emulador Android iniciado en Android Studio                 ║
# ║    • Flutter en PATH                                             ║
# ╠══════════════════════════════════════════════════════════════════╣
# ║  PUERTOS (sin conflicto):                                        ║
# ║    :3000  Docker Nginx  — build web estático + proxy API        ║
# ║    :8080  flutter chrome — dev server web con hot reload        ║
# ║    emulador — Android conecta a 10.0.2.2:3000 → tu Docker      ║
# ╚══════════════════════════════════════════════════════════════════╝

set -e
cd "$(dirname "$0")"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║        AuditCore — Modo DUAL (Android + Web simultáneo)          ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ── Verificar Flutter ──────────────────────────────────────────────
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} Flutter no encontrado en el PATH."
    exit 1
fi

# ── Verificar Docker ───────────────────────────────────────────────
echo -e "${CYAN}[1/5]${NC} Verificando Docker..."
if ! docker compose ps --services --filter status=running 2>/dev/null | grep -q "backend"; then
    echo -e "${YELLOW}[AVISO]${NC} El backend no parece estar corriendo."
    echo "        Ejecuta primero desde la raíz: docker compose up -d"
    echo ""
    read -p "¿Continuar de todas formas? [s/N] " resp
    [[ "$resp" =~ ^[sS]$ ]] || exit 1
fi
echo -e "        ${GREEN}✓${NC} Docker OK"

# ── Configurar .env para Android ──────────────────────────────────
echo -e "${CYAN}[2/5]${NC} Configurando .env para Android (10.0.2.2)..."
cp .env .env.web.bak 2>/dev/null || true
cp .env.android .env
echo -e "        ${GREEN}✓${NC} .env → Android (10.0.2.2:3000)"

restore_env() {
    echo ""
    echo -e "${CYAN}Restaurando .env original (web)...${NC}"
    mv .env.web.bak .env 2>/dev/null || true
    echo -e "${GREEN}✓${NC} .env restaurado."
}
trap restore_env EXIT

# ── Dependencias ───────────────────────────────────────────────────
echo -e "${CYAN}[3/5]${NC} Descargando dependencias Flutter..."
flutter pub get
echo -e "        ${GREEN}✓${NC} Dependencias OK"

# ── Dispositivos ───────────────────────────────────────────────────
echo -e "${CYAN}[4/5]${NC} Dispositivos disponibles:"
flutter devices
echo ""

EMULATOR_ID=$(flutter devices 2>/dev/null | grep -i "emulator\|android" | grep -v "chrome\|web" | awk '{print $1}' | head -1)
[ -z "$EMULATOR_ID" ] && EMULATOR_ID="android"

# ── Instrucciones para Chrome ──────────────────────────────────────
echo -e "${CYAN}[5/5]${NC} Iniciando Android..."
echo ""
echo -e "${BOLD}┌──────────────────────────────────────────────────────────────────┐${NC}"
echo -e "${BOLD}│  Para correr WEB con hot reload — abre OTRA terminal y ejecuta:  │${NC}"
echo -e "${BOLD}│                                                                  │${NC}"
echo -e "${BOLD}│  cd $(pwd)${NC}"
echo -e "${BOLD}│  ./CORRER_WEB_DEV.sh                                             │${NC}"
echo -e "${BOLD}│                                                                  │${NC}"
echo -e "${BOLD}│  Chrome en localhost:8080  ·  Android en 10.0.2.2:3000  ✓       │${NC}"
echo -e "${BOLD}└──────────────────────────────────────────────────────────────────┘${NC}"
echo ""
echo -e " ${YELLOW}Tip:${NC} ${BOLD}r${NC} hot reload  |  ${BOLD}R${NC} hot restart  |  ${BOLD}q${NC} salir"
echo ""

flutter run -d "$EMULATOR_ID"
