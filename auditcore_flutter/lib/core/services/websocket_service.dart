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


    final wasIntentional = _intentionalClose;
    _intentionalClose = true;
    await _channel?.sink.close();
    if (!wasIntentional) _intentionalClose = false;

    final token = await ApiClient.getAccessToken();
    if (token == null || _intentionalClose) return;

    String wsBase;

    if (kIsWeb) {


      final origin = Uri.base.origin;
      wsBase = origin
          .replaceFirst('http://', 'ws://')
          .replaceFirst('https://', 'wss://');
    } else {

      try {
        wsBase = dotenv.env['WS_BASE_URL'] ?? '';
      } catch (_) {
        wsBase = '';
      }
      if (wsBase.isEmpty) {
        wsBase = 'ws://localhost:8000';
      }
    }


    final base = wsBase.replaceAll(RegExp(r'/$'), '');
    final url = '$base/$path?token=$token';


    if (_controller == null || _controller!.isClosed) {
      _controller = StreamController<Map<String, dynamic>>.broadcast();
    }

    try {
      _channel           = WebSocketChannel.connect(Uri.parse(url));
      _reconnectAttempts = 0;

      _channel!.stream.listen(
        (data) {

          if (_controller == null || _controller!.isClosed) return;
          try {
            final decoded = jsonDecode(data as String) as Map<String, dynamic>;
            _controller!.add(decoded);
          } catch (_) {}
        },
        onDone: () {


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


    final delay = min(5 * pow(2, _reconnectAttempts - 1), 60).toInt();


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
