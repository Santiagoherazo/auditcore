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
          _TabRolesPermisos(),
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
          SnackBar(content: Text(_parsearError(e)), backgroundColor: AppColors.danger));
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


String _parsearError(dynamic e) {
  try {
    final resp = (e as dynamic).response;
    if (resp != null) {
      final data = resp.data;
      if (data is Map) {
        final msgs = <String>[];
        data.forEach((k, v) {
          if (v is List) msgs.add('$k: ${v.join(", ")}');
          else if (v is String) msgs.add(v);
        });
        if (msgs.isNotEmpty) return msgs.join('\n');
      }
      if (data is String && data.isNotEmpty) return data;
      return 'Error ${resp.statusCode}';
    }
  } catch (_) {}
  return e.toString();
}

void _snack(BuildContext ctx, String msg, {bool error = false}) {
  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? AppColors.danger : AppColors.success,
    duration: Duration(seconds: error ? 6 : 3),
  ));
}

Future<bool> _confirmar(BuildContext ctx, {
  required String titulo,
  required String mensaje,
  String labelOk = 'Confirmar',
  Color colorOk = AppColors.accent,
}) async {
  final ok = await showDialog<bool>(
    context: ctx,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(titulo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      content: Text(mensaje, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: colorOk, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(labelOk)),
      ],
    ),
  );
  return ok == true;
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
  String _busqueda   = '';

  void _abrirForm({Map<String, dynamic>? u}) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _UsuarioForm(ref: widget.ref, usuarioExistente: u),
  ).then((_) => ref.invalidate(usuariosAdminProvider));

  Future<void> _cambiarEstado(Map<String, dynamic> u, bool activar) async {
    final nombre = '${u['nombre']} ${u['apellido']}';
    final ok = await _confirmar(context,
      titulo: activar ? '¿Activar cuenta?' : '¿Desactivar cuenta?',
      mensaje: activar
          ? '$nombre recuperará el acceso inmediatamente.'
          : '$nombre perderá el acceso inmediatamente. Sus tokens JWT serán revocados.',
      labelOk: activar ? 'Activar' : 'Desactivar',
      colorOk: activar ? AppColors.success : AppColors.danger,
    );
    if (!ok) return;
    try {
      final id = u['id'] as String;
      if (activar) {
        await ApiClient.instance.post('${Endpoints.usuarios}$id/activar/');
      } else {
        await ApiClient.instance.post(Endpoints.usuarioDesactivar(id));
      }
      ref.invalidate(usuariosAdminProvider);
      if (mounted) _snack(context, activar ? 'Cuenta activada.' : 'Cuenta desactivada.');
    } catch (e) {
      if (mounted) _snack(context, _parsearError(e), error: true);
    }
  }

  Future<void> _softDelete(Map<String, dynamic> u) async {
    final nombre = '${u['nombre']} ${u['apellido']}';
    final ok = await _confirmar(context,
      titulo: '¿Eliminar miembro del equipo?',
      mensaje: '$nombre será marcado como INACTIVO y no podrá iniciar sesión. '               'Puedes reactivarlo más adelante desde la misma tarjeta.',
      labelOk: 'Eliminar',
      colorOk: AppColors.danger,
    );
    if (!ok) return;
    try {
      await ApiClient.instance.delete('${Endpoints.usuarios}${u['id']}/');
      ref.invalidate(usuariosAdminProvider);
      if (mounted) _snack(context, 'Usuario desactivado (soft delete).');
    } catch (e) {
      if (mounted) _snack(context, _parsearError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(usuariosAdminProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => EmptyState(
        titulo: 'Error al cargar equipo',
        subtitulo: e.toString(),
        icono: Icons.error_outline,
        labelBoton: 'Reintentar',
        onBoton: () => ref.invalidate(usuariosAdminProvider)),
      data: (todos) {
        var lista = todos.where((u) {
          final tipo = u['tipo_contratacion'] as String? ?? '';
          final rol  = u['rol'] as String? ?? '';
          final nombre = '${u['nombre'] ?? ''} ${u['apellido'] ?? ''} ${u['email'] ?? ''}'.toLowerCase();
          if (_filtroTipo != 'TODOS' && tipo != _filtroTipo) return false;
          if (_filtroRol  != 'TODOS' && rol  != _filtroRol)  return false;
          if (_busqueda.isNotEmpty && !nombre.contains(_busqueda.toLowerCase())) return false;
          return true;
        }).toList();


        final activos  = todos.where((u) => u['estado'] == 'ACTIVO').length;
        final inactivos = todos.length - activos;
        final externos  = todos.where((u) => u['tipo_contratacion'] == 'EXTERNO').length;

        return Stack(children: [
          Column(children: [

            Container(
              color: AppColors.white,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _StatChip(label: 'Total',    valor: '${todos.length}', color: AppColors.accent),
                    const SizedBox(width: 8),
                    _StatChip(label: 'Activos',  valor: '$activos',  color: const Color(0xFF059669)),
                    const SizedBox(width: 8),
                    _StatChip(label: 'Inactivos',valor: '$inactivos', color: AppColors.textTertiary),
                    const SizedBox(width: 8),
                    _StatChip(label: 'Externos', valor: '$externos',  color: const Color(0xFFB45309)),
                  ]),
                ),
                const SizedBox(height: 12),

                TextField(
                  onChanged: (v) => setState(() => _busqueda = v),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre o email...',
                    prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textTertiary),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),

                Row(children: [
                  Expanded(child: DropdownButtonFormField<String>(
                    value: _filtroTipo,
                    style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Contratación',
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      isDense: true),
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
                    decoration: const InputDecoration(
                      labelText: 'Rol',
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'TODOS',      child: Text('Todos los roles')),
                      DropdownMenuItem(value: 'SUPERVISOR', child: Text('Supervisor')),
                      DropdownMenuItem(value: 'ASESOR',     child: Text('Asesor')),
                      DropdownMenuItem(value: 'AUDITOR',    child: Text('Auditor')),
                      DropdownMenuItem(value: 'AUXILIAR',   child: Text('Auxiliar')),
                      DropdownMenuItem(value: 'REVISOR',    child: Text('Revisor')),
                    ],
                    onChanged: (v) => setState(() => _filtroRol = v!))),
                ]),
              ]),
            ),
            const Divider(height: 1),

            Expanded(
              child: lista.isEmpty
                ? const EmptyState(
                    titulo: 'Sin resultados',
                    subtitulo: 'Ajusta los filtros o agrega un nuevo miembro.',
                    icono: Icons.group_off_outlined)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 88),
                    itemCount: lista.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _TarjetaMiembro(
                      u: lista[i],
                      onEditar:      () => _abrirForm(u: lista[i]),
                      onActivar:     () => _cambiarEstado(lista[i], true),
                      onDesactivar:  () => _cambiarEstado(lista[i], false),
                      onSoftDelete:  () => _softDelete(lista[i]),
                    ),
                  ),
            ),
          ]),

          Positioned(
            bottom: 16, right: 16,
            child: FloatingActionButton.extended(
              heroTag: 'fab_equipo',
              onPressed: () => _abrirForm(),
              icon: const Icon(Icons.person_add_outlined, size: 18),
              label: const Text('Nuevo miembro'),
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white),
          ),
        ]);
      },
    );
  }
}


class _TarjetaMiembro extends StatelessWidget {
  final Map<String, dynamic> u;
  final VoidCallback onEditar, onActivar, onDesactivar, onSoftDelete;
  const _TarjetaMiembro({
    required this.u,
    required this.onEditar,
    required this.onActivar,
    required this.onDesactivar,
    required this.onSoftDelete,
  });

  @override
  Widget build(BuildContext context) {
    final nombre  = '${u['nombre'] ?? ''} ${u['apellido'] ?? ''}'.trim();
    final email   = u['email'] as String? ?? '';
    final rol     = u['rol']   as String? ?? '';
    final estado  = u['estado'] as String? ?? '';
    final tipo    = u['tipo_contratacion'] as String? ?? '';
    final espec   = u['especialidad']     as String? ?? '';
    final docId   = u['documento_id']     as String? ?? '';
    final mfa     = u['mfa_habilitado']   == true;
    final activo  = estado == 'ACTIVO';

    return Card(
      elevation: activo ? 1 : 0,
      color: activo ? AppColors.white : AppColors.gray100,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: activo ? AppColors.border : AppColors.gray300,
          width: 1)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: activo ? AppColors.accentLight : AppColors.gray100,
              child: Text(
                nombre.isNotEmpty ? nombre[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: activo ? AppColors.accent : AppColors.textTertiary)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nombre,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: activo ? AppColors.textPrimary : AppColors.textTertiary)),
              const SizedBox(height: 2),
              Text(email,
                style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
              if (espec.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(espec,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ])),

            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'editar')     onEditar();
                else if (v == 'activar')    onActivar();
                else if (v == 'desactivar') onDesactivar();
                else if (v == 'eliminar')   onSoftDelete();
              },
              icon: const Icon(Icons.more_vert, size: 20, color: AppColors.textTertiary),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'editar',
                  child: Row(children: const [
                    Icon(Icons.edit_outlined, size: 16, color: AppColors.accent),
                    SizedBox(width: 10),
                    Text('Editar', style: TextStyle(fontSize: 13)),
                  ])),
                if (activo)
                  PopupMenuItem(
                    value: 'desactivar',
                    child: Row(children: const [
                      Icon(Icons.block_outlined, size: 16, color: AppColors.warning),
                      SizedBox(width: 10),
                      Text('Desactivar acceso', style: TextStyle(fontSize: 13, color: AppColors.warning)),
                    ]))
                else
                  PopupMenuItem(
                    value: 'activar',
                    child: Row(children: const [
                      Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF059669)),
                      SizedBox(width: 10),
                      Text('Activar acceso', style: TextStyle(fontSize: 13, color: Color(0xFF059669))),
                    ])),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'eliminar',
                  child: Row(children: const [
                    Icon(Icons.person_remove_outlined, size: 16, color: AppColors.danger),
                    SizedBox(width: 10),
                    Text('Eliminar (soft)', style: TextStyle(fontSize: 13, color: AppColors.danger)),
                  ])),
              ],
            ),
          ]),
          const SizedBox(height: 10),

          Wrap(spacing: 6, runSpacing: 4, children: [
            _RolBadge(rol: rol),
            StatusBadge(estado: estado),
            if (tipo.isNotEmpty) _TipoBadge(tipo: tipo),
            if (docId.isNotEmpty)
              _InfoChip(icono: Icons.badge_outlined, texto: docId),
            if (mfa)
              _InfoChip(
                icono: Icons.shield_outlined,
                texto: 'MFA',
                color: const Color(0xFF059669),
                bg: const Color(0xFFECFDF5)),
          ]),

          if (!activo) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onActivar,
                icon: const Icon(Icons.check_circle_outline, size: 14),
                label: const Text('Reactivar cuenta', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF059669),
                  side: const BorderSide(color: Color(0xFF059669)),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                )),
            ),
          ],
        ]),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icono;
  final String texto;
  final Color color;
  final Color bg;
  const _InfoChip({
    required this.icono,
    required this.texto,
    this.color = AppColors.textTertiary,
    this.bg    = AppColors.gray100,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icono, size: 10, color: color),
      const SizedBox(width: 4),
      Text(texto, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500)),
    ]),
  );
}

class _StatChip extends StatelessWidget {
  final String label, valor;
  final Color color;
  const _StatChip({required this.label, required this.valor, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withOpacity(0.15))),
    child: Column(children: [
      Text(valor, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
      Text(label, style: TextStyle(fontSize: 10, color: color.withOpacity(0.8), fontWeight: FontWeight.w500)),
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
  late final TextEditingController
      _emailCtrl, _nombreCtrl, _apellidoCtrl,
      _telefonoCtrl, _passCtrl, _documentoCtrl, _especialidadCtrl;
  String _rol              = 'AUDITOR';
  String _estado           = 'ACTIVO';
  String _tipoContratacion = 'PLANTA';
  bool   _guardando = false;
  bool   _verPass   = false;
  String? _error;

  static const _roles = [
    ('SUPERVISOR', 'Supervisor — Acceso total'),
    ('ASESOR',     'Asesor — Gestión comercial'),
    ('AUDITOR',    'Auditor — Ejecución de auditorías'),
    ('AUXILIAR',   'Auxiliar — Soporte operativo'),
    ('REVISOR',    'Revisor — Revisión y control'),
  ];
  static const _estados = [
    ('ACTIVO',    'Activo'),
    ('INACTIVO',  'Inactivo'),
    ('BLOQUEADO', 'Bloqueado'),
  ];
  static const _tipos = [
    ('PLANTA',    'Planta'),
    ('CONTRATO',  'Contrato'),
    ('EXTERNO',   'Externo / Freelance'),
  ];

  bool get _esEdicion => widget.usuarioExistente != null;

  @override
  void initState() {
    super.initState();
    final u = widget.usuarioExistente;
    _emailCtrl        = TextEditingController(text: u?['email']           as String? ?? '');
    _nombreCtrl       = TextEditingController(text: u?['nombre']          as String? ?? '');
    _apellidoCtrl     = TextEditingController(text: u?['apellido']        as String? ?? '');
    _telefonoCtrl     = TextEditingController(text: u?['telefono']        as String? ?? '');
    _documentoCtrl    = TextEditingController(text: u?['documento_id']    as String? ?? '');
    _especialidadCtrl = TextEditingController(text: u?['especialidad']    as String? ?? '');
    _passCtrl         = TextEditingController();
    _rol              = u?['rol']               as String? ?? 'AUDITOR';
    _estado           = u?['estado']            as String? ?? 'ACTIVO';
    _tipoContratacion = u?['tipo_contratacion'] as String? ?? 'PLANTA';
  }

  @override
  void dispose() {
    for (final c in [_emailCtrl, _nombreCtrl, _apellidoCtrl,
                     _telefonoCtrl, _passCtrl, _documentoCtrl, _especialidadCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  void _generarPassword() {
    final pwd = generarPasswordAleatoria();
    setState(() { _passCtrl.text = pwd; _verPass = true; });
    Clipboard.setData(ClipboardData(text: pwd));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Contraseña generada y copiada al portapapeles.'),
      backgroundColor: Color(0xFF059669),
      duration: Duration(seconds: 3)));
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _guardando = true; _error = null; });
    try {
      if (_esEdicion) {
        final id = widget.usuarioExistente!['id'] as String;
        final payload = <String, dynamic>{
          'nombre':            _nombreCtrl.text.trim(),
          'apellido':          _apellidoCtrl.text.trim(),
          'telefono':          _telefonoCtrl.text.trim(),
          'documento_id':      _documentoCtrl.text.trim(),
          'especialidad':      _especialidadCtrl.text.trim(),
          'tipo_contratacion': _tipoContratacion,
          'rol':               _rol,
          'estado':            _estado,
        };
        if (_passCtrl.text.isNotEmpty) payload['password'] = _passCtrl.text;
        await ApiClient.instance.patch('${Endpoints.usuarios}$id/', data: payload);
      } else {
        await ApiClient.instance.post(Endpoints.usuarios, data: {
          'email':             _emailCtrl.text.trim().toLowerCase(),
          'nombre':            _nombreCtrl.text.trim(),
          'apellido':          _apellidoCtrl.text.trim(),
          'telefono':          _telefonoCtrl.text.trim(),
          'documento_id':      _documentoCtrl.text.trim(),
          'especialidad':      _especialidadCtrl.text.trim(),
          'tipo_contratacion': _tipoContratacion,
          'rol':               _rol,
          'password':          _passCtrl.text,
        });
      }
      widget.ref.invalidate(usuariosAdminProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = _parsearError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Widget _seccion(String titulo, {IconData? icono}) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Row(children: [
      if (icono != null) ...[
        Icon(icono, size: 15, color: AppColors.accent),
        const SizedBox(width: 6),
      ],
      Text(titulo, style: const TextStyle(
        fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      const SizedBox(width: 8),
      const Expanded(child: Divider()),
    ]),
  );

  Widget _campo(String label, TextEditingController ctrl, {
    String? hint,
    String? Function(String?)? validator,
    TextInputType teclado = TextInputType.text,
    bool readOnly = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(
        fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
      const SizedBox(height: 5),
      TextFormField(
        controller: ctrl,
        keyboardType: teclado,
        readOnly: readOnly,
        style: TextStyle(fontSize: 13,
          color: readOnly ? AppColors.textTertiary : AppColors.textPrimary),
        decoration: InputDecoration(hintText: hint),
        validator: validator),
    ]),
  );

  Widget _drop<T>(String label, T value, List<(T, String)> items, void Function(T?) onChange) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
        const SizedBox(height: 5),
        DropdownButtonFormField<T>(
          value: value,
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          items: items.map((i) => DropdownMenuItem(value: i.$1, child: Text(i.$2))).toList(),
          onChanged: onChange),
      ]),
    );

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 28),
    child: Form(
      key: _form,
      child: SingleChildScrollView(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Center(child: Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.gray300,
              borderRadius: BorderRadius.circular(2)))),

          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.accentLight,
                borderRadius: BorderRadius.circular(8)),
              child: Icon(
                _esEdicion ? Icons.edit_outlined : Icons.person_add_outlined,
                size: 18, color: AppColors.accent)),
            const SizedBox(width: 12),
            Expanded(child: Text(
              _esEdicion ? 'Editar miembro' : 'Nuevo miembro del equipo',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, size: 20),
              style: IconButton.styleFrom(foregroundColor: AppColors.textSecondary)),
          ]),


          _seccion('Credenciales de acceso', icono: Icons.lock_outline),
          _campo('Email *', _emailCtrl,
            hint: 'usuario@empresa.com',
            teclado: TextInputType.emailAddress,
            readOnly: _esEdicion,
            validator: _esEdicion ? null : (v) {
              if (v == null || v.trim().isEmpty) return 'El email es requerido';
              if (!v.contains('@') || !v.contains('.')) return 'Email inválido';
              return null;
            }),


          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(
                  _esEdicion ? 'Nueva contraseña (opcional)' : 'Contraseña *',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _generarPassword,
                  icon: const Icon(Icons.auto_fix_high_outlined, size: 13),
                  label: const Text('Generar', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap)),
              ]),
              const SizedBox(height: 5),
              TextFormField(
                controller: _passCtrl,
                obscureText: !_verPass,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: _esEdicion
                    ? 'Dejar vacío para no cambiar'
                    : 'Mínimo 8 caracteres',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _verPass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 16, color: AppColors.textTertiary),
                    onPressed: () => setState(() => _verPass = !_verPass))),
                validator: _esEdicion
                  ? (v) {
                      if (v != null && v.isNotEmpty && v.length < 8) return 'Mínimo 8 caracteres';
                      return null;
                    }
                  : (v) {
                      if (v == null || v.isEmpty) return 'La contraseña es requerida';
                      if (v.length < 8) return 'Mínimo 8 caracteres';
                      return null;
                    }),
            ]),
          ),


          _seccion('Datos personales', icono: Icons.person_outline),
          Row(children: [
            Expanded(child: _campo('Nombre *', _nombreCtrl, hint: 'Carlos',
              validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null)),
            const SizedBox(width: 12),
            Expanded(child: _campo('Apellido *', _apellidoCtrl, hint: 'Gómez',
              validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null)),
          ]),
          Row(children: [
            Expanded(child: _campo('Teléfono', _telefonoCtrl,
              hint: '+57 300 000 0000', teclado: TextInputType.phone)),
            const SizedBox(width: 12),
            Expanded(child: _campo('Documento / Cédula', _documentoCtrl, hint: '12345678')),
          ]),
          _campo('Especialidad', _especialidadCtrl,
            hint: 'ISO 27001, NIIF, Calidad...'),


          _seccion('Rol y vinculación', icono: Icons.badge_outlined),
          _drop('Tipo de contratación', _tipoContratacion, _tipos,
            (v) => setState(() => _tipoContratacion = v!)),
          _drop('Rol en el sistema *', _rol, _roles,
            (v) => setState(() => _rol = v!)),

          Builder(builder: (_) {
            final desc = switch (_rol) {
              'SUPERVISOR' => 'Acceso total. Gestiona usuarios, configuración y todas las operaciones.',
              'ASESOR'     => 'Gestión comercial. Crea clientes, ve expedientes y emite reportes.',
              'AUDITOR'    => 'Ejecuta auditorías, registra hallazgos y gestiona evidencias.',
              'AUXILIAR'   => 'Soporte: ve expedientes y documentos, puede crear procedimientos.',
              'REVISOR'    => 'Solo revisión: ve toda la operación y puede exportar reportes.',
              _             => '',
            };
            return Container(
              margin: const EdgeInsets.only(bottom: 12, top: -4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.infoBg,
                borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Icon(Icons.info_outline, size: 13, color: AppColors.info),
                const SizedBox(width: 8),
                Expanded(child: Text(desc,
                  style: const TextStyle(fontSize: 11, color: AppColors.info))),
              ]),
            );
          }),
          if (_esEdicion) _drop('Estado de la cuenta', _estado, _estados,
            (v) => setState(() => _estado = v!)),


          if (_error != null)
            Container(
              margin: const EdgeInsets.only(top: 4, bottom: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.dangerBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.danger.withOpacity(0.3))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.error_outline, size: 14, color: AppColors.danger),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!,
                  style: const TextStyle(fontSize: 12, color: AppColors.danger))),
              ]),
            ),

          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: _guardando
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Icon(_esEdicion ? Icons.save_outlined : Icons.person_add_outlined, size: 16),
              label: Text(_esEdicion ? 'Guardar cambios' : 'Crear miembro'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)))),
        ],
      )),
    ),
  );
}


const _permisosBackend = <String, List<String>>{
  'SUPERVISOR': [
    'usuarios.ver', 'usuarios.crear', 'usuarios.editar', 'usuarios.eliminar',
    'clientes.ver', 'clientes.crear', 'clientes.editar',
    'expedientes.ver', 'expedientes.crear', 'expedientes.editar',
    'hallazgos.ver', 'hallazgos.crear', 'hallazgos.editar',
    'documentos.ver', 'documentos.aprobar',
    'certificaciones.ver', 'certificaciones.emitir',
    'formularios.ver', 'formularios.crear', 'formularios.editar',
    'reportes.ver', 'reportes.exportar',
    'procedimientos.ver', 'procedimientos.crear',
    'caracterizacion.ver', 'caracterizacion.aprobar',
    'acceso_temporal.crear',
  ],
  'ASESOR': [
    'clientes.ver', 'clientes.crear', 'clientes.editar',
    'expedientes.ver',
    'certificaciones.ver',
    'formularios.ver',
    'reportes.ver',
    'caracterizacion.ver',
    'acceso_temporal.crear',
  ],
  'AUDITOR': [
    'clientes.ver',
    'expedientes.ver', 'expedientes.crear', 'expedientes.editar',
    'hallazgos.ver', 'hallazgos.crear', 'hallazgos.editar',
    'documentos.ver', 'documentos.aprobar',
    'certificaciones.ver', 'certificaciones.emitir',
    'formularios.ver',
    'procedimientos.ver', 'procedimientos.crear',
    'reportes.ver',
  ],
  'AUXILIAR': [
    'expedientes.ver',
    'hallazgos.ver',
    'documentos.ver',
    'formularios.ver',
    'procedimientos.ver', 'procedimientos.crear',
    'reportes.ver',
  ],
  'REVISOR': [
    'clientes.ver',
    'expedientes.ver',
    'hallazgos.ver',
    'documentos.ver',
    'certificaciones.ver',
    'formularios.ver',
    'procedimientos.ver',
    'reportes.ver', 'reportes.exportar',
  ],
  'CLIENTE': [
    'expedientes.ver_propio',
    'certificaciones.ver_propio',
    'documentos.ver_propio',
    'reportes.ver_propio',
    'caracterizacion.llenar',
  ],
};

const _todosLosPermisos = [
  ('usuarios.ver',               'Usuarios: Ver',              Icons.people_outlined),
  ('usuarios.crear',             'Usuarios: Crear',            Icons.person_add_outlined),
  ('usuarios.editar',            'Usuarios: Editar',           Icons.edit_outlined),
  ('usuarios.eliminar',          'Usuarios: Eliminar',         Icons.person_remove_outlined),
  ('clientes.ver',               'Clientes: Ver',              Icons.business_center_outlined),
  ('clientes.crear',             'Clientes: Crear',            Icons.add_business_outlined),
  ('clientes.editar',            'Clientes: Editar',           Icons.business_outlined),
  ('expedientes.ver',            'Expedientes: Ver',           Icons.folder_open_outlined),
  ('expedientes.crear',          'Expedientes: Crear',         Icons.create_new_folder_outlined),
  ('expedientes.editar',         'Expedientes: Editar',        Icons.folder_outlined),
  ('hallazgos.ver',              'Hallazgos: Ver',             Icons.warning_amber_outlined),
  ('hallazgos.crear',            'Hallazgos: Crear',           Icons.add_alert_outlined),
  ('hallazgos.editar',           'Hallazgos: Editar',          Icons.edit_note_outlined),
  ('documentos.ver',             'Documentos: Ver',            Icons.description_outlined),
  ('documentos.aprobar',         'Documentos: Aprobar',        Icons.verified_outlined),
  ('certificaciones.ver',        'Certificaciones: Ver',       Icons.workspace_premium_outlined),
  ('certificaciones.emitir',     'Certificaciones: Emitir',    Icons.card_membership_outlined),
  ('formularios.ver',            'Formularios: Ver',           Icons.dynamic_form_outlined),
  ('formularios.crear',          'Formularios: Crear',         Icons.post_add_outlined),
  ('formularios.editar',         'Formularios: Editar',        Icons.edit_document),
  ('reportes.ver',               'Reportes: Ver',              Icons.table_chart_outlined),
  ('reportes.exportar',          'Reportes: Exportar',         Icons.download_outlined),
  ('procedimientos.ver',         'Procedimientos: Ver',        Icons.assignment_outlined),
  ('procedimientos.crear',       'Procedimientos: Crear',      Icons.assignment_add),
  ('caracterizacion.ver',        'Caracterización: Ver',       Icons.manage_search_outlined),
  ('caracterizacion.aprobar',    'Caracterización: Aprobar',   Icons.fact_check_outlined),
  ('acceso_temporal.crear',      'Acceso temporal: Crear',     Icons.link_outlined),
  ('expedientes.ver_propio',     'Mis expedientes',            Icons.folder_shared_outlined),
  ('certificaciones.ver_propio', 'Mis certificaciones',        Icons.card_membership_outlined),
  ('documentos.ver_propio',      'Mis documentos',             Icons.folder_copy_outlined),
  ('reportes.ver_propio',        'Mis reportes',               Icons.summarize_outlined),
  ('caracterizacion.llenar',     'Llenar caracterización',     Icons.edit_note_outlined),
];

const _rolesInfo = <(String, Color, String)>[
  ('SUPERVISOR', Color(0xFF0F2447), 'Acceso total. Gestiona usuarios, tipos de auditoría, formularios y toda la configuración.'),
  ('ASESOR',     Color(0xFFB45309), 'Gestión comercial. Crea clientes, ve expedientes, vencimientos de certificaciones y emite reportes.'),
  ('AUDITOR',    Color(0xFF0369A1), 'Ejecuta auditorías. Registra hallazgos, sube evidencias y gestiona sus expedientes asignados.'),
  ('AUXILIAR',   Color(0xFF0891B2), 'Soporte operativo. Ve expedientes y documentos; puede crear procedimientos.'),
  ('REVISOR',    Color(0xFF059669), 'Revisión y control. Ve toda la operación y puede exportar reportes.'),
  ('CLIENTE',    Color(0xFF6B7280), 'Portal externo. Acceso de solo lectura a sus propios expedientes y certificaciones.'),
];


final _rolesUsuariosProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final resp = await ApiClient.instance.get(Endpoints.usuarios);
  final data = resp.data;
  final lista = data is Map ? (data['results'] as List? ?? []) : (data as List? ?? []);
  return lista.cast<Map<String, dynamic>>();
});


class _TabRolesPermisos extends ConsumerStatefulWidget {
  const _TabRolesPermisos();
  @override
  ConsumerState<_TabRolesPermisos> createState() => _TabRolesPermisosState();
}

class _TabRolesPermisosState extends ConsumerState<_TabRolesPermisos> {
  int _subPestana = 0;
  String? _rolSeleccionado;
  bool _guardando = false;
  String? _usuarioEditandoId;
  Set<String> _permisosExtra = {};

  @override
  void initState() {
    super.initState();
    _rolSeleccionado = _rolesInfo.first.$1;
  }

  @override
  void dispose() { super.dispose(); }

  List<String> _permisosDelRol(String rol) =>
      List<String>.from(_permisosBackend[rol] ?? []);

  Future<void> _guardarPermisosExtra(String usuarioId) async {
    setState(() => _guardando = true);
    try {
      await ApiClient.instance.patch(
        '${Endpoints.usuarios}$usuarioId/',
        data: {'permisos_extra': _permisosExtra.toList()},
      );
      ref.invalidate(_rolesUsuariosProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Permisos adicionales guardados.'),
          backgroundColor: Color(0xFF059669)));
        setState(() { _usuarioEditandoId = null; _permisosExtra = {}; });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_parsearError(e)), backgroundColor: AppColors.danger));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _abrirEditorUsuario(Map<String, dynamic> u) {
    final extras = List<String>.from(u['permisos_extra'] as List? ?? []);
    setState(() {
      _usuarioEditandoId = u['id'] as String?;
      _permisosExtra = extras.toSet();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [


      Container(
        color: AppColors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          _SubTab(
            label: 'Matriz de Roles',
            activo: _subPestana == 0,
            onTap: () => setState(() => _subPestana = 0),
          ),
          const SizedBox(width: 8),
          _SubTab(
            label: 'Permisos por Usuario',
            activo: _subPestana == 1,
            onTap: () => setState(() => _subPestana = 1),
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: IndexedStack(
          index: _subPestana,
          children: [
            _buildMatrizRoles(),
            _buildPermisosUsuarios(),
          ],
        ),
      ),
    ]);
  }


  Widget _buildMatrizRoles() {
    final rolesKeys = _rolesInfo.map((r) => r.$1).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        const Text('Selecciona un rol para ver sus permisos',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: _rolesInfo.map((r) {
            final sel = _rolSeleccionado == r.$1;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _rolSeleccionado = r.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? r.$2 : r.$2.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: r.$2.withOpacity(sel ? 1 : 0.3)),
                  ),
                  child: Text(r.$1,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                        color: sel ? Colors.white : r.$2)),
                ),
              ),
            );
          }).toList()),
        ),

        if (_rolSeleccionado != null) ...[
          const SizedBox(height: 20),

          Builder(builder: (_) {
            final info = _rolesInfo.firstWhere((r) => r.$1 == _rolSeleccionado);
            return Card(
              color: info.$2.withOpacity(0.06),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: info.$2.withOpacity(0.2)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: info.$2, borderRadius: BorderRadius.circular(8)),
                    child: Text(info.$1,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(info.$3,
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary,
                        height: 1.5))),
                ]),
              ),
            );
          }),

          const SizedBox(height: 14),
          const Text('Permisos asignados a este rol',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 8),

          Builder(builder: (_) {
            final perms = _permisosDelRol(_rolSeleccionado!);
            final grupos = <String, List<(String, String, IconData)>>{};
            for (final p in _todosLosPermisos) {
              final grupo = p.$1.split('.').first;
              grupos.putIfAbsent(grupo, () => []).add(p);
            }
            return Column(children: grupos.entries.map((entry) {
              final tieneAlguno = entry.value.any((p) => perms.contains(p.$1));
              return Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      _nombreGrupo(entry.key),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6, runSpacing: 6,
                      children: entry.value.map((p) {
                        final tiene = perms.contains(p.$1);
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: tiene
                                ? const Color(0xFFECFDF5)
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: tiene
                                  ? const Color(0xFF059669).withOpacity(0.3)
                                  : AppColors.border),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(
                              tiene ? Icons.check_circle : Icons.radio_button_unchecked,
                              size: 12,
                              color: tiene
                                  ? const Color(0xFF059669)
                                  : AppColors.textTertiary),
                            const SizedBox(width: 5),
                            Text(p.$2,
                              style: TextStyle(
                                fontSize: 11,
                                color: tiene
                                    ? const Color(0xFF059669)
                                    : AppColors.textTertiary,
                                fontWeight: tiene
                                    ? FontWeight.w500
                                    : FontWeight.w400)),
                          ]),
                        );
                      }).toList(),
                    ),
                  ]),
                ),
              );
            }).toList());
          }),

          const SizedBox(height: 20),

          const Text('Comparativa de todos los roles',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          Card(child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const SizedBox(width: 180),
                  ...rolesKeys.map((r) {
                    final info = _rolesInfo.firstWhere((x) => x.$1 == r);
                    return SizedBox(
                      width: 66,
                      child: Center(child: Text(r,
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                            color: info.$2))),
                    );
                  }),
                ]),
                const Divider(height: 10),
                ..._todosLosPermisos.map((p) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    SizedBox(width: 180, child: Row(children: [
                      Icon(p.$3, size: 11, color: AppColors.textTertiary),
                      const SizedBox(width: 5),
                      Flexible(child: Text(p.$2,
                        style: const TextStyle(fontSize: 10, color: AppColors.textPrimary),
                        overflow: TextOverflow.ellipsis)),
                    ])),
                    ...rolesKeys.map((r) {
                      final tiene = (_permisosBackend[r] ?? []).contains(p.$1);
                      return SizedBox(width: 66, child: Center(child: Icon(
                        tiene ? Icons.check_circle : Icons.remove,
                        size: 14,
                        color: tiene
                            ? const Color(0xFF059669)
                            : const Color(0xFFE2E8F0))));
                    }),
                  ]),
                )),
              ]),
            ),
          )),
        ],
      ]),
    );
  }


  Widget _buildPermisosUsuarios() {
    final asyncUsuarios = ref.watch(_rolesUsuariosProvider);

    if (_usuarioEditandoId != null) {

      return asyncUsuarios.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(titulo: 'Error', subtitulo: e.toString(),
            icono: Icons.error_outline),
        data: (usuarios) {
          final u = usuarios.firstWhere(
            (x) => x['id'] == _usuarioEditandoId,
            orElse: () => {},
          );
          if (u.isEmpty) return const SizedBox();
          final rol = u['rol'] as String? ?? '';
          final basePerms = _permisosDelRol(rol).toSet();
          final nombre = '${u['nombre'] ?? ''} ${u['apellido'] ?? ''}'.trim();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                IconButton(
                  onPressed: () => setState(() {
                    _usuarioEditandoId = null;
                    _permisosExtra = {};
                  }),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  style: IconButton.styleFrom(foregroundColor: AppColors.textSecondary)),
                const SizedBox(width: 4),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(nombre,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                  Row(children: [
                    _RolBadge(rol: rol),
                    const SizedBox(width: 6),
                    Text('Permisos adicionales al rol base',
                      style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                  ]),
                ])),
              ]),

              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.infoBg,
                    borderRadius: BorderRadius.circular(8)),
                child: Row(children: const [
                  Icon(Icons.info_outline, size: 14, color: AppColors.info),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                    'Los permisos marcados en gris ya están incluidos en el rol base. '
                    'Activa los adicionales que quieres agregar a este usuario específicamente.',
                    style: TextStyle(fontSize: 11, color: AppColors.info, height: 1.4))),
                ]),
              ),
              const SizedBox(height: 16),


              ...() {
                final grupos = <String, List<(String, String, IconData)>>{};
                for (final p in _todosLosPermisos) {
                  final grupo = p.$1.split('.').first;
                  grupos.putIfAbsent(grupo, () => []).add(p);
                }
                return grupos.entries.map((entry) => Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_nombreGrupo(entry.key),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary, letterSpacing: 0.5)),
                      const SizedBox(height: 8),
                      ...entry.value.map((p) {
                        final esBase  = basePerms.contains(p.$1);
                        final esExtra = _permisosExtra.contains(p.$1);
                        final activo  = esBase || esExtra;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: esBase ? null : () {
                              setState(() {
                                if (esExtra) {
                                  _permisosExtra.remove(p.$1);
                                } else {
                                  _permisosExtra.add(p.$1);
                                }
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                color: esBase
                                    ? const Color(0xFFF8FAFC)
                                    : esExtra
                                        ? const Color(0xFFF0FDF4)
                                        : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(children: [
                                Icon(p.$3, size: 14,
                                  color: activo
                                      ? const Color(0xFF059669)
                                      : AppColors.textTertiary),
                                const SizedBox(width: 10),
                                Expanded(child: Text(p.$2,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: activo
                                        ? AppColors.textPrimary
                                        : AppColors.textTertiary))),
                                if (esBase)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(4)),
                                    child: const Text('base',
                                      style: TextStyle(fontSize: 9,
                                          color: AppColors.textTertiary)))
                                else
                                  Switch(
                                    value: esExtra,
                                    onChanged: (_) {
                                      setState(() {
                                        if (esExtra) {
                                          _permisosExtra.remove(p.$1);
                                        } else {
                                          _permisosExtra.add(p.$1);
                                        }
                                      });
                                    },
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                              ]),
                            ),
                          ),
                        );
                      }),
                    ]),
                  ),
                ));
              }(),

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _guardando
                      ? null
                      : () => _guardarPermisosExtra(_usuarioEditandoId!),
                  icon: _guardando
                      ? const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.save_outlined, size: 16),
                  label: const Text('Guardar permisos adicionales'),
                ),
              ),
            ]),
          );
        },
      );
    }


    return asyncUsuarios.when(
      loading: () => const Center(child: SizedBox(width: 24, height: 24,
          child: CircularProgressIndicator(strokeWidth: 2))),
      error: (e, _) => EmptyState(titulo: 'Error', subtitulo: e.toString(),
          icono: Icons.error_outline, labelBoton: 'Reintentar',
          onBoton: () => ref.invalidate(_rolesUsuariosProvider)),
      data: (usuarios) {
        if (usuarios.isEmpty) {
          return const EmptyState(
              titulo: 'Sin usuarios',
              subtitulo: 'Crea usuarios desde la pestaña Usuarios.',
              icono: Icons.people_outline);
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
          itemCount: usuarios.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (_, i) {
            final u = usuarios[i];
            final rol = u['rol'] as String? ?? '';
            final nombre =
                '${u['nombre'] ?? ''} ${u['apellido'] ?? ''}'.trim();
            final extras =
                List<String>.from(u['permisos_extra'] as List? ?? []);
            final efectivos =
                List<String>.from(u['permisos_efectivos'] as List? ?? []);
            return Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                child: Row(children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.accentLight,
                    child: Text(
                      nombre.isNotEmpty ? nombre[0].toUpperCase() : '?',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(nombre,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 3),
                    Row(children: [
                      _RolBadge(rol: rol),
                      const SizedBox(width: 6),
                      Text(
                        '${efectivos.length} permisos'
                        '${extras.isNotEmpty ? " (+${extras.length} extra)" : ""}',
                        style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textTertiary)),
                    ]),
                    if (extras.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          ...extras.take(3).map((p) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0FDF4),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: const Color(0xFF059669)
                                      .withOpacity(0.2))),
                            child: Text(p,
                              style: const TextStyle(
                                  fontSize: 9,
                                  color: Color(0xFF059669))),
                          )),
                          if (extras.length > 3)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0FDF4),
                                borderRadius: BorderRadius.circular(4)),
                              child: Text('+${extras.length - 3} más',
                                style: const TextStyle(
                                    fontSize: 9,
                                    color: Color(0xFF059669)))),
                        ],
                      ),
                    ],
                  ])),
                  IconButton(
                    onPressed: () => _abrirEditorUsuario(u),
                    icon: const Icon(Icons.tune_outlined, size: 18),
                    tooltip: 'Editar permisos adicionales',
                    style: IconButton.styleFrom(
                        foregroundColor: AppColors.accent)),
                ]),
              ),
            );
          },
        );
      },
    );
  }

  String _nombreGrupo(String key) => switch (key) {
    'usuarios'         => 'USUARIOS',
    'clientes'         => 'CLIENTES',
    'expedientes'      => 'EXPEDIENTES',
    'hallazgos'        => 'HALLAZGOS',
    'documentos'       => 'DOCUMENTOS',
    'certificaciones'  => 'CERTIFICACIONES',
    'formularios'      => 'FORMULARIOS',
    'reportes'         => 'REPORTES',
    'procedimientos'   => 'PROCEDIMIENTOS',
    'caracterizacion'  => 'CARACTERIZACIÓN',
    'acceso_temporal'  => 'ACCESO TEMPORAL',
    _                  => key.toUpperCase(),
  };
}


class _SubTab extends StatelessWidget {
  final String label;
  final bool activo;
  final VoidCallback onTap;
  const _SubTab({required this.label, required this.activo, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: activo ? AppColors.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: activo ? AppColors.accent : AppColors.border),
      ),
      child: Text(label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: activo ? Colors.white : AppColors.textSecondary)),
    ),
  );
}


class _TabTiposAuditoria extends ConsumerStatefulWidget {
  final WidgetRef ref;
  const _TabTiposAuditoria({required this.ref});
  @override
  ConsumerState<_TabTiposAuditoria> createState() => _TabTiposAuditoriaState();
}

class _TabTiposAuditoriaState extends ConsumerState<_TabTiposAuditoria> {
  String _busqueda = '';
  bool _soloActivos = true;
  bool _cargandoSeed = false;

  Future<void> _cargarSeed() async {
    final ok = await _confirmar(context,
      titulo: '¿Cargar tipos de demostración?',
      mensaje: 'Se crearán ISO 27001, ISO 9001, SOC 2 e ISO 45001 con sus fases, '
               'checklist y documentos. Los que ya existan no se modificarán.',
      labelOk: 'Cargar',
      colorOk: AppColors.accent,
    );
    if (!ok || !mounted) return;
    setState(() => _cargandoSeed = true);
    try {
      final resp = await ApiClient.instance.post(Endpoints.administracionSeed);
      widget.ref.invalidate(tiposAuditoriaAdminProvider);
      if (mounted) _snack(context, (resp.data['detail'] as String?) ?? 'Datos cargados.');
    } catch (e) {
      if (mounted) _snack(context, _parsearError(e), error: true);
    } finally {
      if (mounted) setState(() => _cargandoSeed = false);
    }
  }

  void _abrirForm({Map<String, dynamic>? tipo}) => showModalBottomSheet(
    context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
    builder: (_) => _TipoAuditoriaForm(ref: widget.ref, tipo: tipo))
    .then((_) => widget.ref.invalidate(tiposAuditoriaAdminProvider));

  void _verDetalle(Map<String, dynamic> tipo) => showModalBottomSheet(
    context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
    builder: (_) => _TipoAuditoriaDetalle(ref: widget.ref, tipo: tipo))
    .then((_) => widget.ref.invalidate(tiposAuditoriaAdminProvider));

  Future<void> _toggleActivo(Map<String, dynamic> tipo) async {
    final activo = tipo['activo'] as bool? ?? true;
    final nombre = tipo['nombre'] as String? ?? '';
    final ok = await _confirmar(context,
      titulo: activo ? '¿Desactivar tipo?' : '¿Activar tipo?',
      mensaje: activo
        ? '$nombre dejará de aparecer en el formulario de clientes.'
        : '$nombre volverá a estar disponible para selección.',
      labelOk: activo ? 'Desactivar' : 'Activar',
      colorOk: activo ? AppColors.danger : AppColors.success);
    if (!ok || !mounted) return;
    try {
      await ApiClient.instance.patch(
        Endpoints.tipoAuditoria(tipo['id'] as String),
        data: {'activo': !activo});
      widget.ref.invalidate(tiposAuditoriaAdminProvider);
      if (mounted) _snack(context, activo ? 'Tipo desactivado.' : 'Tipo activado.');
    } catch (e) {
      if (mounted) _snack(context, _parsearError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = widget.ref.watch(tiposAuditoriaAdminProvider);
    return async.when(
      loading: () => const Center(child: SizedBox(width: 24, height: 24,
          child: CircularProgressIndicator(strokeWidth: 2))),
      error: (e, _) => EmptyState(titulo: 'Error', subtitulo: e.toString(),
          icono: Icons.error_outline, labelBoton: 'Reintentar',
          onBoton: () => widget.ref.invalidate(tiposAuditoriaAdminProvider)),
      data: (todos) {

        final lista = todos.where((t) {
          final activo = t['activo'] as bool? ?? true;
          final nombre = '${t['nombre'] ?? ''} ${t['codigo'] ?? ''}'.toLowerCase();
          if (_soloActivos && !activo) return false;
          if (_busqueda.isNotEmpty && !nombre.contains(_busqueda.toLowerCase())) return false;
          return true;
        }).toList();

        final totalActivos = todos.where((t) => t['activo'] == true).length;
        final totalInactivos = todos.length - totalActivos;

        return Stack(children: [
          Column(children: [

            Container(
              color: AppColors.white,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  _StatChip(label: 'Total',    valor: '${todos.length}', color: AppColors.accent),
                  const SizedBox(width: 8),
                  _StatChip(label: 'Activos',  valor: '$totalActivos',   color: const Color(0xFF059669)),
                  const SizedBox(width: 8),
                  _StatChip(label: 'Inactivos',valor: '$totalInactivos', color: AppColors.textTertiary),
                ]),
                const SizedBox(height: 12),
                TextField(
                  onChanged: (v) => setState(() => _busqueda = v),
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'Buscar por nombre o código...',
                    prefixIcon: Icon(Icons.search, size: 18, color: AppColors.textTertiary),
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                    isDense: true)),
                const SizedBox(height: 8),
                Row(children: [
                  Switch(
                    value: _soloActivos,
                    onChanged: (v) => setState(() => _soloActivos = v),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  const SizedBox(width: 6),
                  const Text('Solo activos', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ]),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: lista.isEmpty
                ? EmptyState(
                    titulo: 'Sin tipos de auditoría',
                    subtitulo: todos.isEmpty
                        ? 'Crea el primer tipo para comenzar.'
                        : 'No hay resultados con los filtros actuales.',
                    icono: Icons.assignment_outlined,
                    labelBoton: 'Crear tipo',
                    onBoton: () => _abrirForm())
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 88),
                    itemCount: lista.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _TarjetaTipoAuditoria(
                      tipo: lista[i],
                      onEditar:  () => _abrirForm(tipo: lista[i]),
                      onDetalle: () => _verDetalle(lista[i]),
                      onToggle:  () => _toggleActivo(lista[i]),
                    )),
            ),
          ]),
          Positioned(bottom: 16, right: 16,
            child: Column(mainAxisSize: MainAxisSize.min, children: [

              if (todos.isEmpty) ...[
                FloatingActionButton.small(
                  heroTag: 'fab_seed_tipos',
                  onPressed: _cargandoSeed ? null : _cargarSeed,
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  tooltip: 'Cargar datos de demostración',
                  child: _cargandoSeed
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.auto_awesome_outlined, size: 18)),
                const SizedBox(height: 10),
              ],
              FloatingActionButton.extended(
                heroTag: 'fab_tipos',
                onPressed: () => _abrirForm(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nuevo tipo'),
                backgroundColor: AppColors.accent, foregroundColor: Colors.white),
            ])),
        ]);
      },
    );
  }
}


class _TarjetaTipoAuditoria extends StatelessWidget {
  final Map<String, dynamic> tipo;
  final VoidCallback onEditar, onDetalle, onToggle;
  const _TarjetaTipoAuditoria({
    required this.tipo, required this.onEditar,
    required this.onDetalle, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final activo   = tipo['activo'] as bool? ?? true;
    final codigo   = tipo['codigo'] as String? ?? '';
    final nombre   = tipo['nombre'] as String? ?? '';
    final nivel    = tipo['nivel'] as String? ?? '';
    final cat      = tipo['categoria'] as String? ?? '';
    final fases    = (tipo['fases'] as List? ?? []).length;
    final checks   = (tipo['checklist_items'] as List? ?? []).length;
    final docs     = (tipo['documentos_requeridos'] as List? ?? []).length;
    final dias     = tipo['duracion_estimada_dias'] as int? ?? 0;
    final certTipo = tipo['certificacion_tipo'] as String? ?? '';

    final catColor = switch (cat) {
      'SEGURIDAD'   => const Color(0xFF0369A1),
      'CALIDAD'     => const Color(0xFF059669),
      'AMBIENTAL'   => const Color(0xFF15803D),
      'FINANCIERO'  => const Color(0xFFB45309),
      _             => AppColors.textTertiary,
    };

    return Card(
      elevation: activo ? 1 : 0,
      color: activo ? AppColors.white : AppColors.gray100,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: activo ? AppColors.border : AppColors.gray300)),
      child: InkWell(
        onTap: onDetalle,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: catColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6)),
                child: Text(codigo,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: catColor))),
              const SizedBox(width: 8),
              Expanded(child: Text(nombre,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: activo ? AppColors.textPrimary : AppColors.textTertiary))),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'editar')  onEditar();
                  else if (v == 'detalle') onDetalle();
                  else if (v == 'toggle')  onToggle();
                },
                icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textTertiary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'detalle', child: Row(children: const [
                    Icon(Icons.visibility_outlined, size: 15, color: AppColors.accent),
                    SizedBox(width: 8), Text('Ver fases y checklist', style: TextStyle(fontSize: 13))])),
                  PopupMenuItem(value: 'editar', child: Row(children: const [
                    Icon(Icons.edit_outlined, size: 15),
                    SizedBox(width: 8), Text('Editar', style: TextStyle(fontSize: 13))])),
                  const PopupMenuDivider(),
                  PopupMenuItem(value: 'toggle', child: Row(children: [
                    Icon(activo ? Icons.toggle_off_outlined : Icons.toggle_on_outlined,
                        size: 15, color: activo ? AppColors.danger : AppColors.success),
                    const SizedBox(width: 8),
                    Text(activo ? 'Desactivar' : 'Activar',
                        style: TextStyle(fontSize: 13,
                            color: activo ? AppColors.danger : AppColors.success))])),
                ]),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 4, children: [
              _NivelBadge(nivel: nivel),
              _CertBadge(cert: certTipo),
              _InfoChip(icono: Icons.calendar_today_outlined, texto: '$dias días'),
            ]),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(children: [
              _MiniStat(icono: Icons.linear_scale_outlined, valor: fases, label: 'fases'),
              const SizedBox(width: 16),
              _MiniStat(icono: Icons.checklist_outlined, valor: checks, label: 'checklist'),
              const SizedBox(width: 16),
              _MiniStat(icono: Icons.description_outlined, valor: docs, label: 'documentos'),
              const Spacer(),
              if (!activo)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.dangerBg, borderRadius: BorderRadius.circular(8)),
                  child: const Text('Inactivo',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppColors.danger))),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icono;
  final int valor;
  final String label;
  const _MiniStat({required this.icono, required this.valor, required this.label});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icono, size: 12, color: AppColors.textTertiary),
    const SizedBox(width: 4),
    Text('$valor $label', style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
  ]);
}

class _NivelBadge extends StatelessWidget {
  final String nivel;
  const _NivelBadge({required this.nivel});
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (nivel) {
      'BASICO'      => ('Básico',      const Color(0xFF059669)),
      'INTERMEDIO'  => ('Intermedio',  const Color(0xFF0369A1)),
      'AVANZADO'    => ('Avanzado',    const Color(0xFF7C3AED)),
      _             => (nivel,         AppColors.textTertiary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)));
  }
}

class _CertBadge extends StatelessWidget {
  final String cert;
  const _CertBadge({required this.cert});
  @override
  Widget build(BuildContext context) {
    final label = switch (cert) { 'PROPIA' => 'Propia', 'EXTERNA' => 'Externa', 'AMBAS' => 'Ambas', _ => cert };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)));
  }
}


class _TipoAuditoriaForm extends ConsumerStatefulWidget {
  final Map<String, dynamic>? tipo;
  final WidgetRef ref;
  const _TipoAuditoriaForm({required this.ref, this.tipo});
  @override
  ConsumerState<_TipoAuditoriaForm> createState() => _TipoAuditoriaFormState();
}

class _TipoAuditoriaFormState extends ConsumerState<_TipoAuditoriaForm> {
  final _form      = GlobalKey<FormState>();
  late final TextEditingController _codigoCtrl, _nombreCtrl, _descCtrl,
      _versionCtrl, _diasCtrl;
  String  _categoria     = 'OTRO';
  String  _nivel         = 'BASICO';
  String  _certTipo      = 'PROPIA';
  bool    _activo        = true;
  bool    _guardando     = false;
  String? _error;

  bool get _esEdicion => widget.tipo != null;

  static const _categorias = [
    ('SEGURIDAD',  'Seguridad'),  ('CALIDAD',   'Calidad'),
    ('AMBIENTAL',  'Ambiental'),  ('FINANCIERO','Financiero'), ('OTRO','Otro'),
  ];
  static const _niveles = [
    ('BASICO','Básico'), ('INTERMEDIO','Intermedio'), ('AVANZADO','Avanzado'),
  ];
  static const _certs = [
    ('PROPIA','Propia'), ('EXTERNA','Externa'), ('AMBAS','Ambas'),
  ];

  @override
  void initState() {
    super.initState();
    final t = widget.tipo;
    _codigoCtrl  = TextEditingController(text: t?['codigo']   as String? ?? '');
    _nombreCtrl  = TextEditingController(text: t?['nombre']   as String? ?? '');
    _descCtrl    = TextEditingController(text: t?['descripcion'] as String? ?? '');
    _versionCtrl = TextEditingController(text: t?['version']  as String? ?? '1.0');
    _diasCtrl    = TextEditingController(
        text: (t?['duracion_estimada_dias'] as int? ?? 30).toString());
    _categoria   = t?['categoria']         as String? ?? 'OTRO';
    _nivel       = t?['nivel']             as String? ?? 'BASICO';
    _certTipo    = t?['certificacion_tipo'] as String? ?? 'PROPIA';
    _activo      = t?['activo']            as bool?   ?? true;
  }

  @override
  void dispose() {
    for (final c in [_codigoCtrl, _nombreCtrl, _descCtrl, _versionCtrl, _diasCtrl]) c.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _guardando = true; _error = null; });
    try {
      final payload = {
        'codigo':                 _codigoCtrl.text.trim().toUpperCase(),
        'nombre':                 _nombreCtrl.text.trim(),
        'descripcion':            _descCtrl.text.trim(),
        'version':                _versionCtrl.text.trim(),
        'duracion_estimada_dias': int.tryParse(_diasCtrl.text.trim()) ?? 30,
        'categoria':              _categoria,
        'nivel':                  _nivel,
        'certificacion_tipo':     _certTipo,
        'activo':                 _activo,
      };
      if (_esEdicion) {
        await ApiClient.instance.patch(
          Endpoints.tipoAuditoria(widget.tipo!['id'] as String), data: payload);
      } else {
        await ApiClient.instance.post(Endpoints.tiposAuditoria, data: payload);
      }
      widget.ref.invalidate(tiposAuditoriaAdminProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = _parsearError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Widget _campo(String label, TextEditingController ctrl, {
    String? hint, String? Function(String?)? validator,
    TextInputType teclado = TextInputType.text, int maxLines = 1}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
            color: AppColors.textSecondary)),
        const SizedBox(height: 5),
        TextFormField(controller: ctrl, keyboardType: teclado, maxLines: maxLines,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(hintText: hint),
          validator: validator),
      ]));

  Widget _drop<T>(String label, T value, List<(T, String)> items, void Function(T?) fn) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
            color: AppColors.textSecondary)),
        const SizedBox(height: 5),
        DropdownButtonFormField<T>(
          value: value,
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          items: items.map((i) => DropdownMenuItem(value: i.$1, child: Text(i.$2))).toList(),
          onChanged: fn),
      ]));

  Widget _seccion(String titulo, {IconData? icono}) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 10),
    child: Row(children: [
      if (icono != null) ...[Icon(icono, size: 15, color: AppColors.accent), const SizedBox(width: 6)],
      Text(titulo, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      const SizedBox(width: 8), const Expanded(child: Divider()),
    ]));

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 28),
    child: Form(key: _form, child: SingleChildScrollView(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: AppColors.gray300, borderRadius: BorderRadius.circular(2)))),
        Row(children: [
          Container(padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppColors.accentLight, borderRadius: BorderRadius.circular(8)),
            child: Icon(_esEdicion ? Icons.edit_outlined : Icons.add_box_outlined,
                size: 18, color: AppColors.accent)),
          const SizedBox(width: 12),
          Expanded(child: Text(_esEdicion ? 'Editar tipo de auditoría' : 'Nuevo tipo de auditoría',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          IconButton(onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, size: 20),
              style: IconButton.styleFrom(foregroundColor: AppColors.textSecondary)),
        ]),

        _seccion('Identificación', icono: Icons.tag_outlined),
        Row(children: [
          SizedBox(width: 120, child: _campo('Código *', _codigoCtrl, hint: 'ISO27001',
            validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null)),
          const SizedBox(width: 12),
          Expanded(child: _campo('Versión', _versionCtrl, hint: '1.0')),
        ]),
        _campo('Nombre *', _nombreCtrl, hint: 'Ej: Auditoría ISO 27001',
          validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null),
        _campo('Descripción', _descCtrl, hint: 'Objetivo y alcance del tipo de auditoría',
          maxLines: 3),

        _seccion('Clasificación', icono: Icons.category_outlined),
        _drop('Categoría', _categoria, _categorias, (v) => setState(() => _categoria = v!)),
        _drop('Nivel de complejidad', _nivel, _niveles, (v) => setState(() => _nivel = v!)),
        _drop('Tipo de certificación', _certTipo, _certs, (v) => setState(() => _certTipo = v!)),

        _seccion('Duración', icono: Icons.schedule_outlined),
        _campo('Duración estimada (días) *', _diasCtrl, hint: '30',
          teclado: TextInputType.number,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Requerido';
            if (int.tryParse(v.trim()) == null) return 'Número inválido';
            return null;
          }),

        if (_esEdicion) ...[
          _seccion('Estado', icono: Icons.toggle_on_outlined),
          Row(children: [
            Switch(value: _activo, onChanged: (v) => setState(() => _activo = v),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
            const SizedBox(width: 8),
            Text(_activo ? 'Activo — disponible para selección' : 'Inactivo — no aparece en formularios',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ]),
        ],

        if (_error != null)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.dangerBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.danger.withOpacity(0.3))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.error_outline, size: 14, color: AppColors.danger),
              const SizedBox(width: 8),
              Expanded(child: Text(_error!,
                  style: const TextStyle(fontSize: 12, color: AppColors.danger))),
            ])),

        const SizedBox(height: 20),
        SizedBox(width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _guardando ? null : _guardar,
            icon: _guardando
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Icon(_esEdicion ? Icons.save_outlined : Icons.add, size: 16),
            label: Text(_esEdicion ? 'Guardar cambios' : 'Crear tipo'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)))),
      ]))),
  );
}


class _TipoAuditoriaDetalle extends ConsumerStatefulWidget {
  final Map<String, dynamic> tipo;
  final WidgetRef ref;
  const _TipoAuditoriaDetalle({required this.ref, required this.tipo});
  @override
  ConsumerState<_TipoAuditoriaDetalle> createState() => _TipoAuditoriaDetalleState();
}

class _TipoAuditoriaDetalleState extends ConsumerState<_TipoAuditoriaDetalle>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late Map<String, dynamic> _tipo;
  bool _recargando = false;

  @override
  void initState() {
    super.initState();
    _tipo = Map<String, dynamic>.from(widget.tipo);
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  List<Map<String, dynamic>> get _fases =>
      (_tipo['fases'] as List? ?? []).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get _checklist =>
      (_tipo['checklist_items'] as List? ?? []).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get _docs =>
      (_tipo['documentos_requeridos'] as List? ?? []).cast<Map<String, dynamic>>();

  Future<void> _recargar() async {
    setState(() => _recargando = true);
    try {
      final resp = await ApiClient.instance.get(
          Endpoints.tipoAuditoria(_tipo['id'] as String));
      setState(() => _tipo = Map<String, dynamic>.from(resp.data as Map));
    } catch (_) {} finally {
      if (mounted) setState(() => _recargando = false);
    }
  }


  void _abrirFaseForm({Map<String, dynamic>? fase}) => showModalBottomSheet(
    context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
    builder: (_) => _FaseForm(tipoId: _tipo['id'] as String, fase: fase,
        ordenSiguiente: _fases.length + 1))
    .then((_) => _recargar());

  Future<void> _eliminarFase(Map<String, dynamic> fase) async {
    final ok = await _confirmar(context,
      titulo: '¿Eliminar fase?',
      mensaje: '"${fase['nombre']}" será eliminada permanentemente.',
      labelOk: 'Eliminar', colorOk: AppColors.danger);
    if (!ok) return;
    try {
      await ApiClient.instance.delete(
          Endpoints.tipoAuditoriaFase(fase['id'] as String));
      _recargar();
    } catch (e) {
      if (mounted) _snack(context, _parsearError(e), error: true);
    }
  }


  void _abrirChecklistForm({Map<String, dynamic>? item}) => showModalBottomSheet(
    context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
    builder: (_) => _ChecklistItemForm(
        tipoId: _tipo['id'] as String, fases: _fases, item: item,
        ordenSiguiente: _checklist.length + 1))
    .then((_) => _recargar());

  Future<void> _eliminarChecklist(Map<String, dynamic> item) async {
    final ok = await _confirmar(context,
      titulo: '¿Eliminar ítem?',
      mensaje: '"${item['descripcion']}" será eliminado.',
      labelOk: 'Eliminar', colorOk: AppColors.danger);
    if (!ok) return;
    try {
      await ApiClient.instance.delete(
          Endpoints.tipoAuditoriaChecklistItem(item['id'] as String));
      _recargar();
    } catch (e) {
      if (mounted) _snack(context, _parsearError(e), error: true);
    }
  }


  void _abrirDocForm({Map<String, dynamic>? doc}) => showModalBottomSheet(
    context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
    builder: (_) => _DocumentoRequeridoForm(
        tipoId: _tipo['id'] as String, doc: doc,
        ordenSiguiente: _docs.length + 1))
    .then((_) => _recargar());

  Future<void> _eliminarDoc(Map<String, dynamic> doc) async {
    final ok = await _confirmar(context,
      titulo: '¿Eliminar documento?',
      mensaje: '"${doc['nombre']}" será eliminado.',
      labelOk: 'Eliminar', colorOk: AppColors.danger);
    if (!ok) return;
    try {
      await ApiClient.instance.delete(
          Endpoints.tipoAuditoriaDocumento(doc['id'] as String));
      _recargar();
    } catch (e) {
      if (mounted) _snack(context, _parsearError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(color: AppColors.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    child: DraggableScrollableSheet(
      expand: false, initialChildSize: 0.92, minChildSize: 0.5, maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Column(children: [

        Container(color: AppColors.white,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(children: [
            Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: AppColors.gray300, borderRadius: BorderRadius.circular(2)))),
            Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.accentLight, borderRadius: BorderRadius.circular(6)),
                child: Text(_tipo['codigo'] as String? ?? '',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.accent))),
              const SizedBox(width: 10),
              Expanded(child: Text(_tipo['nombre'] as String? ?? '',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
              if (_recargando)
                const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              IconButton(onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20),
                  style: IconButton.styleFrom(foregroundColor: AppColors.textSecondary)),
            ]),
            const SizedBox(height: 10),
            TabBar(controller: _tabs, tabs: [
              Tab(text: 'Fases (${_fases.length})'),
              Tab(text: 'Checklist (${_checklist.length})'),
              Tab(text: 'Docs (${_docs.length})'),
            ]),
          ])),
        const Divider(height: 1),
        Expanded(child: TabBarView(controller: _tabs, children: [

          _buildListaConFAB(
            items: _fases,
            emptyTitle: 'Sin fases',
            emptySubtitle: 'Define las etapas del proceso de auditoría.',
            onAdd: () => _abrirFaseForm(),
            fabLabel: 'Nueva fase',
            builder: (fase) => _FaseTile(
              fase: fase,
              onEditar: () => _abrirFaseForm(fase: fase),
              onEliminar: () => _eliminarFase(fase)),
          ),

          _buildListaConFAB(
            items: _checklist,
            emptyTitle: 'Sin ítems de checklist',
            emptySubtitle: 'Define los criterios de verificación.',
            onAdd: () => _abrirChecklistForm(),
            fabLabel: 'Nuevo ítem',
            builder: (item) => _ChecklistTile(
              item: item,
              onEditar: () => _abrirChecklistForm(item: item),
              onEliminar: () => _eliminarChecklist(item)),
          ),

          _buildListaConFAB(
            items: _docs,
            emptyTitle: 'Sin documentos requeridos',
            emptySubtitle: 'Define los documentos que el cliente debe entregar.',
            onAdd: () => _abrirDocForm(),
            fabLabel: 'Nuevo documento',
            builder: (doc) => _DocRequeridoTile(
              doc: doc,
              onEditar: () => _abrirDocForm(doc: doc),
              onEliminar: () => _eliminarDoc(doc)),
          ),
        ])),
      ]),
    ),
  );

  Widget _buildListaConFAB({
    required List<Map<String, dynamic>> items,
    required String emptyTitle, required String emptySubtitle,
    required VoidCallback onAdd, required String fabLabel,
    required Widget Function(Map<String, dynamic>) builder,
  }) => Stack(children: [
    items.isEmpty
      ? EmptyState(titulo: emptyTitle, subtitulo: emptySubtitle,
          icono: Icons.add_box_outlined, labelBoton: fabLabel, onBoton: onAdd)
      : ListView.separated(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 88),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (_, i) => builder(items[i])),
    Positioned(bottom: 16, right: 16,
      child: FloatingActionButton.extended(
        heroTag: 'fab_sub_$fabLabel',
        onPressed: onAdd,
        icon: const Icon(Icons.add, size: 18),
        label: Text(fabLabel),
        backgroundColor: AppColors.accent, foregroundColor: Colors.white)),
  ]);
}

class _FaseTile extends StatelessWidget {
  final Map<String, dynamic> fase;
  final VoidCallback onEditar, onEliminar;
  const _FaseTile({required this.fase, required this.onEditar, required this.onEliminar});
  @override
  Widget build(BuildContext context) {
    final esFinal = fase['es_fase_final'] as bool? ?? false;
    return Card(child: Padding(padding: const EdgeInsets.all(12),
      child: Row(children: [
        Container(width: 28, height: 28,
          decoration: BoxDecoration(
            color: esFinal ? AppColors.accentLight : AppColors.gray100,
            borderRadius: BorderRadius.circular(6)),
          child: Center(child: Text('${fase['orden'] ?? '?'}',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
              color: esFinal ? AppColors.accent : AppColors.textSecondary)))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(fase['nombre'] as String? ?? '',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
            if (esFinal) Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: AppColors.accentLight, borderRadius: BorderRadius.circular(8)),
              child: const Text('Final', style: TextStyle(fontSize: 10, color: AppColors.accent, fontWeight: FontWeight.w600))),
          ]),
          if ((fase['descripcion'] as String? ?? '').isNotEmpty)
            Text(fase['descripcion'] as String,
              style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('${fase['duracion_estimada_dias'] ?? 0} días estimados',
            style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
        ])),
        PopupMenuButton<String>(
          onSelected: (v) { if (v == 'editar') onEditar(); else onEliminar(); },
          icon: const Icon(Icons.more_vert, size: 16, color: AppColors.textTertiary),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'editar', child: Row(children: const [
              Icon(Icons.edit_outlined, size: 14), SizedBox(width: 8), Text('Editar', style: TextStyle(fontSize: 13))])),
            PopupMenuItem(value: 'eliminar', child: Row(children: const [
              Icon(Icons.delete_outline, size: 14, color: AppColors.danger),
              SizedBox(width: 8), Text('Eliminar', style: TextStyle(fontSize: 13, color: AppColors.danger))])),
          ]),
      ])));
  }
}

class _ChecklistTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onEditar, onEliminar;
  const _ChecklistTile({required this.item, required this.onEditar, required this.onEliminar});
  @override
  Widget build(BuildContext context) {
    final obligatorio = item['obligatorio'] as bool? ?? true;
    final cat = item['categoria'] as String? ?? '';
    return Card(child: Padding(padding: const EdgeInsets.all(12),
      child: Row(children: [
        Icon(obligatorio ? Icons.check_box_outlined : Icons.check_box_outline_blank_outlined,
          size: 18, color: obligatorio ? AppColors.accent : AppColors.textTertiary),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: AppColors.gray100, borderRadius: BorderRadius.circular(4)),
              child: Text(item['codigo'] as String? ?? '',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
            const SizedBox(width: 6),
            if (cat.isNotEmpty) Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: AppColors.infoBg, borderRadius: BorderRadius.circular(4)),
              child: Text(cat, style: const TextStyle(fontSize: 10, color: AppColors.info))),
          ]),
          const SizedBox(height: 3),
          Text(item['descripcion'] as String? ?? '',
            style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        ])),
        PopupMenuButton<String>(
          onSelected: (v) { if (v == 'editar') onEditar(); else onEliminar(); },
          icon: const Icon(Icons.more_vert, size: 16, color: AppColors.textTertiary),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'editar', child: Row(children: const [
              Icon(Icons.edit_outlined, size: 14), SizedBox(width: 8), Text('Editar', style: TextStyle(fontSize: 13))])),
            PopupMenuItem(value: 'eliminar', child: Row(children: const [
              Icon(Icons.delete_outline, size: 14, color: AppColors.danger),
              SizedBox(width: 8), Text('Eliminar', style: TextStyle(fontSize: 13, color: AppColors.danger))])),
          ]),
      ])));
  }
}

class _DocRequeridoTile extends StatelessWidget {
  final Map<String, dynamic> doc;
  final VoidCallback onEditar, onEliminar;
  const _DocRequeridoTile({required this.doc, required this.onEditar, required this.onEliminar});
  @override
  Widget build(BuildContext context) {
    final obligatorio = doc['obligatorio'] as bool? ?? true;
    return Card(child: Padding(padding: const EdgeInsets.all(12),
      child: Row(children: [
        Icon(Icons.description_outlined, size: 18,
          color: obligatorio ? AppColors.accent : AppColors.textTertiary),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(doc['nombre'] as String? ?? '',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          if ((doc['descripcion'] as String? ?? '').isNotEmpty)
            Text(doc['descripcion'] as String,
              style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          if (!obligatorio)
            const Text('Opcional', style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
        ])),
        PopupMenuButton<String>(
          onSelected: (v) { if (v == 'editar') onEditar(); else onEliminar(); },
          icon: const Icon(Icons.more_vert, size: 16, color: AppColors.textTertiary),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'editar', child: Row(children: const [
              Icon(Icons.edit_outlined, size: 14), SizedBox(width: 8), Text('Editar', style: TextStyle(fontSize: 13))])),
            PopupMenuItem(value: 'eliminar', child: Row(children: const [
              Icon(Icons.delete_outline, size: 14, color: AppColors.danger),
              SizedBox(width: 8), Text('Eliminar', style: TextStyle(fontSize: 13, color: AppColors.danger))])),
          ]),
      ])));
  }
}


class _FaseForm extends StatefulWidget {
  final String tipoId;
  final Map<String, dynamic>? fase;
  final int ordenSiguiente;
  const _FaseForm({required this.tipoId, this.fase, required this.ordenSiguiente});
  @override
  State<_FaseForm> createState() => _FaseFormState();
}

class _FaseFormState extends State<_FaseForm> {
  final _nombreCtrl = TextEditingController();
  final _descCtrl   = TextEditingController();
  final _diasCtrl   = TextEditingController();
  final _ordenCtrl  = TextEditingController();
  bool _esFinal   = false;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final f = widget.fase;
    _nombreCtrl.text = f?['nombre'] as String? ?? '';
    _descCtrl.text   = f?['descripcion'] as String? ?? '';
    _diasCtrl.text   = (f?['duracion_estimada_dias'] as int? ?? 7).toString();
    _ordenCtrl.text  = (f?['orden'] as int? ?? widget.ordenSiguiente).toString();
    _esFinal         = f?['es_fase_final'] as bool? ?? false;
  }

  @override
  void dispose() {
    _nombreCtrl.dispose(); _descCtrl.dispose();
    _diasCtrl.dispose(); _ordenCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_nombreCtrl.text.trim().isEmpty) return;
    setState(() { _guardando = true; _error = null; });
    try {
      final payload = {
        'tipo_auditoria': widget.tipoId,
        'nombre': _nombreCtrl.text.trim(),
        'descripcion': _descCtrl.text.trim(),
        'duracion_estimada_dias': int.tryParse(_diasCtrl.text.trim()) ?? 7,
        'orden': int.tryParse(_ordenCtrl.text.trim()) ?? widget.ordenSiguiente,
        'es_fase_final': _esFinal,
      };
      final id = widget.fase?['id'] as String?;
      if (id != null) {
        await ApiClient.instance.patch(Endpoints.tipoAuditoriaFase(id), data: payload);
      } else {
        await ApiClient.instance.post(Endpoints.tiposAuditoriaFases, data: payload);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = _parsearError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) => _SubFormShell(
    titulo: widget.fase == null ? 'Nueva fase' : 'Editar fase',
    icono: Icons.linear_scale_outlined,
    guardando: _guardando, error: _error,
    onGuardar: _guardar,
    onCancelar: () => Navigator.pop(context),
    child: Column(children: [
      Row(children: [
        SizedBox(width: 70, child: _SubCampo('Orden', _ordenCtrl, teclado: TextInputType.number)),
        const SizedBox(width: 12),
        SizedBox(width: 90, child: _SubCampo('Días est.', _diasCtrl, teclado: TextInputType.number)),
      ]),
      _SubCampo('Nombre *', _nombreCtrl, hint: 'Ej: Análisis de riesgos'),
      _SubCampo('Descripción', _descCtrl, hint: 'Qué se hace en esta fase', maxLines: 2),
      Row(children: [
        Switch(value: _esFinal, onChanged: (v) => setState(() => _esFinal = v),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
        const SizedBox(width: 8),
        const Text('Es la fase final del proceso',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ]),
    ]),
  );
}


class _ChecklistItemForm extends StatefulWidget {
  final String tipoId;
  final List<Map<String, dynamic>> fases;
  final Map<String, dynamic>? item;
  final int ordenSiguiente;
  const _ChecklistItemForm({
    required this.tipoId, required this.fases,
    this.item, required this.ordenSiguiente});
  @override
  State<_ChecklistItemForm> createState() => _ChecklistItemFormState();
}

class _ChecklistItemFormState extends State<_ChecklistItemForm> {
  final _codigoCtrl = TextEditingController();
  final _descCtrl   = TextEditingController();
  final _ordenCtrl  = TextEditingController();
  String  _categoria   = 'DOCUMENTAL';
  String? _faseId;
  bool    _obligatorio = true;
  bool    _guardando   = false;
  String? _error;

  static const _cats = [
    ('DOCUMENTAL','Documental'), ('TECNICO','Técnico'),
    ('LEGAL','Legal'), ('OPERACIONAL','Operacional'),
  ];

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    _codigoCtrl.text  = it?['codigo'] as String? ?? '';
    _descCtrl.text    = it?['descripcion'] as String? ?? '';
    _ordenCtrl.text   = (it?['orden'] as int? ?? widget.ordenSiguiente).toString();
    _categoria        = it?['categoria'] as String? ?? 'DOCUMENTAL';
    _obligatorio      = it?['obligatorio'] as bool? ?? true;
    _faseId           = it?['fase'] as String?;
  }

  @override
  void dispose() { _codigoCtrl.dispose(); _descCtrl.dispose(); _ordenCtrl.dispose(); super.dispose(); }

  Future<void> _guardar() async {
    if (_descCtrl.text.trim().isEmpty || _codigoCtrl.text.trim().isEmpty) return;
    setState(() { _guardando = true; _error = null; });
    try {
      final payload = {
        'tipo_auditoria': widget.tipoId,
        'codigo': _codigoCtrl.text.trim().toUpperCase(),
        'descripcion': _descCtrl.text.trim(),
        'orden': int.tryParse(_ordenCtrl.text.trim()) ?? widget.ordenSiguiente,
        'categoria': _categoria,
        'obligatorio': _obligatorio,
        if (_faseId != null) 'fase': _faseId,
      };
      final id = widget.item?['id'] as String?;
      if (id != null) {
        await ApiClient.instance.patch(Endpoints.tipoAuditoriaChecklistItem(id), data: payload);
      } else {
        await ApiClient.instance.post(Endpoints.tiposAuditoriaChecklist, data: payload);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = _parsearError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) => _SubFormShell(
    titulo: widget.item == null ? 'Nuevo ítem de checklist' : 'Editar ítem',
    icono: Icons.checklist_outlined,
    guardando: _guardando, error: _error,
    onGuardar: _guardar, onCancelar: () => Navigator.pop(context),
    child: Column(children: [
      Row(children: [
        SizedBox(width: 100, child: _SubCampo('Código *', _codigoCtrl, hint: 'CTR-01')),
        const SizedBox(width: 12),
        SizedBox(width: 70, child: _SubCampo('Orden', _ordenCtrl, teclado: TextInputType.number)),
      ]),
      _SubCampo('Descripción *', _descCtrl, hint: 'Criterio de verificación', maxLines: 3),
      _SubDrop<String>('Categoría', _categoria, _cats, (v) => setState(() => _categoria = v!)),
      if (widget.fases.isNotEmpty)
        _SubDrop<String?>('Fase asociada (opcional)', _faseId,
          [const (null, 'General (sin fase específica)'),
           ...widget.fases.map((f) => (f['id'] as String, f['nombre'] as String? ?? ''))],
          (v) => setState(() => _faseId = v)),
      Row(children: [
        Switch(value: _obligatorio, onChanged: (v) => setState(() => _obligatorio = v),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
        const SizedBox(width: 8),
        const Text('Obligatorio', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ]),
    ]),
  );
}


class _DocumentoRequeridoForm extends StatefulWidget {
  final String tipoId;
  final Map<String, dynamic>? doc;
  final int ordenSiguiente;
  const _DocumentoRequeridoForm({
    required this.tipoId, this.doc, required this.ordenSiguiente});
  @override
  State<_DocumentoRequeridoForm> createState() => _DocumentoRequeridoFormState();
}

class _DocumentoRequeridoFormState extends State<_DocumentoRequeridoForm> {
  final _nombreCtrl = TextEditingController();
  final _descCtrl   = TextEditingController();
  final _ordenCtrl  = TextEditingController();
  bool _obligatorio = true;
  bool _guardando   = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final d = widget.doc;
    _nombreCtrl.text = d?['nombre'] as String? ?? '';
    _descCtrl.text   = d?['descripcion'] as String? ?? '';
    _ordenCtrl.text  = (d?['orden'] as int? ?? widget.ordenSiguiente).toString();
    _obligatorio     = d?['obligatorio'] as bool? ?? true;
  }

  @override
  void dispose() { _nombreCtrl.dispose(); _descCtrl.dispose(); _ordenCtrl.dispose(); super.dispose(); }

  Future<void> _guardar() async {
    if (_nombreCtrl.text.trim().isEmpty) return;
    setState(() { _guardando = true; _error = null; });
    try {
      final payload = {
        'tipo_auditoria': widget.tipoId,
        'nombre': _nombreCtrl.text.trim(),
        'descripcion': _descCtrl.text.trim(),
        'orden': int.tryParse(_ordenCtrl.text.trim()) ?? widget.ordenSiguiente,
        'obligatorio': _obligatorio,
      };
      final id = widget.doc?['id'] as String?;
      if (id != null) {
        await ApiClient.instance.patch(Endpoints.tipoAuditoriaDocumento(id), data: payload);
      } else {
        await ApiClient.instance.post(Endpoints.tiposAuditoriaDocumentos, data: payload);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = _parsearError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) => _SubFormShell(
    titulo: widget.doc == null ? 'Nuevo documento requerido' : 'Editar documento',
    icono: Icons.description_outlined,
    guardando: _guardando, error: _error,
    onGuardar: _guardar, onCancelar: () => Navigator.pop(context),
    child: Column(children: [
      Row(children: [
        Expanded(child: _SubCampo('Nombre del documento *', _nombreCtrl,
            hint: 'Ej: Política de seguridad de la información')),
        const SizedBox(width: 12),
        SizedBox(width: 70, child: _SubCampo('Orden', _ordenCtrl, teclado: TextInputType.number)),
      ]),
      _SubCampo('Descripción / instrucciones', _descCtrl,
          hint: 'Formato, versión o condiciones requeridas', maxLines: 2),
      Row(children: [
        Switch(value: _obligatorio, onChanged: (v) => setState(() => _obligatorio = v),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
        const SizedBox(width: 8),
        const Text('Obligatorio', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ]),
    ]),
  );
}


class _SubFormShell extends StatelessWidget {
  final String titulo;
  final IconData icono;
  final Widget child;
  final bool guardando;
  final String? error;
  final VoidCallback onGuardar, onCancelar;
  const _SubFormShell({
    required this.titulo, required this.icono, required this.child,
    required this.guardando, this.error,
    required this.onGuardar, required this.onCancelar});

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 24),
    child: SingleChildScrollView(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min, children: [
      Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(color: AppColors.gray300, borderRadius: BorderRadius.circular(2)))),
      Row(children: [
        Icon(icono, size: 18, color: AppColors.accent),
        const SizedBox(width: 10),
        Expanded(child: Text(titulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
        IconButton(onPressed: onCancelar, icon: const Icon(Icons.close, size: 18),
            style: IconButton.styleFrom(foregroundColor: AppColors.textSecondary)),
      ]),
      const SizedBox(height: 14),
      child,
      if (error != null)
        Container(margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppColors.dangerBg, borderRadius: BorderRadius.circular(8)),
          child: Text(error!, style: const TextStyle(fontSize: 12, color: AppColors.danger))),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: onCancelar, child: const Text('Cancelar'))),
        const SizedBox(width: 12),
        Expanded(child: ElevatedButton.icon(
          onPressed: guardando ? null : onGuardar,
          icon: guardando
            ? const SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.save_outlined, size: 15),
          label: const Text('Guardar'))),
      ]),
    ])));
}

Widget _SubCampo(String label, TextEditingController ctrl, {
  String? hint, TextInputType teclado = TextInputType.text, int maxLines = 1}) =>
  Padding(padding: const EdgeInsets.only(bottom: 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
          color: AppColors.textSecondary)),
      const SizedBox(height: 4),
      TextFormField(controller: ctrl, keyboardType: teclado, maxLines: maxLines,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(hintText: hint, isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8))),
    ]));

Widget _SubDrop<T>(String label, T value, List<(T, String)> items, void Function(T?) fn) =>
  Padding(padding: const EdgeInsets.only(bottom: 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
          color: AppColors.textSecondary)),
      const SizedBox(height: 4),
      DropdownButtonFormField<T>(
        value: value,
        style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
        decoration: const InputDecoration(isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
        items: items.map((i) => DropdownMenuItem(value: i.$1, child: Text(i.$2))).toList(),
        onChanged: fn),
    ]));

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
          SnackBar(content: Text(_parsearError(e)), backgroundColor: AppColors.danger));
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
          SnackBar(content: Text(_parsearError(e)), backgroundColor: AppColors.danger));
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
          SnackBar(content: Text(_parsearError(e)), backgroundColor: AppColors.danger));
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
      'SUPERVISOR' => ('Supervisor', const Color(0xFF0F2447)),
      'ASESOR'     => ('Asesor',     const Color(0xFFB45309)),
      'AUDITOR'    => ('Auditor',    const Color(0xFF0369A1)),
      'AUXILIAR'   => ('Auxiliar',   const Color(0xFF0891B2)),
      'REVISOR'    => ('Revisor',    const Color(0xFF059669)),
      'CLIENTE'    => ('Cliente',    const Color(0xFF6B7280)),
      _            => (rol,          AppColors.textTertiary),
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
