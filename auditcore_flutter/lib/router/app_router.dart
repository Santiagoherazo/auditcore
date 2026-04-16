import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/services/providers.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/login_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/clientes/clientes_list_screen.dart';
import '../features/clientes/cliente_detail_screen.dart';
import '../features/clientes/cliente_form_screen.dart';
import '../features/expedientes/expedientes_list_screen.dart';
import '../features/expedientes/expediente_detail_screen.dart';
import '../features/expedientes/expediente_form_screen.dart';
import '../features/hallazgos/hallazgo_form_screen.dart';
import '../features/certificaciones/certificaciones_screen.dart';
import '../features/certificaciones/certificacion_form_screen.dart';
import '../features/certificaciones/verificar_screen.dart';
import '../features/chatbot/chat_screen.dart';
import '../features/portal_cliente/portal_home_screen.dart';
import '../features/documentos/documentos_screen.dart';
import '../features/admin/admin_panel_screen.dart';
import '../features/setup/setup_screen.dart';
import '../features/calendario/calendario_screen.dart';
import '../features/perfil/preferencias_mfa_screen.dart';

// ── Splash genérico ───────────────────────────────────────────────────────
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.sidebar,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.verified_user, size: 56, color: Colors.white),
            SizedBox(height: 20),
            Text('AuditCore',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: -0.3,
                )),
            SizedBox(height: 28),
            SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  // Escuchamos AMBOS providers para refrescar el router
  final authNotifier = ValueNotifier<bool>(false);
  ref.listen(authProvider, (_, __) {
    authNotifier.value = !authNotifier.value;
  });
  ref.listen(setupStatusProvider, (_, __) {
    authNotifier.value = !authNotifier.value;
  });

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: authNotifier,
    redirect: (context, state) {
      final authState   = ref.read(authProvider);
      final setupAsync  = ref.read(setupStatusProvider);
      final location    = state.matchedLocation;

      // Mientras verifica auth o setup → splash
      if (authState is AsyncLoading || setupAsync is AsyncLoading) {
        return location == '/splash' ? null : '/splash';
      }

      final isLoggedIn   = authState.valueOrNull != null;
      final isConfigured = setupAsync.valueOrNull ?? false;

      final isPublic = location == '/login'
          || location == '/verificar'
          || location == '/setup';

      // Desde splash: primero verificar si el sistema está configurado
      if (location == '/splash') {
        if (!isConfigured) return '/setup';   // ← primer uso
        if (!isLoggedIn)  return '/login';
        return '/dashboard';
      }

      // Si ya está configurado y alguien intenta acceder a /setup → redirigir
      if (location == '/setup' && isConfigured) {
        return isLoggedIn ? '/dashboard' : '/login';
      }

      if (!isLoggedIn && !isPublic) return '/login';
      if (isLoggedIn && location == '/login') return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/splash',    builder: (_, __) => const _SplashScreen()),
      GoRoute(path: '/setup',     name: 'setup',     builder: (_, __) => const SetupScreen()),
      GoRoute(path: '/login',     name: 'login',     builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/dashboard', name: 'dashboard', builder: (_, __) => const DashboardScreen()),

      // Clientes
      GoRoute(
        path: '/clientes', name: 'clientes',
        builder: (_, __) => const ClientesListScreen(),
        routes: [
          GoRoute(path: 'nuevo', name: 'cliente-nuevo',
              builder: (_, __) => const ClienteFormScreen()),
          GoRoute(
            path: ':id', name: 'cliente-detalle',
            builder: (_, state) =>
                ClienteDetailScreen(id: state.pathParameters['id']!),
            routes: [
              GoRoute(path: 'editar', name: 'cliente-editar',
                  builder: (_, state) =>
                      ClienteFormScreen(clienteId: state.pathParameters['id'])),
            ],
          ),
        ],
      ),

      // Expedientes
      GoRoute(
        path: '/expedientes', name: 'expedientes',
        builder: (_, __) => const ExpedientesListScreen(),
        routes: [
          GoRoute(path: 'nuevo', name: 'expediente-nuevo',
              builder: (_, __) => const ExpedienteFormScreen()),
          GoRoute(
            path: ':id', name: 'expediente-detalle',
            builder: (_, state) =>
                ExpedienteDetailScreen(id: state.pathParameters['id']!),
            routes: [
              GoRoute(path: 'hallazgo/nuevo', name: 'hallazgo-nuevo',
                  builder: (_, state) => HallazgoFormScreen(
                      expedienteId: state.pathParameters['id']!)),
            ],
          ),
        ],
      ),

      GoRoute(path: '/documentos',      name: 'documentos',
          builder: (_, __) => const DocumentosScreen()),
      GoRoute(
        path: '/certificaciones',
        name: 'certificaciones',
        builder: (_, __) => const CertificacionesScreen(),
        routes: [
          // FIX Bug 7: ruta de creación de certificaciones — antes no existía.
          // Usa push desde la lista para mantener el botón "atrás".
          GoRoute(
            path: 'nueva',
            name: 'certificacion-nueva',
            builder: (_, __) => const CertificacionFormScreen(),
          ),
        ],
      ),
      GoRoute(path: '/verificar', name: 'verificar',
          builder: (_, state) => VerificarScreen(
              codigoInicial: state.uri.queryParameters['codigo'])),
      GoRoute(
        path: '/chat', name: 'chat',
        redirect: (context, state) {
          // FIX: verificar que el usuario tiene un rol con acceso al chatbot.
          // BUG ORIGINAL: cualquier usuario autenticado accedía a /chat sin
          // verificación de rol, lo que podía causar un 403 en el POST a
          // enviar_mensaje o un 4003 en el WebSocket — experiencia confusa.
          // Con el guard aquí, se redirige antes de mostrar la pantalla.
          final rol = ref.read(authProvider).valueOrNull?.rol ?? '';
          const rolesPermitidos = ['SUPERVISOR', 'SUPERVISOR', 'AUDITOR', 'AUDITOR', 'ASESOR'];
          if (!rolesPermitidos.contains(rol)) return '/dashboard';
          return null;
        },
        builder: (_, state) => ChatScreen(
            expedienteId: state.uri.queryParameters['expediente']),
      ),
      GoRoute(
        path: '/portal', name: 'portal',
        redirect: (context, state) {
          // FIX: solo EJECUTIVO y ADMIN acceden al portal de cliente
          final rol = ref.read(authProvider).valueOrNull?.rol ?? '';
          if (rol != 'SUPERVISOR' && rol != 'ASESOR') return '/dashboard';
          return null;
        },
        builder: (_, __) => const PortalHomeScreen(),
      ),
      GoRoute(
        path: '/admin-panel', name: 'admin-panel',
        redirect: (context, state) {
          // FIX: solo ADMIN puede acceder al panel de administración
          final rol = ref.read(authProvider).valueOrNull?.rol ?? '';
          if (rol != 'SUPERVISOR') return '/dashboard';
          return null;
        },
        builder: (_, __) => const AdminPanelScreen(),
      ),

      // FIX: estas rutas estaban fuera del array routes[] — GoRouter nunca las
      // registraba, causando que /calendario y /perfil/mfa cayeran siempre en
      // el errorBuilder en lugar de mostrar la pantalla correcta.
      GoRoute(
        path: '/calendario', name: 'calendario',
        redirect: (context, state) {
          final rol = ref.read(authProvider).valueOrNull?.rol ?? '';
          if (!['SUPERVISOR', 'ASESOR', 'AUDITOR', 'AUXILIAR', 'REVISOR'].contains(rol)) {
            return '/dashboard';
          }
          return null;
        },
        builder: (_, __) => const CalendarioScreen(),
      ),
      GoRoute(
        path: '/perfil/mfa', name: 'mfa-preferencias',
        builder: (_, __) => const PreferenciasMfaScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 40,
              color: AppColors.textTertiary),
          const SizedBox(height: 12),
          Text('Ruta no encontrada: ${state.uri}',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => GoRouter.of(context).go('/login'),
            child: const Text('Ir al inicio'),
          ),
        ]),
      ),
    ),
  );
});
