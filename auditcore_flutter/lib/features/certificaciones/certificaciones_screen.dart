import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/services/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

class CertificacionesScreen extends ConsumerWidget {
  const CertificacionesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState  = ref.watch(authProvider);
    final usuario    = authState.valueOrNull;
    final certsAsync = ref.watch(certificacionesProvider);
    final esAdminOLider = ['SUPERVISOR', 'SUPERVISOR'].contains(usuario?.rol ?? '');

    return AppShell(
      rutaActual:    '/certificaciones',
      rolUsuario:    usuario?.rol ?? '',
      nombreUsuario: usuario?.nombreCompleto ?? '',
      titulo:        'Certificaciones',
      showBottomNav: true,
      actions: [
        // FIX Bug 7: botón para crear certificación (solo ADMIN/AUDITOR_LIDER)
        if (esAdminOLider)
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 20),
            tooltip: 'Nueva certificación',
            // FIX: usar context.push en lugar de context.go para mantener
            // el stack y poder volver con el botón atrás.
            onPressed: () => context.push('/certificaciones/nueva'),
            style: IconButton.styleFrom(foregroundColor: AppColors.textSecondary),
          ),
        IconButton(
          icon: const Icon(Icons.qr_code_scanner_outlined, size: 18),
          tooltip: 'Verificar certificado',
          // FIX: push para mantener stack de navegación
          onPressed: () => context.push('/verificar'),
          style: IconButton.styleFrom(foregroundColor: AppColors.textSecondary),
        ),
        const SizedBox(width: 8),
      ],
      child: certsAsync.when(
        loading: () => const Center(
          child: SizedBox(width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (e, _) => EmptyState(
          titulo: 'Error',
          subtitulo: e.toString(),
          icono: Icons.error_outline,
          labelBoton: 'Reintentar',
          onBoton: () => ref.invalidate(certificacionesProvider),
        ),
        data: (certs) => certs.isEmpty
            ? EmptyState(
                titulo: 'Sin certificaciones',
                subtitulo: 'Las certificaciones emitidas aparecerán aquí.',
                icono: Icons.verified_outlined,
                labelBoton: esAdminOLider ? 'Nueva certificación' : null,
                onBoton: esAdminOLider
                    ? () => context.push('/certificaciones/nueva')
                    : null,
              )
            : ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: certs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final c    = certs[i];
                  final urgente = c.diasParaVencer > 0 && c.diasParaVencer < 30;
                  final vencida = c.estado == 'VENCIDA';

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(children: [
                          Expanded(
                            child: Text(c.numero,
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary)),
                          ),
                          StatusBadge(estado: c.estado),
                        ]),
                        const SizedBox(height: 4),
                        Text(c.clienteNombre,
                            style: const TextStyle(fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary)),
                        Text(c.tipoNombre,
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textTertiary)),
                        const SizedBox(height: 10),

                        // Vencimiento
                        Row(children: [
                          Icon(Icons.calendar_today_outlined,
                              size: 13,
                              color: urgente
                                  ? AppColors.warning
                                  : vencida
                                      ? AppColors.danger
                                      : AppColors.textTertiary),
                          const SizedBox(width: 5),
                          Text(
                            'Vence: ${c.fechaVencimiento}',
                            style: TextStyle(
                              fontSize: 12,
                              color: urgente
                                  ? AppColors.warning
                                  : vencida
                                      ? AppColors.danger
                                      : AppColors.textSecondary,
                              fontWeight: (urgente || vencida)
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                            ),
                          ),
                          if (urgente) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.warningBg,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                c.diasParaVencer <= 0 ? 'Vencida' : '${c.diasParaVencer} días',
                                style: const TextStyle(
                                    fontSize: 10, color: AppColors.warning,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ]),

                        // Acciones
                        const SizedBox(height: 10),
                        Row(children: [
                          if (c.certificadoPdf == null)
                            OutlinedButton.icon(
                              icon: const Icon(Icons.picture_as_pdf_outlined,
                                  size: 13),
                              label: const Text('Generar PDF',
                                  style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6)),
                              onPressed: () async {
                                await ref
                                    .read(certServiceProvider)
                                    .generarPdf(c.id);
                                if (context.mounted)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'PDF en generación. Recibirás una notificación.')));
                              },
                            ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.qr_code_outlined, size: 13),
                            label: const Text('Verificar',
                                style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6)),
                            onPressed: () => context.go(
                                '/verificar?codigo=${c.codigoVerificacion}'),
                          ),
                          if (vencida) ...[
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.refresh_outlined,
                                  size: 13),
                              label: const Text('Renovar',
                                  style: TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6)),
                              onPressed: () =>
                                  context.push('/expedientes/nuevo'),
                            ),
                          ],
                        ]),
                      ]),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
