import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/services/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

class DocumentosScreen extends ConsumerStatefulWidget {
  const DocumentosScreen({super.key});
  @override
  ConsumerState<DocumentosScreen> createState() => _DocumentosScreenState();
}

class _DocumentosScreenState extends ConsumerState<DocumentosScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  String? _estadoFiltro;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final usuario   = authState.valueOrNull;
    final docsAsync = ref.watch(documentosProvider);

    return AppShell(
      rutaActual:    '/documentos',
      rolUsuario:    usuario?.rol ?? '',
      nombreUsuario: usuario?.nombreCompleto ?? '',
      titulo:        'Documentos',
      showBottomNav: true,


      actions: [
        IconButton(
          icon: const Icon(Icons.upload_file_outlined, size: 20),
          tooltip: 'Subir documento',
          onPressed: () => _abrirSubirDocumento(context, ref),
          style: IconButton.styleFrom(foregroundColor: AppColors.textSecondary),
        ),
        const SizedBox(width: 8),
      ],
      child: Column(children: [

        Container(
          color: AppColors.white,
          child: Column(children: [
            TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: 'Todos'),
                Tab(text: 'Pendientes'),
                Tab(text: 'Aprobados'),
              ],
              onTap: (i) {
                setState(() {
                  _estadoFiltro = switch (i) {
                    1 => 'PENDIENTE',
                    2 => 'APROBADO',
                    _ => null,
                  };
                });
              },
            ),
          ]),
        ),
        const Divider(),
        Expanded(
          child: docsAsync.when(
            loading: () => const Center(
              child: SizedBox(width: 24, height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (e, _) => EmptyState(
              titulo: 'Error cargando documentos',
              subtitulo: e.toString(),
              icono: Icons.error_outline,
              labelBoton: 'Reintentar',
              onBoton: () => ref.invalidate(documentosProvider),
            ),
            data: (docs) {
              final filtrados = _estadoFiltro == null
                  ? docs
                  : docs.where((d) =>
                          (d['estado'] as String? ?? '') == _estadoFiltro)
                      .toList();

              if (filtrados.isEmpty) {
                return EmptyState(
                  titulo: 'Sin documentos',
                  subtitulo: _estadoFiltro == null
                      ? 'Los documentos aparecerán aquí cuando se creen expedientes.'
                      : 'No hay documentos con estado "$_estadoFiltro".',
                  icono: Icons.description_outlined,
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: filtrados.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final d     = filtrados[i];
                  final estado = d['estado'] as String? ?? 'PENDIENTE';
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: _colorDoc(estado).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(_iconoDoc(d['tipo_archivo'] as String? ?? ''),
                                size: 18, color: _colorDoc(estado)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(d['nombre'] as String? ?? 'Documento',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.textPrimary)),
                              const SizedBox(height: 2),
                              Text(
                                  'Expediente: ${d['expediente_numero'] as String? ?? '—'}',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textTertiary)),
                            ]),
                          ),
                          StatusBadge(estado: estado),
                        ]),
                        if ((d['descripcion'] as String? ?? '').isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(d['descripcion'] as String,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        ],


                        if (['RECIBIDO', 'PENDIENTE'].contains(estado) &&
                            (usuario?.rol == 'SUPERVISOR' ||
                                usuario?.rol == 'SUPERVISOR')) ...[
                          const SizedBox(height: 10),
                          Row(children: [
                            OutlinedButton.icon(
                              icon: const Icon(Icons.check_outlined, size: 13),
                              label: const Text('Aprobar',
                                  style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.success,
                                  side: const BorderSide(
                                      color: AppColors.success, width: 0.5),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5)),
                              onPressed: () => _revisar(
                                  ref, d['id'] as String, 'APROBADO'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.close_outlined, size: 13),
                              label: const Text('Rechazar',
                                  style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.danger,
                                  side: const BorderSide(
                                      color: AppColors.danger, width: 0.5),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5)),
                              onPressed: () => _revisar(
                                  ref, d['id'] as String, 'RECHAZADO'),
                            ),
                          ]),
                        ],
                      ]),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }

  Future<void> _abrirSubirDocumento(BuildContext context, WidgetRef ref) async {
    final clientesAsync = ref.read(clientesProvider);
    final clientes      = clientesAsync.valueOrNull ?? [];
    final expedientesAsync = ref.read(expedientesProvider);
    final expedientes   = expedientesAsync.valueOrNull ?? [];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SubirDocumentoSheet(
        ref: ref,
        clientes: clientes,
        expedientes: expedientes,
        onSubido: () {
          ref.invalidate(documentosProvider);
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Documento subido correctamente.')));
        },
      ),
    );
  }

  Future<void> _revisar(WidgetRef ref, String id, String nuevoEstado) async {
    try {
      await ref.read(documentosServiceProvider).revisar(id, nuevoEstado);
      ref.invalidate(documentosProvider);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Documento $nuevoEstado correctamente.')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.danger));
    }
  }

  Color _colorDoc(String estado) => switch (estado.toUpperCase()) {
    'APROBADO'    => AppColors.success,
    'RECHAZADO'   => AppColors.danger,
    'EN_REVISION' => AppColors.accent,
    _             => AppColors.textTertiary,
  };

  IconData _iconoDoc(String tipo) => switch (tipo.toLowerCase()) {
    'pdf'                => Icons.picture_as_pdf_outlined,
    'xlsx' || 'xls'      => Icons.table_chart_outlined,
    'docx' || 'doc'      => Icons.description_outlined,
    'jpg' || 'jpeg' || 'png' => Icons.image_outlined,
    _                    => Icons.attach_file_outlined,
  };
}


class _SubirDocumentoSheet extends StatefulWidget {
  final WidgetRef ref;
  final List<dynamic> clientes;
  final List<dynamic> expedientes;
  final VoidCallback onSubido;
  const _SubirDocumentoSheet({
    required this.ref,
    required this.clientes,
    required this.expedientes,
    required this.onSubido,
  });
  @override
  State<_SubirDocumentoSheet> createState() => _SubirDocumentoSheetState();
}

class _SubirDocumentoSheetState extends State<_SubirDocumentoSheet> {
  final _nombreCtrl = TextEditingController();
  String?       _expedienteId;
  PlatformFile? _archivo;
  bool          _subiendo = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    super.dispose();
  }

  Future<void> _seleccionarArchivo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _archivo = result.files.first;
        if (_nombreCtrl.text.isEmpty) {
          _nombreCtrl.text = result.files.first.name
              .replaceAll(RegExp(r'\.[^.]+$'), '');
        }
      });
    }
  }

  Future<void> _subir() async {
    if (_expedienteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Selecciona un expediente.')));
      return;
    }
    if (_archivo == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Selecciona un archivo.')));
      return;
    }
    if (_nombreCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ingresa un nombre para el documento.')));
      return;
    }
    setState(() => _subiendo = true);
    try {
      await widget.ref.read(documentosServiceProvider).subir(
        expedienteId:  _expedienteId!,
        nombre:        _nombreCtrl.text.trim(),
        bytesArchivo:  _archivo!.bytes?.toList(),
        rutaArchivo:   _archivo!.path,
        nombreArchivo: _archivo!.name,
      );
      if (mounted) Navigator.pop(context);
      widget.onSubido();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error al subir: $e'),
            backgroundColor: AppColors.danger));
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final expedientes = widget.expedientes;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [

        Center(child: Container(
          width: 36, height: 4,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        )),
        const Text('Subir documento',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const SizedBox(height: 16),


        const Text('Expediente *',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _expedienteId,
          hint: const Text('Selecciona el expediente', style: TextStyle(fontSize: 13)),
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          isExpanded: true,
          items: expedientes.map((e) => DropdownMenuItem<String>(
            value: e.id as String,
            child: Text('${e.numeroExpediente} — ${e.clienteNombre}',
                overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: (v) => setState(() => _expedienteId = v),
        ),
        const SizedBox(height: 14),


        const Text('Nombre del documento *',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: _nombreCtrl,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(
              hintText: 'Ej: Política de Seguridad v2'),
        ),
        const SizedBox(height: 14),


        const Text('Archivo *',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        if (_archivo == null)
          OutlinedButton.icon(
            icon: const Icon(Icons.attach_file_outlined, size: 15),
            label: const Text('Seleccionar archivo (PDF, Word, Excel, imagen)'),
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
              const Icon(Icons.check_circle_outline, size: 14, color: AppColors.success),
              const SizedBox(width: 8),
              Expanded(child: Text(
                '${_archivo!.name}  (${(_archivo!.size / 1024).toStringAsFixed(1)} KB)',
                style: const TextStyle(fontSize: 12, color: AppColors.success),
              )),
              GestureDetector(
                onTap: () => setState(() => _archivo = null),
                child: const Icon(Icons.close, size: 14, color: AppColors.success),
              ),
            ]),
          ),
        const SizedBox(height: 20),


        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          )),
          const SizedBox(width: 12),
          Expanded(child: ElevatedButton.icon(
            icon: _subiendo
                ? const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.upload_outlined, size: 15),
            label: const Text('Subir'),
            onPressed: _subiendo ? null : _subir,
          )),
        ]),
      ]),
    );
  }
}
