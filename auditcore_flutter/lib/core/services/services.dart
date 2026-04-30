import 'package:dio/dio.dart';
import '../api/api_client.dart';
import '../api/endpoints.dart';
import '../models/models.dart';

// ── Auth ──────────────────────────────────────────
class AuthService {
  Dio get _dio => ApiClient.instance;

  Future<UsuarioModel> login(String email, String password, {String? codigoMfa}) async {
    final body = <String, dynamic>{
      'email':    email.trim().toLowerCase(),
      'password': password,
    };
    if (codigoMfa != null && codigoMfa.isNotEmpty) {
      body['codigo_mfa'] = codigoMfa;
    }
    final resp = await _dio.post(Endpoints.login, data: body);

    // FIX: manejar respuesta MFA antes de intentar parsear tokens
    // El backend devuelve {'detail': '...', 'mfa_required': true} con HTTP 200
    // cuando el usuario tiene MFA activo. Sin este check, falla al parsear.
    final data = resp.data as Map<String, dynamic>? ?? {};
    if (data['mfa_required'] == true) {
      throw Exception('MFA_REQUIRED:${data['detail'] ?? 'Se requiere código MFA.'}');
    }

    final access  = data['access']  as String?;
    final refresh = data['refresh'] as String?;
    if (access == null || refresh == null) {
      throw Exception('Respuesta de login inválida: faltan tokens.');
    }
    await ApiClient.saveTokens(access: access, refresh: refresh);
    return await getMe();
  }

  Future<UsuarioModel> getMe() async {
    final resp = await _dio.get(Endpoints.usuarioMe);
    return UsuarioModel.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> logout() async {
    try {
      final refresh = await ApiClient.getRefreshToken();
      if (refresh != null) {
        await _dio.post(Endpoints.logout, data: {'refresh': refresh});
      }
    } catch (_) {}
    await ApiClient.clearTokens();
  }
}

// ── Clientes ──────────────────────────────────────
class ClientesService {
  Dio get _dio => ApiClient.instance;

  Future<List<ClienteModel>> listar({
    String? estado,
    String? sector,
    String? busqueda,
  }) async {
    final resp = await _dio.get(Endpoints.clientes, queryParameters: {
      if (estado != null)   'estado': estado,
      if (sector != null)   'sector': sector,
      if (busqueda != null) 'search': busqueda,
    });
    final data = resp.data;
    final lista = data is Map ? (data['results'] as List? ?? []) : (data as List? ?? []);
    return lista.map((j) => ClienteModel.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<ClienteModel> obtener(String id) async {
    final resp = await _dio.get(Endpoints.cliente(id));
    return ClienteModel.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<ClienteModel> crear(Map<String, dynamic> data) async {
    final resp = await _dio.post(Endpoints.clientes, data: data);
    return ClienteModel.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<ClienteModel> actualizar(String id, Map<String, dynamic> data) async {
    final resp = await _dio.patch(Endpoints.cliente(id), data: data);
    return ClienteModel.fromJson(resp.data as Map<String, dynamic>);
  }

  /// Cambia el estado del cliente a través del endpoint controlado /cambiar-estado/.
  /// El campo 'estado' es read_only en el serializer estándar para evitar
  /// que ediciones normales reseten el estado accidentalmente.
  Future<Map<String, dynamic>> cambiarEstado(
      String id, String nuevoEstado, {String motivo = ''}) async {
    final resp = await _dio.post(
      Endpoints.clienteCambiarEstado(id),
      data: {'estado': nuevoEstado, if (motivo.isNotEmpty) 'motivo': motivo},
    );
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> dashboard(String id) async {
    final resp = await _dio.get(Endpoints.clienteDashboard(id));
    return resp.data as Map<String, dynamic>;
  }
}

// ── Expedientes ───────────────────────────────────
class ExpedientesService {
  Dio get _dio => ApiClient.instance;

  Future<List<ExpedienteModel>> listar({String? estado, String? cliente}) async {
    final resp = await _dio.get(Endpoints.expedientes, queryParameters: {
      if (estado != null)  'estado': estado,
      if (cliente != null) 'cliente': cliente,
    });
    final data = resp.data;
    final lista = data is Map ? (data['results'] as List? ?? []) : (data as List? ?? []);
    return lista.map((j) => ExpedienteModel.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<ExpedienteModel> obtener(String id) async {
    final resp = await _dio.get(Endpoints.expediente(id));
    return ExpedienteModel.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<ExpedienteModel> crear(Map<String, dynamic> data) async {
    final resp = await _dio.post(Endpoints.expedientes, data: data);
    return ExpedienteModel.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<List<BitacoraModel>> bitacora(String id) async {
    final resp = await _dio.get(Endpoints.expedienteBitacora(id));
    // FIX: la bitácora no está paginada — devuelve lista directa
    final lista = resp.data as List? ?? [];
    return lista.map((j) => BitacoraModel.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> dashboard(String id) async {
    final resp = await _dio.get(Endpoints.expedienteDashboard(id));
    return resp.data as Map<String, dynamic>;
  }

  Future<ExpedienteModel> cambiarEstado(
      String id, String estado, String motivo) async {
    final resp = await _dio.post(
      Endpoints.expedienteCambiarEstado(id),
      data: {'estado': estado, 'motivo': motivo},
    );
    return ExpedienteModel.fromJson(resp.data as Map<String, dynamic>);
  }
}

// ── Hallazgos ─────────────────────────────────────
class HallazgosService {
  Dio get _dio => ApiClient.instance;

  Future<List<HallazgoModel>> listar({
    String? expediente,
    String? estado,
    String? criticidad,
  }) async {
    final resp = await _dio.get(Endpoints.hallazgos, queryParameters: {
      if (expediente != null) 'expediente': expediente,
      if (estado != null)     'estado': estado,
      if (criticidad != null) 'nivel_criticidad': criticidad,
    });
    final data = resp.data;
    final lista = data is Map ? (data['results'] as List? ?? []) : (data as List? ?? []);
    return lista.map((j) => HallazgoModel.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<HallazgoModel> crear(Map<String, dynamic> data) async {
    final resp = await _dio.post(Endpoints.hallazgos, data: data);
    return HallazgoModel.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<HallazgoModel> actualizar(String id, Map<String, dynamic> data) async {
    final resp = await _dio.patch(Endpoints.hallazgo(id), data: data);
    return HallazgoModel.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> subirEvidencia({
    required String expedienteId,
    required String hallazgoId,
    String? rutaArchivo,
    List<int>? bytesArchivo,
    required String nombreArchivo,
    required String descripcion,
  }) async {
    final MultipartFile multipart;
    if (bytesArchivo != null) {
      multipart = MultipartFile.fromBytes(bytesArchivo, filename: nombreArchivo);
    } else if (rutaArchivo != null) {
      multipart = await MultipartFile.fromFile(rutaArchivo, filename: nombreArchivo);
    } else {
      return;
    }
    final formData = FormData.fromMap({
      'expediente': expedienteId,
      'hallazgo':   hallazgoId,
      'descripcion': descripcion,
      'archivo':    multipart,
    });
    await _dio.post(
      Endpoints.evidencias,
      data: formData,
      options: Options(headers: {'Content-Type': 'multipart/form-data'}),
    );
  }
}

// ── Certificaciones ───────────────────────────────
class CertificacionesService {
  Dio get _dio => ApiClient.instance;

  Future<List<CertificacionModel>> listar({String? estado}) async {
    final resp = await _dio.get(Endpoints.certificaciones, queryParameters: {
      if (estado != null) 'estado': estado,
    });
    final data = resp.data;
    final lista = data is Map ? (data['results'] as List? ?? []) : (data as List? ?? []);
    return lista.map((j) => CertificacionModel.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> verificar(String codigo) async {
    // FIX: el endpoint es una acción del ViewSet, no una URL separada
    final resp = await _dio.get(
      Endpoints.certificacionVerificar,
      queryParameters: {'codigo': codigo.trim()},
    );
    return resp.data as Map<String, dynamic>;
  }

  Future<void> generarPdf(String id) async {
    await _dio.get(Endpoints.certificacionPdf(id));
  }
}

// ── Chatbot ───────────────────────────────────────
class ChatbotService {
  Dio get _dio => ApiClient.instance;

  Future<String> crearConversacion({String? expedienteId}) async {
    final resp = await _dio.post(Endpoints.conversaciones, data: {
      if (expedienteId != null) 'expediente': expedienteId,
    });
    return (resp.data['id'] ?? '').toString();
  }

  /// FIX: busca la conversación activa más reciente para no crear una nueva
  /// cada vez que el usuario entra a la pantalla del chat.
  Future<String?> obtenerConversacionActiva({String? expedienteId}) async {
    try {
      final resp = await _dio.get(Endpoints.conversaciones, queryParameters: {
        if (expedienteId != null) 'expediente': expedienteId,
        'ordering': '-fecha_actualizacion',
        'limit': 1,
      });
      final data = resp.data;
      final lista = data is Map
          ? (data['results'] as List? ?? [])
          : (data as List? ?? []);
      if (lista.isEmpty) return null;
      return (lista.first['id'] ?? '').toString();
    } catch (_) {
      return null;
    }
  }

  Future<List<MensajeModel>> mensajes(String convId) async {
    final resp = await _dio.get('${Endpoints.conversacion(convId)}mensajes/');
    final lista = resp.data as List? ?? [];
    return lista.map((j) => MensajeModel.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<void> enviarMensaje(String convId, String contenido) async {
    await _dio.post(
      Endpoints.enviarMensaje(convId),
      data: {'contenido': contenido},
    );
  }
}

// ── Dashboard ─────────────────────────────────────
class DashboardService {
  Dio get _dio => ApiClient.instance;

  Future<DashboardModel> global() async {
    final resp = await _dio.get(Endpoints.dashboard);
    return DashboardModel.fromJson(resp.data as Map<String, dynamic>);
  }
}

// ── Documentos ────────────────────────────────────
class DocumentosService {
  Dio get _dio => ApiClient.instance;

  Future<List<Map<String, dynamic>>> listar({String? estado}) async {
    final resp = await _dio.get(Endpoints.documentos, queryParameters: {
      if (estado != null) 'estado': estado,
    });
    final data = resp.data;
    final lista = data is Map ? (data['results'] as List? ?? []) : (data as List? ?? []);
    return lista.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> porExpediente(String expedienteId) async {
    final resp = await _dio.get(Endpoints.documentos, queryParameters: {
      'expediente': expedienteId,
    });
    final data = resp.data;
    final lista = data is Map ? (data['results'] as List? ?? []) : (data as List? ?? []);
    return lista.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> revisar(
    String id,
    String estado, {
    String? observacion,
  }) async {
    final resp = await _dio.post(
      Endpoints.documentoRevisar(id),
      data: {
        'estado': estado,
        if (observacion != null) 'observacion': observacion,
      },
    );
    return resp.data as Map<String, dynamic>;
  }

  /// Sube un documento a un expediente.
  Future<Map<String, dynamic>> subir({
    required String expedienteId,
    required String nombre,
    List<int>?  bytesArchivo,
    String?     rutaArchivo,
    required String nombreArchivo,
    String?     documentoRequeridoId,
  }) async {
    final MultipartFile multipart;
    if (bytesArchivo != null) {
      multipart = MultipartFile.fromBytes(bytesArchivo, filename: nombreArchivo);
    } else if (rutaArchivo != null) {
      multipart = await MultipartFile.fromFile(rutaArchivo, filename: nombreArchivo);
    } else {
      throw ArgumentError('Se requiere bytesArchivo o rutaArchivo');
    }

    final formData = FormData.fromMap({
      'expediente': expedienteId,
      'nombre':     nombre,
      'archivo':    multipart,
      if (documentoRequeridoId != null) 'documento_requerido': documentoRequeridoId,
    });

    final resp = await _dio.post(
      Endpoints.documentos,
      data: formData,
      options: Options(headers: {'Content-Type': 'multipart/form-data'}),
    );
    return resp.data as Map<String, dynamic>;
  }
}

// ── Checklist ─────────────────────────────────────
class ChecklistService {
  Dio get _dio => ApiClient.instance;

  Future<List<ChecklistEjecucionModel>> porExpediente(String expedienteId) async {
    final resp = await _dio.get(Endpoints.checklist, queryParameters: {
      'expediente': expedienteId,
    });
    final data = resp.data;
    final lista = data is Map ? (data['results'] as List? ?? []) : (data as List? ?? []);
    return lista
        .map((j) => ChecklistEjecucionModel.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<ChecklistEjecucionModel> actualizar(
    String id,
    String estado, {
    String? observacion,
  }) async {
    final resp = await _dio.patch(Endpoints.checklistItem(id), data: {
      'estado': estado,
      if (observacion != null) 'observacion': observacion,
    });
    return ChecklistEjecucionModel.fromJson(resp.data as Map<String, dynamic>);
  }
}

// ── Formularios dinámicos ─────────────────────────
class FormulariosService {
  Dio get _dio => ApiClient.instance;

  Future<List<CampoFormularioModel>> campos({
    String? tipoAuditoriaId,
    String contexto = 'expediente',
  }) async {
    final resp = await _dio.get('formularios/esquemas/', queryParameters: {
      if (tipoAuditoriaId != null) 'tipo_auditoria': tipoAuditoriaId,
      'contexto': contexto,
    });
    final data = resp.data;
    final esquemas = data is Map ? (data['results'] as List? ?? []) : (data as List? ?? []);
    if (esquemas.isEmpty) return [];
    // FIX: verificar que esquemas.first no sea nulo y que tenga el campo 'campos'.
    // Si el tipo de auditoría no tiene esquema de formulario configurado,
    // 'campos' puede ser null → castear directo lanzaba RangeError/TypeError.
    final primerEsquema = esquemas.first;
    if (primerEsquema == null) return [];
    final campos = (primerEsquema as Map<String, dynamic>)['campos'] as List? ?? [];
    return campos
        .map((j) => CampoFormularioModel.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<void> guardarValores({
    required String esquemaId,
    required String entidadTipo,
    required String entidadId,
    required Map<String, dynamic> valores,
  }) async {
    await _dio.post('formularios/valores/', data: {
      'esquema':      esquemaId,
      'entidad_tipo': entidadTipo,
      'entidad_id':   entidadId,
      'valores':      valores,
    });
  }
}

// ── Modelo CampoFormulario (solo en services, no en models globales) ──────
class CampoFormularioModel {
  final String id;
  final String nombreCampo;
  final String etiqueta;
  final String tipoDato;
  final bool esObligatorio;
  final int orden;
  final List<String> opciones;

  const CampoFormularioModel({
    required this.id,
    required this.nombreCampo,
    required this.etiqueta,
    required this.tipoDato,
    required this.esObligatorio,
    required this.orden,
    required this.opciones,
  });

  factory CampoFormularioModel.fromJson(Map<String, dynamic> j) {
    // FIX: 'opciones' en el serializer es una List directa (no un Map anidado)
    final raw = j['opciones'];
    List<String> opts = [];
    if (raw is List) {
      opts = raw.map((e) => e.toString()).toList();
    } else if (raw is Map) {
      final inner = raw['opciones'] as List? ?? [];
      opts = inner.map((e) => e.toString()).toList();
    }
    return CampoFormularioModel(
      id:            j['id']?.toString() ?? '',
      nombreCampo:   j['nombre'] ?? j['nombre_campo'] ?? '',
      etiqueta:      j['etiqueta'] ?? '',
      tipoDato:      j['tipo'] ?? j['tipo_dato'] ?? 'texto',
      esObligatorio: j['obligatorio'] ?? j['es_obligatorio'] ?? false,
      orden:         j['orden'] ?? 0,
      opciones:      opts,
    );
  }
}
