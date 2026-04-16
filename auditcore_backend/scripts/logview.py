#!/usr/bin/env python3
"""
logview.py — Visor en tiempo real del log de AuditCore
=======================================================

Uso:
    # Monitor en vivo (pipe desde tail -f)
    docker compose exec backend tail -f /app/logs/auditcore.log | python3 /app/scripts/logview.py

    # Solo errores y warnings
    docker compose exec backend tail -f /app/logs/auditcore.log | python3 /app/scripts/logview.py --min-level warning

    # Solo categoría HTTP y SEC
    docker compose exec backend tail -f /app/logs/auditcore.log | python3 /app/scripts/logview.py --cat HTTP SEC

    # Buscar por usuario
    docker compose exec backend grep '"user":"jperez"' /app/logs/auditcore.log | python3 /app/scripts/logview.py

    # Estadísticas de los últimos N minutos
    docker compose exec backend python3 /app/scripts/logview.py --stats --file /app/logs/auditcore.log

    # Ver solo errores del log de errores
    docker compose exec backend tail -100 /app/logs/auditcore_err.log | python3 /app/scripts/logview.py
"""
import sys
import json
import argparse
from collections import Counter, defaultdict
from datetime import datetime

# Colores ANSI
RESET  = '\033[0m'
BOLD   = '\033[1m'
DIM    = '\033[2m'
RED    = '\033[31m'
YELLOW = '\033[33m'
GREEN  = '\033[32m'
CYAN   = '\033[36m'
BLUE   = '\033[34m'
MAGENTA= '\033[35m'
WHITE  = '\033[37m'
GRAY   = '\033[90m'

LEVEL_COLOR = {
    'DEBUG':    GRAY,
    'INFO':     '',
    'WARNING':  YELLOW,
    'ERROR':    RED,
    'CRITICAL': f'{MAGENTA}{BOLD}',
}

CAT_COLOR = {
    'HTTP':   CYAN,
    'AUTH':   BLUE,
    'DB':     GRAY,
    'CELERY': GREEN,
    'WS':     MAGENTA,
    'SEC':    f'{RED}{BOLD}',
    'DOC':    YELLOW,
    'AUDIT':  f'{BLUE}{BOLD}',
    'SYS':    WHITE,
    'ERROR':  f'{RED}{BOLD}',
}

CAT_ICON = {
    'HTTP':   '🌐',
    'AUTH':   '🔐',
    'DB':     '🗄️ ',
    'CELERY': '⚙️ ',
    'WS':     '🔌',
    'SEC':    '🚨',
    'DOC':    '📄',
    'AUDIT':  '📋',
    'SYS':    '💻',
    'ERROR':  '💥',
}

LEVEL_ORDER = {'DEBUG': 0, 'INFO': 1, 'WARNING': 2, 'ERROR': 3, 'CRITICAL': 4}


def format_line(d: dict, compact: bool = False) -> str:
    ts    = d.get('ts', '')
    ms    = d.get('ms', 0)
    level = d.get('level', 'INFO')
    cat   = d.get('cat', '?')
    op    = d.get('op', d.get('msg', ''))
    proc  = d.get('proc', '?')
    user  = d.get('user', '')
    ip    = d.get('ip', '')
    op_id = d.get('op_id', '')
    status     = d.get('status', '')
    latency_ms = d.get('latency_ms', '')
    traceback  = d.get('traceback', '')

    # Tiempo legible
    time_str = f"{ts}.{ms:03d}" if ts else '?'

    lc = LEVEL_COLOR.get(level, '')
    cc = CAT_COLOR.get(cat, '')
    icon = CAT_ICON.get(cat, '  ')

    # Extras (sin campos base)
    skip = {'ts', 'ms', 'level', 'cat', 'proc', 'pid', 'op', 'msg',
            'user', 'ip', 'op_id', 'status', 'latency_ms', 'traceback'}
    extras = {k: v for k, v in d.items() if k not in skip}

    # Construir línea principal
    parts = []
    parts.append(f"{GRAY}{time_str}{RESET}")
    parts.append(f"{cc}{icon} {cat:<6}{RESET}")
    if not compact:
        parts.append(f"{GRAY}[{proc:<12}]{RESET}")
    parts.append(f"{lc}{level:<8}{RESET}")
    parts.append(f"{lc}{op}{RESET}")

    tags = []
    if user:      tags.append(f"{CYAN}👤{user}{RESET}")
    if ip:        tags.append(f"{GRAY}🌍{ip}{RESET}")
    if status:    tags.append(f"{_status_color(int(status))}{status}{RESET}")
    if latency_ms:tags.append(f"{_latency_color(int(latency_ms))}⏱{latency_ms}ms{RESET}")
    if op_id:     tags.append(f"{GRAY}#{op_id[:8]}{RESET}")

    for k, v in extras.items():
        tags.append(f"{GRAY}{k}={RESET}{str(v)[:80]}")

    line = '  '.join(parts)
    if tags:
        line += '  ' + '  '.join(tags)

    # Traceback en rojo indentado
    if traceback:
        tb_lines = traceback.strip().split('\n')
        tb_formatted = '\n    '.join(f'{RED}{l}{RESET}' for l in tb_lines[-10:])
        line += f'\n    {tb_formatted}'

    return line


def _status_color(s: int) -> str:
    if s < 300: return GREEN
    if s < 400: return CYAN
    if s < 500: return YELLOW
    return RED


def _latency_color(ms: int) -> str:
    if ms < 100: return GREEN
    if ms < 500: return YELLOW
    if ms < 2000: return f'{YELLOW}{BOLD}'
    return RED


def print_stats(records: list[dict]) -> None:
    print(f"\n{BOLD}{'═'*60}{RESET}")
    print(f"{BOLD}  ESTADÍSTICAS — {len(records)} eventos{RESET}")
    print(f"{BOLD}{'═'*60}{RESET}\n")

    # Por categoría
    cats = Counter(r.get('cat', '?') for r in records)
    print(f"{BOLD}Por categoría:{RESET}")
    for cat, n in sorted(cats.items(), key=lambda x: -x[1]):
        bar = '█' * min(n, 40)
        cc = CAT_COLOR.get(cat, '')
        print(f"  {cc}{cat:<8}{RESET}  {bar} {n}")

    # Por nivel
    levels = Counter(r.get('level', '?') for r in records)
    print(f"\n{BOLD}Por nivel:{RESET}")
    for lvl in ['CRITICAL', 'ERROR', 'WARNING', 'INFO', 'DEBUG']:
        n = levels.get(lvl, 0)
        if n:
            lc = LEVEL_COLOR.get(lvl, '')
            print(f"  {lc}{lvl:<10}{RESET}  {n}")

    # Latencia HTTP
    http_latencies = [int(r['latency_ms']) for r in records
                      if r.get('cat') == 'HTTP' and r.get('latency_ms')]
    if http_latencies:
        http_latencies.sort()
        n = len(http_latencies)
        print(f"\n{BOLD}Latencia HTTP ({n} requests):{RESET}")
        print(f"  p50  = {http_latencies[n//2]}ms")
        print(f"  p95  = {http_latencies[int(n*.95)]}ms")
        print(f"  p99  = {http_latencies[int(n*.99)]}ms")
        print(f"  max  = {http_latencies[-1]}ms")

    # Top errores
    errors = [r for r in records if r.get('level') in ('ERROR', 'CRITICAL')]
    if errors:
        print(f"\n{BOLD}{RED}Top errores ({len(errors)}):{RESET}")
        ops = Counter(r.get('op', '?') for r in errors)
        for op, n in ops.most_common(10):
            print(f"  {RED}{n:4}x{RESET}  {op}")

    # Top usuarios
    users = Counter(r['user'] for r in records if r.get('user'))
    if users:
        print(f"\n{BOLD}Top usuarios ({len(users)} únicos):{RESET}")
        for u, n in users.most_common(5):
            print(f"  {CYAN}{n:4}x{RESET}  {u}")

    # IPs sospechosas (muchos 401/403)
    sec_ips = Counter(r.get('ip', '?') for r in records
                      if r.get('cat') == 'SEC' and r.get('ip'))
    if sec_ips:
        print(f"\n{BOLD}{RED}IPs con eventos de seguridad:{RESET}")
        for ip, n in sec_ips.most_common(5):
            print(f"  {RED}{n:4}x{RESET}  {ip}")

    # Documentos analizados
    docs = [r for r in records if r.get('cat') == 'DOC']
    if docs:
        ops_doc = Counter(r.get('op', '?') for r in docs)
        print(f"\n{BOLD}Documentos:{RESET}")
        for op, n in ops_doc.most_common():
            print(f"  {YELLOW}{n:4}x{RESET}  {op}")

    print(f"\n{BOLD}{'═'*60}{RESET}\n")


def main():
    parser = argparse.ArgumentParser(description='Visor de logs AuditCore')
    parser.add_argument('--min-level', default='debug',
                        choices=['debug', 'info', 'warning', 'error', 'critical'],
                        help='Nivel mínimo a mostrar')
    parser.add_argument('--cat', nargs='+', metavar='CAT',
                        help='Filtrar por categorías (HTTP AUTH DB ...)')
    parser.add_argument('--user', help='Filtrar por usuario')
    parser.add_argument('--ip', help='Filtrar por IP')
    parser.add_argument('--stats', action='store_true',
                        help='Mostrar estadísticas al final')
    parser.add_argument('--file', metavar='PATH',
                        help='Leer desde archivo en lugar de stdin')
    parser.add_argument('--compact', action='store_true',
                        help='Formato compacto (sin nombre de proceso)')
    parser.add_argument('--no-color', action='store_true',
                        help='Sin colores ANSI')
    args = parser.parse_args()

    min_level = LEVEL_ORDER.get(args.min_level.upper(), 0)
    cats_filter = set(c.upper() for c in args.cat) if args.cat else None

    if args.no_color:
        # Desactivar todos los colores
        global RESET, BOLD, DIM, RED, YELLOW, GREEN, CYAN, BLUE, MAGENTA, WHITE, GRAY
        RESET = BOLD = DIM = RED = YELLOW = GREEN = CYAN = BLUE = MAGENTA = WHITE = GRAY = ''
        for k in LEVEL_COLOR: LEVEL_COLOR[k] = ''
        for k in CAT_COLOR:   CAT_COLOR[k]   = ''

    source = open(args.file) if args.file else sys.stdin
    records = []
    errors_count = 0

    try:
        for line in source:
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                # Línea no-JSON (arranque del proceso, etc.)
                print(f"{GRAY}{line}{RESET}")
                continue

            # Filtros
            level_num = LEVEL_ORDER.get(d.get('level', 'INFO'), 1)
            if level_num < min_level:
                continue
            if cats_filter and d.get('cat', '?') not in cats_filter:
                continue
            if args.user and d.get('user', '') != args.user:
                continue
            if args.ip and d.get('ip', '') != args.ip:
                continue

            if args.stats:
                records.append(d)

            print(format_line(d, compact=args.compact))

            level = d.get('level', 'INFO')
            if level in ('ERROR', 'CRITICAL'):
                errors_count += 1

    except KeyboardInterrupt:
        pass
    finally:
        if args.file and source != sys.stdin:
            source.close()

    if args.stats and records:
        print_stats(records)

    if errors_count > 0:
        print(f"\n{RED}{BOLD}⚠  {errors_count} ERROR(ES) detectados{RESET}\n")


if __name__ == '__main__':
    main()
