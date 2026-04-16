#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
echo "Compilando Flutter Web para producción..."
flutter build web --release --no-wasm-dry-run
echo "Listo. Archivos en: build/web/"
