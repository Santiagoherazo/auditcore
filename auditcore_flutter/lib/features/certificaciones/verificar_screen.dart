import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/providers.dart';
import '../../core/theme/app_theme.dart';

class VerificarScreen extends ConsumerStatefulWidget {
  final String? codigoInicial;
  const VerificarScreen({super.key, this.codigoInicial});
  @override
  ConsumerState<VerificarScreen> createState() => _VerificarScreenState();
}

class _VerificarScreenState extends ConsumerState<VerificarScreen> {
  final _ctrl = TextEditingController();
  Map<String, dynamic>? _resultado;
  bool _cargando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.codigoInicial != null) {
      _ctrl.text = widget.codigoInicial!;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _verificar());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _verificar() async {
    if (_ctrl.text.trim().isEmpty) return;
    setState(() {
      _cargando = true;
      _resultado = null;
      _error = null;
    });
    try {
      final res =
          await ref.read(certServiceProvider).verificar(_ctrl.text.trim());
      setState(() => _resultado = res);
    } catch (_) {
      setState(() =>
          _error = 'No se pudo verificar el certificado. Revisa el código.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final valido = _resultado?['valido'] == true;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Verificar certificado')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(children: [

            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: AppColors.accentLight,
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(Icons.verified_outlined,
                  size: 28, color: AppColors.accent),
            ),
            const SizedBox(height: 14),
            const Text('Verificación de autenticidad',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            const Text(
              'Ingresa el código de verificación del certificado.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 28),


            TextField(
              controller: _ctrl,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Código de verificación',
                prefixIcon: const Icon(Icons.qr_code_outlined,
                    size: 16, color: AppColors.textTertiary),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search, size: 18,
                      color: AppColors.textTertiary),
                  onPressed: _verificar,
                ),
                filled: true,
                fillColor: AppColors.white,
              ),
              onSubmitted: (_) => _verificar(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _cargando ? null : _verificar,
                child: _cargando
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Verificar'),
              ),
            ),


            if (_resultado != null) ...[
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: valido ? AppColors.successBg : AppColors.dangerBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: valido
                        ? AppColors.success.withOpacity(0.3)
                        : AppColors.danger.withOpacity(0.3),
                    width: 0.5,
                  ),
                ),
                child: Column(children: [
                  Icon(
                    valido ? Icons.check_circle_outline : Icons.cancel_outlined,
                    size: 40,
                    color: valido ? AppColors.success : AppColors.danger,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    valido ? 'Certificado VÁLIDO' : 'Certificado NO ENCONTRADO',
                    style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600,
                      color: valido ? AppColors.success : AppColors.danger,
                    ),
                  ),
                  if (valido) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    ...[
                      ['Número',         _resultado!['numero']],
                      ['Empresa',        _resultado!['cliente']],
                      ['Tipo',           _resultado!['tipo_auditoria']],
                      ['Fecha emisión',  _resultado!['fecha_emision']],
                      ['Válido hasta',   _resultado!['fecha_vencimiento']],
                      ['Estado',         _resultado!['estado']],
                    ].map((row) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        SizedBox(
                          width: 110,
                          child: Text(row[0] as String,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary)),
                        ),
                        Expanded(
                          child: Text(row[1]?.toString() ?? '—',
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w500,
                                  color: AppColors.textPrimary)),
                        ),
                      ]),
                    )),
                  ],
                ]),
              ),
            ],


            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.dangerBg,
                  borderRadius: BorderRadius.circular(8),
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
            ],
          ]),
        ),
      ),
    );
  }
}
