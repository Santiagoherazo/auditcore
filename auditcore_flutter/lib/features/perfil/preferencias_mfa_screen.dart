import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/services/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';


final mfaEstadoProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final resp = await ApiClient.instance.get(Endpoints.mfaSetup);
  return resp.data as Map<String, dynamic>;
});


class PreferenciasMfaScreen extends ConsumerStatefulWidget {
  const PreferenciasMfaScreen({super.key});
  @override
  ConsumerState<PreferenciasMfaScreen> createState() =>
      _PreferenciasMfaScreenState();
}

class _PreferenciasMfaScreenState
    extends ConsumerState<PreferenciasMfaScreen> {

  @override
  Widget build(BuildContext context) {
    final authState    = ref.watch(authProvider);
    final usuario      = authState.valueOrNull;
    final mfaAsync     = ref.watch(mfaEstadoProvider);
    final mfaActivado  = usuario?.mfaHabilitado ?? false;

    return AppShell(
      rutaActual:    '/perfil/mfa',
      rolUsuario:    usuario?.rol ?? '',
      nombreUsuario: usuario?.nombreCompleto ?? '',
      titulo:        'Verificación en dos pasos',
      subtitulo:     'Seguridad de tu cuenta',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: mfaActivado
                        ? const Color(0xFFECFDF5)
                        : const Color(0xFFFFF3CD),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Icon(
                    mfaActivado ? Icons.shield : Icons.shield_outlined,
                    color: mfaActivado
                        ? const Color(0xFF059669)
                        : const Color(0xFFD97706),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mfaActivado
                            ? 'Verificación activa'
                            : 'Verificación inactiva',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: mfaActivado
                              ? const Color(0xFF059669)
                              : const Color(0xFFD97706),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        mfaActivado
                            ? 'Tu cuenta está protegida con TOTP.'
                            : 'Activa el MFA para mayor seguridad.',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textTertiary),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          if (!mfaActivado) ...[

            const Text('Configurar verificación en dos pasos',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            const Text(
              'Usa cualquier app autenticadora compatible con TOTP:\n'
              '• Google Authenticator\n'
              '• Microsoft Authenticator\n'
              '• Bitwarden (Authenticator)\n'
              '• Authy\n'
              '• 1Password\n'
              '• Cualquier app que soporte TOTP (RFC 6238)',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary,
                  height: 1.6),
            ),
            const SizedBox(height: 16),
            mfaAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => EmptyState(
                titulo: 'Error', subtitulo: e.toString(),
                icono: Icons.error_outline, labelBoton: 'Reintentar',
                onBoton: () => ref.invalidate(mfaEstadoProvider),
              ),
              data: (data) => _PanelActivarMfa(
                qrBase64: data['qr_base64'] as String? ?? '',
                secret:   data['secret']   as String? ?? '',
                onActivado: () {
                  ref.invalidate(mfaEstadoProvider);
                  ref.read(authProvider.notifier).cargarUsuario();
                },
              ),
            ),
          ] else ...[

            const Text('Desactivar verificación en dos pasos',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.dangerBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.danger.withOpacity(0.3)),
              ),
              child: const Row(children: [
                Icon(Icons.warning_amber_outlined,
                    size: 16, color: AppColors.danger),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Al desactivar el MFA tu cuenta quedará protegida '
                    'solo por contraseña. Necesitarás ingresar tu contraseña '
                    'actual para confirmar.',
                    style: TextStyle(fontSize: 12, color: AppColors.danger,
                        height: 1.4),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            _PanelDesactivarMfa(
              onDesactivado: () {
                ref.invalidate(mfaEstadoProvider);
                ref.read(authProvider.notifier).cargarUsuario();
              },
            ),
          ],
        ]),
      ),
    );
  }
}


class _PanelActivarMfa extends ConsumerStatefulWidget {
  final String qrBase64;
  final String secret;
  final VoidCallback onActivado;
  const _PanelActivarMfa({
    required this.qrBase64,
    required this.secret,
    required this.onActivado,
  });
  @override
  ConsumerState<_PanelActivarMfa> createState() => _PanelActivarMfaState();
}

class _PanelActivarMfaState extends ConsumerState<_PanelActivarMfa> {
  final _codigoCtrl = TextEditingController();
  bool    _enviando = false;
  String? _error;

  @override
  void dispose() { _codigoCtrl.dispose(); super.dispose(); }

  Future<void> _activar() async {
    final codigo = _codigoCtrl.text.trim().replaceAll(' ', '');
    if (codigo.length != 6) {
      setState(() => _error = 'El código debe tener 6 dígitos.');
      return;
    }
    setState(() { _enviando = true; _error = null; });
    try {
      await ApiClient.instance.post(Endpoints.mfaSetup, data: {'codigo': codigo});
      widget.onActivado();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('MFA activado correctamente.'),
          backgroundColor: Color(0xFF059669),
        ));
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _error = 'Código incorrecto o expirado. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      const Text('Sigue estos pasos:',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
              color: AppColors.textPrimary)),
      const SizedBox(height: 12),


      _Paso(
        numero: '1',
        titulo: 'Escanea el código QR con tu app',
        child: widget.qrBase64.isNotEmpty
            ? Center(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),


                  child: Image.memory(
                    base64Decode(widget.qrBase64),
                    width: 160, height: 160,
                    fit: BoxFit.contain,
                  ),
                ),
              )
            : const Text('Cargando QR...',
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
      ),
      const SizedBox(height: 8),


      if (widget.secret.isNotEmpty) ...[
        const Text('¿No puedes escanear? Ingresa esta clave manualmente:',
            style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: widget.secret));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Clave copiada al portapapeles.'),
              duration: Duration(seconds: 2),
            ));
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              Expanded(
                child: Text(
                  widget.secret,
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    letterSpacing: 1.5,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const Icon(Icons.copy, size: 14, color: AppColors.textTertiary),
            ]),
          ),
        ),
        const SizedBox(height: 16),
      ],


      _Paso(
        numero: '2',
        titulo: 'Ingresa el código que muestra tu app',
        child: Column(children: [
          TextFormField(
            controller: _codigoCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            onChanged: (v) {
              if (_error != null) setState(() => _error = null);
              if (v.length == 6) _activar();
            },
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: 8,
            ),
            decoration: InputDecoration(
              hintText: '······',
              hintStyle: TextStyle(
                fontSize: 24, letterSpacing: 8,
                color: AppColors.textTertiary.withOpacity(0.4),
              ),
              counterText: '',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: const TextStyle(fontSize: 12, color: AppColors.danger)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _enviando ? null : _activar,
              child: _enviando
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Activar verificación en dos pasos'),
            ),
          ),
        ]),
      ),
    ]);
  }
}


class _PanelDesactivarMfa extends ConsumerStatefulWidget {
  final VoidCallback onDesactivado;
  const _PanelDesactivarMfa({required this.onDesactivado});
  @override
  ConsumerState<_PanelDesactivarMfa> createState() =>
      _PanelDesactivarMfaState();
}

class _PanelDesactivarMfaState extends ConsumerState<_PanelDesactivarMfa> {
  final _passCtrl = TextEditingController();
  bool    _verPass  = false;
  bool    _enviando = false;
  String? _error;

  @override
  void dispose() { _passCtrl.dispose(); super.dispose(); }

  Future<void> _desactivar() async {
    if (_passCtrl.text.isEmpty) {
      setState(() => _error = 'Ingresa tu contraseña.');
      return;
    }
    setState(() { _enviando = true; _error = null; });
    try {
      await ApiClient.instance.delete(
        Endpoints.mfaSetup,
        data: {'password': _passCtrl.text},
      );
      widget.onDesactivado();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('MFA desactivado.'),
          backgroundColor: Color(0xFFD97706),
        ));
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _error = 'Contraseña incorrecta. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const Text('Confirma tu contraseña actual:',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
              color: AppColors.textSecondary)),
      const SizedBox(height: 8),
      TextFormField(
        controller: _passCtrl,
        obscureText: !_verPass,
        onChanged: (_) { if (_error != null) setState(() => _error = null); },
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Tu contraseña',
          prefixIcon: const Icon(Icons.lock_outline,
              size: 16, color: AppColors.textTertiary),
          suffixIcon: IconButton(
            icon: Icon(
              _verPass ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 16, color: AppColors.textTertiary,
            ),
            onPressed: () => setState(() => _verPass = !_verPass),
          ),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 6),
        Text(_error!, style: const TextStyle(
            fontSize: 12, color: AppColors.danger)),
      ],
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _enviando ? null : _desactivar,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.danger,
            foregroundColor: Colors.white,
          ),
          child: _enviando
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Text('Desactivar MFA'),
        ),
      ),
    ]);
  }
}


class _Paso extends StatelessWidget {
  final String numero;
  final String titulo;
  final Widget child;
  const _Paso({required this.numero, required this.titulo, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 24, height: 24,
              decoration: const BoxDecoration(
                color: AppColors.accent, shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(numero,
                    style: const TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
            const SizedBox(width: 10),
            Text(titulo, style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500,
                color: AppColors.textPrimary)),
          ]),
          const SizedBox(height: 12),
          child,
        ]),
      ),
    );
  }
}
