import 'dart:math';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/services/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

final usuariosAdminProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final resp = await ApiClient.instance.get(Endpoints.usuarios);
  final data = resp.data;
  final lista = data is Map ? (data['results'] as List? ?? []) : (data as List? ?? []);
  return lista.cast<Map<String, dynamic>>();
});

final tiposAuditoriaAdminProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final resp = await ApiClient.instance.get(Endpoints.tiposAuditoria);
  final data = resp.data;
  final lista = data is Map ? (data['results'] as List? ?? []) : (data as List? ?? []);
  return lista.cast<Map<String, dynamic>>();
});

final _esquemasFetchProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final resp = await ApiClient.instance.get('formularios/esquemas/');
  final data = resp.data;
  final lista = data is Map ? (data['results'] as List? ?? []) : (data as List? ?? []);
  return lista.cast<Map<String, dynamic>>();
});

String generarPasswordAleatoria({int longitud = 12}) {
  const mayus      = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  const minus      = 'abcdefghjkmnpqrstuvwxyz';
  const numeros    = '23456789';
  const especiales = '@#\$!%*?&';
  final rng  = Random.secure();
  final chars = [
    mayus[rng.nextInt(mayus.length)],
    minus[rng.nextInt(minus.length)],
    numeros[rng.nextInt(numeros.length)],
    especiales[rng.nextInt(especiales.length)],
  ];
  final todos = mayus + minus + numeros + especiales;
  for (int i = 4; i < longitud; i++) chars.add(todos[rng.nextInt(todos.length)]);
  chars.shuffle(rng);
  return chars.join();
}

class AdminPanelScreen extends ConsumerStatefulWidget {
  const AdminPanelScreen({super.key});
  @override
  ConsumerState<AdminPanelScreen> createState() => _AdminPanelState();
}

class _AdminPanelState extends ConsumerState<AdminPanelScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() { super.initState(); _tabs = TabController(length: 5, vsync: this); }
  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final usuario = ref.watch(authProvider).valueOrNull;
    if (!['SUPERVISOR'].contains(usuario?.rol)) {
      return AppShell(
        rutaActual: '/admin-panel', rolUsuario: usuario?.rol ?? '',
        nombreUsuario: usuario?.nombreCompleto ?? '', titulo: 'Administración',
        child: const EmptyState(titulo: 'Acceso restringido',
            subtitulo: 'Solo los administradores pueden acceder a este módulo.',
            icono: Icons.lock_outlined),
      );
    }
    return AppShell(
      rutaActual: '/admin-panel', rolUsuario: usuario?.rol ?? '',
      nombreUsuario: usuario?.nombreCompleto ?? '', titulo: 'Administración',
      child: Column(children: [
        Container(color: AppColors.white, child: TabBar(
          controller: _tabs, isScrollable: true,
          tabs: const [
            Tab(text: 'Usuarios'), Tab(text: 'Equipo'),
            Tab(text: 'Roles y Permisos'),
            Tab(text: 'Tipos de Auditoría'), Tab(text: 'Formularios'),
          ],
        )),
        Expanded(child: TabBarView(controller: _tabs, children: [
          _TabUsuarios(ref: ref),
          _TabEquipo(ref: ref),
          const _TabRolesPermisos(),
          _TabTiposAuditoria(ref: ref),
          _TabFormularios(ref: ref),
        ])),
      ]),
    );
  }
}

class _TabUsuarios extends StatelessWidget {
  final WidgetRef ref;
  const _TabUsuarios({required this.ref});

  void _abrir(BuildContext ctx, {Map<String, dynamic>? u}) => showModalBottomSheet(
    context: ctx, isScrollControlled: true, backgroundColor: Colors.transparent,
    builder: (_) => _UsuarioForm(ref: ref, usuarioExistente: u));

  Future<void> _cambiarEstado(BuildContext ctx, Map<String, dynamic> u, bool activar) async {
    final nombre = '${u['nombre']} ${u['apellido']}';
    final ok = await showDialog<bool>(context: ctx, builder: (_) => AlertDialog(
      title: Text(activar ? '¿Activar usuario?' : '¿Desactivar usuario?',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      content: Text(activar ? 'Se restaurará el acceso de $nombre.'
          : '$nombre perderá el acceso inmediatamente.',
          style: const TextStyle(fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: activar ? AppColors.accent : AppColors.danger,
              foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(activar ? 'Activar' : 'Desactivar')),
      ]));
    if (ok != true) return;
    try {
      final id = u['id'] as String;
      if (activar) await ApiClient.instance.post('${Endpoints.usuarios}$id/activar/');
      else await ApiClient.instance.post(Endpoints.usuarioDesactivar(id));
      ref.invalidate(usuariosAdminProvider);
    } catch (e) {
      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(usuariosAdminProvider);
    return Stack(children: [
      async.when(
        loading: () => const Center(child: SizedBox(width: 24, height: 24,
            child: CircularProgressIndicator(strokeWidth: 2))),
        error: (e, _) => EmptyState(titulo: 'Error', subtitulo: e.toString(),
            icono: Icons.error_outline, labelBoton: 'Reintentar',
            onBoton: () => ref.invalidate(usuariosAdminProvider)),
        data: (usuarios) => usuarios.isEmpty
          ? EmptyState(titulo: 'Sin usuarios', subtitulo: 'Crea el primer usuario.',
              icono: Icons.people_outline, labelBoton: 'Nuevo usuario',
              onBoton: () => _abrir(context))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
              itemCount: usuarios.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) {
                final u      = usuarios[i];
                final nombre = '${u['nombre'] ?? ''} ${u['apellido'] ?? ''}';
                final rol    = u['rol'] as String? ?? '';
                final estado = u['estado'] as String? ?? '';
                final activo = estado == 'ACTIVO';
                final tipo   = u['tipo_contratacion'] as String? ?? '';
                return Card(child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(children: [
                    CircleAvatar(radius: 20,
                      backgroundColor: activo ? AppColors.accentLight : const Color(0xFFF1F5F9),
                      child: Text(nombre.isNotEmpty ? nombre[0].toUpperCase() : '?',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                              color: activo ? AppColors.accent : AppColors.textTertiary))),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(nombre, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                          color: activo ? AppColors.textPrimary : AppColors.textTertiary)),
                      Text(u['email'] as String? ?? '',
                          style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                      const SizedBox(height: 4),
                      Wrap(spacing: 6, children: [
                        _RolBadge(rol: rol),
                        StatusBadge(estado: estado),
                        if (tipo.isNotEmpty) _TipoBadge(tipo: tipo),
                        if (u['mfa_habilitado'] == true)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(10)),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.shield_outlined, size: 10, color: Color(0xFF059669)),
                              SizedBox(width: 3),
                              Text('MFA', style: TextStyle(fontSize: 10,
                                  color: Color(0xFF059669), fontWeight: FontWeight.w500)),
                            ])),
                      ]),
                    ])),
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'editar') _abrir(context, u: u);
                        else if (v == 'activar') _cambiarEstado(context, u, true);
                        else if (v == 'desactivar') _cambiarEstado(context, u, false);
                      },
                      icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textTertiary),
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'editar', child: Row(children: [
                          Icon(Icons.edit_outlined, size: 16), SizedBox(width: 8),
                          Text('Editar', style: TextStyle(fontSize: 13))])),
                        if (activo)
                          const PopupMenuItem(value: 'desactivar', child: Row(children: [
                            Icon(Icons.person_off_outlined, size: 16, color: AppColors.danger),
                            SizedBox(width: 8),
                            Text('Desactivar', style: TextStyle(fontSize: 13, color: AppColors.danger))]))
                        else
                          const PopupMenuItem(value: 'activar', child: Row(children: [
                            Icon(Icons.person_outlined, size: 16, color: AppColors.accent),
                            SizedBox(width: 8),
                            Text('Activar', style: TextStyle(fontSize: 13, color: AppColors.accent))])),
                      ]),
                  ])));
              })),
      Positioned(bottom: 16, right: 16,
        child: FloatingActionButton.extended(
          heroTag: 'fab_usuarios',
          onPressed: () => _abrir(context),
          icon: const Icon(Icons.person_add_outlined, size: 18),
          label: const Text('Nuevo usuario'),
          backgroundColor: AppColors.accent, foregroundColor: Colors.white)),
    ]);
  }
}

class _TabEquipo extends ConsumerStatefulWidget {
  final WidgetRef ref;
  const _TabEquipo({required this.ref});
  @override
  ConsumerState<_TabEquipo> createState() => _TabEquipoState();
}

class _TabEquipoState extends ConsumerState<_TabEquipo> {
  String _filtroTipo = 'TODOS';
  String _filtroRol  = 'TODOS';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(usuariosAdminProvider);
    return async.when(
      loading: () => const Center(child: SizedBox(width: 24, height: 24,
          child: CircularProgressIndicator(strokeWidth: 2))),
      error: (e, _) => EmptyState(titulo: 'Error', subtitulo: e.toString(),
          icono: Icons.error_outline, labelBoton: 'Reintentar',
          onBoton: () => ref.invalidate(usuariosAdminProvider)),
      data: (todos) {
        var usuarios = todos;
        if (_filtroTipo != 'TODOS') {
          usuarios = usuarios.where((u) =>
            (u['tipo_contratacion'] as String? ?? '') == _filtroTipo).toList();
        }
        if (_filtroRol != 'TODOS') {
          usuarios = usuarios.where((u) =>
            (u['rol'] as String? ?? '') == _filtroRol).toList();
        }
        final auditores = todos.where((u) => ['SUPERVISOR', 'AUDITOR', 'AUDITOR']
            .contains(u['rol'])).length;
        final externos = todos.where((u) =>
            (u['tipo_contratacion'] as String? ?? '') == 'EXTERNO').length;

        return Column(children: [
          Container(color: AppColors.white, padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _StatChip(label: 'Total', valor: '${todos.length}', color: AppColors.accent),
                const SizedBox(width: 8),
                _StatChip(label: 'Auditores', valor: '$auditores', color: const Color(0xFF7C3AED)),
                const SizedBox(width: 8),
                _StatChip(label: 'Externos', valor: '$externos', color: const Color(0xFFB45309)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: DropdownButtonFormField<String>(
                  value: _filtroTipo,
                  style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                  decoration: const InputDecoration(labelText: 'Contratación',
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                  items: const [
                    DropdownMenuItem(value: 'TODOS',    child: Text('Todos')),
                    DropdownMenuItem(value: 'PLANTA',   child: Text('Planta')),
                    DropdownMenuItem(value: 'CONTRATO', child: Text('Contrato')),
                    DropdownMenuItem(value: 'EXTERNO',  child: Text('Externo')),
                  ],
                  onChanged: (v) => setState(() => _filtroTipo = v!))),
                const SizedBox(width: 10),
                Expanded(child: DropdownButtonFormField<String>(
                  value: _filtroRol,
                  style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                  decoration: const InputDecoration(labelText: 'Rol',
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                  items: const [
                    DropdownMenuItem(value: 'TODOS',           child: Text('Todos')),
                    DropdownMenuItem(value: 'SUPERVISOR',   child: Text('Líder')),
                    DropdownMenuItem(value: 'AUDITOR', child: Text('Interno')),
                    DropdownMenuItem(value: 'AUDITOR', child: Text('Externo')),
                    DropdownMenuItem(value: 'ASESOR',       child: Text('Ejecutivo')),
                    DropdownMenuItem(value: 'SUPERVISOR',           child: Text('Admin')),
                  ],
                  onChanged: (v) => setState(() => _filtroRol = v!))),
              ]),
            ])),
          Expanded(child: usuarios.isEmpty
            ? const EmptyState(titulo: 'Sin resultados',
                subtitulo: 'Cambia los filtros.', icono: Icons.group_off_outlined)
            : ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: usuarios.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final u      = usuarios[i];
                  final nombre = '${u['nombre'] ?? ''} ${u['apellido'] ?? ''}';
                  final espec  = u['especialidad']   as String? ?? '';
                  final docId  = u['documento_id']   as String? ?? '';
                  final tipo   = u['tipo_contratacion'] as String? ?? 'PLANTA';
                  return Card(child: Padding(padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      CircleAvatar(radius: 22, backgroundColor: AppColors.accentLight,
                        child: Text(nombre.isNotEmpty ? nombre[0].toUpperCase() : '?',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                                color: AppColors.accent))),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(nombre, style: const TextStyle(fontSize: 13,
                            fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                        Text(u['email'] as String? ?? '',
                            style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                        if (espec.isNotEmpty) Text('Especialidad: $espec',
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        if (docId.isNotEmpty) Text('Doc: $docId',
                            style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, children: [
                          _RolBadge(rol: u['rol'] as String? ?? ''),
                          _TipoBadge(tipo: tipo),
                          StatusBadge(estado: u['estado'] as String? ?? ''),
                        ]),
                      ])),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 16, color: AppColors.textTertiary),
                        onPressed: () => showModalBottomSheet(
                          context: context, isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => _UsuarioForm(ref: ref, usuarioExistente: u),
                        ).then((_) => ref.invalidate(usuariosAdminProvider))),
                    ])));
                })),
        ]);
      });
  }
}

class _StatChip extends StatelessWidget {
  final String label, valor;
  final Color color;
  const _StatChip({required this.label, required this.valor, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8)),
    child: Column(children: [
      Text(valor, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
      Text(label, style: TextStyle(fontSize: 11, color: color.withOpacity(0.8))),
    ]));
}

class _UsuarioForm extends ConsumerStatefulWidget {
  final Map<String, dynamic>? usuarioExistente;
  final WidgetRef ref;
  const _UsuarioForm({required this.ref, this.usuarioExistente});
  @override
  ConsumerState<_UsuarioForm> createState() => _UsuarioFormState();
}

class _UsuarioFormState extends ConsumerState<_UsuarioForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _emailCtrl, _nombreCtrl, _apellidoCtrl,
      _telefonoCtrl, _passCtrl, _documentoCtrl, _especialidadCtrl;
  String  _rol              = 'AUDITOR';
  String  _estado           = 'ACTIVO';
  String  _tipoContratacion = 'PLANTA';
  bool    _guardando = false, _verPass = false;
  String? _error;

  static const _roles = [
    ('SUPERVISOR', 'Supervisor'),
    ('ASESOR',     'Asesor'),
    ('AUDITOR',    'Auditor'),
    ('AUXILIAR',   'Auxiliar'),
    ('REVISOR',    'Revisor'),
    ('CLIENTE',    'Cliente'),
  ];
  static const _estados = [('ACTIVO', 'Activo'), ('INACTIVO', 'Inactivo')];
  static const _tipos = [
    ('PLANTA', 'Planta'), ('CONTRATO', 'Contrato'), ('EXTERNO', 'Externo / Freelance'),
  ];

  bool get _esEdicion => widget.usuarioExistente != null;

  @override
  void initState() {
    super.initState();
    final u = widget.usuarioExistente;
    _emailCtrl        = TextEditingController(text: u?['email']             as String? ?? '');
    _nombreCtrl       = TextEditingController(text: u?['nombre']            as String? ?? '');
    _apellidoCtrl     = TextEditingController(text: u?['apellido']          as String? ?? '');
    _telefonoCtrl     = TextEditingController(text: u?['telefono']          as String? ?? '');
    _documentoCtrl    = TextEditingController(text: u?['documento_id']      as String? ?? '');
    _especialidadCtrl = TextEditingController(text: u?['especialidad']      as String? ?? '');
    _passCtrl         = TextEditingController();
    _rol              = u?['rol']               as String? ?? 'AUDITOR';
    _estado           = u?['estado']            as String? ?? 'ACTIVO';
    _tipoContratacion = u?['tipo_contratacion'] as String? ?? 'PLANTA';
  }

  @override
  void dispose() {
    for (final c in [_emailCtrl, _nombreCtrl, _apellidoCtrl, _telefonoCtrl,
                     _passCtrl, _documentoCtrl, _especialidadCtrl]) c.dispose();
    super.dispose();
  }

  void _generarPassword() {
    final pwd = generarPasswordAleatoria();
    setState(() { _passCtrl.text = pwd; _verPass = true; });
    Clipboard.setData(ClipboardData(text: pwd));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Contraseña generada y copiada.'),
      backgroundColor: AppColors.accent, duration: Duration(seconds: 3)));
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _guardando = true; _error = null; });
    try {
      if (_esEdicion) {
        final id = widget.usuarioExistente!['id'] as String;
        final payload = <String, dynamic>{
          'nombre': _nombreCtrl.text.trim(), 'apellido': _apellidoCtrl.text.trim(),
          'telefono': _telefonoCtrl.text.trim(), 'documento_id': _documentoCtrl.text.trim(),
          'especialidad': _especialidadCtrl.text.trim(),
          'tipo_contratacion': _tipoContratacion, 'rol': _rol, 'estado': _estado,
        };
        if (_passCtrl.text.isNotEmpty) payload['password'] = _passCtrl.text;
        await ApiClient.instance.patch('${Endpoints.usuarios}$id/', data: payload);
      } else {
        await ApiClient.instance.post(Endpoints.usuarios, data: {
          'email': _emailCtrl.text.trim().toLowerCase(),
          'nombre': _nombreCtrl.text.trim(), 'apellido': _apellidoCtrl.text.trim(),
          'telefono': _telefonoCtrl.text.trim(), 'documento_id': _documentoCtrl.text.trim(),
          'especialidad': _especialidadCtrl.text.trim(),
          'tipo_contratacion': _tipoContratacion, 'rol': _rol, 'password': _passCtrl.text,
        });
      }
      widget.ref.invalidate(usuariosAdminProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) { setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _guardando = false); }
  }

  Widget _campo(String label, TextEditingController ctrl, {String? hint,
    String? Function(String?)? validator, TextInputType teclado = TextInputType.text, bool readOnly = false}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
          color: AppColors.textSecondary)),
      const SizedBox(height: 5),
      TextFormField(controller: ctrl, keyboardType: teclado, readOnly: readOnly,
        style: TextStyle(fontSize: 13,
            color: readOnly ? AppColors.textTertiary : AppColors.textPrimary),
        decoration: InputDecoration(hintText: hint), validator: validator),
    ]);

  Widget _drop<T>(String label, T value, List<(T, String)> items, void Function(T?) onChange) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
          color: AppColors.textSecondary)),
      const SizedBox(height: 5),
      DropdownButtonFormField<T>(
        value: value,
        style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
        items: items.map((i) => DropdownMenuItem(value: i.$1, child: Text(i.$2))).toList(),
        onChanged: onChange),
    ]);

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
    child: Form(key: _form, child: SingleChildScrollView(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(_esEdicion ? 'Editar usuario' : 'Nuevo usuario',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const Spacer(),
        IconButton(onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 18),
            style: IconButton.styleFrom(foregroundColor: AppColors.textSecondary)),
      ]),
      const SizedBox(height: 16),
      _campo('Email', _emailCtrl, hint: 'usuario@empresa.com',
        teclado: TextInputType.emailAddress, readOnly: _esEdicion,
        validator: _esEdicion ? null : (v) {
          if (v == null || v.trim().isEmpty) return 'Requerido';
          if (!v.contains('@')) return 'Email inválido';
          return null;
        }),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _campo('Nombre *', _nombreCtrl, hint: 'Carlos',
          validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null)),
        const SizedBox(width: 12),
        Expanded(child: _campo('Apellido *', _apellidoCtrl, hint: 'Gómez',
          validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null)),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _campo('Teléfono', _telefonoCtrl,
            hint: '+57 300 000 0000', teclado: TextInputType.phone)),
        const SizedBox(width: 12),
        Expanded(child: _campo('Documento / Cédula', _documentoCtrl, hint: '12345678')),
      ]),
      const SizedBox(height: 12),
      _campo('Especialidad', _especialidadCtrl, hint: 'ISO 27001, Calidad...'),
      const SizedBox(height: 12),
      _drop('Tipo de contratación', _tipoContratacion, _tipos,
          (v) => setState(() => _tipoContratacion = v!)),
      const SizedBox(height: 12),
      _drop('Rol *', _rol, _roles, (v) => setState(() => _rol = v!)),
      const SizedBox(height: 12),
      if (_esEdicion) ...[
        _drop('Estado', _estado, _estados, (v) => setState(() => _estado = v!)),
        const SizedBox(height: 12),
      ],
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(_esEdicion ? 'Nueva contraseña (opcional)' : 'Contraseña *',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary)),
          const Spacer(),
          TextButton.icon(onPressed: _generarPassword,
            icon: const Icon(Icons.casino_outlined, size: 14), label: const Text('Generar', style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(foregroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4))),
        ]),
        const SizedBox(height: 5),
        TextFormField(controller: _passCtrl, obscureText: !_verPass,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: _esEdicion ? 'Dejar vacío para no cambiar' : 'Mínimo 8 caracteres',
            suffixIcon: IconButton(
              icon: Icon(_verPass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 16, color: AppColors.textTertiary),
              onPressed: () => setState(() => _verPass = !_verPass))),
          validator: _esEdicion
            ? (v) { if (v != null && v.isNotEmpty && v.length < 8) return 'Mínimo 8 caracteres'; return null; }
            : (v) { if (v == null || v.isEmpty) return 'Requerida'; if (v.length < 8) return 'Mínimo 8 caracteres'; return null; }),
      ]),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppColors.dangerBg, borderRadius: BorderRadius.circular(6)),
          child: Text(_error!, style: const TextStyle(fontSize: 12, color: AppColors.danger))),
      ],
      const SizedBox(height: 20),
      SizedBox(width: double.infinity, child: ElevatedButton(
        onPressed: _guardando ? null : _guardar,
        child: _guardando
          ? const SizedBox(width: 16, height: 16,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : Text(_esEdicion ? 'Guardar cambios' : 'Crear usuario'))),
    ]))));
}

class _TabRolesPermisos extends StatelessWidget {
  const _TabRolesPermisos();

  @override
  Widget build(BuildContext context) {
    const roles   = ['SUPERVISOR', 'LIDER', 'INT', 'EXT', 'EJEC'];
    const modulos = [
      _Modulo('Usuarios',        Icons.people_outlined,            [true,  false, false, false, false, false]),
      _Modulo('Equipo/Contrat.', Icons.badge_outlined,             [true,  false, false, false, false, false]),
      _Modulo('Clientes (crear)',Icons.business_outlined,          [true,  true,  false, false, false, false]),
      _Modulo('Clientes (ver)',  Icons.business_center_outlined,   [true,  true,  false, false, true,  false]),
      _Modulo('Expedientes',     Icons.folder_open_outlined,       [true,  false, true,  true,  true,  true ]),
      _Modulo('Hallazgos',       Icons.warning_amber_outlined,     [true,  false, true,  true,  true,  false]),
      _Modulo('Documentos',      Icons.description_outlined,       [true,  false, true,  true,  true,  true ]),
      _Modulo('Aprobar Docs',    Icons.verified_outlined,          [true,  false, true,  false, false, false]),
      _Modulo('Certificaciones', Icons.workspace_premium_outlined, [true,  true,  true,  false, true,  true ]),
      _Modulo('Formularios',     Icons.dynamic_form_outlined,      [true,  false, true,  true,  true,  false]),
      _Modulo('Crear Formul.',   Icons.edit_document,              [true,  false, true,  false, false, false]),
      _Modulo('Procedimientos',  Icons.assignment_outlined,        [true,  false, true,  true,  false, false]),
      _Modulo('AuditBot',        Icons.smart_toy_outlined,         [true,  true,  true,  true,  true,  false]),
      _Modulo('Reportes',        Icons.table_chart_outlined,       [true,  true,  true,  false, true,  false]),
      _Modulo('Portal cliente',  Icons.person_outlined,            [false, false, false, false, false, true ]),
    ];

    return SingleChildScrollView(padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Matriz de accesos', style: TextStyle(fontSize: 15,
            fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        const Text('Accesos base por rol. Permisos individuales adicionales configurables por usuario.',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary, height: 1.4)),
        const SizedBox(height: 16),
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          Row(children: [
            const SizedBox(width: 120),
            ...roles.map((r) => Expanded(child: Center(child: Text(r,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary))))),
          ]),
          const Divider(height: 16),
          ...modulos.map((m) => Padding(padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              SizedBox(width: 135, child: Row(children: [
                Icon(m.icono, size: 13, color: AppColors.textSecondary),
                const SizedBox(width: 5),
                Expanded(child: Text(m.nombre, style: const TextStyle(fontSize: 11,
                    color: AppColors.textPrimary), overflow: TextOverflow.ellipsis)),
              ])),
              ...List.generate(roles.length, (i) => Expanded(child: Center(child: Icon(
                m.permisos[i] ? Icons.check_circle : Icons.cancel_outlined, size: 16,
                color: m.permisos[i] ? const Color(0xFF059669) : const Color(0xFFCBD5E1))))),
            ]))),
        ]))),
        const SizedBox(height: 20),
        const Text('Descripción de roles', style: TextStyle(fontSize: 14,
            fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        ...[
          ('SUPERVISOR',           AppColors.accent,           'Acceso total. Gestiona usuarios, tipos de auditoría, formularios y configuración global.'),
          ('SUPERVISOR',   const Color(0xFF7C3AED),    'Lidera equipos. Aprueba documentos, emite certificaciones y ve el dashboard completo.'),
          ('AUDITOR', const Color(0xFF0369A1),    'Ejecuta auditorías como parte del equipo de planta. Registra hallazgos y sube evidencias.'),
          ('AUDITOR', const Color(0xFF0891B2),    'Auditor contratado externamente. Acceso limitado a sus expedientes asignados.'),
          ('ASESOR',       const Color(0xFFB45309),    'Gestión comercial. Ve expedientes, vencimientos de certificaciones y emite reportes.'),
        ].map((r) => Padding(padding: const EdgeInsets.only(bottom: 10),
          child: Card(child: Padding(padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _RolBadge(rol: r.$1),
              const SizedBox(width: 12),
              Expanded(child: Text(r.$3, style: const TextStyle(fontSize: 12,
                  color: AppColors.textSecondary, height: 1.4))),
            ]))))),
      ]));
  }
}

class _Modulo {
  final String nombre; final IconData icono; final List<bool> permisos;
  const _Modulo(this.nombre, this.icono, this.permisos);
}

class _TabTiposAuditoria extends StatelessWidget {
  final WidgetRef ref;
  const _TabTiposAuditoria({required this.ref});

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(tiposAuditoriaAdminProvider);
    return async.when(
      loading: () => const Center(child: SizedBox(width: 24, height: 24,
          child: CircularProgressIndicator(strokeWidth: 2))),
      error: (e, _) => EmptyState(titulo: 'Error', subtitulo: e.toString(),
          icono: Icons.error_outline, labelBoton: 'Reintentar',
          onBoton: () => ref.invalidate(tiposAuditoriaAdminProvider)),
      data: (tipos) => tipos.isEmpty
        ? const EmptyState(titulo: 'Sin tipos de auditoría',
            subtitulo: 'Configura los tipos con el seed de datos.',
            icono: Icons.assignment_outlined)
        : ListView.separated(
            padding: const EdgeInsets.all(14), itemCount: tipos.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, i) {
              final t = tipos[i];
              return Card(child: Padding(padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('${t['codigo']} — ${t['nombre']}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                    StatusBadge(estado: (t['activo'] as bool? ?? true) ? 'ACTIVO' : 'INACTIVO'),
                  ]),
                  const SizedBox(height: 6),
                  Text('Nivel: ${t['nivel'] ?? '—'}  ·  '
                      '${(t['fases'] as List? ?? []).length} fases  ·  '
                      '${(t['checklist_items'] as List? ?? []).length} checklist',
                      style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                ])));
            }));
  }
}

class _TabFormularios extends ConsumerStatefulWidget {
  final WidgetRef ref;
  const _TabFormularios({required this.ref});
  @override
  ConsumerState<_TabFormularios> createState() => _TabFormulariosState();
}

class _TabFormulariosState extends ConsumerState<_TabFormularios> {
  bool _subiendoBot = false;

  Future<void> _importarBot(BuildContext ctx) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['pdf', 'docx', 'doc', 'xlsx', 'xls'],
      withData: false);
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    final path   = picked.path;
    if (path == null) return;

    final nombreCtrl = TextEditingController();
    final tipos      = ref.read(tiposAuditoriaAdminProvider).valueOrNull ?? [];
    String? tipoSel;
    String  contextoSel = 'EXPEDIENTE';

    final ok = await showDialog<bool>(context: ctx, builder: (_) =>
      StatefulBuilder(builder: (ctx2, set2) => AlertDialog(
        title: const Text('Importar formulario con IA',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.infoBg, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              const Icon(Icons.auto_awesome_outlined, size: 16, color: AppColors.info),
              const SizedBox(width: 8),
              Expanded(child: Text('El bot analizará "${picked.name}" y extraerá los campos.',
                  style: const TextStyle(fontSize: 12, color: AppColors.info))),
            ])),
          const SizedBox(height: 14),
          const Text('Nombre del formulario *', style: TextStyle(fontSize: 12,
              fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          TextField(controller: nombreCtrl, style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(hintText: 'Ej: Checklist ISO 27001')),
          const SizedBox(height: 12),
          const Text('Contexto', style: TextStyle(fontSize: 12,
              fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: contextoSel,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
            items: const [
              DropdownMenuItem(value: 'EXPEDIENTE', child: Text('Expediente')),
              DropdownMenuItem(value: 'HALLAZGO',   child: Text('Hallazgo')),
              DropdownMenuItem(value: 'DOCUMENTO',  child: Text('Documento')),
            ],
            onChanged: (v) => set2(() => contextoSel = v!)),
          const SizedBox(height: 12),
          const Text('Tipo de auditoría (opcional)', style: TextStyle(fontSize: 12,
              fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String?>(
            value: tipoSel,
            hint: const Text('Genérico', style: TextStyle(fontSize: 13)),
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
            isExpanded: true,
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Genérico')),
              ...tipos.map((t) => DropdownMenuItem<String?>(
                value: t['id'] as String,
                child: Text('${t['codigo']} — ${t['nombre']}', overflow: TextOverflow.ellipsis))),
            ],
            onChanged: (v) => set2(() => tipoSel = v)),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx2, false), child: const Text('Cancelar')),
          ElevatedButton.icon(
            icon: const Icon(Icons.auto_awesome_outlined, size: 15),
            label: const Text('Analizar'),
            onPressed: () { if (nombreCtrl.text.trim().isEmpty) return; Navigator.pop(ctx2, true); }),
        ])));

    if (ok != true || !mounted) return;
    setState(() => _subiendoBot = true);
    try {
      final formData = FormData.fromMap({
        'archivo':  await MultipartFile.fromFile(path, filename: picked.name),
        'nombre':   nombreCtrl.text.trim(),
        'contexto': contextoSel,
        if (tipoSel != null) 'tipo_auditoria': tipoSel,
      });
      await ApiClient.instance.post('formularios/esquemas/importar-bot/', data: formData,
          options: Options(contentType: 'multipart/form-data'));
      ref.invalidate(_esquemasFetchProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Formulario en procesamiento. Aparecerá en breve.'),
        backgroundColor: AppColors.accent, duration: Duration(seconds: 5)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger));
    } finally {
      if (mounted) setState(() => _subiendoBot = false);
    }
  }

  Future<void> _abrirForm(BuildContext ctx, {Map<String, dynamic>? e}) async {
    final tipos = ref.read(tiposAuditoriaAdminProvider).valueOrNull ?? [];
    await showModalBottomSheet(context: ctx, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EsquemaFormSheet(ref: ref, esquema: e, tipos: tipos,
          onGuardado: () => ref.invalidate(_esquemasFetchProvider)));
  }

  Future<void> _toggle(BuildContext ctx, String id, bool nuevoActivo) async {
    try {
      await ApiClient.instance.patch('formularios/esquemas/$id/', data: {'activo': nuevoActivo});
      ref.invalidate(_esquemasFetchProvider);
    } catch (e) {
      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_esquemasFetchProvider);
    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, children: [
        FloatingActionButton.small(
          heroTag: 'fab_bot', tooltip: 'Importar con IA',
          backgroundColor: const Color(0xFF7C3AED), foregroundColor: Colors.white,
          onPressed: _subiendoBot ? null : () => _importarBot(context),
          child: _subiendoBot
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.auto_awesome_outlined, size: 18)),
        const SizedBox(height: 10),
        FloatingActionButton.extended(
          heroTag: 'fab_form', icon: const Icon(Icons.add, size: 18),
          label: const Text('Nuevo formulario'),
          backgroundColor: AppColors.accent, foregroundColor: Colors.white,
          onPressed: () => _abrirForm(context)),
      ]),
      body: async.when(
        loading: () => const Center(child: SizedBox(width: 24, height: 24,
            child: CircularProgressIndicator(strokeWidth: 2))),
        error: (e, _) => EmptyState(titulo: 'Error', subtitulo: e.toString(),
            icono: Icons.error_outline, labelBoton: 'Reintentar',
            onBoton: () => ref.invalidate(_esquemasFetchProvider)),
        data: (esquemas) => esquemas.isEmpty
          ? EmptyState(titulo: 'Sin formularios',
              subtitulo: 'Crea manualmente o importa con IA desde PDF/Word/Excel.',
              icono: Icons.dynamic_form_outlined,
              labelBoton: 'Crear formulario', onBoton: () => _abrirForm(context))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 120),
              itemCount: esquemas.length, separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) {
                final e      = esquemas[i];
                final campos = e['campos'] as List? ?? [];
                final activo = e['activo'] as bool? ?? true;
                final origen = e['origen'] as String? ?? 'MANUAL';
                final procesando = !activo && origen != 'MANUAL';
                return Card(child: Padding(padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      if (origen != 'MANUAL') ...[
                        const Icon(Icons.auto_awesome_outlined, size: 13, color: Color(0xFF7C3AED)),
                        const SizedBox(width: 4),
                      ],
                      Expanded(child: Text(e['nombre'] as String? ?? '—',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: activo ? AppColors.accentLight : AppColors.dangerBg,
                          borderRadius: BorderRadius.circular(10)),
                        child: Text(activo ? (e['contexto'] as String? ?? '—') : 'Inactivo',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500,
                                color: activo ? AppColors.accentDark : AppColors.danger))),
                    ]),
                    if ((e['descripcion'] as String? ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(e['descripcion'] as String,
                          style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                    ],
                    const SizedBox(height: 4),
                    Text('${campos.length} campos  ·  v${e['version'] ?? 1}  ·  '
                        '${_origenLabel(origen)}',
                        style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                    if (procesando) ...[
                      const SizedBox(height: 6),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFFEF08A))),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.hourglass_top_outlined, size: 12, color: Color(0xFFD97706)),
                          SizedBox(width: 5),
                          Text('Bot procesando...', style: TextStyle(fontSize: 11, color: Color(0xFFD97706))),
                        ])),
                    ],
                    const SizedBox(height: 10),
                    Row(children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.edit_outlined, size: 13),
                        label: const Text('Editar', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5)),
                        onPressed: () => _abrirForm(context, e: e)),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: Icon(activo ? Icons.toggle_off_outlined : Icons.toggle_on_outlined,
                            size: 13, color: activo ? AppColors.danger : AppColors.success),
                        label: Text(activo ? 'Desactivar' : 'Activar',
                            style: TextStyle(fontSize: 12,
                                color: activo ? AppColors.danger : AppColors.success)),
                        style: OutlinedButton.styleFrom(
                            side: BorderSide(color: activo ? AppColors.danger : AppColors.success, width: 0.5),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5)),
                        onPressed: () => _toggle(context, e['id'] as String, !activo)),
                    ]),
                  ])));
              })));
  }

  String _origenLabel(String o) => switch (o) {
    'BOT_PDF'   => '📄 PDF',
    'BOT_WORD'  => '📝 Word',
    'BOT_EXCEL' => '📊 Excel',
    _           => '✏️ Manual',
  };
}

class _EsquemaFormSheet extends StatefulWidget {
  final WidgetRef ref;
  final Map<String, dynamic>? esquema;
  final List<Map<String, dynamic>> tipos;
  final VoidCallback onGuardado;
  const _EsquemaFormSheet({required this.ref, required this.esquema,
      required this.tipos, required this.onGuardado});
  @override
  State<_EsquemaFormSheet> createState() => _EsquemaFormSheetState();
}

class _EsquemaFormSheetState extends State<_EsquemaFormSheet> {
  final _nombreCtrl = TextEditingController();
  final _descCtrl   = TextEditingController();
  String  _contexto        = 'EXPEDIENTE';
  String? _tipoAuditoriaId;
  bool    _activo = true, _guardando = false;
  final List<Map<String, dynamic>> _campos = [];

  @override
  void initState() {
    super.initState();
    final e = widget.esquema;
    if (e != null) {
      _nombreCtrl.text = e['nombre']      as String? ?? '';
      _descCtrl.text   = e['descripcion'] as String? ?? '';
      _contexto        = e['contexto']    as String? ?? 'EXPEDIENTE';
      _tipoAuditoriaId = e['tipo_auditoria'] as String?;
      _activo          = e['activo']      as bool?   ?? true;
      _campos.addAll((e['campos'] as List? ?? []).cast<Map<String, dynamic>>());
    }
  }

  @override
  void dispose() { _nombreCtrl.dispose(); _descCtrl.dispose(); super.dispose(); }

  Future<void> _guardar() async {
    if (_nombreCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El nombre es requerido.'))); return;
    }
    setState(() => _guardando = true);
    try {
      final payload = {
        'nombre': _nombreCtrl.text.trim(), 'descripcion': _descCtrl.text.trim(),
        'contexto': _contexto, 'activo': _activo,
        if (_tipoAuditoriaId != null) 'tipo_auditoria': _tipoAuditoriaId,
      };
      final id = widget.esquema?['id'] as String?;
      if (id != null) {
        await ApiClient.instance.patch('formularios/esquemas/$id/', data: payload);
      } else {
        await ApiClient.instance.post('formularios/esquemas/', data: payload);
      }
      if (mounted) Navigator.pop(context);
      widget.onGuardado();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger));
    } finally { if (mounted) setState(() => _guardando = false); }
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    padding: EdgeInsets.only(left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20),
    child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
      Text(widget.esquema == null ? 'Nuevo formulario' : 'Editar formulario',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      const SizedBox(height: 16),
      const Text('Nombre *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
          color: AppColors.textSecondary)),
      const SizedBox(height: 6),
      TextField(controller: _nombreCtrl, style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(hintText: 'Ej: Checklist ISO 27001')),
      const SizedBox(height: 12),
      const Text('Descripción', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
          color: AppColors.textSecondary)),
      const SizedBox(height: 6),
      TextField(controller: _descCtrl, maxLines: 2, style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(hintText: 'Opcional')),
      const SizedBox(height: 12),
      const Text('Contexto', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
          color: AppColors.textSecondary)),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        value: _contexto, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
        items: const [
          DropdownMenuItem(value: 'EXPEDIENTE', child: Text('Expediente')),
          DropdownMenuItem(value: 'HALLAZGO',   child: Text('Hallazgo')),
          DropdownMenuItem(value: 'DOCUMENTO',  child: Text('Documento')),
          DropdownMenuItem(value: 'CLIENTE',    child: Text('Cliente')),
        ],
        onChanged: (v) => setState(() => _contexto = v!)),
      const SizedBox(height: 12),
      const Text('Tipo de auditoría (opcional)', style: TextStyle(fontSize: 12,
          fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
      const SizedBox(height: 6),
      DropdownButtonFormField<String?>(
        value: _tipoAuditoriaId,
        hint: const Text('Genérico', style: TextStyle(fontSize: 13)),
        style: const TextStyle(fontSize: 13, color: AppColors.textPrimary), isExpanded: true,
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('Genérico')),
          ...widget.tipos.map((t) => DropdownMenuItem<String?>(value: t['id'] as String,
              child: Text('${t['codigo']} — ${t['nombre']}', overflow: TextOverflow.ellipsis))),
        ],
        onChanged: (v) => setState(() => _tipoAuditoriaId = v)),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Campos', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        TextButton.icon(icon: const Icon(Icons.add, size: 15), label: const Text('Agregar'),
          onPressed: () => setState(() => _campos.add({
            'nombre': 'campo_${_campos.length + 1}', 'etiqueta': 'Campo ${_campos.length + 1}',
            'tipo': 'TEXTO', 'obligatorio': false, 'orden': _campos.length + 1,
            'opciones': [], 'ayuda': ''}))),
      ]),
      const SizedBox(height: 8),
      if (_campos.isEmpty)
        Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border)),
          child: const Center(child: Text('Toca "Agregar" para añadir campos.',
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary))))
      else
        ..._campos.asMap().entries.map((entry) {
          final idx = entry.key; final c = entry.value;
          return Card(margin: const EdgeInsets.only(bottom: 8),
            child: Padding(padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('Campo ${idx + 1}', style: const TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w500, color: AppColors.textSecondary))),
                  GestureDetector(onTap: () => setState(() => _campos.removeAt(idx)),
                      child: const Icon(Icons.delete_outline, size: 16, color: AppColors.danger)),
                ]),
                const SizedBox(height: 8),
                TextFormField(initialValue: c['etiqueta'] as String? ?? '',
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(labelText: 'Etiqueta visible',
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                  onChanged: (v) => _campos[idx]['etiqueta'] = v),
                const SizedBox(height: 6),
                TextFormField(initialValue: c['ayuda'] as String? ?? '',
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(labelText: 'Ayuda (opcional)',
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                  onChanged: (v) => _campos[idx]['ayuda'] = v),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: c['tipo'] as String? ?? 'TEXTO',
                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                  decoration: const InputDecoration(labelText: 'Tipo',
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                  items: const [
                    DropdownMenuItem(value: 'TEXTO',    child: Text('Texto libre')),
                    DropdownMenuItem(value: 'NUMERO',   child: Text('Número')),
                    DropdownMenuItem(value: 'BOOLEANO', child: Text('Sí / No')),
                    DropdownMenuItem(value: 'LISTA',    child: Text('Lista de opciones')),
                    DropdownMenuItem(value: 'FECHA',    child: Text('Fecha')),
                    DropdownMenuItem(value: 'ARCHIVO',  child: Text('Archivo')),
                    DropdownMenuItem(value: 'TABLA',    child: Text('Tabla')),
                  ],
                  onChanged: (v) => setState(() => _campos[idx]['tipo'] = v)),
                const SizedBox(height: 6),
                Row(children: [
                  Switch(value: c['obligatorio'] as bool? ?? false,
                    onChanged: (v) => setState(() => _campos[idx]['obligatorio'] = v),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  const SizedBox(width: 6),
                  const Text('Obligatorio', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ]),
              ])));
        }),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(child: OutlinedButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancelar'))),
        const SizedBox(width: 12),
        Expanded(child: ElevatedButton.icon(
          icon: _guardando ? const SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.save_outlined, size: 15),
          label: Text(widget.esquema == null ? 'Crear' : 'Guardar'),
          onPressed: _guardando ? null : _guardar)),
      ]),
    ])));
}

class _RolBadge extends StatelessWidget {
  final String rol;
  const _RolBadge({required this.rol});
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (rol) {
      'SUPERVISOR'           => ('Admin',     const Color(0xFF0F2447)),
      'SUPERVISOR'   => ('Líder',     const Color(0xFF7C3AED)),
      'AUDITOR' => ('Interno',   const Color(0xFF0369A1)),
      'AUDITOR' => ('Externo',   const Color(0xFF0891B2)),
      'ASESOR'       => ('Ejecutivo', const Color(0xFFB45309)),
      _                 => (rol,         AppColors.textTertiary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)));
  }
}

class _TipoBadge extends StatelessWidget {
  final String tipo;
  const _TipoBadge({required this.tipo});
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (tipo) {
      'PLANTA'   => ('Planta',   const Color(0xFF059669)),
      'CONTRATO' => ('Contrato', const Color(0xFF0369A1)),
      'EXTERNO'  => ('Externo',  const Color(0xFFB45309)),
      _          => (tipo,       AppColors.textTertiary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: color)));
  }
}
