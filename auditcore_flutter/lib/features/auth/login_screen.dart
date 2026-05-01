import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/providers.dart';
import '../../core/theme/app_theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey   = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _mfaCtrl   = TextEditingController();
  final _mfaFocus  = FocusNode();

  bool _verPass   = false;
  bool _cargando  = false;
  bool _mfaStep   = false;
  String? _error;

  late final AnimationController _animCtrl;
  late final Animation<double>    _fadeAnim;
  late final Animation<Offset>    _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnim  = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _mfaCtrl.dispose();
    _mfaFocus.dispose();
    super.dispose();
  }


  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _cargando = true; _error = null; });
    try {
      final service = ref.read(authServiceProvider);
      await service.login(
        _emailCtrl.text.trim(),
        _passCtrl.text,
      );

      if (mounted) {
        await ref.read(authProvider.notifier).cargarUsuario();
        context.go('/dashboard');
      }
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('MFA_REQUIRED') || msg.contains('mfa_required')) {
        if (mounted) {
          setState(() {
            _mfaStep  = true;
            _error    = null;
            _cargando = false;
          });
          _animCtrl.forward(from: 0);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _mfaFocus.requestFocus();
          });
        }
      } else {
        if (mounted) setState(() { _error = _mensajeError(msg); _cargando = false; });
      }
    } finally {
      if (mounted && !_mfaStep) setState(() => _cargando = false);
    }
  }


  Future<void> _verificarMfa() async {
    final codigo = _mfaCtrl.text.trim().replaceAll(' ', '');
    if (codigo.length != 6) {
      setState(() => _error = 'El código debe tener 6 dígitos.');
      return;
    }
    setState(() { _cargando = true; _error = null; });
    try {
      final service = ref.read(authServiceProvider);
      await service.login(
        _emailCtrl.text.trim(),
        _passCtrl.text,
        codigoMfa: codigo,
      );

      if (mounted) {
        await ref.read(authProvider.notifier).cargarUsuario();
        context.go('/dashboard');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error    = _mensajeError(e.toString());
          _cargando = false;
        });
        _mfaCtrl.clear();
        _mfaFocus.requestFocus();
      }
    }
  }

  void _volverAlLogin() {
    _animCtrl.reverse();
    setState(() {
      _mfaStep  = false;
      _error    = null;
      _cargando = false;
    });
    _mfaCtrl.clear();
  }

  String _mensajeError(String raw) {
    if (raw.contains('MFA_REQUIRED') || raw.contains('mfa_required')) {
      return 'Se requiere código de verificación.';
    }
    if (raw.contains('MFA inválido') || raw.contains('MFA invalido') ||
        raw.contains('Código MFA')   || raw.contains('expirado')) {
      return 'Código incorrecto o expirado. Abre tu app autenticadora y escribe el código actual.';
    }
    if (raw.contains('403') || raw.contains('bloqueada') ||
        raw.contains('inactivo') || raw.contains('administrador')) {
      return 'Cuenta bloqueada o inactiva. Contacta al administrador.';
    }
    if (raw.contains('429') || raw.contains('Demasiados')) {
      return 'Demasiados intentos. Espera unos minutos.';
    }
    if (raw.contains('401') || raw.contains('inválido') ||
        raw.contains('incorrect') || raw.contains('credential') ||
        raw.contains('Credenciales')) {
      return 'Email o contraseña incorrectos.';
    }
    if (raw.contains('SocketException') || raw.contains('Connection') ||
        raw.contains('XMLHttpRequest') || raw.contains('Network') ||
        raw.contains('onError') || raw.contains('Failed to fetch')) {
      return 'No se pudo conectar con el servidor.\n'
             'Verifica que los servicios estén corriendo (docker compose up).';
    }
    return 'Error al iniciar sesión. Intenta de nuevo.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.sidebar,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.verified_user,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(height: 16),
                const Text('AuditCore',
                    style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w600,
                      color: Colors.white, letterSpacing: -0.3,
                    )),
                const SizedBox(height: 4),
                const Text('Plataforma de Auditorías',
                    style: TextStyle(
                        fontSize: 13, color: Color(0x66FFFFFF))),
                const SizedBox(height: 32),


                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border, width: 0.5),
                  ),
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    child: _mfaStep
                        ? _buildMfaStep()
                        : _buildLoginStep(),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => context.go('/verificar'),
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0x80FFFFFF)),
                  child: const Text(
                      '¿Tienes un certificado? Verifica su autenticidad →',
                      style: TextStyle(fontSize: 12)),
                ),
                TextButton(
                  onPressed: () => context.go('/setup'),
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0x40FFFFFF)),
                  child: const Text(
                      'Primera vez aquí · Configurar plataforma',
                      style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildLoginStep() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Iniciar sesión',
              style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              )),
          const SizedBox(height: 20),

          const Text('Correo electrónico',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'tu@empresa.com',
              prefixIcon: Icon(Icons.mail_outline,
                  size: 16, color: AppColors.textTertiary),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Ingresa tu correo.';
              if (!v.contains('@')) return 'Correo no válido.';
              return null;
            },
          ),
          const SizedBox(height: 14),

          const Text('Contraseña',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _passCtrl,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            obscureText: !_verPass,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: '••••••••',
              prefixIcon: const Icon(Icons.lock_outline,
                  size: 16, color: AppColors.textTertiary),
              suffixIcon: IconButton(
                icon: Icon(
                  _verPass
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 16, color: AppColors.textTertiary,
                ),
                onPressed: () =>
                    setState(() => _verPass = !_verPass),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Ingresa tu contraseña.';
              if (v.length < 6) return 'Mínimo 6 caracteres.';
              return null;
            },
            onFieldSubmitted: (_) => _login(),
          ),
          const SizedBox(height: 20),

          if (_error != null) _buildError(),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _cargando ? null : _login,
              child: _cargando
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Iniciar sesión'),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildMfaStep() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new,
                    size: 16, color: AppColors.textSecondary),
                onPressed: _volverAlLogin,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              const Text('Verificación en dos pasos',
                  style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  )),
            ]),
            const SizedBox(height: 16),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBAE6FD)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.shield_outlined,
                        size: 16, color: Color(0xFF0369A1)),
                    SizedBox(width: 6),
                    Text('Tu cuenta está protegida',
                        style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600,
                          color: Color(0xFF0369A1),
                        )),
                  ]),
                  SizedBox(height: 6),
                  Text(
                    'Abre tu app autenticadora (Google Authenticator, '
                    'Microsoft Authenticator, Bitwarden, Authy u otra app TOTP) '
                    'e ingresa el código de 6 dígitos.',
                    style: TextStyle(
                        fontSize: 12, color: Color(0xFF0369A1), height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            const Text('Código de verificación',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 6),

            TextFormField(
              controller:   _mfaCtrl,
              focusNode:    _mfaFocus,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              onChanged: (v) {
                if (_error != null) setState(() => _error = null);
                if (v.length == 6 && !_cargando) _verificarMfa();
              },
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                letterSpacing: 8,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: '······',
                hintStyle: TextStyle(
                  fontSize: 22, letterSpacing: 8,
                  color: AppColors.textTertiary.withOpacity(0.5),
                ),
                prefixIcon: const Icon(Icons.vpn_key_outlined,
                    size: 16, color: AppColors.textTertiary),
                counterText: '',
              ),
              onFieldSubmitted: (_) {
                if (!_cargando) _verificarMfa();
              },
            ),
            const SizedBox(height: 6),
            const Text(
              'El código cambia cada 30 segundos.',
              style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 20),

            if (_error != null) _buildError(),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _cargando ? null : _verificarMfa,
                child: _cargando
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Verificar código'),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: _volverAlLogin,
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary),
                child: const Text('← Usar otra cuenta',
                    style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.dangerBg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline,
              size: 14, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_error!,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.danger)),
          ),
        ]),
      ),
    );
  }
}
