import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/services/providers.dart';
import '../../core/theme/app_theme.dart';

// setupStatusProvider moved to core/services/providers.dart to avoid
// circular dependency with the router.

// ── Wizard de instalación ─────────────────────────────────────────────────
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});
  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _pageCtrl = PageController();
  int _paso = 0;

  // Paso 1
  final _nombreCtrl  = TextEditingController(text: 'AuditCore');
  // FIX: en web Docker, la API se accede via proxy nginx (/api/).
  // Si API_BASE_URL está en .env se usa ese valor; si no, se deja vacío
  // y ApiClient usará rutas relativas automáticamente.
  final _apiUrlCtrl  = TextEditingController(
    text: ApiClient.baseUrl.isEmpty ? '' : ApiClient.baseUrl,
  );

  // Paso 2
  final _nombreAdminCtrl   = TextEditingController();
  final _apellidoAdminCtrl = TextEditingController();
  final _emailAdminCtrl    = TextEditingController();
  final _passCtrl          = TextEditingController();
  final _passConfCtrl      = TextEditingController();

  bool _verPass     = false;
  bool _verPassConf = false;
  bool _cargando    = false;
  String? _error;

  final _form1 = GlobalKey<FormState>();
  final _form2 = GlobalKey<FormState>();

  @override
  void dispose() {
    _pageCtrl.dispose();
    _nombreCtrl.dispose(); _apiUrlCtrl.dispose();
    _nombreAdminCtrl.dispose(); _apellidoAdminCtrl.dispose();
    _emailAdminCtrl.dispose(); _passCtrl.dispose(); _passConfCtrl.dispose();
    super.dispose();
  }

  void _irPaso(int paso) {
    setState(() { _paso = paso; _error = null; });
    _pageCtrl.animateToPage(paso,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  Future<void> _finalizar() async {
    if (!_form2.currentState!.validate()) return;
    setState(() { _cargando = true; _error = null; });

    try {
      // FIX: si el campo URL quedó vacío (web Docker con nginx proxy),
      // usar el ApiClient existente directamente.
      final urlIngresada = _apiUrlCtrl.text.trim().replaceAll(RegExp(r'/$'), '');
      final baseUrl = urlIngresada.isNotEmpty ? urlIngresada : ApiClient.baseUrl;

      // Usar un Dio temporal con la URL configurada para el setup
      final apiBase = baseUrl.isEmpty ? '/api/' : '$baseUrl/api/';
      final dio = Dio(BaseOptions(
        baseUrl: apiBase,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ));

      await dio.post('auth/setup/', data: {
        'nombre_plataforma': _nombreCtrl.text.trim(),
        'nombre':            _nombreAdminCtrl.text.trim(),
        'apellido':          _apellidoAdminCtrl.text.trim(),
        'email':             _emailAdminCtrl.text.trim(),
        'password':          _passCtrl.text,
      });

      ApiClient.setBaseUrl(baseUrl);

      // FIX: invalidar el provider para que el router detecte el cambio
      // y redirija automáticamente a /login sin quedarse en /setup
      ref.invalidate(setupStatusProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Plataforma configurada. Inicia sesión.')),
        );
        context.go('/login');
      }
    } on DioException catch (e) {
      final data = e.response?.data;
      String msg;
      if (data is Map) {
        msg = data['detail'] ?? data['error'] ?? e.message ?? 'Error de conexión';
      } else {
        msg = e.message ?? 'Error de conexión';
      }
      setState(() => _error = msg.toString());
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Si la plataforma ya está configurada, mostrar aviso y redirigir
    final statusAsync = ref.watch(setupStatusProvider);

    return Scaffold(
      backgroundColor: AppColors.sidebar,
      body: statusAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
        error: (_, __) => _buildWizard(), // si falla la comprobación, mostrar wizard
        data: (configured) {
          if (configured) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Container(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 56, height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.successBg,
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: const Icon(Icons.check_circle_outline,
                            color: AppColors.success, size: 28),
                      ),
                      const SizedBox(height: 16),
                      const Text('Plataforma ya configurada',
                          style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          )),
                      const SizedBox(height: 8),
                      const Text(
                        'Este instalador solo puede ejecutarse una vez. '
                        'Inicia sesión con las credenciales que creaste.',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => context.go('/login'),
                          child: const Text('Ir al inicio de sesión'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          return _buildWizard();
        },
      ),
    );
  }

  Widget _buildWizard() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.verified_user, size: 48, color: Colors.white),
              const SizedBox(height: 12),
              const Text('Bienvenido a AuditCore',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600,
                      color: Colors.white, letterSpacing: -0.3)),
              const SizedBox(height: 6),
              const Text('Configuración inicial de la plataforma',
                  style: TextStyle(fontSize: 13, color: Color(0x80FFFFFF))),
              const SizedBox(height: 32),

              _PasoIndicador(paso: _paso),
              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: SizedBox(
                  height: 420,
                  child: PageView(
                    controller: _pageCtrl,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _Paso1(
                        formKey: _form1,
                        nombreCtrl: _nombreCtrl,
                        apiUrlCtrl: _apiUrlCtrl,
                        onSiguiente: () {
                          if (_form1.currentState!.validate()) _irPaso(1);
                        },
                      ),
                      _Paso2(
                        formKey: _form2,
                        nombreCtrl: _nombreAdminCtrl,
                        apellidoCtrl: _apellidoAdminCtrl,
                        emailCtrl: _emailAdminCtrl,
                        passCtrl: _passCtrl,
                        passConfCtrl: _passConfCtrl,
                        verPass: _verPass,
                        verPassConf: _verPassConf,
                        onTogglePass: () => setState(() => _verPass = !_verPass),
                        onTogglePassConf: () => setState(() => _verPassConf = !_verPassConf),
                        onAtras: () => _irPaso(0),
                        onFinalizar: _finalizar,
                        cargando: _cargando,
                        error: _error,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Indicador de pasos ────────────────────────────────────────────────────
class _PasoIndicador extends StatelessWidget {
  final int paso;
  const _PasoIndicador({required this.paso});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Dot(activo: paso >= 0, label: '1  Plataforma'),
        Container(
          width: 40, height: 1,
          color: paso >= 1 ? AppColors.accent : Colors.white.withOpacity(0.3),
        ),
        _Dot(activo: paso >= 1, label: '2  Superadmin'),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final bool activo;
  final String label;
  const _Dot({required this.activo, required this.label});

  @override
  Widget build(BuildContext context) => Column(children: [
    Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        color: activo ? AppColors.accent : Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Icon(activo ? Icons.check : Icons.circle,
            size: 12, color: Colors.white),
      ),
    ),
    const SizedBox(height: 4),
    Text(label,
        style: TextStyle(
          fontSize: 10,
          color: activo ? Colors.white : Colors.white.withOpacity(0.4),
        )),
  ]);
}

// ── Paso 1 ────────────────────────────────────────────────────────────────
class _Paso1 extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nombreCtrl;
  final TextEditingController apiUrlCtrl;
  final VoidCallback onSiguiente;

  const _Paso1({
    required this.formKey, required this.nombreCtrl,
    required this.apiUrlCtrl, required this.onSiguiente,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Configura la plataforma',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        const Text('Define el nombre y la URL del servidor API.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 24),

        _Label('Nombre de la plataforma *'),
        const SizedBox(height: 5),
        TextFormField(
          controller: nombreCtrl,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'Ej: AuditCore, Mi Consultora',
            prefixIcon: Icon(Icons.verified_user_outlined, size: 16),
          ),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'El nombre es requerido.' : null,
        ),
        const SizedBox(height: 16),

        _Label('URL del servidor API (opcional)'),
        const SizedBox(height: 5),
        TextFormField(
          controller: apiUrlCtrl,
          style: const TextStyle(fontSize: 13),
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'http://localhost:8000  (dejar vacío si usas Docker)',
            prefixIcon: Icon(Icons.cloud_outlined, size: 16),
            helperText: 'En Docker con nginx deja vacío. Sin Docker: http://localhost:8000',
          ),
          validator: (v) {
            // FIX: permitir campo vacío — en Docker/web la app usa rutas relativas
            // a través del proxy nginx. Solo validar si se ingresó algo.
            if (v != null && v.trim().isNotEmpty && !v.startsWith('http')) {
              return 'Debe empezar con http:// o https://';
            }
            return null;
          },
        ),

        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onSiguiente,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Siguiente'),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward, size: 15),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Paso 2 ────────────────────────────────────────────────────────────────
class _Paso2 extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nombreCtrl, apellidoCtrl, emailCtrl, passCtrl, passConfCtrl;
  final bool verPass, verPassConf;
  final VoidCallback onTogglePass, onTogglePassConf, onAtras, onFinalizar;
  final bool cargando;
  final String? error;

  const _Paso2({
    required this.formKey, required this.nombreCtrl,
    required this.apellidoCtrl, required this.emailCtrl,
    required this.passCtrl, required this.passConfCtrl,
    required this.verPass, required this.verPassConf,
    required this.onTogglePass, required this.onTogglePassConf,
    required this.onAtras, required this.onFinalizar,
    required this.cargando, required this.error,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Crea el superadministrador',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          const Text('Este usuario tendrá acceso total al sistema.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 20),

          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Label('Nombre *'),
              const SizedBox(height: 5),
              TextFormField(
                controller: nombreCtrl,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(hintText: 'Juan'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
            ])),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Label('Apellido *'),
              const SizedBox(height: 5),
              TextFormField(
                controller: apellidoCtrl,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(hintText: 'García'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
            ])),
          ]),
          const SizedBox(height: 12),

          _Label('Correo electrónico *'),
          const SizedBox(height: 5),
          TextFormField(
            controller: emailCtrl,
            style: const TextStyle(fontSize: 13),
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              hintText: 'admin@miempresa.com',
              prefixIcon: Icon(Icons.mail_outline, size: 16),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Requerido';
              if (!v.contains('@')) return 'Email inválido';
              return null;
            },
          ),
          const SizedBox(height: 12),

          _Label('Contraseña *'),
          const SizedBox(height: 5),
          TextFormField(
            controller: passCtrl,
            obscureText: !verPass,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Mínimo 8 caracteres',
              prefixIcon: const Icon(Icons.lock_outline, size: 16),
              suffixIcon: IconButton(
                icon: Icon(verPass
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                    size: 16),
                onPressed: onTogglePass,
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Requerido';
              if (v.length < 8) return 'Mínimo 8 caracteres';
              return null;
            },
          ),
          const SizedBox(height: 12),

          _Label('Confirmar contraseña *'),
          const SizedBox(height: 5),
          TextFormField(
            controller: passConfCtrl,
            obscureText: !verPassConf,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Repite la contraseña',
              prefixIcon: const Icon(Icons.lock_outline, size: 16),
              suffixIcon: IconButton(
                icon: Icon(verPassConf
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                    size: 16),
                onPressed: onTogglePassConf,
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Requerido';
              if (v != passCtrl.text) return 'Las contraseñas no coinciden';
              return null;
            },
          ),

          if (error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.dangerBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline, size: 14, color: AppColors.danger),
                const SizedBox(width: 8),
                Expanded(child: Text(error!,
                    style: const TextStyle(fontSize: 12, color: AppColors.danger))),
              ]),
            ),
          ],

          const SizedBox(height: 16),
          Row(children: [
            OutlinedButton(
              onPressed: onAtras,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(color: AppColors.border),
              ),
              child: const Row(children: [
                Icon(Icons.arrow_back, size: 14),
                SizedBox(width: 6),
                Text('Atrás'),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: cargando ? null : onFinalizar,
                child: cargando
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Completar instalación'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
          color: AppColors.textSecondary));
}
