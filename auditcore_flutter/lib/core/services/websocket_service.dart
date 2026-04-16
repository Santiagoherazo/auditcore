import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../api/api_client.dart';

class WebSocketService {
  WebSocketChannel?                    _channel;
  StreamController<Map<String, dynamic>>? _controller;
  String?  _currentPath;
  Timer?   _pingTimer;
  Timer?   _reconnectTimer;
  int      _reconnectAttempts = 0;
  bool     _intentionalClose  = false;

  Stream<Map<String, dynamic>> get stream =>
      _controller?.stream ?? const Stream.empty();

  Future<void> connect(String path) async {
    _intentionalClose = false;
    _currentPath      = path;
    await _doConnect(path);
  }

  Future<void> _doConnect(String path) async {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    // FIX: marcar cierre intencional del canal anterior ANTES de cerrarlo,
    // para evitar que su onDone dispare un _scheduleReconnect() concurrente
    // con el _doConnect que ya está en curso → loop de reconexión doble.
    // Se restaura a false inmediatamente después para que el nuevo canal
    // sí pueda reconectar si falla.
    final wasIntentional = _intentionalClose;
    _intentionalClose = true;
    await _channel?.sink.close();
    if (!wasIntentional) _intentionalClose = false;

    final token = await ApiClient.getAccessToken();
    if (token == null || _intentionalClose) return;

    String wsBase;

    if (kIsWeb) {
      // FIX: en web SIEMPRE usar el origen del browser (Uri.base.origin).
      // El .env puede tener una IP de Android (10.0.2.2) si se compiló para móvil,
      // lo que hace que el WS intente conectar a una IP inaccesible desde el browser.
      // En web el origen siempre es el mismo que sirve Nginx (:3000),
      // que hace proxy de /ws/ al backend internamente.
      final origin = Uri.base.origin;
      wsBase = origin
          .replaceFirst('http://', 'ws://')
          .replaceFirst('https://', 'wss://');
    } else {
      // Móvil/desktop: leer del .env
      try {
        wsBase = dotenv.env['WS_BASE_URL'] ?? '';
      } catch (_) {
        wsBase = '';
      }
      if (wsBase.isEmpty) {
        wsBase = 'ws://localhost:8000';
      }
    }

    // FIX: eliminar slash final de wsBase para evitar doble barra en la URL
    // si alguien pone WS_BASE_URL=ws://localhost:3000/ en el .env.
    final base = wsBase.replaceAll(RegExp(r'/$'), '');
    final url = '$base/$path?token=$token';

    // Recrear el controller solo si fue cerrado o no existe
    if (_controller == null || _controller!.isClosed) {
      _controller = StreamController<Map<String, dynamic>>.broadcast();
    }

    try {
      _channel           = WebSocketChannel.connect(Uri.parse(url));
      _reconnectAttempts = 0;

      _channel!.stream.listen(
        (data) {
          // Verificar que el controller sigue abierto antes de emitir
          if (_controller == null || _controller!.isClosed) return;
          try {
            final decoded = jsonDecode(data as String) as Map<String, dynamic>;
            _controller!.add(decoded);
          } catch (_) {}
        },
        onDone: () {
          // FIX: en Flutter Web, _channel?.closeCode es null en onDone porque
          // web_socket_channel no lo puebla sincrónicamente antes de llamar al
          // callback. Se lee con un microtask delay para dar tiempo al canal a
          // registrar el código de cierre antes de decidir si reconectar.
          // 4001 = no autenticado, 4003 = sin permiso — nunca reconectar.
          Future.microtask(() {
            final closeCode = _channel?.closeCode;
            final isPermanent = closeCode == 4001 || closeCode == 4003;
            if (!_intentionalClose && !isPermanent) _scheduleReconnect(path);
          });
        },
        onError: (_) {
          if (!_intentionalClose) _scheduleReconnect(path);
        },
        cancelOnError: false,
      );

      _startPing();
    } catch (_) {
      if (!_intentionalClose) _scheduleReconnect(path);
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      try {
        _channel?.sink.add(jsonEncode({'type': 'ping'}));
      } catch (_) {}
    });
  }

  void _scheduleReconnect(String path) {
    if (_intentionalClose) return;
    _reconnectTimer?.cancel();

    _reconnectAttempts++;

    // FIX: backoff mínimo de 5s (era 3s) con máximo de 60s.
    // Con 3s el primer reintento llegaba antes de que el servidor terminara
    // de procesar el cierre anterior → loop WSCONNECT/WSDISCONNECT visible
    // en logs cada 4s que saturaba Daphne. Con 5s se da tiempo suficiente.
    // Fórmula: 5, 10, 20, 40, 60, 60, 60...
    final delay = min(5 * pow(2, _reconnectAttempts - 1), 60).toInt();

    // FIX: límite de reintentos — después de 10 intentos fallidos dejar de
    // reconectar silenciosamente. El usuario verá el indicador de desconexión
    // y puede refrescar la página manualmente. Evita reconexiones infinitas
    // cuando el backend está genuinamente caído.
    if (_reconnectAttempts > 10) {
      return;
    }

    _reconnectTimer = Timer(Duration(seconds: delay), () {
      if (!_intentionalClose) _doConnect(path);
    });
  }

  Future<void> disconnect() async {
    _intentionalClose  = true;
    _reconnectAttempts = 0;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _pingTimer      = null;
    _reconnectTimer = null;
    await _channel?.sink.close();
    await _controller?.close();
    _channel    = null;
    _controller = null;
  }
}

final wsExpediente     = WebSocketService();
final wsDashboard      = WebSocketService();
final wsChatbot        = WebSocketService();
final wsNotificaciones = WebSocketService();
