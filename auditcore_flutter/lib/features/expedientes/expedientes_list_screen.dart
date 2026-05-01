import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/models.dart';
import '../../core/services/providers.dart';
import '../../core/models/models.dart' show ChecklistEjecucionModel;
import '../../core/services/websocket_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';


final evidenciasExpedienteProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, expedienteId) async {
    final resp = await ApiClient.instance.get(
      Endpoints.evidencias,
      queryParameters: {'expediente': expedienteId},
    );
    final data  = resp.data;
    final lista = data is Map ? (data['results'] as List? ?? []) : (data as List? ?? []);
    return lista.cast<Map<String, dynamic>>();
  },
);


class ExpedientesListScreen extends ConsumerStatefulWidget {
  const ExpedientesListScreen({super.key});
  @override
  ConsumerState<ExpedientesListScreen> createState() => _ExpedientesListState();
}

class _ExpedientesListState extends ConsumerState<ExpedientesListScreen> {
  String? _estadoFiltro;
  final _busquedaCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final usuario   = authState.valueOrNull;
    final expAsync  = ref.watch(expedientesProvider);

    return AppShell(
      rutaActual:    '/expedientes',
      rolUsuario:    usuario?.rol ?? '',
      nombreUsuario: usuario?.nombreCompleto ?? '',
      titulo:        'Expedientes',
      showBottomNav: true,
      actions: [
        if (!['AUDITOR', 'AUDITOR'].contains(usuario?.rol))
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 15),
              label: const Text('Nuevo'),
              onPressed: () => context.go('/expedientes/nuevo'),
            ),
          ),
      ],
      child: Column(children: [

        Container(
          color: AppColors.white,
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _busquedaCtrl,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'Buscar expediente o cliente...',
                  prefixIcon: Icon(Icons.search, size: 16, color: AppColors.textTertiary),
                ),
                onChanged: (v) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 400), () => setState(() {}));
                },
              ),
            ),
            const SizedBox(width: 10),
            DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _estadoFiltro,
                hint: const Text('Estado', style: TextStyle(fontSize: 12)),
                style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                borderRadius: BorderRadius.circular(8),
                items: const [
                  DropdownMenuItem(value: null,          child: Text('Todos')),
                  DropdownMenuItem(value: 'BORRADOR',    child: Text('Borrador')),
                  DropdownMenuItem(value: 'ACTIVO',      child: Text('Activo')),
                  DropdownMenuItem(value: 'EN_EJECUCION',child: Text('En Ejecución')),
                  DropdownMenuItem(value: 'COMPLETADO',  child: Text('Completado')),
                ],
                onChanged: (v) => setState(() => _estadoFiltro = v),
              ),
            ),
          ]),
        ),
        const Divider(),
        Expanded(
          child: expAsync.when(
            loading: () => const Center(
              child: SizedBox(width: 24, height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (e, _) => EmptyState(
              titulo: 'Error cargando expedientes',
              subtitulo: e.toString(),
              icono: Icons.error_outline,
              labelBoton: 'Reintentar',
              onBoton: () => ref.invalidate(expedientesProvider),
            ),
            data: (lista) {
              final q = _busquedaCtrl.text.toLowerCase();
              final filtrados = lista.where((e) {
                final matchEstado  = _estadoFiltro == null || e.estado == _estadoFiltro;
                final matchBusqueda = q.isEmpty ||
                    e.numeroExpediente.toLowerCase().contains(q) ||
                    e.clienteNombre.toLowerCase().contains(q) ||
                    e.tipoNombre.toLowerCase().contains(q);
                return matchEstado && matchBusqueda;
              }).toList();

              if (filtrados.isEmpty) {
                return EmptyState(
                  titulo: 'Sin expedientes',
                  subtitulo: lista.isEmpty
                      ? 'Abre el primer expediente para comenzar.'
                      : 'No hay resultados para los filtros aplicados.',
                  icono: Icons.folder_outlined,
                  labelBoton: lista.isEmpty ? 'Nuevo expediente' : null,
                  onBoton: lista.isEmpty ? () => context.go('/expedientes/nuevo') : null,
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: filtrados.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) => _ExpedienteTile(exp: filtrados[i]),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _ExpedienteTile extends StatelessWidget {
  final ExpedienteModel exp;
  const _ExpedienteTile({required this.exp});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: () => context.go('/expedientes/${exp.id}'),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(exp.numeroExpediente,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                    )),
              ),
              StatusBadge(estado: exp.estado),
            ]),
            const SizedBox(height: 4),
            Text(exp.clienteNombre,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary)),
            Text(exp.tipoNombre,
                style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: InlineProgress(value: exp.porcentajeAvance / 100)),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, size: 16, color: AppColors.textTertiary),
            ]),
          ]),
        ),
      ),
    );
  }
}


class ExpedienteDetailScreen extends ConsumerStatefulWidget {
  final String id;
  const ExpedienteDetailScreen({super.key, required this.id});
  @override
  ConsumerState<ExpedienteDetailScreen> createState() => _ExpedienteDetailState();
}

class _ExpedienteDetailState extends ConsumerState<ExpedienteDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _conectado = false;
  StreamSubscription? _wsSub;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
    wsExpediente.connect('ws/expediente/${widget.id}/');

    _wsSub = wsExpediente.stream.listen((event) {
      if (!mounted) return;
      setState(() => _conectado = true);
      if (['expediente_update', 'hallazgo_creado', 'documento_actualizado']
          .contains(event['type'])) {
        ref.invalidate(expedienteProvider(widget.id));
        ref.invalidate(hallazgosProvider(widget.id));
        ref.invalidate(bitacoraProvider(widget.id));
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _wsSub?.cancel();
    wsExpediente.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final usuario   = authState.valueOrNull;
    final expAsync  = ref.watch(expedienteProvider(widget.id));

    return AppShell(
      rutaActual:    '/expedientes',
      rolUsuario:    usuario?.rol ?? '',
      nombreUsuario: usuario?.nombreCompleto ?? '',
      titulo: expAsync.valueOrNull?.numeroExpediente ?? 'Expediente',
      subtitulo: expAsync.valueOrNull?.clienteNombre,
      actions: [

        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 6, height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _conectado ? AppColors.success : AppColors.textTertiary,
              ),
            ),
            const SizedBox(width: 5),
            Text(_conectado ? 'En vivo' : 'Conectando',
                style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
          ]),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.add_task_outlined, size: 18),
          tooltip: 'Nuevo hallazgo',
          onPressed: () =>
              context.go('/expedientes/${widget.id}/hallazgo/nuevo'),
          style: IconButton.styleFrom(foregroundColor: AppColors.textSecondary),
        ),
        const SizedBox(width: 8),
      ],
      child: Column(children: [

        Container(
          color: AppColors.white,
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabs: const [
              Tab(text: 'Resumen'),
              Tab(text: 'Hallazgos'),
              Tab(text: 'Documentos'),
              Tab(text: 'Fases'),
              Tab(text: 'Checklist'),
              Tab(text: 'Bitácora'),
            ],
          ),
        ),
        Expanded(
          child: expAsync.when(
            loading: () => const Center(
              child: SizedBox(width: 24, height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (exp) => TabBarView(controller: _tabs, children: [
              _TabResumen(exp: exp),
              _TabHallazgos(expedienteId: widget.id),
              _TabDocumentos(expedienteId: widget.id),
              _TabFases(exp: exp),
              _TabChecklist(expedienteId: widget.id),
              _TabBitacora(expedienteId: widget.id),
            ]),
          ),
        ),
      ]),
    );
  }
}


class _TabResumen extends StatelessWidget {
  final ExpedienteModel exp;
  const _TabResumen({required this.exp});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  StatusBadge(estado: exp.estado),
                  Text(exp.fechaApertura.length >= 10
                          ? exp.fechaApertura.substring(0, 10) : exp.fechaApertura,
                      style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                ],
              ),
              const SizedBox(height: 12),
              Text(exp.clienteNombre,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(exp.tipoNombre,
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              ProgressCard(
                titulo: 'Avance de la auditoría',
                porcentaje: exp.porcentajeAvance,
                color: exp.porcentajeAvance >= 100 ? AppColors.success : AppColors.accent,
              ),
            ]),
          ),
        ),
        const SectionHeader(titulo: 'Información del expediente'),
        Card(
          child: Column(children: [
            _InfoRow(label: 'Número',         valor: exp.numeroExpediente),
            const Divider(),
            _InfoRow(label: 'Auditor líder',  valor: exp.auditorNombre),
            if (exp.fechaEstimadaCierre != null) ...[
              const Divider(),
              _InfoRow(label: 'Cierre estimado', valor: exp.fechaEstimadaCierre!),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.smart_toy_outlined, size: 15),
            label: const Text('Consultar AuditBot sobre este expediente'),
            onPressed: () => context.go('/chat?expediente=${exp.id}'),
          ),
        ),
        const SizedBox(height: 16),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String valor;
  const _InfoRow({required this.label, required this.valor});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    child: Row(children: [
      SizedBox(
        width: 120,
        child: Text(label,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ),
      Expanded(
        child: Text(valor,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary,
                fontWeight: FontWeight.w500)),
      ),
    ]),
  );
}


class _TabHallazgos extends ConsumerWidget {
  final String expedienteId;
  const _TabHallazgos({required this.expedienteId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(hallazgosProvider(expedienteId));
    return async.when(
      loading: () => const Center(
        child: SizedBox(width: 24, height: 24,
            child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => Center(child: Text('$e')),
      data: (lista) => lista.isEmpty
          ? EmptyState(
              titulo: 'Sin hallazgos',
              subtitulo: 'Registra el primer hallazgo de esta auditoría.',
              icono: Icons.fact_check_outlined,
              labelBoton: 'Nuevo hallazgo',
              onBoton: () =>
                  context.go('/expedientes/$expedienteId/hallazgo/nuevo'),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: lista.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) {
                final h = lista[i];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(children: [
                        StatusBadge(estado: h.nivelCriticidad),
                        const SizedBox(width: 6),
                        StatusBadge(estado: h.estado),
                        const Spacer(),
                        Text(h.tipo,
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textTertiary)),
                      ]),
                      const SizedBox(height: 8),
                      Text(h.titulo,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 4),
                      Text(h.descripcion,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                      const SizedBox(height: 6),
                      Text('Reportado por ${h.reportadoNombre}',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textTertiary)),
                    ]),
                  ),
                );
              },
            ),
    );
  }
}


class _CambiarEstadoButton extends ConsumerWidget {
  final ExpedienteModel exp;
  const _CambiarEstadoButton({required this.exp});

  static const _transiciones = {
    'BORRADOR':     ['ACTIVO', 'CANCELADO'],
    'ACTIVO':       ['EN_EJECUCION', 'SUSPENDIDO', 'CANCELADO'],
    'EN_EJECUCION': ['COMPLETADO', 'SUSPENDIDO', 'CANCELADO'],
    'SUSPENDIDO':   ['ACTIVO', 'CANCELADO'],
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estados = _transiciones[exp.estado] ?? [];
    if (estados.isEmpty) return const SizedBox.shrink();

    return OutlinedButton.icon(
      icon: const Icon(Icons.swap_horiz_outlined, size: 15),
      label: const Text('Cambiar estado'),
      onPressed: () => _mostrarDialogo(context, ref, estados),
    );
  }

  void _mostrarDialogo(BuildContext context, WidgetRef ref, List<String> estados) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambiar estado', style: TextStyle(fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: estados.map((e) => ListTile(
            title: StatusBadge(estado: e),
            onTap: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(expedientesServiceProvider).cambiarEstado(
                    exp.id, e, 'Cambio de estado desde la app');
                ref.invalidate(expedienteProvider(exp.id));
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Estado cambiado a ${e.toLowerCase()}')));
              } catch (err) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $err'),
                      backgroundColor: AppColors.danger));
              }
            },
          )).toList(),
        ),
      ),
    );
  }
}


class _TabChecklist extends ConsumerWidget {
  final String expedienteId;
  const _TabChecklist({required this.expedienteId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(checklistExpedienteProvider(expedienteId));
    return async.when(
      loading: () => const Center(
        child: SizedBox(width: 24, height: 24,
            child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => EmptyState(
        titulo: 'Error cargando checklist',
        subtitulo: e.toString(),
        icono: Icons.error_outline,
        labelBoton: 'Reintentar',
        onBoton: () => ref.invalidate(checklistExpedienteProvider(expedienteId)),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const EmptyState(
            titulo: 'Checklist vacío',
            subtitulo: 'Los criterios de verificación aparecerán aquí.',
            icono: Icons.fact_check_outlined,
          );
        }


        final Map<String, List<ChecklistEjecucionModel>> grupos = {};
        for (final item in items) {
          grupos.putIfAbsent(item.descripcion.isNotEmpty ? 'Criterios' : 'General', () => []).add(item);
        }


        final total      = items.length;
        final cumple     = items.where((i) => i.estado == 'CUMPLE').length;
        final noCumple   = items.where((i) => i.estado == 'NO_CUMPLE').length;
        final pendientes = items.where((i) => i.estado == 'PENDIENTE').length;

        return ListView(
          padding: const EdgeInsets.all(14),
          children: [

            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  _ChecklistStat(valor: total, label: 'Total', color: AppColors.textSecondary),
                  _ChecklistStat(valor: cumple, label: 'Cumple', color: AppColors.success),
                  _ChecklistStat(valor: noCumple, label: 'No cumple', color: AppColors.danger),
                  _ChecklistStat(valor: pendientes, label: 'Pendiente', color: AppColors.warning),
                ]),
              ),
            ),
            const SizedBox(height: 10),


            ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  leading: _estadoIcon(item.estado),
                  title: Text(item.descripcion,
                      style: const TextStyle(fontSize: 13,
                          color: AppColors.textPrimary)),
                  subtitle: item.observacion != null && item.observacion!.isNotEmpty
                      ? Text(item.observacion!,
                          style: const TextStyle(fontSize: 11,
                              color: AppColors.textTertiary))
                      : null,
                  trailing: StatusBadge(estado: item.estado),
                ),
              ),
            )),
          ],
        );
      },
    );
  }

  Widget _estadoIcon(String estado) {
    final (icon, color) = switch (estado) {
      'CUMPLE'    => (Icons.check_circle_outline, AppColors.success),
      'NO_CUMPLE' => (Icons.cancel_outlined, AppColors.danger),
      'NO_APLICA' => (Icons.remove_circle_outline, AppColors.textTertiary),
      _           => (Icons.radio_button_unchecked, AppColors.warning),
    };
    return Icon(icon, color: color, size: 20);
  }
}

class _ChecklistStat extends StatelessWidget {
  final int valor;
  final String label;
  final Color color;
  const _ChecklistStat({required this.valor, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(children: [
      Text('$valor', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: color)),
      Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textTertiary)),
    ]),
  );
}


class _TabDocumentos extends ConsumerStatefulWidget {
  final String expedienteId;
  const _TabDocumentos({required this.expedienteId});
  @override
  ConsumerState<_TabDocumentos> createState() => _TabDocumentosState();
}

class _TabDocumentosState extends ConsumerState<_TabDocumentos> {
  Future<void> _subirDocumento() async {
    PlatformFile? archivo;
    final nombreCtrl = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          decoration: const BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(
              width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
            )),
            const Text('Subir documento',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            TextField(
              controller: nombreCtrl,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(labelText: 'Nombre del documento *'),
            ),
            const SizedBox(height: 12),
            if (archivo == null)
              OutlinedButton.icon(
                icon: const Icon(Icons.attach_file_outlined, size: 15),
                label: const Text('Seleccionar archivo'),
                onPressed: () async {
                  final r = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['pdf','doc','docx','xls','xlsx','jpg','jpeg','png'],
                    withData: true,
                  );
                  if (r != null && r.files.isNotEmpty) {
                    setModal(() {
                      archivo = r.files.first;
                      if (nombreCtrl.text.isEmpty) {
                        nombreCtrl.text = r.files.first.name.replaceAll(RegExp(r'\.[^.]+$'), '');
                      }
                    });
                  }
                },
              )
            else
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.successBg, borderRadius: BorderRadius.circular(6)),
                child: Row(children: [
                  const Icon(Icons.check_circle_outline, size: 14, color: AppColors.success),
                  const SizedBox(width: 8),
                  Expanded(child: Text(archivo!.name,
                      style: const TextStyle(fontSize: 12, color: AppColors.success))),
                  GestureDetector(
                    onTap: () => setModal(() => archivo = null),
                    child: const Icon(Icons.close, size: 14, color: AppColors.success)),
                ]),
              ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'))),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton.icon(
                icon: const Icon(Icons.upload_outlined, size: 15),
                label: const Text('Subir'),
                onPressed: () async {
                  if (archivo == null || nombreCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Completa el nombre y selecciona un archivo.')));
                    return;
                  }
                  Navigator.pop(ctx);
                  try {
                    await ref.read(documentosServiceProvider).subir(
                      expedienteId:  widget.expedienteId,
                      nombre:        nombreCtrl.text.trim(),
                      bytesArchivo:  archivo!.bytes?.toList(),
                      rutaArchivo:   archivo!.path,
                      nombreArchivo: archivo!.name,
                    );
                    ref.invalidate(documentosExpedienteProvider(widget.expedienteId));
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Documento subido correctamente.')));
                  } catch (e) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Error: $e'), backgroundColor: AppColors.danger));
                  }
                },
              )),
            ]),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final docsAsync      = ref.watch(documentosExpedienteProvider(widget.expedienteId));
    final evidAsync      = ref.watch(evidenciasExpedienteProvider(widget.expedienteId));

    return Column(children: [

      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.upload_file_outlined, size: 15),
            label: const Text('Subir documento'),
            onPressed: _subirDocumento,
          ),
        ),
      ),
      Expanded(
        child: docsAsync.when(
          loading: () => const Center(child: SizedBox(width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2))),
          error: (e, _) => EmptyState(
            titulo: 'Error cargando documentos', subtitulo: e.toString(),
            icono: Icons.error_outline, labelBoton: 'Reintentar',
            onBoton: () => ref.invalidate(documentosExpedienteProvider(widget.expedienteId)),
          ),
          data: (docs) {


            final evidencias = evidAsync.valueOrNull ?? [];
            final todasEvidencias = evidencias.map((e) => <String, dynamic>{
              'id':       e['id'],
              'nombre':   e['nombre_original'] ?? e['nombre'] ?? 'Evidencia',
              'estado':   'EVIDENCIA',
              'descripcion': 'Evidencia de hallazgo: ${e['descripcion'] ?? ''}',
              'tipo_archivo': e['tipo_archivo'] ?? '',
            }).toList();

            final todos = [...docs, ...todasEvidencias];

            if (todos.isEmpty) {
              return const EmptyState(
                titulo: 'Sin documentos',
                subtitulo: 'Sube los documentos requeridos usando el botón de arriba.',
                icono: Icons.description_outlined,
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: todos.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) {
                final d     = todos[i];
                final estado = d['estado'] as String? ?? 'PENDIENTE';
                final esEvidencia = estado == 'EVIDENCIA';
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: _colorDoc(estado).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          esEvidencia ? Icons.attach_file_outlined
                              : _iconoDoc(d['tipo_archivo'] as String? ?? ''),
                          size: 18, color: _colorDoc(estado)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(d['nombre'] as String? ?? 'Documento',
                            style: const TextStyle(fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 2),
                        Text(d['descripcion'] as String? ?? '',
                            style: const TextStyle(fontSize: 11,
                                color: AppColors.textTertiary),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ])),
                      StatusBadge(estado: estado),
                    ]),
                  ),
                );
              },
            );
          },
        ),
      ),
    ]);
  }

  Color _colorDoc(String estado) => switch (estado.toUpperCase()) {
    'APROBADO'   => AppColors.success,
    'RECHAZADO'  => AppColors.danger,
    'EVIDENCIA'  => AppColors.accent,
    _            => AppColors.textTertiary,
  };

  IconData _iconoDoc(String tipo) => switch (tipo.toLowerCase()) {
    'pdf'  => Icons.picture_as_pdf_outlined,
    'xlsx' || 'xls' => Icons.table_chart_outlined,
    'docx' || 'doc' => Icons.description_outlined,
    'jpg' || 'jpeg' || 'png' => Icons.image_outlined,
    _ => Icons.attach_file_outlined,
  };
}


class _TabFases extends StatelessWidget {
  final ExpedienteModel exp;
  const _TabFases({required this.exp});

  @override
  Widget build(BuildContext context) {
    if (exp.fases.isEmpty) {
      return const EmptyState(
        titulo: 'Sin fases',
        subtitulo: 'Las fases se generan automáticamente al crear el expediente.',
        icono: Icons.linear_scale_outlined,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: exp.fases.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final fase = exp.fases[i];
        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: fase.estado.badgeBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text('${fase.orden}',
                    style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600,
                      color: fase.estado.badgeColor,
                    )),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(fase.faseNombre,
                      style: const TextStyle(fontSize: 13,
                          fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                  if (fase.fechaInicio != null)
                    Text('Inicio: ${fase.fechaInicio}',
                        style: const TextStyle(fontSize: 11,
                            color: AppColors.textTertiary)),
                ]),
              ),
              StatusBadge(estado: fase.estado),
            ]),
          ),
        );
      },
    );
  }
}


class _TabBitacora extends ConsumerStatefulWidget {
  final String expedienteId;
  const _TabBitacora({required this.expedienteId});
  @override
  ConsumerState<_TabBitacora> createState() => _TabBitacoraState();
}

class _TabBitacoraState extends ConsumerState<_TabBitacora> {


  Future<void> _agregarNota() async {
    final ctrl = TextEditingController();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Agregar nota a bitácora',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          autofocus: true,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'Escribe la nota o anotación para el expediente...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (confirmado != true || ctrl.text.trim().isEmpty) return;
    try {
      await ApiClient.instance.post(
        '${Endpoints.expediente(widget.expedienteId)}bitacora_nota/',
        data: {'descripcion': ctrl.text.trim()},
      );
      ref.invalidate(bitacoraProvider(widget.expedienteId));
    } catch (e) {

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al guardar nota: $e'),
          backgroundColor: AppColors.danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(bitacoraProvider(widget.expedienteId));
    return Column(children: [

      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.note_add_outlined, size: 15),
            label: const Text('Agregar nota manual'),
            onPressed: _agregarNota,
          ),
        ),
      ),
      Expanded(
        child: async.when(
          loading: () => const Center(child: SizedBox(width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2))),
          error: (e, _) => Center(child: Text('$e')),
          data: (lista) => lista.isEmpty
              ? const EmptyState(
                  titulo: 'Bitácora vacía',
                  subtitulo: 'Las acciones y notas aparecerán aquí conforme avance la auditoría.',
                  icono: Icons.history_outlined,
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  itemCount: lista.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final b = lista[i];

                    final esNota = b.accion == 'NOTA_MANUAL';
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 0, vertical: 4),
                      leading: Icon(
                        esNota ? Icons.sticky_note_2_outlined : Icons.circle,
                        size: esNota ? 16 : 6,
                        color: esNota ? AppColors.accent : AppColors.textTertiary,
                      ),
                      title: Text(b.descripcion,
                          style: const TextStyle(fontSize: 13,
                              color: AppColors.textPrimary)),
                      subtitle: Text(
                        '${b.usuarioNombre}  ·  '
                        '${b.fecha.length >= 16 ? b.fecha.substring(0, 16).replaceAll('T', ' ') : b.fecha}',
                        style: const TextStyle(fontSize: 11,
                            color: AppColors.textTertiary),
                      ),
                    );
                  },
                ),
        ),
      ),
    ]);
  }
}
