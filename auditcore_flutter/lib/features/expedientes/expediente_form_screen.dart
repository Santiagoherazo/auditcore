import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/services/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

final tiposAuditoriaSimpleProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final resp = await ApiClient.instance.get(Endpoints.tiposAuditoria);
  final data = resp.data;
  final lista = data is Map ? (data['results'] as List? ?? []) : (data as List? ?? []);
  return lista.cast<Map<String, dynamic>>();
});

// Provider para listar auditores disponibles (ADMIN, AUDITOR_LIDER, AUDITOR)
final auditoresProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  // Usar endpoint /auditores/ que tiene permiso IsAuthenticated
  // /usuarios/ requiere IsAdmin y rompe para AUDITOR_LIDER
  final resp = await ApiClient.instance.get('\${Endpoints.usuarios}auditores/');
  final data = resp.data;
  final lista = data is Map ? (data['results'] as List? ?? []) : (data as List? ?? []);
  return lista.cast<Map<String, dynamic>>();
});

class ExpedienteFormScreen extends ConsumerStatefulWidget {
  const ExpedienteFormScreen({super.key});
  @override
  ConsumerState<ExpedienteFormScreen> createState() => _ExpedienteFormState();
}

class _ExpedienteFormState extends ConsumerState<ExpedienteFormScreen> {
  final _formKey          = GlobalKey<FormState>();
  final _notasCtrl        = TextEditingController();
  String?   _clienteId;
  String?   _tipoId;
  String?   _auditorLiderId;
  DateTime? _fechaCierre;
  String    _tipoOrigen   = 'NUEVO';
  bool      _cargando     = false;
  bool      _auditorInicializado = false;

  @override
  void dispose() {
    _notasCtrl.dispose();
    super.dispose();
  }

  Future<void> _seleccionarFecha() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _fechaCierre = picked);
  }

  Future<void> _crear() async {
    if (!_formKey.currentState!.validate()) return;
    // Sin esto, el usuario puede tocar "Crear" varias veces mientras el botón
    // está en estado loading, generando múltiples expedientes duplicados.
    if (_cargando) return;

    final usuario   = ref.read(authProvider).valueOrNull;
    final auditorId = _auditorLiderId ?? usuario?.id;

    setState(() => _cargando = true);
    try {
      await ref.read(expedientesServiceProvider).crear({
        'cliente':        _clienteId,
        'tipo_auditoria': _tipoId,
        'auditor_lider':  auditorId,
        'tipo_origen':    _tipoOrigen,
        if (_fechaCierre != null)
          'fecha_estimada_cierre':
              '${_fechaCierre!.year}-${_fechaCierre!.month.toString().padLeft(2, '0')}-${_fechaCierre!.day.toString().padLeft(2, '0')}',
        if (_notasCtrl.text.trim().isNotEmpty) 'notas': _notasCtrl.text.trim(),
      });
      ref.invalidate(expedientesProvider);
      if (mounted) {
        context.go('/expedientes');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Expediente creado. Fases y checklist generados automáticamente.')));
      }
    } on DioException catch (e) {
      // 500 en señales de bitácora/WebSocket — expediente YA fue creado.
      if (e.response?.statusCode == 500) {
        ref.invalidate(expedientesProvider);
        if (mounted) {
          context.go('/expedientes');
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Expediente creado correctamente.')));
        }
        return;
      }
      if (mounted) {
        final msg = _parsearErrorDio(e);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(msg),
            backgroundColor: AppColors.danger,
            duration: const Duration(seconds: 6)));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString()), backgroundColor: AppColors.danger));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState      = ref.watch(authProvider);
    final usuario        = authState.valueOrNull;
    final clientesAsync  = ref.watch(clientesProvider);
    final tiposAsync     = ref.watch(tiposAuditoriaSimpleProvider);
    final auditoresAsync = ref.watch(auditoresProvider);

    final esEjecutivo = usuario?.rol == 'ASESOR';

    return AppShell(
      rutaActual:    '/expedientes',
      rolUsuario:    usuario?.rol ?? '',
      nombreUsuario: usuario?.nombreCompleto ?? '',
      titulo:        'Nuevo expediente',
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
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    // ── Cliente ──────────────────────────────────────
                    _label('Cliente *'),
                    const SizedBox(height: 6),
                    clientesAsync.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) => const Text('Error cargando clientes',
                          style: TextStyle(color: AppColors.danger, fontSize: 12)),
                      data: (clientes) => DropdownButtonFormField<String>(
                        value: _clienteId,
                        hint: const Text('Selecciona un cliente',
                            style: TextStyle(fontSize: 13)),
                        style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                        isExpanded: true,
                        items: clientes
                            .map((c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(c.razonSocial,
                                    overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (v) => setState(() => _clienteId = v),
                        validator: (v) =>
                            v == null ? 'Selecciona un cliente.' : null,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Tipo de auditoría ─────────────────────────────
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
                        style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                        isExpanded: true,
                        items: tipos
                            .map((t) => DropdownMenuItem(
                                value: t['id'] as String,
                                child: Text(
                                    '${t['codigo']} — ${t['nombre']}',
                                    overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (v) => setState(() => _tipoId = v),
                        validator: (v) =>
                            v == null ? 'Selecciona un tipo.' : null,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Auditor líder ────────────────────────────────
                    _label('Auditor líder *'),
                    const SizedBox(height: 6),
                    auditoresAsync.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) => const Text('Error cargando auditores',
                          style: TextStyle(color: AppColors.danger, fontSize: 12)),
                      data: (auditores) {
                        // race condition si el usuario toca "Crear" antes del callback.
                        if (esEjecutivo && !_auditorInicializado && auditores.isNotEmpty) {
                          _auditorInicializado = true;
                          _auditorLiderId = auditores.first['id'] as String;
                        }
                        return DropdownButtonFormField<String>(
                          value: _auditorLiderId ??
                              (esEjecutivo ? null : usuario?.id),
                          hint: const Text('Selecciona el auditor líder',
                              style: TextStyle(fontSize: 13)),
                          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                          isExpanded: true,
                          items: auditores
                              .map((a) => DropdownMenuItem(
                                  value: a['id'] as String,
                                  child: Text(
                                      '${a['nombre']} ${a['apellido']} · ${_rolLabel(a['rol'] as String)}',
                                      overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: (v) => setState(() => _auditorLiderId = v),
                          validator: (v) {
                            final id = v ?? _auditorLiderId ?? (esEjecutivo ? null : usuario?.id);
                            return id == null ? 'Selecciona un auditor líder.' : null;
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),

                    // ── Tipo de origen ────────────────────────────────
                    _label('Tipo de origen'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _tipoOrigen,
                      style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                      items: const [
                        DropdownMenuItem(value: 'NUEVO',       child: Text('Nuevo')),
                        DropdownMenuItem(value: 'RENOVACION',  child: Text('Renovación')),
                        DropdownMenuItem(value: 'SEGUIMIENTO', child: Text('Seguimiento')),
                      ],
                      onChanged: (v) => setState(() => _tipoOrigen = v!),
                    ),
                    const SizedBox(height: 16),

                    // ── Fecha estimada de cierre ─────────────────────
                    _label('Fecha estimada de cierre'),
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
                            _fechaCierre != null
                                ? '${_fechaCierre!.day.toString().padLeft(2,'0')}/${_fechaCierre!.month.toString().padLeft(2,'0')}/${_fechaCierre!.year}'
                                : 'Opcional — selecciona una fecha',
                            style: TextStyle(
                              fontSize: 13,
                              color: _fechaCierre != null
                                  ? AppColors.textPrimary
                                  : AppColors.textTertiary,
                            ),
                          ),
                          const Spacer(),
                          if (_fechaCierre != null)
                            GestureDetector(
                              onTap: () => setState(() => _fechaCierre = null),
                              child: const Icon(Icons.close,
                                  size: 14, color: AppColors.textTertiary),
                            ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Notas ─────────────────────────────────────────
                    _label('Notas internas'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _notasCtrl,
                      maxLines: 3,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                          hintText: 'Observaciones opcionales sobre el expediente...'),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),

              // Info box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.accentLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.accent.withOpacity(0.2), width: 0.5),
                ),
                child: const Row(children: [
                  Icon(Icons.info_outline, size: 15, color: AppColors.accent),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'El sistema generará automáticamente las fases, checklist y documentos requeridos según el tipo de auditoría.',
                      style: TextStyle(fontSize: 12, color: AppColors.accentDark),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),

              Row(children: [
                OutlinedButton(
                  onPressed: () => context.go('/expedientes'),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  icon: const Icon(Icons.create_new_folder_outlined, size: 15),
                  label: _cargando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('Crear expediente'),
                  onPressed: _cargando ? null : _crear,
                ),
              ]),
              const SizedBox(height: 24),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _label(String texto) => Text(
        texto,
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary),
      );

  String _rolLabel(String rol) => switch (rol) {
        'SUPERVISOR' => 'Supervisor',
        'ASESOR'     => 'Asesor',
        'AUDITOR'    => 'Auditor',
        'AUXILIAR'   => 'Auxiliar',
        'REVISOR'    => 'Revisor',
        _            => rol,
      };

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
}
