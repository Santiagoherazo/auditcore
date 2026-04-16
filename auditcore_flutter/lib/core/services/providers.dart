import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../models/models.dart';
import '../services/services.dart';

// ── Servicios (singleton por provider) ───────────────────────────────────
final authServiceProvider        = Provider((_) => AuthService());
final clientesServiceProvider    = Provider((_) => ClientesService());
final expedientesServiceProvider = Provider((_) => ExpedientesService());
final hallazgosServiceProvider   = Provider((_) => HallazgosService());
final certServiceProvider        = Provider((_) => CertificacionesService());
final chatbotServiceProvider     = Provider((_) => ChatbotService());
final dashboardServiceProvider   = Provider((_) => DashboardService());

// ── Setup status — ¿la plataforma ya fue configurada? ───────────────────────
// con el router, que necesita este provider antes de que setup_screen se cargue.
final setupStatusProvider = FutureProvider<bool>((ref) async {
  try {
    // incluyendo rutas relativas en web Docker) en vez de crear un Dio suelto.
    // Timeout corto para no bloquear el splash demasiado tiempo.
    final resp = await ApiClient.instance
        .get(
          'auth/setup/status/',
          options: Options(
            sendTimeout: const Duration(seconds: 6),
            receiveTimeout: const Duration(seconds: 6),
          ),
        );
    return resp.data['configured'] == true;
  } catch (_) {
    // Si el backend no responde (primera vez sin Docker), asumir no configurado
    return false;
  }
});


// ── Usuario autenticado ───────────────────────────────────────────────────
class AuthNotifier extends StateNotifier<AsyncValue<UsuarioModel?>> {
  AuthNotifier(this._service) : super(const AsyncValue.loading()) {
    cargarUsuario();
  }

  final AuthService _service;

  Future<void> login(String email, String password, {String? codigoMfa}) async {
    state = const AsyncValue.loading();
    try {
      final user = await _service.login(email, password, codigoMfa: codigoMfa);
      state = AsyncValue.data(user);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> cargarUsuario() async {
    try {
      final token = await ApiClient.getAccessToken();
      if (token == null) {
        state = const AsyncValue.data(null);
        return;
      }
      final user = await _service.getMe().timeout(const Duration(seconds: 8));
      state = AsyncValue.data(user);
    } on DioException catch (e) {
      // sesión activa, getMe() devolvía sus datos normalmente (200) y Flutter
      // no detectaba el cambio de estado. Ahora el backend devuelve 403 para
      // cuentas no activas, y Flutter limpia la sesión al detectarlo.
      if (e.response?.statusCode == 403) {
        await ApiClient.clearTokens();
        state = const AsyncValue.data(null);
        return;
      }
      state = const AsyncValue.data(null);
    } catch (_) {
      state = const AsyncValue.data(null);
    }
  }

  Future<void> logout() async {
    await _service.logout();
    state = const AsyncValue.data(null);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AsyncValue<UsuarioModel?>>(
  (ref) => AuthNotifier(ref.watch(authServiceProvider)),
);

// ── Dashboard global ──────────────────────────────────────────────────────
// Sin autoDispose, el provider vive indefinidamente con su caché aunque nadie lo escuche,
// y al volver al dashboard devuelve datos obsoletos hasta el próximo invalidate.
final dashboardProvider = FutureProvider.autoDispose<DashboardModel>((ref) async {
  return ref.watch(dashboardServiceProvider).global();
});

// ── Clientes ──────────────────────────────────────────────────────────────
final clientesFiltroProvider = StateProvider<Map<String, String?>>((ref) => {});

final clientesProvider = FutureProvider.autoDispose<List<ClienteModel>>((ref) async {
  final filtros = ref.watch(clientesFiltroProvider);
  return ref.watch(clientesServiceProvider).listar(
    estado: filtros['estado'],
    sector: filtros['sector'],
    busqueda: filtros['busqueda'],
  );
});

final clienteProvider = FutureProvider.autoDispose.family<ClienteModel, String>(
  (ref, id) => ref.watch(clientesServiceProvider).obtener(id),
);

// ── Expedientes ───────────────────────────────────────────────────────────
final expedientesProvider = FutureProvider.autoDispose<List<ExpedienteModel>>((ref) async {
  return ref.watch(expedientesServiceProvider).listar();
});

final expedienteProvider = FutureProvider.autoDispose.family<ExpedienteModel, String>(
  (ref, id) => ref.watch(expedientesServiceProvider).obtener(id),
);

final bitacoraProvider = FutureProvider.autoDispose.family<List<BitacoraModel>, String>(
  (ref, id) => ref.watch(expedientesServiceProvider).bitacora(id),
);

// ── Hallazgos ─────────────────────────────────────────────────────────────
final hallazgosProvider = FutureProvider.autoDispose.family<List<HallazgoModel>, String>(
  (ref, expedienteId) => ref.watch(hallazgosServiceProvider).listar(expediente: expedienteId),
);

// ── Certificaciones ───────────────────────────────────────────────────────
final certificacionesProvider = FutureProvider.autoDispose<List<CertificacionModel>>((ref) async {
  return ref.watch(certServiceProvider).listar();
});

// ── Documentos ────────────────────────────────────────────────────────────
final documentosServiceProvider = Provider((_) => DocumentosService());

final documentosProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(documentosServiceProvider).listar();
});

final documentosExpedienteProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, expedienteId) => ref.watch(documentosServiceProvider).porExpediente(expedienteId),
);

// ── Checklist ─────────────────────────────────────────────────────────────
final checklistServiceProvider   = Provider((_) => ChecklistService());
final formulariosServiceProvider = Provider((_) => FormulariosService());

final checklistExpedienteProvider =
    FutureProvider.autoDispose.family<List<ChecklistEjecucionModel>, String>(
  (ref, expedienteId) => ref.watch(checklistServiceProvider).porExpediente(expedienteId),
);

// ── Chatbot ───────────────────────────────────────────────────────────────
class ChatNotifier extends StateNotifier<List<MensajeModel>> {
  ChatNotifier(this._service) : super([]);
  final ChatbotService _service;

  /// ID de conversación activa. Persiste mientras dure la sesión del usuario.
  /// Solo se limpia al hacer logout (SessionService.logout → limpiar()).
  String? convId;

  /// expedienteId vinculado a la conversación activa.
  String? _expedienteId;

  /// Inicia o reanuda la sesión de chat.
  ///
  /// - Si ya hay convId activo y el expediente NO cambió → reanuda sin tocar
  ///   el historial. El ChatScreen solo reconecta el WebSocket.
  /// - Si no hay convId, o el expediente cambió → crea conversación nueva.
  ///
  /// Esto resuelve el bug donde navegar a otra pantalla y volver al chat
  /// borraba toda la conversación al recrear el widget.
  Future<void> iniciarOReanudar({String? expedienteId}) async {
    final expedienteCambio = expedienteId != _expedienteId;
    if (convId != null && !expedienteCambio) {
      return; // Reanuda — no borrar historial
    }
    state        = [];
    _expedienteId = expedienteId;
    convId = await _service.crearConversacion(expedienteId: expedienteId);
  }

  /// Alias para compatibilidad con código existente.
  Future<void> iniciarNueva({String? expedienteId}) =>
      iniciarOReanudar(expedienteId: expedienteId);

  /// Limpia completamente la sesión de chat.
  /// Solo llamar desde SessionService.logout() — no al navegar entre pantallas.
  void limpiar() {
    state         = [];
    convId        = null;
    _expedienteId = null;
  }

  Future<void> enviar(String texto) async {
    if (convId == null) return;
    state = [
      ...state,
      MensajeModel(
        id:           DateTime.now().millisecondsSinceEpoch.toString(),
        rol:          'USUARIO',
        contenido:    texto,
        tokensUsados: 0,
        fecha:        DateTime.now().toIso8601String(),
      ),
    ];
    await _service.enviarMensaje(convId!, texto);
  }

  /// Streaming: crea una burbuja vacía del asistente para ir llenando
  void iniciarStreamAsistente() {
    state = [
      ...state,
      MensajeModel(
        id:           'stream_${DateTime.now().millisecondsSinceEpoch}',
        rol:          'ASISTENTE',
        contenido:    '',
        tokensUsados: 0,
        fecha:        DateTime.now().toIso8601String(),
      ),
    ];
  }

  /// Streaming: actualiza el texto de la última burbuja del asistente
  void actualizarStreamAsistente(String contenido) {
    if (state.isEmpty || state.last.rol != 'ASISTENTE') return;
    final ultimo = state.last;
    state = [
      ...state.sublist(0, state.length - 1),
      MensajeModel(
        id:           ultimo.id,
        rol:          'ASISTENTE',
        contenido:    contenido,
        tokensUsados: ultimo.tokensUsados,
        fecha:        ultimo.fecha,
      ),
    ];
  }

  /// Streaming: finaliza con el texto completo.
  /// FIX: si contenidoFinal está vacío (timeout antes del primer chunk),
  /// eliminar la burbuja del asistente en lugar de dejar una burbuja vacía visible.
  void finalizarStreamAsistente(String contenidoFinal) {
    if (contenidoFinal.isEmpty) {
      // Eliminar la burbuja vacía de streaming si existe
      if (state.isNotEmpty && state.last.rol == 'ASISTENTE' &&
          state.last.contenido.isEmpty) {
        state = state.sublist(0, state.length - 1);
      }
      return;
    }
    if (state.isEmpty || state.last.rol != 'ASISTENTE') {
      agregarRespuesta(contenidoFinal);
      return;
    }
    actualizarStreamAsistente(contenidoFinal);
  }

  void agregarRespuesta(String contenido) {
    if (contenido.isEmpty) return;
    // streaming ya entregó la misma respuesta. Compara por contenido exacto
    // con cualquier mensaje del asistente reciente (no solo el último),
    // porque el polling puede llegar después de que _terminarEspera() limpió timers.
    final yaExiste = state.any((m) =>
        m.rol == 'ASISTENTE' && m.contenido == contenido);
    if (yaExiste) return;
    state = [
      ...state,
      MensajeModel(
        id:           DateTime.now().millisecondsSinceEpoch.toString(),
        rol:          'ASISTENTE',
        contenido:    contenido,
        tokensUsados: 0,
        fecha:        DateTime.now().toIso8601String(),
      ),
    ];
  }

  Future<void> sincronizarMensajes(String convId) async {
    try {
      final msgs = await _service.mensajes(convId);
      if (msgs.length > state.length) state = msgs;
    } catch (_) {}
  }
}

// streaming. Si se destruye al navegar fuera, la conversación activa en el
// backend queda huérfana (sigue procesando pero nadie escucha los eventos WS).
// Al volver, chat_screen llama _iniciar() que ya hace limpiar() + nueva conv.
final chatProvider = StateNotifierProvider<ChatNotifier, List<MensajeModel>>(
  (ref) => ChatNotifier(ref.watch(chatbotServiceProvider)),
);
