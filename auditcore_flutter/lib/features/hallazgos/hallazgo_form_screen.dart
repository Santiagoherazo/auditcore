import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/services/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

class HallazgoFormScreen extends ConsumerStatefulWidget {
  final String expedienteId;
  const HallazgoFormScreen({super.key, required this.expedienteId});
  @override
  ConsumerState<HallazgoFormScreen> createState() => _HallazgoFormState();
}

class _HallazgoFormState extends ConsumerState<HallazgoFormScreen> {
  final _formKey    = GlobalKey<FormState>();
  final _tituloCtrl = TextEditingController();
  final _descCtrl   = TextEditingController();
  String _tipo       = 'HALLAZGO';
  String _criticidad = 'MENOR';
  PlatformFile? _archivo;
  bool _cargando = false;

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _seleccionarArchivo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'mp4', 'mov', 'mp3', 'wav'],
      withData: true, // necesario para web (bytes)
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _archivo = result.files.first);
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (widget.expedienteId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Error: expediente no identificado. Vuelve a la lista.'),
        backgroundColor: AppColors.danger,
      ));
      return;
    }
    // FIX: guardia anti-doble-submit
    if (_cargando) return;
    setState(() => _cargando = true);
    try {
      final svc = ref.read(hallazgosServiceProvider);
      final hallazgo = await svc.crear({
        'expediente':       widget.expedienteId,
        'tipo':             _tipo,
        'nivel_criticidad': _criticidad,
        'titulo':           _tituloCtrl.text.trim(),
        'descripcion':      _descCtrl.text.trim(),
        'estado':           'ABIERTO',
      });
      if (_archivo != null) {
        await svc.subirEvidencia(
          expedienteId:  widget.expedienteId,
          hallazgoId:    hallazgo.id,
          rutaArchivo:   _archivo!.path,
          bytesArchivo:  _archivo!.bytes?.toList(),
          nombreArchivo: _archivo!.name,
          descripcion:   'Evidencia de: ${_tituloCtrl.text}',
        );
      }
      ref.invalidate(hallazgosProvider(widget.expedienteId));
      if (mounted) {
        context.go('/expedientes/${widget.expedienteId}');
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hallazgo registrado correctamente.')));
      }
    } on DioException catch (e) {
      // FIX: error 500 post-creación (notificación crítica/WebSocket) —
      // el hallazgo ya existe, navegar de vuelta y refrescar.
      if (e.response?.statusCode == 500) {
        ref.invalidate(hallazgosProvider(widget.expedienteId));
        if (mounted) {
          context.go('/expedientes/${widget.expedienteId}');
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Hallazgo registrado (con advertencia del servidor).')));
        }
        return;
      }
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: ${e.message}'), backgroundColor: AppColors.danger));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'), backgroundColor: AppColors.danger));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final usuario   = authState.valueOrNull;

    return AppShell(
      rutaActual:    '/expedientes',
      rolUsuario:    usuario?.rol ?? '',
      nombreUsuario: usuario?.nombreCompleto ?? '',
      titulo:        'Nuevo hallazgo',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Form(
            key: _formKey,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    // Tipo y criticidad en fila
                    Row(children: [
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          const Text('Tipo',
                              style: TextStyle(fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textSecondary)),
                          const SizedBox(height: 5),
                          DropdownButtonFormField<String>(
                            value: _tipo,
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.textPrimary),
                            items: const [
                              DropdownMenuItem(value: 'HALLAZGO',
                                  child: Text('Hallazgo')),
                              DropdownMenuItem(value: 'OBSERVACION',
                                  child: Text('Observación')),
                              DropdownMenuItem(value: 'NO_CONFORMIDAD',
                                  child: Text('No Conformidad')),
                              DropdownMenuItem(value: 'OPORTUNIDAD',
                                  child: Text('Oportunidad')),
                            ],
                            onChanged: (v) => setState(() => _tipo = v!),
                          ),
                        ]),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          const Text('Criticidad',
                              style: TextStyle(fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textSecondary)),
                          const SizedBox(height: 5),
                          DropdownButtonFormField<String>(
                            value: _criticidad,
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.textPrimary),
                            items: const [
                              DropdownMenuItem(value: 'CRITICO',
                                  child: Text('Crítico')),
                              DropdownMenuItem(value: 'MAYOR',
                                  child: Text('Mayor')),
                              DropdownMenuItem(value: 'MENOR',
                                  child: Text('Menor')),
                              DropdownMenuItem(value: 'INFORMATIVO',
                                  child: Text('Informativo')),
                            ],
                            onChanged: (v) => setState(() => _criticidad = v!),
                          ),
                        ]),
                      ),
                    ]),

                    // Alerta crítico
                    if (_criticidad == 'CRITICO') ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.dangerBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(children: [
                          Icon(Icons.warning_amber_outlined,
                              size: 14, color: AppColors.danger),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Los hallazgos críticos generan notificación inmediata al Auditor Líder.',
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.danger),
                            ),
                          ),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 14),

                    // Título
                    const Text('Título *',
                        style: TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 5),
                    TextFormField(
                      controller: _tituloCtrl,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                          hintText: 'Describe brevemente el hallazgo'),
                      validator: (v) =>
                          v!.isEmpty ? 'El título es requerido.' : null,
                    ),
                    const SizedBox(height: 14),

                    // Descripción
                    const Text('Descripción detallada *',
                        style: TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 5),
                    TextFormField(
                      controller: _descCtrl,
                      maxLines: 5,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        hintText:
                            'Documenta el hallazgo con evidencia objetiva...',
                      ),
                      validator: (v) =>
                          v!.isEmpty ? 'La descripción es requerida.' : null,
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),

              // Evidencia
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('Evidencia (opcional)',
                        style: TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 10),
                    if (_archivo == null)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.attach_file_outlined, size: 15),
                        label: const Text(
                            'Adjuntar archivo (PDF, imagen, video, audio)'),
                        onPressed: _seleccionarArchivo,
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.successBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(children: [
                          const Icon(Icons.check_circle_outline,
                              size: 14, color: AppColors.success),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${_archivo!.name}  (${(_archivo!.size / 1024).toStringAsFixed(1)} KB)',
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.success),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _archivo = null),
                            child: const Icon(Icons.close,
                                size: 14, color: AppColors.success),
                          ),
                        ]),
                      ),
                  ]),
                ),
              ),
              const SizedBox(height: 16),

              Row(children: [
                OutlinedButton(
                  onPressed: () =>
                      context.go('/expedientes/${widget.expedienteId}'),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save_outlined, size: 15),
                  label: _cargando
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('Registrar hallazgo'),
                  onPressed: _cargando ? null : _guardar,
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
