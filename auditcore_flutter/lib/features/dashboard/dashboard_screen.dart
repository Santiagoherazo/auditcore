import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/services/providers.dart';
import '../../core/services/session_service.dart';
import '../../core/services/websocket_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  Timer? _refreshTimer;
  StreamSubscription? _wsDashSub;
  StreamSubscription? _wsNotiSub;

  @override
  void initState() {
    super.initState();

    // FIX: cancelar suscripciones anteriores antes de reconectar.
    // Sin esto, cada navegación acumula listeners sobre la misma instancia
    // global → múltiples callbacks por evento y conexiones huérfanas.
    _wsDashSub?.cancel();
    _wsNotiSub?.cancel();

    // FIX: solo conectar el WS del dashboard para roles que tienen acceso.
    // BUG ORIGINAL: siempre se intentaba conectar wsDashboard sin verificar el rol.
    // Un AUDITOR (sin acceso al dashboard WS) generaba un 4003 en cada sesión,
    // llenando los logs del backend con rechazos innecesarios.
    // Los roles con acceso al dashboard WS son ADMIN, AUDITOR_LIDER, EJECUTIVO.
    // El AUDITOR recibe actualizaciones solo via polling (refreshTimer).
    final rol = ref.read(authProvider).valueOrNull?.rol ?? '';
    const rolesConDashboardWs = ['SUPERVISOR', 'SUPERVISOR', 'ASESOR'];

    if (rolesConDashboardWs.contains(rol)) {
      wsDashboard.connect('ws/dashboard/');
      _wsDashSub = wsDashboard.stream.listen((event) {
        // FIX: data:{} vacío significa "recargar desde HTTP" (señal de refresh).
        // El endpoint GET /api/dashboard/ filtra los KPIs por rol del token.
        if ((event['type'] == 'dashboard_update') && mounted) {
          ref.invalidate(dashboardProvider);
        }
      });
    }

    wsNotificaciones.connect('ws/notificaciones/');
    _wsNotiSub = wsNotificaciones.stream.listen((event) {
      if (!mounted) return;
      if (event['type'] == 'notificacion') {
        _mostrarNotificacion(event['titulo'] ?? '', event['tipo'] ?? 'INFO');
      }
    });

    // Polling de respaldo cada 30 s — cubre a AUDITOR y casos donde WS falla
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) ref.invalidate(dashboardProvider);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _wsDashSub?.cancel();
    _wsNotiSub?.cancel();
    // FIX: desconectar WebSockets al destruir el widget.
    // Sin esto, al navegar a otra pantalla el widget se destruye pero los
    // sockets siguen vivos. Al volver, initState abre conexiones nuevas
    // sin cerrar las anteriores → loop WSCONNECT/WSDISCONNECT cada 4s
    // que colapsa Daphne y bloquea el broker AMQP del backend.
    wsDashboard.disconnect();
    wsNotificaciones.disconnect();
    super.dispose();
  }

  void _mostrarNotificacion(String titulo, String tipo) {
    final bg = tipo == 'CRITICO' ? AppColors.danger : AppColors.accent;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: bg,
      content: Text(titulo),
      behavior: SnackBarBehavior.floating,
    ));
  }

  String _saludo() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Buenos días';
    if (h < 18) return 'Buenas tardes';
    return 'Buenas noches';
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final usuario   = authState.valueOrNull;
    final dashAsync = ref.watch(dashboardProvider);
    final hoy = DateFormat("EEEE d 'de' MMMM, yyyy", 'es').format(DateTime.now());

    return AppShell(
      rutaActual:    '/dashboard',
      rolUsuario:    usuario?.rol ?? '',
      nombreUsuario: usuario?.nombreCompleto ?? '',
      titulo:        'Dashboard',
      subtitulo:     hoy,
      showBottomNav: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_outlined, size: 18),
          tooltip: 'Actualizar',
          onPressed: () => ref.invalidate(dashboardProvider),
          style: IconButton.styleFrom(foregroundColor: AppColors.textSecondary),
        ),
        const SizedBox(width: 4),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'logout') {
                await SessionService.logout(context, ref);
              } else if (v == 'mfa') {
                context.go('/perfil/mfa');
              }
            },
            tooltip: 'Menú de usuario',
            child: CircleAvatar(
              radius: 15,
              backgroundColor: AppColors.accentLight,
              child: Text(
                (usuario?.nombre ?? 'U').substring(0, 1).toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accent,
                ),
              ),
            ),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'mfa',
                child: Row(children: [
                  Icon(Icons.security, size: 16, color: AppColors.textSecondary),
                  SizedBox(width: 8),
                  Text('Verificación 2 pasos', style: TextStyle(fontSize: 13)),
                ]),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Row(children: [
                  Icon(Icons.logout, size: 16, color: AppColors.textSecondary),
                  SizedBox(width: 8),
                  Text('Cerrar sesión', style: TextStyle(fontSize: 13)),
                ]),
              ),
            ],
          ),
        ),
      ],
      child: dashAsync.when(
        loading: () => const Center(
          child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined, size: 40, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            const Text('No se pudo cargar el dashboard.',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => ref.invalidate(dashboardProvider),
              child: const Text('Reintentar'),
            ),
          ]),
        ),
        data: (dash) => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Saludo
            Text(
              '${_saludo()}, ${usuario?.nombre ?? 'Usuario'}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 2),
            const Text('Aquí está el resumen de la operación.',
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
            const SizedBox(height: 20),

            // Métricas 4 columnas responsive
            LayoutBuilder(builder: (ctx, c) {
              final cols = c.maxWidth > 600 ? 4 : 2;
              return GridView.count(
                crossAxisCount: cols,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: c.maxWidth > 600 ? 1.6 : 1.4,
                children: [
                  MetricCard(
                    valor: '${dash.clientesActivos}',
                    label: 'Clientes activos',
                    delta: 'Ver clientes →',
                    deltaType: MetricDeltaType.up,
                    onTap: () => context.go('/clientes'),
                  ),
                  MetricCard(
                    valor: '${dash.expedientesActivos}',
                    label: 'Expedientes activos',
                    delta: '${dash.expedientesCompletados} completados',
                    deltaType: MetricDeltaType.neutral,
                    onTap: () => context.go('/expedientes'),
                  ),
                  MetricCard(
                    valor: '${dash.certificacionesVigentes}',
                    label: 'Certificaciones vigentes',
                    delta: dash.certificacionesPorVencer > 0
                        ? '${dash.certificacionesPorVencer} por vencer'
                        : 'Todo en orden',
                    deltaType: dash.certificacionesPorVencer > 0
                        ? MetricDeltaType.warning
                        : MetricDeltaType.up,
                    onTap: () => context.go('/certificaciones'),
                  ),
                  MetricCard(
                    valor: '${dash.hallazgosCriticosAbiertos}',
                    label: 'Hallazgos críticos',
                    delta: dash.hallazgosCriticosAbiertos > 0
                        ? 'Requieren atención'
                        : 'Sin hallazgos críticos',
                    deltaType: dash.hallazgosCriticosAbiertos > 0
                        ? MetricDeltaType.down
                        : MetricDeltaType.up,
                  ),
                ],
              );
            }),

            // Alerta por vencer
            if (dash.certificacionesPorVencer > 0) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warningBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.warning.withOpacity(0.25)),
                ),
                child: Row(children: [
                  const Icon(Icons.schedule_outlined, size: 16, color: AppColors.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${dash.certificacionesPorVencer} certificación(es) próximas a vencer.',
                      style: const TextStyle(fontSize: 12, color: AppColors.warning),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.go('/certificaciones'),
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.warning,
                        textStyle: const TextStyle(fontSize: 12)),
                    child: const Text('Ver →'),
                  ),
                ]),
              ),
            ],

            // Expedientes por estado
            if (dash.expedientesPorEstado.isNotEmpty) ...[
              const SectionHeader(titulo: 'Distribución por estado'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: dash.expedientesPorEstado.map((e) {
                      final estado = e['estado'] as String;
                      final total  = e['total'] as int;
                      final max    = (dash.expedientesActivos + dash.expedientesCompletados)
                          .clamp(1, 9999);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(children: [
                          SizedBox(
                            width: 110,
                            child: StatusBadge(estado: estado),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InlineProgress(value: total / max),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 20,
                            child: Text('$total',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textPrimary,
                                ),
                                textAlign: TextAlign.right),
                          ),
                        ]),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],

            // Accesos rápidos
            const SectionHeader(titulo: 'Accesos rápidos'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _AccesoRapido('Nuevo cliente',     Icons.person_add_outlined,       () => context.go('/clientes/nuevo')),
                _AccesoRapido('Nuevo expediente',  Icons.create_new_folder_outlined, () => context.go('/expedientes/nuevo')),
                _AccesoRapido('AuditBot',          Icons.smart_toy_outlined,         () => context.go('/chat')),
                _AccesoRapido('Verificar cert.',   Icons.qr_code_scanner_outlined,   () => context.go('/verificar')),
              ],
            ),
            const SizedBox(height: 20),
          ]),
        ),
      ),
    );
  }
}

class _AccesoRapido extends StatelessWidget {
  final String titulo;
  final IconData icono;
  final VoidCallback onTap;
  const _AccesoRapido(this.titulo, this.icono, this.onTap);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 130,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(icono, size: 16, color: AppColors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(titulo,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}
