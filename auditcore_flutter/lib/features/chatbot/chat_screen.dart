import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/api/api_client.dart';
import '../../core/services/providers.dart';
import '../../core/services/websocket_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String? expedienteId;
  const ChatScreen({super.key, this.expedienteId});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scroll    = ScrollController();

  bool _iniciando  = true;
  bool _esperando  = false;
  String? _convId;
  StreamSubscription? _wsSub;
  Timer? _pollTimer;
  Timer? _timeoutTimer;
  Timer? _estadoTimer;

  // Buffer de streaming — acumula chunks antes de mostrarlos
  final StringBuffer _streamBuffer = StringBuffer();
  bool _streamActivo = false;

  // Índice del mensaje del asistente que está siendo construido
  int? _streamMsgIndex;

  // ── Adjunto de documentos ──────────────────────────────────────────────────
  bool _subiendoDoc = false;   // cargando archivo al servidor
  String? _nombreDocPendiente; // nombre del archivo seleccionado (preview)

  int _segundosEsperando = 0;
  String _mensajeEstado  = '';

  // Mensajes de estado progresivos durante carga del modelo
  static const _mensajesEspera = [
    (10,  'Procesando...'),
    (25,  'Generando respuesta...'),
    (45,  'Cargando modelo en GPU... (primera consulta tarda ~40s)'),
    (90,  'El modelo está casi listo. Próximas respuestas serán más rápidas.'),
    (150, 'Procesando tu consulta. Llama 3.1 en GPU...'),
    (240, 'Respuesta en camino. El sistema sigue procesando.'),
  ];

  // Tiempo máximo de espera: 7 minutos (cubre cold start completo)
  static const _timeoutSeg = 420;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    final notifier = ref.read(chatProvider.notifier);

    // y el expediente no cambió. El usuario puede navegar a Clientes, Expedientes,
    // etc. y volver al chat sin perder el hilo de la conversación.
    // El historial solo se limpia en logout (SessionService → limpiar()).
    await notifier.iniciarOReanudar(expedienteId: widget.expedienteId);
    _convId = notifier.convId;

    if (_convId != null) {
      // Reconectar el WS al conv_id activo. Si ya había un WS abierto al mismo
      // conv_id, connect() lo cierra primero y abre uno nuevo — el historial
      // en memoria (state) no se toca.
      await wsChatbot.connect('ws/chatbot/$_convId/');
      _wsSub = wsChatbot.stream.listen(_manejarEventoWS);
    }

    if (mounted) setState(() => _iniciando = false);
  }

  void _manejarEventoWS(Map<String, dynamic> event) {
    if (!mounted) return;
    final type = event['type'] as String? ?? '';

    switch (type) {
      case 'chatbot_token':
        // STREAMING: agregar fragmento al buffer y actualizar la burbuja
        // El consumer envía el chunk bajo la clave 'chunk'
        final chunk = (event['chunk'] ?? event['contenido'] ?? '') as String;
        if (chunk.isEmpty) return;
        _streamBuffer.write(chunk);

        if (!_streamActivo) {
          // Primer chunk — crear burbuja vacía del asistente
          _streamActivo = true;
          ref.read(chatProvider.notifier).iniciarStreamAsistente();
          _streamMsgIndex = ref.read(chatProvider).length - 1;
          // Cancelar estado progresivo al recibir primer chunk
          _estadoTimer?.cancel();
          if (mounted) setState(() => _mensajeEstado = '');
        }

        // Actualizar el texto de la burbuja de streaming
        ref.read(chatProvider.notifier)
            .actualizarStreamAsistente(_streamBuffer.toString());
        _scrollAbajo();

      case 'chatbot_done':
        // Respuesta completa confirmada — finalizar streaming
        if (_streamActivo) {
          final textoFinal = _streamBuffer.toString().trim();
          if (textoFinal.isNotEmpty) {
            ref.read(chatProvider.notifier).finalizarStreamAsistente(textoFinal);
          }
          _streamBuffer.clear();
          _streamActivo = false;
          _streamMsgIndex = null;
        } else {
          // Sin streaming previo (fallback) — mostrar respuesta directa
          final contenido = event['contenido'] as String? ?? '';
          if (contenido.isNotEmpty) {
            ref.read(chatProvider.notifier).agregarRespuesta(contenido);
          }
        }
        _terminarEspera();

      case 'chatbot_typing':
        // El worker confirmó que Ollama está procesando — activar indicador de espera.
        // Solo actuar si todavía no hay streaming activo (para no interrumpir tokens).
        if (!_streamActivo && mounted) {
          setState(() => _esperando = true);
          // Si los timers no están corriendo (widget recreado por navegación o
          // reconexión WS), arrancarlos para mostrar mensajes de estado progresivo.
          if (_estadoTimer == null || !(_estadoTimer!.isActive)) {
            _iniciarTimerEstado();
          }
        }

      case 'chatbot_error':
        _streamBuffer.clear();
        _streamActivo = false;
        final msg = event['mensaje'] as String? ?? 'Error del asistente.';
        ref.read(chatProvider.notifier).agregarRespuesta(msg);
        _terminarEspera();
    }
  }

  void _terminarEspera() {
    _limpiarTimers();
    _pollTimer?.cancel();
    _pollTimer = null;
    if (mounted) setState(() { _esperando = false; _subiendoDoc = false; _nombreDocPendiente = null; });
    _scrollAbajo();
  }

  void _limpiarTimers() {
    _timeoutTimer?.cancel(); _timeoutTimer = null;
    _estadoTimer?.cancel();  _estadoTimer  = null;
    _segundosEsperando = 0;
    _mensajeEstado = '';
  }

  /// Arranca el timer de mensajes de estado progresivos durante la espera.
  /// Idempotente: si ya corre, no hace nada (el caller debe verificar antes).
  void _iniciarTimerEstado() {
    _segundosEsperando = 0;
    _estadoTimer?.cancel();
    _estadoTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_esperando) return;
      _segundosEsperando++;
      String nuevo = '';
      for (final (seg, msg) in _mensajesEspera) {
        if (_segundosEsperando >= seg) nuevo = msg;
      }
      if (nuevo != _mensajeEstado) setState(() => _mensajeEstado = nuevo);
    });
  }

  Future<void> _enviar() async {
    final texto = _inputCtrl.text.trim();
    if (texto.isEmpty || _esperando || _convId == null) return;
    _inputCtrl.clear();
    setState(() { _esperando = true; _mensajeEstado = ''; });

    await ref.read(chatProvider.notifier).enviar(texto);
    _scrollAbajo();

    // POLLING FALLBACK — por si el WS no llega (Redis caído, etc.)
    final mensajesAntesDeEnviar = ref.read(chatProvider).length;
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      // no está esperando respuesta — evita condición de carrera con chatbot_done.
      if (!_esperando || _streamActivo || !mounted) return;
      try {
        final resp = await ApiClient.instance
            .get('chatbot/conversaciones/$_convId/mensajes/');
        final lista = resp.data as List? ?? [];
        if (lista.length > mensajesAntesDeEnviar) {
          final ultimo = lista.last as Map<String, dynamic>;
          if ((ultimo['rol'] as String? ?? '').toUpperCase() == 'ASISTENTE') {
            final contenido = ultimo['contenido'] as String? ?? '';
            // porque el await anterior puede haber permitido que chatbot_done
            // llegara por WS mientras el polling estaba en vuelo.
            if (contenido.isNotEmpty && !_streamActivo && _esperando) {
              ref.read(chatProvider.notifier).agregarRespuesta(contenido);
              _terminarEspera();
            }
          }
        }
      } catch (_) {}
    });

    // Estado progresivo durante la espera
    _iniciarTimerEstado();

    // Timeout total
    _timeoutTimer = Timer(const Duration(seconds: _timeoutSeg), () {
      if (!mounted || !_esperando) return;
      _streamBuffer.clear();
      _streamActivo = false;
      ref.read(chatProvider.notifier).agregarRespuesta(
        'El modelo no respondió en el tiempo límite.\n\n'
        'La GPU puede estar compartiendo VRAM con otros procesos (Chrome, escritorio).\n'
        'Cierra aplicaciones pesadas y reintenta — el modelo ya está cargado.',
      );
      _terminarEspera();
      if (mounted) setState(() => _esperando = false);
    });
  }

  /// Permite al usuario seleccionar un archivo y enviarlo al endpoint
  /// de análisis inteligente de documentos.
  Future<void> _adjuntarDocumento() async {
    if (_esperando || _subiendoDoc || _convId == null) return;

    // 1. Seleccionar archivo
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'doc', 'xlsx', 'xls', 'txt', 'csv',
                          'jpg', 'jpeg', 'png'],
      withData: false,
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.first;
    final path   = picked.path;
    if (path == null) return;

    final nombre = picked.name;

    // 2. Capturar pregunta opcional del campo de texto
    final pregunta = _inputCtrl.text.trim();
    _inputCtrl.clear();

    setState(() {
      _subiendoDoc     = true;
      _esperando       = true;
      _mensajeEstado   = 'Subiendo documento...';
      _nombreDocPendiente = nombre;
    });

    _iniciarTimerEstado();

    try {
      final formData = FormData.fromMap({
        'conversacion_id': _convId,
        'pregunta':        pregunta,
        'archivo': await MultipartFile.fromFile(path, filename: nombre),
      });

      await ApiClient.instance.post(
        'chatbot/analizar-documento/',
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout:    const Duration(seconds: 60),
        ),
      );

      // Éxito — el análisis llega por WebSocket (chatbot_done)
      if (mounted) {
        setState(() {
          _mensajeEstado      = 'Analizando documento...';
          _nombreDocPendiente = null;
        });
      }
    } on DioException catch (e) {
      final msg = (e.response?.data as Map<String, dynamic>?)?['error']
          as String? ?? 'Error al subir el documento.';
      if (mounted) {
        ref.read(chatProvider.notifier).agregarRespuesta('⚠️ $msg');
        _terminarEspera();
        setState(() { _subiendoDoc = false; _nombreDocPendiente = null; });
      }
    } catch (e) {
      if (mounted) {
        ref.read(chatProvider.notifier).agregarRespuesta(
            '⚠️ Error inesperado al subir el archivo.');
        _terminarEspera();
        setState(() { _subiendoDoc = false; _nombreDocPendiente = null; });
      }
    } finally {
      if (mounted) setState(() => _subiendoDoc = false);
    }
  }

  void _scrollAbajo() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _limpiarTimers();
    _pollTimer?.cancel();
    _wsSub?.cancel();
    _inputCtrl.dispose();
    _scroll.dispose();
    wsChatbot.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final usuario   = authState.valueOrNull;
    final mensajes  = ref.watch(chatProvider);

    return AppShell(
      rutaActual:    '/chat',
      rolUsuario:    usuario?.rol ?? '',
      nombreUsuario: usuario?.nombreCompleto ?? '',
      titulo:        'AuditBot',
      subtitulo:     'IA local · Conversación activa en sesión',
      showBottomNav: true,
      actions: [
        _OllamaStatusChip(),
        const SizedBox(width: 4),
        // Botón para limpiar la sesión actual
        IconButton(
          icon: const Icon(Icons.refresh_outlined, size: 18),
          tooltip: 'Nueva conversación',
          onPressed: _esperando ? null : () async {
            _limpiarTimers();
            _pollTimer?.cancel();
            _streamBuffer.clear();
            _streamActivo = false;
            setState(() { _iniciando = true; _esperando = false; });
            await wsChatbot.disconnect();
            ref.read(chatProvider.notifier).limpiar();
            await _iniciar();
          },
          style: IconButton.styleFrom(foregroundColor: AppColors.textSecondary),
        ),
        const SizedBox(width: 4),
      ],
      child: _iniciando
          ? const Center(child: SizedBox(width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2)))
          : Column(children: [
              // Banner informativo de sesión temporal
              Container(
                color: AppColors.infoBg,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(children: [
                  const Icon(Icons.info_outline, size: 13, color: AppColors.info),
                  const SizedBox(width: 6),
                  const Expanded(child: Text(
                    'Conversación temporal — los mensajes no se conservan al salir.',
                    style: TextStyle(fontSize: 11, color: AppColors.info),
                  )),
                ]),
              ),
              Expanded(
                child: mensajes.isEmpty
                    ? _EmptyChat(onSugerencia: (s) {
                        _inputCtrl.text = s;
                        _enviar();
                      })
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(16),
                        itemCount: mensajes.length + (_esperando && !_streamActivo ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (!_streamActivo && _esperando && i == mensajes.length) {
                            return _TypingIndicator(mensajeEstado: _mensajeEstado);
                          }
                          final m = mensajes[i];
                          return _Burbuja(
                            contenido:  m.contenido,
                            esUsuario:  m.rol == 'USUARIO',
                            enStreaming: _streamActivo && i == mensajes.length - 1 && m.rol == 'ASISTENTE',
                          );
                        },
                      ),
              ),
              // Input
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.white,
                  border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
                ),
                padding: const EdgeInsets.all(12),
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Preview del documento seleccionado
                      if (_nombreDocPendiente != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppColors.accent.withOpacity(0.3)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.insert_drive_file_outlined,
                                size: 14, color: AppColors.accent),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _nombreDocPendiente!,
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.accent),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_subiendoDoc)
                              const SizedBox(
                                width: 12, height: 12,
                                child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: AppColors.accent),
                              )
                            else
                              GestureDetector(
                                onTap: () => setState(() =>
                                    _nombreDocPendiente = null),
                                child: const Icon(Icons.close,
                                    size: 14, color: AppColors.textTertiary),
                              ),
                          ]),
                        ),
                      Row(children: [
                        // Botón adjuntar documento
                        Tooltip(
                          message: 'Adjuntar documento para análisis',
                          child: GestureDetector(
                            onTap: (_esperando || _subiendoDoc)
                                ? null
                                : _adjuntarDocumento,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 36, height: 36,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: (_esperando || _subiendoDoc)
                                    ? AppColors.bg
                                    : AppColors.bg,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: (_esperando || _subiendoDoc)
                                      ? AppColors.border
                                      : AppColors.textTertiary.withOpacity(0.4),
                                ),
                              ),
                              child: Icon(
                                Icons.attach_file_rounded,
                                size: 16,
                                color: (_esperando || _subiendoDoc)
                                    ? AppColors.textTertiary
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _inputCtrl,
                            maxLines: null,
                            style: const TextStyle(fontSize: 13),
                            decoration: InputDecoration(
                              hintText: _nombreDocPendiente != null
                                  ? 'Pregunta sobre el documento (opcional)...'
                                  : 'Escribe tu consulta...',
                              filled: true,
                              fillColor: AppColors.bg,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: const BorderSide(
                                    color: AppColors.accent, width: 1.5),
                              ),
                            ),
                            onSubmitted: (_) {
                              if (_nombreDocPendiente != null) {
                                _adjuntarDocumento();
                              } else {
                                _enviar();
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _esperando
                              ? null
                              : (_nombreDocPendiente != null
                                  ? _adjuntarDocumento
                                  : _enviar),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: _esperando
                                  ? AppColors.textTertiary
                                  : AppColors.accent,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Icon(
                              _nombreDocPendiente != null
                                  ? Icons.upload_rounded
                                  : Icons.send_rounded,
                              color: Colors.white, size: 16,
                            ),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ]),
    );
  }
}

// ── Chip de estado Ollama ─────────────────────────────────────────────────────
class _OllamaStatusChip extends ConsumerStatefulWidget {
  @override
  ConsumerState<_OllamaStatusChip> createState() => _OllamaStatusChipState();
}

class _OllamaStatusChipState extends ConsumerState<_OllamaStatusChip> {
  bool   _disponible = false;
  String _modelo     = 'llama3.1:8b';
  bool   _checkeando = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _check();
    // Cada llamada valida que haya token antes de hacer el request
    // para no generar un 401 si el usuario cerró sesión en background.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
  }

  Future<void> _check() async {
    // Esto ocurre cuando el widget se monta durante la animación de entrada
    // antes de que ApiClient haya cargado el token desde SecureStorage,
    // o cuando el timer dispara justo después de un logout.
    final token = await ApiClient.getAccessToken();
    if (token == null || token.isEmpty) {
      if (mounted) setState(() { _disponible = false; _checkeando = false; });
      return;
    }

    try {
      // .timeout() cancela el Future pero deja la conexión HTTP viva en el backend
      // durante hasta 115s (receiveTimeout global). Con Options el timeout se aplica
      // a nivel de transporte y cierra la conexión limpiamente.
      final resp = await ApiClient.instance.get(
        'chatbot/status/',
        options: Options(receiveTimeout: const Duration(seconds: 5)),
      );
      final data = resp.data as Map<String, dynamic>;
      if (mounted) setState(() {
        _disponible = data['disponible'] == true;
        _modelo     = data['modelo'] as String? ?? 'llama3.1:8b';
        _checkeando = false;
      });
    } catch (_) {
      if (mounted) setState(() { _disponible = false; _checkeando = false; });
    }
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (_checkeando) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        width: 12, height: 12,
        child: const CircularProgressIndicator(
            strokeWidth: 1.5, color: AppColors.textTertiary),
      );
    }
    return GestureDetector(
      onTap: _check,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: _disponible ? AppColors.successBg : AppColors.warningBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 6,
              color: _disponible ? AppColors.success : AppColors.warning),
          const SizedBox(width: 4),
          Text(
            _disponible ? _modelo : 'Cargando...',
            style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w500,
              color: _disponible ? AppColors.success : AppColors.warning,
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────
class _EmptyChat extends StatelessWidget {
  final void Function(String) onSugerencia;
  const _EmptyChat({required this.onSugerencia});

  @override
  Widget build(BuildContext context) {
    const sugerencias = [
      '¿Cuántos hallazgos críticos hay abiertos?',
      '¿Qué certificaciones vencen pronto?',
      '¿En qué fase están las auditorías activas?',
      'Resume el estado general de la operación.',
    ];
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: AppColors.accentLight,
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Icon(Icons.smart_toy_outlined, size: 28, color: AppColors.accent),
          ),
          const SizedBox(height: 16),
          const Text('AuditBot', style: TextStyle(fontSize: 18,
              fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          const Text(
            'IA local con Llama 3.1.\nPregúntame sobre auditorías, expedientes y certificaciones.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8, runSpacing: 8,
            alignment: WrapAlignment.center,
            children: sugerencias.map((s) => GestureDetector(
              onTap: () => onSugerencia(s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: Text(s, style: const TextStyle(fontSize: 12,
                    color: AppColors.textSecondary)),
              ),
            )).toList(),
          ),
        ]),
      ),
    );
  }
}

// ── Burbuja ───────────────────────────────────────────────────────────────────
class _Burbuja extends StatelessWidget {
  final String contenido;
  final bool   esUsuario;
  final bool   enStreaming;
  const _Burbuja({
    required this.contenido,
    required this.esUsuario,
    this.enStreaming = false,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: esUsuario ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: esUsuario ? AppColors.accent : AppColors.white,
          borderRadius: BorderRadius.only(
            topLeft:     const Radius.circular(16),
            topRight:    const Radius.circular(16),
            bottomLeft:  Radius.circular(esUsuario ? 16 : 4),
            bottomRight: Radius.circular(esUsuario ? 4 : 16),
          ),
          border: esUsuario ? null : Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              contenido.isEmpty ? ' ' : contenido,
              style: TextStyle(
                fontSize: 13, height: 1.5,
                color: esUsuario ? Colors.white : AppColors.textPrimary,
              ),
            ),
            // Cursor de streaming
            if (enStreaming && !esUsuario)
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 8, height: 14,
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Indicador de escritura ────────────────────────────────────────────────────
class _TypingIndicator extends StatefulWidget {
  final String mensajeEstado;
  const _TypingIndicator({this.mensajeEstado = ''});
  @override State<_TypingIndicator> createState() => _TypingState();
}

class _TypingState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        duration: const Duration(milliseconds: 700), vsync: this)
      ..repeat(reverse: true);
    _anim = Tween(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16), topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4), bottomRight: Radius.circular(16),
          ),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FadeTransition(
              opacity: _anim,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _Dot(), const SizedBox(width: 4),
                _Dot(), const SizedBox(width: 4),
                _Dot(),
              ]),
            ),
            if (widget.mensajeEstado.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(widget.mensajeEstado,
                  style: const TextStyle(
                    fontSize: 11, color: AppColors.textTertiary,
                    fontStyle: FontStyle.italic,
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 6, height: 6,
    decoration: const BoxDecoration(
        shape: BoxShape.circle, color: AppColors.textTertiary),
  );
}
