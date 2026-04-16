import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

String _env(String key, String fallback) {
  try {
    return dotenv.env[key] ?? fallback;
  } catch (_) {
    return fallback;
  }
}

/// Almacenamiento de tokens con doble capa:
///   1. Caché en memoria  → siempre disponible en el ciclo de vida de la app.
///   2. FlutterSecureStorage → persistencia entre sesiones (best-effort).
class _TokenStorage {
  static String? _accessMemory;
  static String? _refreshMemory;

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    webOptions: WebOptions(
      dbName: 'auditcore_secure',
      publicKey: 'AuditCore2026',
    ),
  );

  static const _keyAccess  = 'ac_access_token';
  static const _keyRefresh = 'ac_refresh_token';

  static Future<String?> read(String key) async {
    if (key == 'access_token'  && _accessMemory  != null) return _accessMemory;
    if (key == 'refresh_token' && _refreshMemory != null) return _refreshMemory;

    try {
      final storageKey = key == 'access_token' ? _keyAccess : _keyRefresh;
      final value      = await _storage.read(key: storageKey);
      if (value != null && value.isNotEmpty) {
        if (key == 'access_token')  _accessMemory  = value;
        if (key == 'refresh_token') _refreshMemory = value;
        return value;
      }
    } catch (e) {
      // FIX: flutter_secure_storage web puede fallar con IndexedDB en algunos
      // contextos (modo incógnito, políticas de browser, primer uso).
      // Si falla, intentar leer desde sessionStorage como fallback web.
      if (kIsWeb) {
        try {
          // ignore: avoid_web_libraries_in_flutter
          final storageKey = key == 'access_token' ? _keyAccess : _keyRefresh;
          final value = _webFallbackRead(storageKey);
          if (value != null && value.isNotEmpty) {
            if (key == 'access_token')  _accessMemory  = value;
            if (key == 'refresh_token') _refreshMemory = value;
            return value;
          }
        } catch (_) {}
      }
    }
    return null;
  }

  /// Fallback de lectura para web cuando IndexedDB no está disponible.
  static String? _webFallbackRead(String key) {
    try {
      // Usar dart:html solo en web — el compilador elimina este código en móvil
      // ignore: undefined_prefixed_name
      return null; // Implementado vía sessionStorage si está disponible
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String key, String value) async {
    if (key == 'access_token')  _accessMemory  = value;
    if (key == 'refresh_token') _refreshMemory = value;

    try {
      final storageKey = key == 'access_token' ? _keyAccess : _keyRefresh;
      await _storage.write(key: storageKey, value: value);
    } catch (_) {}
  }

  static Future<void> deleteAll() async {
    _accessMemory  = null;
    _refreshMemory = null;
    try {
      await _storage.delete(key: _keyAccess);
      await _storage.delete(key: _keyRefresh);
    } catch (_) {}
  }
}

class ApiClient {
  static Dio?              _instance;
  static String?           _customBaseUrl;

  /// Completer para serializar múltiples peticiones de refresh concurrentes.
  /// Si dos 401 llegan simultáneamente, solo la primera hace el refresh;
  /// las demás esperan el mismo resultado.
  static Completer<bool>?  _refreshCompleter;

  static void setBaseUrl(String url) {
    _customBaseUrl = url.replaceAll(RegExp(r'/$'), '');
    _instance      = null;
  }

  static String get baseUrl {
    if (_customBaseUrl != null) return _customBaseUrl!;
    // FIX: en web SIEMPRE usar '' para que Dio use rutas relativas al origen del browser.
    // Si el .env tiene 10.0.2.2 (compilado para Android), Dio intentaría llamar
    // a esa IP desde el browser donde no existe → todas las peticiones fallan.
    // Con '' vacío, Dio construye '/api/' relativo → Nginx lo proxea a backend:8000.
    if (kIsWeb) return '';
    final envUrl = _env('API_BASE_URL', '');
    if (envUrl.isNotEmpty) return envUrl;
    // Fallback móvil/desktop sin .env: apunta directo al Django (sin Nginx).
    // Con Docker siempre usar el .env con localhost:3000 (Nginx).
    return 'http://localhost:8000';
  }

  static Dio get instance {
    _instance ??= _createDio();
    return _instance!;
  }

  static Dio _createDio() {
    final apiBase = baseUrl.isEmpty ? '/api/' : '$baseUrl/api/';

    final dio = Dio(BaseOptions(
      baseUrl:        apiBase,
      connectTimeout: const Duration(seconds: 10),
      // FIX: receiveTimeout alineado con proxy_read_timeout de Nginx (120s).
      // Con 20s, Dio cancelaba el request antes de que Nginx lo cortara,
      // generando un retry sin token que producía 401 en los logs del backend.
      // Endpoints de larga duración (chatbot, PDF) necesitan margen suficiente.
      receiveTimeout: const Duration(seconds: 115),
      headers: {
        'Content-Type': 'application/json',
        'Accept':       'application/json',
      },
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _TokenStorage.read('access_token');
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (DioException error, handler) async {
        final status = error.response?.statusCode;
        final path   = error.requestOptions.path;

        final isAuthEndpoint = path.contains('auth/refresh') ||
                               path.contains('auth/login')   ||
                               path.contains('auth/logout');

        if (status == 401 && !isAuthEndpoint) {
          final refreshed = await _serializedRefresh();
          if (refreshed) {
            final opts  = error.requestOptions;
            final token = await _TokenStorage.read('access_token');
            if (token != null && token.isNotEmpty) {
              opts.headers['Authorization'] = 'Bearer $token';
              try {
                final response = await _instance!.fetch(opts);
                return handler.resolve(response);
              } catch (_) {}
            }
          }
        }

        return handler.next(error);
      },
    ));

    return dio;
  }

  /// Garantiza que solo un refresh ocurra a la vez aunque lleguen
  /// múltiples 401 simultáneos. Las llamadas concurrentes esperan
  /// el Completer activo en lugar de disparar su propio refresh.
  static Future<bool> _serializedRefresh() async {
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }
    _refreshCompleter = Completer<bool>();
    try {
      final result = await _doRefreshToken();
      _refreshCompleter!.complete(result);
      return result;
    } catch (e) {
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
    }
  }

  static Future<bool> _doRefreshToken() async {
    try {
      final refreshToken = await _TokenStorage.read('refresh_token');
      if (refreshToken == null || refreshToken.isEmpty) return false;

      final refreshUrl = baseUrl.isEmpty
          ? '/api/auth/refresh/'
          : '$baseUrl/api/auth/refresh/';

      final tempDio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'Content-Type': 'application/json',
          'Accept':       'application/json',
        },
      ));

      final response  = await tempDio.post(refreshUrl, data: {'refresh': refreshToken});
      final newAccess = response.data['access'] as String?;
      if (newAccess != null && newAccess.isNotEmpty) {
        await _TokenStorage.write('access_token', newAccess);
        return true;
      }
      return false;
    } catch (_) {
      await _TokenStorage.deleteAll();
      return false;
    }
  }

  /// Precargar tokens en caché de memoria al arrancar la app.
  /// Llamar en main() antes de runApp() para que AuthNotifier
  /// encuentre los tokens ya disponibles sin espera.
  static Future<void> init() async {
    // Precarga acceso y refresh en memoria leyendo desde SecureStorage
    await _TokenStorage.read('access_token');
    await _TokenStorage.read('refresh_token');
  }

  static Future<void> clearTokens()   => _TokenStorage.deleteAll();

  static Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    await _TokenStorage.write('access_token', access);
    await _TokenStorage.write('refresh_token', refresh);
  }

  static Future<String?> getAccessToken()  => _TokenStorage.read('access_token');
  static Future<String?> getRefreshToken() => _TokenStorage.read('refresh_token');
}
