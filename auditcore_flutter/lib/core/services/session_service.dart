/// session_service.dart — Cierre de sesión centralizado.
///
/// PROBLEMA ORIGINAL: el logout en dashboard_screen.dart solo llamaba a
/// authProvider.notifier.logout() + context.go('/login'), dejando los 4
/// WebSockets (chatbot, notificaciones, dashboard, expediente) vivos e
/// intentando reconectar con backoff → UI bloqueada hasta recargar la página.
///
/// SOLUCIÓN: este servicio desconecta todos los WS antes de limpiar tokens,
/// limpia el estado del chat, y muestra un mensaje de confirmación.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'providers.dart';
import 'websocket_service.dart';

class SessionService {
  SessionService._();

  /// Cierra la sesión correctamente desde cualquier pantalla.
  ///
  /// [showConfirmDialog] — false para logout forzado (token expirado).
  static Future<void> logout(
    BuildContext context,
    WidgetRef ref, {
    bool showConfirmDialog = true,
  }) async {
    if (showConfirmDialog) {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _LogoutConfirmDialog(),
      );
      if (confirmed != true) return;
    }

    // 1. Desconectar TODOS los WebSockets antes de limpiar tokens.
    //    El orden importa: si se limpian tokens primero los sockets intentan
    //    reconectar con token nulo generando bucles de error.
    await Future.wait([
      wsChatbot.disconnect(),
      wsNotificaciones.disconnect(),
      wsDashboard.disconnect(),
      wsExpediente.disconnect(),
    ]);

    // 2. Limpiar historial del chat en memoria.
    ref.read(chatProvider.notifier).limpiar();

    // 3. Blacklist del refresh token en backend + limpiar storage local.
    await ref.read(authProvider.notifier).logout();

    // 4. Navegar a /login y mostrar snackbar de confirmación.
    if (context.mounted) {
      context.go('/login');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(children: [
                Icon(Icons.check_circle_outline, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text('Sesión finalizada correctamente.',
                    style: TextStyle(fontSize: 13)),
              ]),
              backgroundColor: const Color(0xFF1A3A5C),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              margin: const EdgeInsets.all(16),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      });
    }
  }
}

class _LogoutConfirmDialog extends StatelessWidget {
  const _LogoutConfirmDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3CD),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Icon(Icons.logout_rounded,
              color: Color(0xFFD97706), size: 24),
        ),
        const SizedBox(height: 16),
        const Text('¿Cerrar sesión?',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                color: Color(0xFF0F2447))),
        const SizedBox(height: 8),
        const Text(
          'Se desconectarán todas las actualizaciones en tiempo real y '
          'el historial del chat se cerrará.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 4),
      ]),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context, false),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF64748B),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0F2447),
            foregroundColor: Colors.white,
          ),
          child: const Text('Cerrar sesión'),
        ),
      ],
    );
  }
}
