import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

class PortalHomeScreen extends ConsumerWidget {
  const PortalHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState  = ref.watch(authProvider);
    final usuario    = authState.valueOrNull;
    final certsAsync = ref.watch(certificacionesProvider);
    final expsAsync  = ref.watch(expedientesProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Portal del cliente'),
        actions: [
          IconButton(
            icon: const Icon(Icons.smart_toy_outlined, size: 18),
            onPressed: () => context.go('/chat'),
            style:
                IconButton.styleFrom(foregroundColor: AppColors.textSecondary),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'logout') {
                await ref.read(authProvider.notifier).logout();
                if (context.mounted) context.go('/login');
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'logout',
                child: Row(children: [
                  Icon(Icons.logout, size: 16,
                      color: AppColors.textSecondary),
                  SizedBox(width: 8),
                  Text('Salir', style: TextStyle(fontSize: 13)),
                ]),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Bienvenida
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.sidebar,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const Icon(Icons.verified_user_outlined,
                  color: Colors.white, size: 28),
              const SizedBox(height: 12),
              Text(
                'Bienvenido, ${usuario?.nombre ?? 'Cliente'}',
                style: const TextStyle(
                    color: Colors.white, fontSize: 18,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'Consulta el estado de tus auditorías y certificaciones.',
                style: TextStyle(color: Color(0x80FFFFFF), fontSize: 12),
              ),
            ]),
          ),
          const SizedBox(height: 20),

          // Certificaciones vigentes
          const SectionHeader(titulo: 'Mis certificaciones'),
          certsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const Text('Error cargando certificaciones',
                style: TextStyle(fontSize: 12, color: AppColors.danger)),
            data: (certs) {
              final vigentes =
                  certs.where((c) => c.estado == 'VIGENTE').toList();
              if (vigentes.isEmpty) {
                return const EmptyState(
                  titulo: 'Sin certificaciones vigentes',
                  subtitulo: 'Tus certificaciones aparecerán aquí.',
                  icono: Icons.verified_outlined,
                );
              }
              return Column(
                children: vigentes
                    .map((c) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Card(
                            child: ListTile(
                              leading: Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  color: AppColors.successBg,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: const Icon(Icons.verified_outlined,
                                    size: 18, color: AppColors.success),
                              ),
                              title: Text(c.numero,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c.tipoNombre,
                                      style: const TextStyle(fontSize: 11)),
                                  Text(
                                    'Válida hasta: ${c.fechaVencimiento}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textTertiary),
                                  ),
                                ],
                              ),
                              trailing: const Icon(Icons.chevron_right,
                                  size: 16, color: AppColors.textTertiary),
                              onTap: () => context.go(
                                  '/verificar?codigo=${c.codigoVerificacion}'),
                            ),
                          ),
                        ))
                    .toList(),
              );
            },
          ),

          // Auditorías activas
          const SectionHeader(titulo: 'Mis auditorías activas'),
          expsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const Text('Error cargando auditorías',
                style: TextStyle(fontSize: 12, color: AppColors.danger)),
            data: (exps) {
              final activos = exps
                  .where((e) =>
                      e.estado == 'ACTIVO' || e.estado == 'EN_EJECUCION')
                  .toList();
              if (activos.isEmpty) {
                return const EmptyState(
                  titulo: 'Sin auditorías activas',
                  subtitulo:
                      'Cuando inicie una auditoría, verás su avance aquí.',
                  icono: Icons.folder_outlined,
                );
              }
              return Column(
                children: activos
                    .map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                Row(children: [
                                  Expanded(
                                    child: Text(e.tipoNombre,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: AppColors.textPrimary)),
                                  ),
                                  StatusBadge(estado: e.estado),
                                ]),
                                const SizedBox(height: 4),
                                Text(e.numeroExpediente,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textTertiary)),
                                const SizedBox(height: 10),
                                InlineProgress(
                                    value: e.porcentajeAvance / 100),
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  icon: const Icon(
                                      Icons.smart_toy_outlined,
                                      size: 13),
                                  label: const Text(
                                      'Consultar al asistente',
                                      style: TextStyle(fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 6)),
                                  onPressed: () => context
                                      .go('/chat?expediente=${e.id}'),
                                ),
                              ]),
                            ),
                          ),
                        ))
                    .toList(),
              );
            },
          ),

          const SizedBox(height: 20),
          // CTA verificar
          Card(
            child: ListTile(
              leading: const Icon(Icons.qr_code_scanner_outlined,
                  color: AppColors.accent, size: 20),
              title: const Text('Verificar autenticidad de un certificado',
                  style: TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary)),
              subtitle: const Text('Consulta si un certificado es válido',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textTertiary)),
              trailing: const Icon(Icons.chevron_right,
                  size: 16, color: AppColors.textTertiary),
              onTap: () => context.go('/verificar'),
            ),
          ),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }
}
