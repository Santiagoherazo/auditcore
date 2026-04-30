import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/services/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

// Provider de tipos de auditoría para certificaciones (top-level, no inline en build)
final _tiposCertProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final resp = await ApiClient.instance.get(Endpoints.tiposAuditoria);
  final data = resp.data;
  final lista = data is Map ? (data['results'] as List? ?? []) : (data as List? ?? []);
  return lista.cast<Map<String, dynamic>>();
});

/// FIX Bug 7: pantalla de creación de certificaciones.
/// Antes no existía ninguna forma de emitir certificaciones desde la app —
/// solo se podían visualizar. Ahora ADMIN y AUDITOR_LIDER pueden emitir
/// certificaciones nuevas directamente.
class CertificacionFormScreen extends ConsumerStatefulWidget {
  const CertificacionFormScreen({super.key});
  @override
  ConsumerState<CertificacionFormScreen> createState() =>
      _CertificacionFormState();
}

class _CertificacionFormState extends ConsumerState<CertificacionFormScreen> {
  final _formKey       = GlobalKey<FormState>();
  final _observCtrl    = TextEditingController();
  String? _clienteId;
  String? _expedienteId;
  String? _tipoId;
  DateTime? _fechaVencimiento;
  String _tipoEmision  = 'NUEVA';
  bool   _guardando    = false;

  @override
  void dispose() {
    _observCtrl.dispose();
    super.dispose();
  }

  Future<void> _seleccionarFecha() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _fechaVencimiento = picked);
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_guardando) return;
    if (_fechaVencimiento == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Selecciona la fecha de vencimiento.')));
      return;
    }
    setState(() => _guardando = true);
    try {
      await ApiClient.instance.post(Endpoints.certificaciones, data: {
        'cliente':          _clienteId,
        'tipo_auditoria':   _tipoId,
        if (_expedienteId != null) 'expediente': _expedienteId,
        'tipo_emision':     _tipoEmision,
        'fecha_vencimiento': '${_fechaVencimiento!.year}-'
            '${_fechaVencimiento!.month.toString().padLeft(2,'0')}-'
            '${_fechaVencimiento!.day.toString().padLeft(2,'0')}',
        if (_observCtrl.text.trim().isNotEmpty)
          'observaciones': _observCtrl.text.trim(),
      });
      ref.invalidate(certificacionesProvider);
      if (mounted) {
        // FIX: usar context.pop() en vez de context.go() para volver correctamente
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Certificación emitida correctamente.')));
      }
    } on DioException catch (e) {
      if (mounted) {
        final msg = _parsearErrorDio(e);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(msg),
            backgroundColor: AppColors.danger,
            duration: const Duration(seconds: 6)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()), backgroundColor: AppColors.danger));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState      = ref.watch(authProvider);
    final usuario        = authState.valueOrNull;
    final clientesAsync  = ref.watch(clientesProvider);
    final tiposAsync     = ref.watch(_tiposCertProvider);
    final expedientesAsync = ref.watch(expedientesProvider);

    return AppShell(
      rutaActual:    '/certificaciones',
      rolUsuario:    usuario?.rol ?? '',
      nombreUsuario: usuario?.nombreCompleto ?? '',
      titulo:        'Nueva certificación',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Form(
            key: _formKey,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    // Cliente
                    _label('Cliente *'),
                    const SizedBox(height: 6),
                    clientesAsync.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) => const Text('Error cargando clientes',
                          style: TextStyle(color: AppColors.danger, fontSize: 12)),
                      data: (clientes) => DropdownButtonFormField<String>(
                        value: _clienteId,
                        hint: const Text('Selecciona el cliente',
                            style: TextStyle(fontSize: 13)),
                        style: const TextStyle(fontSize: 13,
                            color: AppColors.textPrimary),
                        isExpanded: true,
                        items: clientes.map((c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.razonSocial,
                              overflow: TextOverflow.ellipsis),
                        )).toList(),
                        onChanged: (v) => setState(() => _clienteId = v),
                        validator: (v) =>
                            v == null ? 'Selecciona un cliente.' : null,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Tipo auditoría
                    _label('Tipo de auditoría *'),
                    const SizedBox(height: 6),
                    tiposAsync.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) => const Text('Error cargando tipos',
                          style: TextStyle(color: AppColors.danger, fontSize: 12)),
                      data: (tipos) => DropdownButtonFormField<String>(
                        value: _tipoId,
                        hint: const Text('Selecciona el tipo',
                            style: TextStyle(fontSize: 13)),
                        style: const TextStyle(fontSize: 13,
                            color: AppColors.textPrimary),
                        isExpanded: true,
                        items: tipos.map((t) => DropdownMenuItem(
                          value: t['id'] as String,
                          child: Text('${t['codigo']} — ${t['nombre']}',
                              overflow: TextOverflow.ellipsis),
                        )).toList(),
                        onChanged: (v) => setState(() => _tipoId = v),
                        validator: (v) =>
                            v == null ? 'Selecciona un tipo.' : null,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Expediente (opcional)
                    _label('Expediente relacionado (opcional)'),
                    const SizedBox(height: 6),
                    expedientesAsync.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (exps) => DropdownButtonFormField<String>(
                        value: _expedienteId,
                        hint: const Text('Sin expediente',
                            style: TextStyle(fontSize: 13)),
                        style: const TextStyle(fontSize: 13,
                            color: AppColors.textPrimary),
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem<String>(
                              value: null, child: Text('Sin expediente')),
                          ...exps.map((e) => DropdownMenuItem(
                            value: e.id,
                            child: Text(
                                '${e.numeroExpediente} — ${e.clienteNombre}',
                                overflow: TextOverflow.ellipsis),
                          )),
                        ],
                        onChanged: (v) => setState(() => _expedienteId = v),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Tipo de emisión
                    _label('Tipo de emisión'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _tipoEmision,
                      style: const TextStyle(fontSize: 13,
                          color: AppColors.textPrimary),
                      items: const [
                        DropdownMenuItem(value: 'NUEVA',      child: Text('Nueva')),
                        DropdownMenuItem(value: 'RENOVACION', child: Text('Renovación')),
                        DropdownMenuItem(value: 'AMPLIACION', child: Text('Ampliación')),
                      ],
                      onChanged: (v) => setState(() => _tipoEmision = v!),
                    ),
                    const SizedBox(height: 16),

                    // Fecha vencimiento
                    _label('Fecha de vencimiento *'),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: _seleccionarFecha,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 13),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(children: [
                          const Icon(Icons.calendar_today_outlined,
                              size: 14, color: AppColors.textTertiary),
                          const SizedBox(width: 8),
                          Text(
                            _fechaVencimiento != null
                                ? '${_fechaVencimiento!.day.toString().padLeft(2,'0')}/'
                                  '${_fechaVencimiento!.month.toString().padLeft(2,'0')}/'
                                  '${_fechaVencimiento!.year}'
                                : 'Selecciona la fecha de vencimiento',
                            style: TextStyle(
                              fontSize: 13,
                              color: _fechaVencimiento != null
                                  ? AppColors.textPrimary
                                  : AppColors.textTertiary,
                            ),
                          ),
                          const Spacer(),
                          if (_fechaVencimiento != null)
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _fechaVencimiento = null),
                              child: const Icon(Icons.close,
                                  size: 14, color: AppColors.textTertiary),
                            ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Observaciones
                    _label('Observaciones'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _observCtrl,
                      maxLines: 3,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                          hintText: 'Notas u observaciones opcionales...'),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                OutlinedButton(
                  onPressed: () => context.pop(),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  icon: _guardando
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.verified_outlined, size: 15),
                  label: const Text('Emitir certificación'),
                  onPressed: _guardando ? null : _guardar,
                ),
              ]),
              const SizedBox(height: 24),
            ]),
          ),
        ),
      ),
    );
  }

  String _parsearErrorDio(DioException e) {
    try {
      final data = e.response?.data;
      if (data is Map) {
        final msgs = <String>[];
        data.forEach((k, v) {
          if (v is List) msgs.add('$k: \${v.join(", ")}');
          else if (v is String) msgs.add(v);
        });
        if (msgs.isNotEmpty) return msgs.join('\n');
      }
      if (data is String && data.isNotEmpty) return data;
      return 'Error ${e.response?.statusCode ?? "desconocido"}';
    } catch (_) {
      return e.message ?? 'Error desconocido';
    }
  }

  Widget _label(String texto) => Text(
    texto,
    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
        color: AppColors.textSecondary),
  );
}
