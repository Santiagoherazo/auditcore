import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/models.dart';
import '../../core/services/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

// ── Lista de Clientes ────────────────────────────────────────────────────
class ClientesListScreen extends ConsumerStatefulWidget {
  const ClientesListScreen({super.key});
  @override
  ConsumerState<ClientesListScreen> createState() => _ClientesListScreenState();
}

class _ClientesListScreenState extends ConsumerState<ClientesListScreen> {
  final _busquedaCtrl = TextEditingController();
  Timer? _debounce;
  String? _estadoFiltro;

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onBusqueda(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      ref.read(clientesFiltroProvider.notifier).update(
            (s) => {...s, 'busqueda': v.isEmpty ? null : v},
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final usuario   = authState.valueOrNull;
    final clientesAsync = ref.watch(clientesProvider);

    return AppShell(
      rutaActual:    '/clientes',
      rolUsuario:    usuario?.rol ?? '',
      nombreUsuario: usuario?.nombreCompleto ?? '',
      titulo:        'Clientes',
      showBottomNav: true,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 15),
            label: const Text('Nuevo'),
            onPressed: () => context.go('/clientes/nuevo'),
          ),
        ),
      ],
      child: Column(
        children: [
          // Barra de filtros
          Container(
            color: AppColors.white,
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _busquedaCtrl,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'Buscar por nombre o NIT...',
                    prefixIcon: Icon(Icons.search, size: 16, color: AppColors.textTertiary),
                  ),
                  onChanged: _onBusqueda,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 36,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _estadoFiltro,
                    hint: const Text('Estado', style: TextStyle(fontSize: 12)),
                    style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                    borderRadius: BorderRadius.circular(8),
                    items: const [
                      DropdownMenuItem(value: null,       child: Text('Todos')),
                      DropdownMenuItem(value: 'ACTIVO',   child: Text('Activo')),
                      DropdownMenuItem(value: 'INACTIVO', child: Text('Inactivo')),
                      DropdownMenuItem(value: 'PROSPECTO',child: Text('Prospecto')),
                    ],
                    onChanged: (v) {
                      setState(() => _estadoFiltro = v);
                      ref.read(clientesFiltroProvider.notifier)
                          .update((s) => {...s, 'estado': v});
                    },
                  ),
                ),
              ),
            ]),
          ),
          const Divider(),
          Expanded(
            child: clientesAsync.when(
              loading: () => const Center(
                child: SizedBox(width: 24, height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (e, _) => EmptyState(
                titulo: 'Error cargando clientes',
                subtitulo: e.toString(),
                icono: Icons.error_outline,
                labelBoton: 'Reintentar',
                onBoton: () => ref.invalidate(clientesProvider),
              ),
              data: (clientes) => clientes.isEmpty
                  ? EmptyState(
                      titulo: 'Sin clientes',
                      subtitulo: 'Crea el primer cliente para comenzar.',
                      icono: Icons.business_outlined,
                      labelBoton: 'Nuevo cliente',
                      onBoton: () => context.go('/clientes/nuevo'),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(14),
                      itemCount: clientes.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (_, i) => _ClienteTile(cliente: clientes[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClienteTile extends StatelessWidget {
  final ClienteModel cliente;
  const _ClienteTile({required this.cliente});

  @override
  Widget build(BuildContext context) {
    final initials = cliente.razonSocial.isNotEmpty
        ? cliente.razonSocial.trim().split(' ').take(2)
            .map((w) => w[0].toUpperCase()).join()
        : '?';

    return Card(
      child: InkWell(
        onTap: () => context.go('/clientes/${cliente.id}'),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.accentLight,
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              child: Text(initials,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accent,
                  )),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(cliente.razonSocial,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    )),
                const SizedBox(height: 2),
                Text('NIT ${cliente.nit}  ·  ${cliente.ciudad}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
              ]),
            ),
            StatusBadge(estado: cliente.estado),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 16, color: AppColors.textTertiary),
          ]),
        ),
      ),
    );
  }
}

// ── Detalle del Cliente ──────────────────────────────────────────────────
class ClienteDetailScreen extends ConsumerWidget {
  final String id;
  const ClienteDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState    = ref.watch(authProvider);
    final usuario      = authState.valueOrNull;
    final clienteAsync = ref.watch(clienteProvider(id));

    return AppShell(
      rutaActual:    '/clientes',
      rolUsuario:    usuario?.rol ?? '',
      nombreUsuario: usuario?.nombreCompleto ?? '',
      titulo:        'Detalle del cliente',
      actions: [
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 18),
          onPressed: () => context.go('/clientes/$id/editar'),
          style: IconButton.styleFrom(foregroundColor: AppColors.textSecondary),
        ),
        const SizedBox(width: 8),
      ],
      child: clienteAsync.when(
        loading: () => const Center(
          child: SizedBox(width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (cliente) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Cabecera
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.accentLight,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      cliente.razonSocial.isNotEmpty
                          ? cliente.razonSocial[0].toUpperCase() : '?',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(cliente.razonSocial,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          )),
                      const SizedBox(height: 2),
                      Text('NIT: ${cliente.nit}',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      const SizedBox(height: 6),
                      StatusBadge(estado: cliente.estado),
                    ]),
                  ),
                ]),
              ),
            ),

            const SectionHeader(titulo: 'Información general'),
            Card(
              child: Column(children: [
                _InfoRow(icono: Icons.location_city_outlined, label: 'Ciudad',  valor: cliente.ciudad),
                const Divider(),
                _InfoRow(icono: Icons.flag_outlined,          label: 'País',    valor: cliente.pais),
                const Divider(),
                _InfoRow(icono: Icons.email_outlined,         label: 'Email',   valor: cliente.email),
                const Divider(),
                _InfoRow(icono: Icons.category_outlined,      label: 'Sector',  valor: cliente.sector),
              ]),
            ),

            if (cliente.contactos.isNotEmpty) ...[
              const SectionHeader(titulo: 'Contactos'),
              ...cliente.contactos.map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Card(
                  child: ListTile(
                    leading: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.accentLight,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.person_outline, size: 16, color: AppColors.accent),
                    ),
                    title: Text('${c.nombre} ${c.apellido}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    subtitle: Text('${c.cargo}  ·  ${c.email}',
                        style: const TextStyle(fontSize: 11)),
                    trailing: c.esPrincipal
                        ? const StatusBadge(estado: 'ACTIVO', label: 'Principal')
                        : null,
                  ),
                ),
              )),
            ],

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.folder_open_outlined, size: 16),
                label: const Text('Ver expedientes del cliente'),
                onPressed: () => context.go('/expedientes?cliente=$id'),
              ),
            ),
            const SizedBox(height: 20),
          ]),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icono;
  final String label;
  final String valor;
  const _InfoRow({required this.icono, required this.label, required this.valor});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    child: Row(children: [
      Icon(icono, size: 15, color: AppColors.textTertiary),
      const SizedBox(width: 10),
      SizedBox(
        width: 80,
        child: Text(label,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ),
      Expanded(
        child: Text(valor.isEmpty ? '—' : valor,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
      ),
    ]),
  );
}

// ── Formulario de Cliente ────────────────────────────────────────────────
