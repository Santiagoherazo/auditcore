import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/services/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

class ClienteFormScreen extends ConsumerStatefulWidget {
  final String? clienteId;
  const ClienteFormScreen({super.key, this.clienteId});
  @override
  ConsumerState<ClienteFormScreen> createState() => _ClienteFormScreenState();
}

class _ClienteFormScreenState extends ConsumerState<ClienteFormScreen> {
  final _pageCtrl = PageController();
  int  _paso      = 0;
  bool _cargando  = false;
  String? _clienteIdCreado;

  // Paso 1 — Perfil legal
  final _razonCtrl          = TextEditingController();
  final _nitCtrl            = TextEditingController();
  final _digitoCtrl         = TextEditingController();
  final _matriculaCtrl      = TextEditingController();
  final _objetoCtrl         = TextEditingController();
  final _ciiuCtrl           = TextEditingController();
  String  _tipoPersona      = 'JURIDICA';
  String? _fechaConstitucion;
  String  _regimenTrib      = 'COMUN';
  bool    _respIva          = true;

  // Paso 2 — Representante legal
  final _repNombreCtrl      = TextEditingController();
  final _repDocCtrl         = TextEditingController();
  final _repCargoCtrl       = TextEditingController();
  final _repEmailCtrl       = TextEditingController();
  final _repTelCtrl         = TextEditingController();
  String  _repTipoDoc       = 'CC';

  // Paso 3 — Ubicación y contacto
  final _paisCtrl           = TextEditingController(text: 'Colombia');
  final _deptoCtrl          = TextEditingController();
  final _ciudadCtrl         = TextEditingController();
  final _direccionCtrl      = TextEditingController();
  final _cpCtrl             = TextEditingController();
  final _telCtrl            = TextEditingController();
  final _tel2Ctrl           = TextEditingController();
  final _emailCtrl          = TextEditingController();
  final _webCtrl            = TextEditingController();

  // Paso 4 — Segmentación
  String  _sector           = 'OTRO';
  final _subsectorCtrl      = TextEditingController();
  String  _tamano           = 'MEDIANA';
  final _empleadosCtrl      = TextEditingController();
  final _ingresosCtrl       = TextEditingController();

  // Paso 5 — Alcance y necesidad
  final _alcanceCtrl        = TextEditingController();
  final _normasCtrl         = TextEditingController();
  final _declaracionCtrl    = TextEditingController();
  String  _motivoAuditoria  = 'MEJORA_CONTINUA';
  String  _urgencia         = 'MEDIA';
  bool    _certPrevia       = false;
  final _certPreviaDetalleCtrl = TextEditingController();

  // Paso 6 — Contacto operativo
  final _contactoNombreCtrl  = TextEditingController();
  final _contactoApellidoCtrl= TextEditingController();
  final _contactoCargoCtrl   = TextEditingController();
  final _contactoEmailCtrl   = TextEditingController();
  final _contactoTelCtrl     = TextEditingController();
  final _contactoDeptoCtrl   = TextEditingController();
  String  _contactoTipo      = 'OPERATIVO';

  static const _pasos = [
    'Perfil Legal', 'Representante', 'Ubicación',
    'Segmentación', 'Alcance / Necesidad', 'Contacto Operativo',
  ];

  @override
  void dispose() {
    for (final c in [
      _razonCtrl, _nitCtrl, _digitoCtrl, _matriculaCtrl, _objetoCtrl, _ciiuCtrl,
      _repNombreCtrl, _repDocCtrl, _repCargoCtrl, _repEmailCtrl, _repTelCtrl,
      _paisCtrl, _deptoCtrl, _ciudadCtrl, _direccionCtrl, _cpCtrl,
      _telCtrl, _tel2Ctrl, _emailCtrl, _webCtrl,
      _subsectorCtrl, _empleadosCtrl, _ingresosCtrl,
      _alcanceCtrl, _normasCtrl, _declaracionCtrl, _certPreviaDetalleCtrl,
      _contactoNombreCtrl, _contactoApellidoCtrl, _contactoCargoCtrl,
      _contactoEmailCtrl, _contactoTelCtrl, _contactoDeptoCtrl,
    ]) c.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  void _irPaso(int paso) {
    setState(() => _paso = paso);
    _pageCtrl.animateToPage(paso,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  Future<void> _guardarYAvanzar() async {
    if (_cargando) return;
    setState(() => _cargando = true);
    try {
      final payload = _buildPayload();
      if (widget.clienteId != null || _clienteIdCreado != null) {
        final id = widget.clienteId ?? _clienteIdCreado!;
        await ApiClient.instance.patch('${Endpoints.clientes}$id/', data: payload);
      } else {
        final resp = await ApiClient.instance.post(Endpoints.clientes, data: payload);
        _clienteIdCreado = (resp.data as Map<String, dynamic>)['id']?.toString();
      }
      ref.invalidate(clientesProvider);
      if (_paso < _pasos.length - 1) {
        _irPaso(_paso + 1);
      } else {
        await _enviarAccesoCaracterizacion();
        if (mounted) {
          context.go('/clientes');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cliente creado. Se enviará el formulario de caracterización.')));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _enviarAccesoCaracterizacion() async {
    final id    = widget.clienteId ?? _clienteIdCreado;
    final email = _contactoEmailCtrl.text.trim().isEmpty
        ? _emailCtrl.text.trim()
        : _contactoEmailCtrl.text.trim();
    if (id == null || email.isEmpty) return;
    try {
      await ApiClient.instance.post('clientes/acceso-temporal/', data: {
        'cliente_id': id, 'email_destino': email,
      });
    } catch (_) {}
  }

  Map<String, dynamic> _buildPayload() {
    final raw = <String, dynamic>{
      'tipo_persona':    _tipoPersona,
      'razon_social':    _razonCtrl.text.trim(),
      'nit':             _nitCtrl.text.trim(),
      'sector':          _sector,
      'tamano':          _tamano,
      'motivo_auditoria':_motivoAuditoria,
      'urgencia':        _urgencia,
      'responsable_iva': _respIva,
      'tiene_certificacion_previa': _certPrevia,
      'estado':          'PROSPECTO',
      'normas_interes':  _normasCtrl.text.trim().isEmpty
          ? <String>[] : _normasCtrl.text.split(',').map((e) => e.trim()).toList(),
    };

    void addIfNotEmpty(String key, String value) {
      if (value.isNotEmpty) raw[key] = value;
    }
    void addIfNotNull(String key, dynamic value) {
      if (value != null) raw[key] = value;
    }

    addIfNotEmpty('digito_verificacion',          _digitoCtrl.text.trim());
    addIfNotEmpty('matricula_mercantil',           _matriculaCtrl.text.trim());
    addIfNotEmpty('objeto_social',                 _objetoCtrl.text.trim());
    addIfNotEmpty('codigo_ciiu',                   _ciiuCtrl.text.trim());
    addIfNotEmpty('regimen_tributario',            _regimenTrib);
    addIfNotEmpty('rep_legal_nombre',              _repNombreCtrl.text.trim());
    addIfNotEmpty('rep_legal_documento',           _repDocCtrl.text.trim());
    addIfNotEmpty('rep_legal_tipo_doc',            _repTipoDoc);
    addIfNotEmpty('rep_legal_cargo',               _repCargoCtrl.text.trim());
    addIfNotEmpty('rep_legal_email',               _repEmailCtrl.text.trim());
    addIfNotEmpty('rep_legal_telefono',            _repTelCtrl.text.trim());
    addIfNotEmpty('pais',                          _paisCtrl.text.trim());
    addIfNotEmpty('departamento',                  _deptoCtrl.text.trim());
    addIfNotEmpty('ciudad',                        _ciudadCtrl.text.trim());
    addIfNotEmpty('direccion_principal',           _direccionCtrl.text.trim());
    addIfNotEmpty('codigo_postal',                 _cpCtrl.text.trim());
    addIfNotEmpty('telefono',                      _telCtrl.text.trim());
    addIfNotEmpty('telefono_alt',                  _tel2Ctrl.text.trim());
    addIfNotEmpty('email',                         _emailCtrl.text.trim());
    addIfNotEmpty('sitio_web',                     _webCtrl.text.trim());
    addIfNotEmpty('subsector',                     _subsectorCtrl.text.trim());
    addIfNotEmpty('ingresos_anuales',              _ingresosCtrl.text.trim());
    addIfNotEmpty('alcance_descripcion',           _alcanceCtrl.text.trim());
    addIfNotEmpty('declaracion_necesidad',         _declaracionCtrl.text.trim());
    addIfNotEmpty('certificacion_previa_detalle',  _certPreviaDetalleCtrl.text.trim());
    addIfNotNull('num_empleados', int.tryParse(_empleadosCtrl.text.trim()));

    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final usuario = ref.watch(authProvider).valueOrNull;
    return AppShell(
      rutaActual:    '/clientes',
      rolUsuario:    usuario?.rol ?? '',
      nombreUsuario: usuario?.nombreCompleto ?? '',
      titulo:        widget.clienteId != null ? 'Editar cliente' : 'Nuevo cliente',
      child: Column(children: [
        _Stepper(paso: _paso, pasos: _pasos, onTap: _irPaso),
        Expanded(child: PageView(
          controller: _pageCtrl,
          physics: const NeverScrollableScrollPhysics(),
          onPageChanged: (p) => setState(() => _paso = p),
          children: [
            _PasoPerfil(
              tipoPersona: _tipoPersona, onTipoPersona: (v) => setState(() => _tipoPersona = v!),
              razonCtrl: _razonCtrl, nitCtrl: _nitCtrl, digitoCtrl: _digitoCtrl,
              matriculaCtrl: _matriculaCtrl, objetoCtrl: _objetoCtrl, ciiuCtrl: _ciiuCtrl,
              regimenTrib: _regimenTrib, onRegimen: (v) => setState(() => _regimenTrib = v!),
              respIva: _respIva, onRespIva: (v) => setState(() => _respIva = v),
              onSiguiente: _guardarYAvanzar, cargando: _cargando,
            ),
            _PasoRepresentante(
              nombreCtrl: _repNombreCtrl, docCtrl: _repDocCtrl,
              tipoDoc: _repTipoDoc, onTipoDoc: (v) => setState(() => _repTipoDoc = v!),
              cargoCtrl: _repCargoCtrl, emailCtrl: _repEmailCtrl, telCtrl: _repTelCtrl,
              tipoPersona: _tipoPersona,
              onAnterior: () => _irPaso(_paso - 1),
              onSiguiente: _guardarYAvanzar, cargando: _cargando,
            ),
            _PasoUbicacion(
              paisCtrl: _paisCtrl, deptoCtrl: _deptoCtrl, ciudadCtrl: _ciudadCtrl,
              direccionCtrl: _direccionCtrl, cpCtrl: _cpCtrl,
              telCtrl: _telCtrl, tel2Ctrl: _tel2Ctrl, emailCtrl: _emailCtrl, webCtrl: _webCtrl,
              onAnterior: () => _irPaso(_paso - 1),
              onSiguiente: _guardarYAvanzar, cargando: _cargando,
            ),
            _PasoSegmentacion(
              sector: _sector, onSector: (v) => setState(() => _sector = v!),
              subsectorCtrl: _subsectorCtrl,
              tamano: _tamano, onTamano: (v) => setState(() => _tamano = v!),
              empleadosCtrl: _empleadosCtrl, ingresosCtrl: _ingresosCtrl,
              onAnterior: () => _irPaso(_paso - 1),
              onSiguiente: _guardarYAvanzar, cargando: _cargando,
            ),
            _PasoAlcanceNecesidad(
              alcanceCtrl: _alcanceCtrl, normasCtrl: _normasCtrl,
              declaracionCtrl: _declaracionCtrl,
              motivo: _motivoAuditoria, onMotivo: (v) => setState(() => _motivoAuditoria = v!),
              urgencia: _urgencia, onUrgencia: (v) => setState(() => _urgencia = v!),
              certPrevia: _certPrevia, onCertPrevia: (v) => setState(() => _certPrevia = v),
              certPreviaDetalleCtrl: _certPreviaDetalleCtrl,
              onAnterior: () => _irPaso(_paso - 1),
              onSiguiente: _guardarYAvanzar, cargando: _cargando,
            ),
            _PasoContacto(
              tipo: _contactoTipo, onTipo: (v) => setState(() => _contactoTipo = v!),
              nombreCtrl: _contactoNombreCtrl, apellidoCtrl: _contactoApellidoCtrl,
              cargoCtrl: _contactoCargoCtrl, emailCtrl: _contactoEmailCtrl,
              telCtrl: _contactoTelCtrl, deptoCtrl: _contactoDeptoCtrl,
              onAnterior: () => _irPaso(_paso - 1),
              onFinalizar: _guardarYAvanzar, cargando: _cargando,
            ),
          ],
        )),
      ]),
    );
  }
}

// ── Stepper visual ────────────────────────────────────────────────────────────
class _Stepper extends StatelessWidget {
  final int paso;
  final List<String> pasos;
  final void Function(int) onTap;
  const _Stepper({required this.paso, required this.pasos, required this.onTap});

  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.white,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    child: Row(children: List.generate(pasos.length, (i) {
      final activo    = i == paso;
      final completado = i < paso;
      return Expanded(child: GestureDetector(
        onTap: () { if (completado) onTap(i); },
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            if (i > 0) Expanded(child: Container(height: 1,
                color: completado ? AppColors.accent : AppColors.border)),
            Container(
              width: 24, height: 24,
              decoration: BoxDecoration(
                color: activo ? AppColors.accent
                    : completado ? AppColors.accent
                    : AppColors.border,
                shape: BoxShape.circle,
              ),
              child: Center(child: completado
                ? const Icon(Icons.check, size: 13, color: Colors.white)
                : Text('${i + 1}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                    color: activo ? Colors.white : AppColors.textTertiary))),
            ),
            if (i < pasos.length - 1) Expanded(child: Container(height: 1,
                color: completado ? AppColors.accent : AppColors.border)),
          ]),
          const SizedBox(height: 4),
          Text(pasos[i],
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500,
                color: activo ? AppColors.accent
                    : completado ? AppColors.accentDark
                    : AppColors.textTertiary),
            textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
        ]),
      ));
    })),
  );
}

// ── Helpers compartidos ───────────────────────────────────────────────────────
Widget _campo(String label, Widget child, {bool requerido = false}) =>
  Padding(padding: const EdgeInsets.only(bottom: 14), child:
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$label${requerido ? ' *' : ''}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
              color: AppColors.textSecondary)),
      const SizedBox(height: 5),
      child,
    ]));

Widget _tf(TextEditingController ctrl, {String? hint, int? maxLines,
  TextInputType? teclado, String? Function(String?)? validator}) =>
  TextFormField(
    controller: ctrl, maxLines: maxLines ?? 1,
    keyboardType: teclado, validator: validator,
    style: const TextStyle(fontSize: 13),
    decoration: InputDecoration(hintText: hint));

Widget _dd<T>(T value, List<(T, String)> items, void Function(T?) onChange) =>
  DropdownButtonFormField<T>(
    value: value,
    style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
    items: items.map((i) => DropdownMenuItem(value: i.$1, child: Text(i.$2))).toList(),
    onChanged: onChange);

Widget _navRow({required VoidCallback? onAnterior, required VoidCallback onSiguiente,
  required bool cargando, String labelSig = 'Guardar y continuar'}) =>
  Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), child:
    Row(children: [
      if (onAnterior != null) ...[
        OutlinedButton.icon(
          onPressed: onAnterior,
          icon: const Icon(Icons.arrow_back, size: 15),
          label: const Text('Anterior')),
        const SizedBox(width: 10),
      ],
      Expanded(child: ElevatedButton(
        onPressed: cargando ? null : onSiguiente,
        child: cargando
          ? const SizedBox(width: 16, height: 16,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : Text(labelSig))),
    ]));

// ── Paso 1: Perfil Legal ──────────────────────────────────────────────────────
class _PasoPerfil extends StatelessWidget {
  final String tipoPersona;
  final void Function(String?) onTipoPersona;
  final TextEditingController razonCtrl, nitCtrl, digitoCtrl, matriculaCtrl, objetoCtrl, ciiuCtrl;
  final String regimenTrib;
  final void Function(String?) onRegimen;
  final bool respIva;
  final void Function(bool) onRespIva;
  final VoidCallback onSiguiente;
  final bool cargando;
  const _PasoPerfil({
    required this.tipoPersona, required this.onTipoPersona,
    required this.razonCtrl, required this.nitCtrl, required this.digitoCtrl,
    required this.matriculaCtrl, required this.objetoCtrl, required this.ciiuCtrl,
    required this.regimenTrib, required this.onRegimen,
    required this.respIva, required this.onRespIva,
    required this.onSiguiente, required this.cargando,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Card(child: Padding(padding: const EdgeInsets.all(16), child:
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Tipo de persona', style: TextStyle(fontSize: 13,
              fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          Row(children: [
            _TipoChip(label: 'Persona Jurídica', selected: tipoPersona == 'JURIDICA',
                onTap: () => onTipoPersona('JURIDICA')),
            const SizedBox(width: 10),
            _TipoChip(label: 'Persona Natural', selected: tipoPersona == 'NATURAL',
                onTap: () => onTipoPersona('NATURAL')),
          ]),
        ]))),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(16), child:
        Column(children: [
          _campo('Razón Social / Nombre', _tf(razonCtrl,
              hint: tipoPersona == 'JURIDICA' ? 'Empresa S.A.S.' : 'Nombre completo'), requerido: true),
          Row(children: [
            Expanded(child: _campo('NIT / RUT / Cédula',
                _tf(nitCtrl, hint: '900.000.000'), requerido: true)),
            const SizedBox(width: 10),
            SizedBox(width: 70, child: _campo('Dígito',
                _tf(digitoCtrl, hint: '0'))),
          ]),
          if (tipoPersona == 'JURIDICA') ...[
            _campo('Matrícula mercantil', _tf(matriculaCtrl, hint: 'No. de matrícula')),
            _campo('Objeto social / Actividad principal',
                _tf(objetoCtrl, hint: 'Describe la actividad económica...', maxLines: 2)),
            _campo('Código CIIU', _tf(ciiuCtrl, hint: 'Ej: 6201')),
            _campo('Régimen tributario', _dd(regimenTrib, const [
              ('COMUN',          'Régimen Común'),
              ('SIMPLIFICADO',   'Régimen Simplificado'),
              ('ESPECIAL',       'Régimen Especial'),
              ('NO_RESPONSABLE', 'No Responsable de IVA'),
            ], onRegimen)),
            Row(children: [
              Switch(value: respIva, onChanged: onRespIva,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
              const SizedBox(width: 8),
              const Text('Responsable de IVA',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ]),
          ],
        ]))),
      _navRow(onAnterior: null, onSiguiente: onSiguiente, cargando: cargando),
    ]));
}

class _TipoChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TipoChip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? AppColors.accent : AppColors.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: selected ? AppColors.accent : AppColors.border),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
          color: selected ? Colors.white : AppColors.textSecondary))));
}

// ── Paso 2: Representante Legal ───────────────────────────────────────────────
class _PasoRepresentante extends StatelessWidget {
  final TextEditingController nombreCtrl, docCtrl, cargoCtrl, emailCtrl, telCtrl;
  final String tipoDoc, tipoPersona;
  final void Function(String?) onTipoDoc;
  final VoidCallback onAnterior, onSiguiente;
  final bool cargando;
  const _PasoRepresentante({
    required this.nombreCtrl, required this.docCtrl, required this.tipoDoc,
    required this.onTipoDoc, required this.cargoCtrl, required this.emailCtrl,
    required this.telCtrl, required this.tipoPersona,
    required this.onAnterior, required this.onSiguiente, required this.cargando,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(children: [
      Card(child: Padding(padding: const EdgeInsets.all(16), child:
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            tipoPersona == 'JURIDICA'
              ? 'Representante Legal de la empresa'
              : 'Datos del titular',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          _campo('Nombre completo',
              _tf(nombreCtrl, hint: 'Nombre y apellido del representante'), requerido: true),
          Row(children: [
            SizedBox(width: 110, child: _campo('Tipo doc.',
                _dd(tipoDoc, const [
                  ('CC', 'C.C.'), ('CE', 'C.E.'),
                  ('PAS', 'Pasaporte'), ('NIT', 'NIT'),
                ], onTipoDoc))),
            const SizedBox(width: 10),
            Expanded(child: _campo('Número de documento',
                _tf(docCtrl, hint: '1234567890'))),
          ]),
          _campo('Cargo', _tf(cargoCtrl,
              hint: tipoPersona == 'JURIDICA' ? 'Gerente General' : 'Propietario')),
          _campo('Email del representante',
              _tf(emailCtrl, hint: 'rep@empresa.com', teclado: TextInputType.emailAddress)),
          _campo('Teléfono',
              _tf(telCtrl, hint: '+57 300 000 0000', teclado: TextInputType.phone)),
        ]))),
      _navRow(onAnterior: onAnterior, onSiguiente: onSiguiente, cargando: cargando),
    ]));
}

// ── Paso 3: Ubicación y Contacto ──────────────────────────────────────────────
class _PasoUbicacion extends StatelessWidget {
  final TextEditingController paisCtrl, deptoCtrl, ciudadCtrl, direccionCtrl,
      cpCtrl, telCtrl, tel2Ctrl, emailCtrl, webCtrl;
  final VoidCallback onAnterior, onSiguiente;
  final bool cargando;
  const _PasoUbicacion({
    required this.paisCtrl, required this.deptoCtrl, required this.ciudadCtrl,
    required this.direccionCtrl, required this.cpCtrl,
    required this.telCtrl, required this.tel2Ctrl,
    required this.emailCtrl, required this.webCtrl,
    required this.onAnterior, required this.onSiguiente, required this.cargando,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(children: [
      Card(child: Padding(padding: const EdgeInsets.all(16), child:
        Column(children: [
          const Align(alignment: Alignment.centerLeft, child:
            Text('Sede principal', style: TextStyle(fontSize: 13,
                fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _campo('País', _tf(paisCtrl, hint: 'Colombia'), requerido: true)),
            const SizedBox(width: 10),
            Expanded(child: _campo('Departamento', _tf(deptoCtrl, hint: 'Cundinamarca'))),
          ]),
          Row(children: [
            Expanded(child: _campo('Ciudad *', _tf(ciudadCtrl, hint: 'Bogotá'), requerido: true)),
            const SizedBox(width: 10),
            SizedBox(width: 100, child: _campo('Código postal', _tf(cpCtrl, hint: '110111'))),
          ]),
          _campo('Dirección principal', _tf(direccionCtrl, hint: 'Cra. 7 # 45-23, Piso 3'), requerido: true),
        ]))),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(16), child:
        Column(children: [
          const Align(alignment: Alignment.centerLeft, child:
            Text('Datos de contacto', style: TextStyle(fontSize: 13,
                fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _campo('Teléfono principal',
                _tf(telCtrl, hint: '+57 1 234 5678', teclado: TextInputType.phone))),
            const SizedBox(width: 10),
            Expanded(child: _campo('Teléfono alternativo',
                _tf(tel2Ctrl, hint: '+57 300 000 0000', teclado: TextInputType.phone))),
          ]),
          _campo('Email corporativo',
              _tf(emailCtrl, hint: 'info@empresa.com', teclado: TextInputType.emailAddress)),
          _campo('Sitio web', _tf(webCtrl, hint: 'https://empresa.com',
              teclado: TextInputType.url)),
        ]))),
      _navRow(onAnterior: onAnterior, onSiguiente: onSiguiente, cargando: cargando),
    ]));
}

// ── Paso 4: Segmentación ──────────────────────────────────────────────────────
class _PasoSegmentacion extends StatelessWidget {
  final String sector, tamano;
  final void Function(String?) onSector, onTamano;
  final TextEditingController subsectorCtrl, empleadosCtrl, ingresosCtrl;
  final VoidCallback onAnterior, onSiguiente;
  final bool cargando;
  const _PasoSegmentacion({
    required this.sector, required this.onSector,
    required this.subsectorCtrl, required this.tamano, required this.onTamano,
    required this.empleadosCtrl, required this.ingresosCtrl,
    required this.onAnterior, required this.onSiguiente, required this.cargando,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(children: [
      Card(child: Padding(padding: const EdgeInsets.all(16), child:
        Column(children: [
          _campo('Sector económico', _dd(sector, const [
            ('TECNOLOGIA',    'Tecnología'),
            ('SALUD',         'Salud'),
            ('FINANCIERO',    'Financiero / Fintech'),
            ('MANUFACTURA',   'Manufactura / Industrial'),
            ('SERVICIOS',     'Servicios'),
            ('GOBIERNO',      'Gobierno / Sector Público'),
            ('EDUCACION',     'Educación'),
            ('ENERGIA',       'Energía y Recursos'),
            ('TRANSPORTE',    'Transporte y Logística'),
            ('CONSTRUCCION',  'Construcción e Inmobiliario'),
            ('COMERCIO',      'Comercio y Retail'),
            ('AGROPECUARIO',  'Agropecuario'),
            ('TELECOMUNICACIONES', 'Telecomunicaciones'),
            ('SEGUROS',       'Seguros'),
            ('OTRO',          'Otro'),
          ], onSector), requerido: true),
          _campo('Subsector / Nicho', _tf(subsectorCtrl, hint: 'Ej: Fintech B2B, Salud preventiva...')),
          _campo('Tamaño de la empresa', _dd(tamano, const [
            ('MICRO',   'Microempresa (1-10 empleados)'),
            ('PEQUENA', 'Pequeña (11-50 empleados)'),
            ('MEDIANA', 'Mediana (51-250 empleados)'),
            ('GRANDE',  'Grande (251-1000 empleados)'),
            ('CORP',    'Corporación (>1000 empleados)'),
          ], onTamano), requerido: true),
          Row(children: [
            Expanded(child: _campo('Número de empleados',
                _tf(empleadosCtrl, hint: '150', teclado: TextInputType.number))),
            const SizedBox(width: 10),
            Expanded(child: _campo('Ingresos anuales aprox.',
                _tf(ingresosCtrl, hint: 'Ej: \$500M - \$1.000M COP'))),
          ]),
        ]))),
      _navRow(onAnterior: onAnterior, onSiguiente: onSiguiente, cargando: cargando),
    ]));
}

// ── Paso 5: Alcance y Necesidad ───────────────────────────────────────────────
class _PasoAlcanceNecesidad extends StatelessWidget {
  final TextEditingController alcanceCtrl, normasCtrl, declaracionCtrl, certPreviaDetalleCtrl;
  final String motivo, urgencia;
  final void Function(String?) onMotivo, onUrgencia;
  final bool certPrevia;
  final void Function(bool) onCertPrevia;
  final VoidCallback onAnterior, onSiguiente;
  final bool cargando;
  const _PasoAlcanceNecesidad({
    required this.alcanceCtrl, required this.normasCtrl,
    required this.declaracionCtrl, required this.certPreviaDetalleCtrl,
    required this.motivo, required this.onMotivo,
    required this.urgencia, required this.onUrgencia,
    required this.certPrevia, required this.onCertPrevia,
    required this.onAnterior, required this.onSiguiente, required this.cargando,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(children: [
      Card(child: Padding(padding: const EdgeInsets.all(16), child:
        Column(children: [
          _campo('Tipo de auditoría solicitada',
              _tf(alcanceCtrl, hint: 'ISO 27001, Financiera, Control Interno...', maxLines: 2),
              requerido: true),
          _campo('Normas de interés (separadas por coma)',
              _tf(normasCtrl, hint: 'ISO 27001, ISO 9001, NIIF, SOX...')),
          _campo('Motivo principal de la auditoría', _dd(motivo, const [
            ('REQUERIMIENTO_LEGAL',   'Requerimiento legal / regulatorio'),
            ('REQUERIMIENTO_CLIENTE', 'Exigencia de clientes o socios'),
            ('MEJORA_CONTINUA',       'Mejora continua interna'),
            ('FALLA_INTERNA',         'Falla o incidente interno detectado'),
            ('EXPANSION',             'Expansión de mercado / certificación nueva'),
            ('RENOVACION',            'Renovación de certificación existente'),
            ('OTRO',                  'Otro'),
          ], onMotivo), requerido: true),
          _campo('Declaración de necesidad',
              _tf(declaracionCtrl,
                  hint: 'Describa por qué busca la auditoría y qué espera lograr...',
                  maxLines: 3), requerido: true),
          _campo('Nivel de urgencia', _dd(urgencia, const [
            ('BAJA',    'Baja — sin fecha crítica'),
            ('MEDIA',   'Media — en los próximos 6 meses'),
            ('ALTA',    'Alta — en los próximos 3 meses'),
            ('CRITICA', 'Crítica — inmediata'),
          ], onUrgencia)),
          Row(children: [
            Switch(value: certPrevia, onChanged: onCertPrevia,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
            const SizedBox(width: 8),
            const Expanded(child: Text('¿Tiene certificación previa?',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary))),
          ]),
          if (certPrevia)
            _campo('Detalle de certificación previa',
                _tf(certPreviaDetalleCtrl,
                    hint: 'Norma, entidad certificadora, vigencia...', maxLines: 2)),
        ]))),
      _navRow(onAnterior: onAnterior, onSiguiente: onSiguiente, cargando: cargando),
    ]));
}

// ── Paso 6: Contacto Operativo ────────────────────────────────────────────────
class _PasoContacto extends StatelessWidget {
  final String tipo;
  final void Function(String?) onTipo;
  final TextEditingController nombreCtrl, apellidoCtrl, cargoCtrl,
      emailCtrl, telCtrl, deptoCtrl;
  final VoidCallback onAnterior, onFinalizar;
  final bool cargando;
  const _PasoContacto({
    required this.tipo, required this.onTipo,
    required this.nombreCtrl, required this.apellidoCtrl, required this.cargoCtrl,
    required this.emailCtrl, required this.telCtrl, required this.deptoCtrl,
    required this.onAnterior, required this.onFinalizar, required this.cargando,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.infoBg,
            borderRadius: BorderRadius.circular(8)),
        child: Row(children: const [
          Icon(Icons.info_outline, size: 16, color: AppColors.info),
          SizedBox(width: 8),
          Expanded(child: Text(
            'El contacto operativo recibirá el formulario de caracterización '
            'para completar la información del cliente y coordinar el cronograma.',
            style: TextStyle(fontSize: 12, color: AppColors.info, height: 1.4))),
        ])),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(16), child:
        Column(children: [
          _campo('Tipo de contacto', _dd(tipo, const [
            ('OPERATIVO',     'Contacto Operativo / Punto de Enlace'),
            ('GERENCIAL',     'Gerencial / Directivo'),
            ('TECNICO',       'Técnico'),
            ('ADMINISTRATIVO','Administrativo'),
            ('JURIDICO',      'Jurídico'),
            ('FINANCIERO',    'Financiero'),
          ], onTipo)),
          Row(children: [
            Expanded(child: _campo('Nombre *', _tf(nombreCtrl, hint: 'Juan'), requerido: true)),
            const SizedBox(width: 10),
            Expanded(child: _campo('Apellido *', _tf(apellidoCtrl, hint: 'Pérez'), requerido: true)),
          ]),
          _campo('Cargo', _tf(cargoCtrl, hint: 'Jefe de Sistemas')),
          _campo('Departamento / Área', _tf(deptoCtrl, hint: 'Tecnología')),
          _campo('Email *',
              _tf(emailCtrl, hint: 'jperez@empresa.com',
                  teclado: TextInputType.emailAddress), requerido: true),
          _campo('Celular / Teléfono',
              _tf(telCtrl, hint: '+57 300 000 0000', teclado: TextInputType.phone)),
        ]))),
      _navRow(
        onAnterior: onAnterior, onSiguiente: onFinalizar, cargando: cargando,
        labelSig: 'Crear cliente y enviar formulario'),
    ]));
}
