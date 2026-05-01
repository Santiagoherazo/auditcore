import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/theme/app_theme.dart';


class StatusBadge extends StatelessWidget {
  final String estado;
  final String? label;
  const StatusBadge({super.key, required this.estado, this.label});

  @override
  Widget build(BuildContext context) {
    final text = label ?? estado.badgeLabel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: estado.badgeBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: estado.badgeColor,
        ),
      ),
    );
  }
}


class AppSidebar extends StatelessWidget {
  final String rutaActual;
  final String rolUsuario;
  final String nombreUsuario;

  const AppSidebar({
    super.key,
    required this.rutaActual,
    required this.rolUsuario,
    required this.nombreUsuario,
  });

  @override
  Widget build(BuildContext context) {
    final items = _itemsParaRol(rolUsuario);
    final initials = nombreUsuario.isNotEmpty
        ? nombreUsuario.trim().split(' ').take(2).map((w) => w[0].toUpperCase()).join()
        : 'U';

    return Container(
      width: 220,
      color: AppColors.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Container(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0x14FFFFFF), width: 0.5),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.verified_user, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 8),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AuditCore',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: -0.2,
                        )),
                    Text('v2.0',
                        style: TextStyle(fontSize: 10, color: Color(0x59FFFFFF))),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),
          _SidebarSection(label: 'Principal'),
          ..._buildItems(context, items.where((i) => i['section'] == 'principal').toList()),
          _SidebarSection(label: 'Gestión'),
          ..._buildItems(context, items.where((i) => i['section'] == 'gestion').toList()),
          if (['SUPERVISOR'].contains(rolUsuario)) ...[
            _SidebarSection(label: 'Sistema'),
            ..._buildItems(context, items.where((i) => i['section'] == 'sistema').toList()),
          ],

          const Spacer(),


          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Color(0x14FFFFFF), width: 0.5),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  alignment: Alignment.center,
                  child: Text(initials,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      )),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombreUsuario,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xB3FFFFFF),
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _labelRol(rolUsuario),
                        style: const TextStyle(fontSize: 10, color: Color(0x59FFFFFF)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildItems(BuildContext context, List<Map<String, dynamic>> items) {
    return items.map((item) {
      final active = rutaActual.startsWith(item['ruta'] as String);
      return _SidebarItem(
        icon: item['icon'] as IconData,
        label: item['label'] as String,
        ruta: item['ruta'] as String,
        active: active,
        badge: item['badge'] as String?,
        onTap: () => context.go(item['ruta'] as String),
      );
    }).toList();
  }


  List<Map<String, dynamic>> _itemsParaRol(String rol) {
    return [
      {'section': 'principal', 'label': 'Dashboard',
       'icon': Icons.dashboard_outlined, 'ruta': '/dashboard', 'badge': null},

      if (['SUPERVISOR', 'ASESOR', 'REVISOR'].contains(rol))
        {'section': 'principal', 'label': 'Clientes',
         'icon': Icons.business_outlined, 'ruta': '/clientes', 'badge': null},

      if (rol != 'CLIENTE')
        {'section': 'principal', 'label': 'Expedientes',
         'icon': Icons.folder_open_outlined, 'ruta': '/expedientes', 'badge': null},

      if (rol != 'CLIENTE')
        {'section': 'gestion', 'label': 'Documentos',
         'icon': Icons.description_outlined, 'ruta': '/documentos', 'badge': null},

      if (['SUPERVISOR', 'AUDITOR', 'REVISOR', 'ASESOR'].contains(rol))
        {'section': 'gestion', 'label': 'Certificaciones',
         'icon': Icons.verified_outlined, 'ruta': '/certificaciones', 'badge': null},

      if (['SUPERVISOR', 'ASESOR', 'AUDITOR', 'AUXILIAR', 'REVISOR'].contains(rol))
        {'section': 'gestion', 'label': 'AuditBot',
         'icon': Icons.smart_toy_outlined, 'ruta': '/chat', 'badge': 'IA'},

      if (['SUPERVISOR', 'AUDITOR', 'AUXILIAR'].contains(rol))
        {'section': 'gestion', 'label': 'Calendario',
         'icon': Icons.calendar_month_outlined, 'ruta': '/calendario', 'badge': null},

      {'section': 'gestion', 'label': 'Verificar cert.',
       'icon': Icons.qr_code_scanner_outlined, 'ruta': '/verificar', 'badge': null},

      if (rol != 'CLIENTE')
        {'section': 'sistema', 'label': 'Mi perfil / 2FA',
         'icon': Icons.security_outlined, 'ruta': '/perfil/mfa', 'badge': null},

      if (rol == 'SUPERVISOR')
        {'section': 'sistema', 'label': 'Administración',
         'icon': Icons.manage_accounts_outlined, 'ruta': '/admin-panel', 'badge': null},
    ];
  }

  String _labelRol(String rol) => switch (rol) {
    'SUPERVISOR' => 'Supervisor',
    'ASESOR'     => 'Asesor',
    'AUDITOR'    => 'Auditor',
    'AUXILIAR'   => 'Auxiliar',
    'REVISOR'    => 'Revisor',
    'CLIENTE'    => 'Cliente',
    _            => rol.isNotEmpty
        ? rol[0].toUpperCase() + rol.substring(1).toLowerCase()
        : 'Usuario',
  };
}

class _SidebarSection extends StatelessWidget {
  final String label;
  const _SidebarSection({required this.label});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
    child: Text(
      label.toUpperCase(),
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: Color(0x4DFFFFFF),
        letterSpacing: 0.8,
      ),
    ),
  );
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String ruta;
  final bool active;
  final String? badge;
  final VoidCallback onTap;
  const _SidebarItem({
    required this.icon, required this.label, required this.ruta,
    required this.active, required this.onTap, this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          hoverColor: const Color(0x0FFFFFFF),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: active ? const Color(0x403B82F6) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(icon, size: 15,
                    color: active ? const Color(0xFF93C5FD) : const Color(0x66FFFFFF)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label,
                    style: TextStyle(
                      fontSize: 13,
                      color: active ? Colors.white : const Color(0xA6FFFFFF),
                      fontWeight: active ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(badge!,
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        )),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


class AppShell extends StatelessWidget {
  final Widget child;
  final String rutaActual;
  final String rolUsuario;
  final String nombreUsuario;
  final String titulo;
  final String? subtitulo;
  final List<Widget>? actions;
  final bool showBottomNav;

  const AppShell({
    super.key,
    required this.child,
    required this.rutaActual,
    required this.rolUsuario,
    required this.nombreUsuario,
    required this.titulo,
    this.subtitulo,
    this.actions,
    this.showBottomNav = false,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 720;

    if (isWide) {

      return Scaffold(
        backgroundColor: AppColors.bg,
        body: Row(
          children: [
            AppSidebar(
              rutaActual: rutaActual,
              rolUsuario: rolUsuario,
              nombreUsuario: nombreUsuario,
            ),
            Expanded(
              child: Column(
                children: [
                  _TopBar(titulo: titulo, subtitulo: subtitulo, actions: actions),
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      );
    } else {

      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: Text(titulo),
          actions: actions,
        ),
        drawer: Drawer(
          child: AppSidebar(
            rutaActual: rutaActual,
            rolUsuario: rolUsuario,
            nombreUsuario: nombreUsuario,
          ),
        ),
        body: child,
        bottomNavigationBar: showBottomNav
            ? _MobileBottomNav(rutaActual: rutaActual, rolUsuario: rolUsuario)
            : null,
      );
    }
  }
}

class _TopBar extends StatelessWidget {
  final String titulo;
  final String? subtitulo;
  final List<Widget>? actions;
  const _TopBar({required this.titulo, this.subtitulo, this.actions});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.2,
                    )),
                if (subtitulo != null)
                  Text(subtitulo!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      )),
              ],
            ),
          ),
          if (actions != null) Row(children: actions!),
        ],
      ),
    );
  }
}

class _MobileBottomNav extends StatelessWidget {
  final String rutaActual;
  final String rolUsuario;
  const _MobileBottomNav({required this.rutaActual, required this.rolUsuario});

  @override
  Widget build(BuildContext context) {
    final tabs = [
      _NavTab(icon: Icons.dashboard_outlined, label: 'Dashboard', ruta: '/dashboard'),
      _NavTab(icon: Icons.folder_open_outlined, label: 'Expedientes', ruta: '/expedientes'),
      _NavTab(icon: Icons.description_outlined, label: 'Docs', ruta: '/documentos'),
      _NavTab(icon: Icons.smart_toy_outlined, label: 'AuditBot', ruta: '/chat'),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: SafeArea(
        child: Row(
          children: tabs.map((t) {
            final active = rutaActual.startsWith(t.ruta);
            return Expanded(
              child: InkWell(
                onTap: () => context.go(t.ruta),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(t.icon,
                          size: 20,
                          color: active ? AppColors.accent : AppColors.textTertiary),
                      const SizedBox(height: 3),
                      Text(t.label,
                          style: TextStyle(
                            fontSize: 10,
                            color: active ? AppColors.accent : AppColors.textTertiary,
                            fontWeight: active ? FontWeight.w500 : FontWeight.w400,
                          )),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _NavTab {
  final IconData icon;
  final String label;
  final String ruta;
  const _NavTab({required this.icon, required this.label, required this.ruta});
}


class MetricCard extends StatelessWidget {
  final String valor;
  final String label;
  final String? delta;
  final MetricDeltaType deltaType;
  final VoidCallback? onTap;

  const MetricCard({
    super.key,
    required this.valor,
    required this.label,
    this.delta,
    this.deltaType = MetricDeltaType.neutral,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final deltaColor = switch (deltaType) {
      MetricDeltaType.up      => AppColors.success,
      MetricDeltaType.down    => AppColors.danger,
      MetricDeltaType.warning => AppColors.warning,
      MetricDeltaType.neutral => AppColors.textTertiary,
    };

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(valor,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                    height: 1,
                  )),
              const SizedBox(height: 4),
              Text(label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  )),
              if (delta != null) ...[
                const SizedBox(height: 6),
                Text(delta!,
                    style: TextStyle(
                      fontSize: 11,
                      color: deltaColor,
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum MetricDeltaType { up, down, warning, neutral }


class InlineProgress extends StatelessWidget {
  final double value;
  const InlineProgress({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    final color = value >= 1.0
        ? AppColors.success
        : value >= 0.6
            ? AppColors.accent
            : value >= 0.3
                ? AppColors.warning
                : AppColors.danger;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 4,
              backgroundColor: AppColors.border,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 30,
          child: Text(
            '${(value * 100).round()}%',
            style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}


class EmptyState extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final IconData icono;
  final String? labelBoton;
  final VoidCallback? onBoton;

  const EmptyState({
    super.key,
    required this.titulo,
    required this.subtitulo,
    this.icono = Icons.inbox_outlined,
    this.labelBoton,
    this.onBoton,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 48, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            Text(titulo,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(subtitulo,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center),
            if (labelBoton != null && onBoton != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(onPressed: onBoton, child: Text(labelBoton!)),
            ],
          ],
        ),
      ),
    );
  }
}


class SectionHeader extends StatelessWidget {
  final String titulo;
  final Widget? trailing;
  const SectionHeader({super.key, required this.titulo, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(titulo,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.2,
                )),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}


class LoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final Widget child;
  const LoadingOverlay({super.key, required this.isLoading, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Container(
            color: Colors.white.withOpacity(0.7),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
    );
  }
}


class InfoCard extends StatelessWidget {
  final String titulo;
  final String valor;
  final IconData icono;
  final Color color;
  final String? subtitulo;
  final VoidCallback? onTap;

  const InfoCard({
    super.key,
    required this.titulo,
    required this.valor,
    required this.icono,
    this.color = AppColors.accent,
    this.subtitulo,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icono, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(valor,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          color: color,
                        )),
                    Text(titulo,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        )),
                    if (subtitulo != null)
                      Text(subtitulo!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textTertiary,
                          )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class ProgressCard extends StatelessWidget {
  final String titulo;
  final double porcentaje;
  final Color color;
  const ProgressCard({
    super.key,
    required this.titulo,
    required this.porcentaje,
    this.color = AppColors.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(titulo,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      )),
                ),
                Text('${porcentaje.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: color,
                    )),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: porcentaje / 100,
                minHeight: 4,
                backgroundColor: AppColors.border,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class AppDrawer extends StatelessWidget {
  final String rolUsuario;
  final String nombreUsuario;
  final String rutaActual;

  const AppDrawer({
    super.key,
    required this.rolUsuario,
    required this.nombreUsuario,
    required this.rutaActual,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.sidebar,
      child: AppSidebar(
        rutaActual: rutaActual,
        rolUsuario: rolUsuario,
        nombreUsuario: nombreUsuario,
      ),
    );
  }
}
