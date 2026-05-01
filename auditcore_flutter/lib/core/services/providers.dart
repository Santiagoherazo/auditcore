import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../models/models.dart';
import '../services/services.dart';


final authServiceProvider        = Provider((_) => AuthService());
final clientesServiceProvider    = Provider((_) => ClientesService());
final expedientesServiceProvider = Provider((_) => ExpedientesService());
final hallazgosServiceProvider   = Provider((_) => HallazgosService());
final certServiceProvider        = Provider((_) => CertificacionesService());
final chatbotServiceProvider     = Provider((_) => ChatbotService());
final dashboardServiceProvider   = Provider((_) => DashboardService());


final setupStatusProvider = FutureProvider<bool>((ref) async {
  try {


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

    return false;
  }
});


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
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {

        await ApiClient.clearTokens();
        state = const AsyncValue.data(null);
      } else {


        if (state is! AsyncData) {
          state = const AsyncValue.data(null);
        }
      }
    } on TimeoutException {

      if (state is! AsyncData) {
        state = const AsyncValue.data(null);
      }
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


final dashboardProvider = FutureProvider.autoDispose<DashboardModel>((ref) async {
  return ref.watch(dashboardServiceProvider).global();
});


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


final expedientesProvider = FutureProvider.autoDispose<List<ExpedienteModel>>((ref) async {
  return ref.watch(expedientesServiceProvider).listar();
});

final expedienteProvider = FutureProvider.autoDispose.family<ExpedienteModel, String>(
  (ref, id) => ref.watch(expedientesServiceProvider).obtener(id),
);

final bitacoraProvider = FutureProvider.autoDispose.family<List<BitacoraModel>, String>(
  (ref, id) => ref.watch(expedientesServiceProvider).bitacora(id),
);


final hallazgosProvider = FutureProvider.autoDispose.family<List<HallazgoModel>, String>(
  (ref, expedienteId) => ref.watch(hallazgosServiceProvider).listar(expediente: expedienteId),
);


final certificacionesProvider = FutureProvider.autoDispose<List<CertificacionModel>>((ref) async {
  return ref.watch(certServiceProvider).listar();
});


final documentosServiceProvider = Provider((_) => DocumentosService());

final documentosProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(documentosServiceProvider).listar();
});

final documentosExpedienteProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, expedienteId) => ref.watch(documentosServiceProvider).porExpediente(expedienteId),
);


final checklistServiceProvider   = Provider((_) => ChecklistService());
final formulariosServiceProvider = Provider((_) => FormulariosService());

final checklistExpedienteProvider =
    FutureProvider.autoDispose.family<List<ChecklistEjecucionModel>, String>(
  (ref, expedienteId) => ref.watch(checklistServiceProvider).porExpediente(expedienteId),
);


class ChatNotifier extends StateNotifier<List<MensajeModel>> {
  ChatNotifier(this._service) : super([]);
  final ChatbotService _service;


  String? convId;


  String? _expedienteId;


  Future<void> iniciarOReanudar({String? expedienteId}) async {
    final expedienteCambio = expedienteId != _expedienteId;
    if (convId != null && !expedienteCambio) {
      return;
    }
    state        = [];
    _expedienteId = expedienteId;
    convId = await _service.crearConversacion(expedienteId: expedienteId);
  }


  Future<void> iniciarNueva({String? expedienteId}) =>
      iniciarOReanudar(expedienteId: expedienteId);


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


  void finalizarStreamAsistente(String contenidoFinal) {
    if (contenidoFinal.isEmpty) {

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


final chatProvider = StateNotifierProvider<ChatNotifier, List<MensajeModel>>(
  (ref) => ChatNotifier(ref.watch(chatbotServiceProvider)),
);
