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


      if (kIsWeb) {
        try {

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


  static String? _webFallbackRead(String key) {
    try {


      return null;
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


  static Completer<bool>?  _refreshCompleter;

  static void setBaseUrl(String url) {
    _customBaseUrl = url.replaceAll(RegExp(r'/$'), '');
    _instance      = null;
  }

  static String get baseUrl {
    if (_customBaseUrl != null) return _customBaseUrl!;

    if (kIsWeb) {


      return '';
    }

    final envUrl = _env('API_BASE_URL', '');
    if (envUrl.isNotEmpty) return envUrl;

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


  static Future<void> init() async {

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
