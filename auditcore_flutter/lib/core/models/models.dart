class UsuarioModel {
  final String id;
  final String email;
  final String nombre;
  final String apellido;
  final String nombreCompleto;
  final String rol;
  final String estado;
  final bool mfaHabilitado;

  const UsuarioModel({
    required this.id,
    required this.email,
    required this.nombre,
    required this.apellido,
    required this.nombreCompleto,
    required this.rol,
    required this.estado,
    required this.mfaHabilitado,
  });

  factory UsuarioModel.fromJson(Map<String, dynamic> j) => UsuarioModel(
        id:             j['id']?.toString() ?? '',
        email:          j['email'] ?? '',
        nombre:         j['nombre'] ?? '',
        apellido:       j['apellido'] ?? '',
        nombreCompleto: j['nombre_completo'] ?? '',
        rol:            j['rol'] ?? '',
        estado:         j['estado'] ?? '',
        mfaHabilitado:  j['mfa_habilitado'] ?? false,
      );
}


class ClienteModel {
  final String id;
  final String razonSocial;
  final String nit;
  final String sector;
  final String pais;
  final String ciudad;
  final String email;
  final String estado;
  final List<ContactoModel> contactos;

  const ClienteModel({
    required this.id,
    required this.razonSocial,
    required this.nit,
    required this.sector,
    required this.pais,
    required this.ciudad,
    required this.email,
    required this.estado,
    this.contactos = const [],
  });

  factory ClienteModel.fromJson(Map<String, dynamic> j) => ClienteModel(
        id:          j['id']?.toString() ?? '',
        razonSocial: j['razon_social'] ?? '',
        nit:         j['nit'] ?? '',
        sector:      j['sector'] ?? '',
        pais:        j['pais'] ?? '',
        ciudad:      j['ciudad'] ?? '',
        email:       j['email'] ?? '',
        estado:      j['estado'] ?? '',
        contactos:   (j['contactos'] as List? ?? [])
            .map((c) => ContactoModel.fromJson(c as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'razon_social': razonSocial,
        'nit':          nit,
        'sector':       sector,
        'pais':         pais,
        'ciudad':       ciudad,
        'email':        email,
        'estado':       estado,
      };
}

class ContactoModel {
  final String id;
  final String nombre;
  final String apellido;
  final String cargo;
  final String email;
  final String telefono;
  final bool esPrincipal;

  const ContactoModel({
    required this.id,
    required this.nombre,
    required this.apellido,
    required this.cargo,
    required this.email,
    required this.telefono,
    required this.esPrincipal,
  });

  factory ContactoModel.fromJson(Map<String, dynamic> j) => ContactoModel(
        id:          j['id']?.toString() ?? '',
        nombre:      j['nombre'] ?? '',
        apellido:    j['apellido'] ?? '',
        cargo:       j['cargo'] ?? '',
        email:       j['email'] ?? '',
        telefono:    j['telefono'] ?? '',
        esPrincipal: j['es_principal'] ?? false,
      );
}


class ExpedienteModel {
  final String id;
  final String numeroExpediente;
  final String? clienteId;
  final String clienteNombre;
  final String? tipoId;
  final String tipoNombre;
  final String estado;
  final double porcentajeAvance;
  final String auditorNombre;
  final String fechaApertura;
  final String? fechaEstimadaCierre;
  final List<FaseModel> fases;

  const ExpedienteModel({
    required this.id,
    required this.numeroExpediente,
    this.clienteId,
    required this.clienteNombre,
    this.tipoId,
    required this.tipoNombre,
    required this.estado,
    required this.porcentajeAvance,
    required this.auditorNombre,
    required this.fechaApertura,
    this.fechaEstimadaCierre,
    this.fases = const [],
  });

  factory ExpedienteModel.fromJson(Map<String, dynamic> j) {

    double parseAvance(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    return ExpedienteModel(
      id:                   j['id']?.toString() ?? '',
      numeroExpediente:     j['numero_expediente'] ?? '',
      clienteId:            j['cliente']?.toString(),
      clienteNombre:        j['cliente_nombre'] ?? '',
      tipoId:               j['tipo_auditoria']?.toString(),
      tipoNombre:           j['tipo_nombre'] ?? '',
      estado:               j['estado'] ?? '',
      porcentajeAvance:     parseAvance(j['porcentaje_avance']),
      auditorNombre:        j['auditor_nombre'] ?? '',
      fechaApertura:        j['fecha_apertura'] ?? '',
      fechaEstimadaCierre:  j['fecha_estimada_cierre']?.toString(),
      fases:                (j['fases'] as List? ?? [])
          .map((f) => FaseModel.fromJson(f as Map<String, dynamic>))
          .toList(),
    );
  }
}

class FaseModel {
  final String id;
  final String faseNombre;
  final int orden;
  final String estado;
  final String? fechaInicio;
  final String? fechaFin;

  const FaseModel({
    required this.id,
    required this.faseNombre,
    required this.orden,
    required this.estado,
    this.fechaInicio,
    this.fechaFin,
  });

  factory FaseModel.fromJson(Map<String, dynamic> j) => FaseModel(
        id:          j['id']?.toString() ?? '',
        faseNombre:  j['fase_nombre'] ?? '',
        orden:       j['orden'] ?? 0,
        estado:      j['estado'] ?? '',
        fechaInicio: j['fecha_inicio']?.toString(),
        fechaFin:    j['fecha_fin']?.toString(),
      );
}


class HallazgoModel {
  final String id;
  final String expediente;
  final String tipo;
  final String nivelCriticidad;
  final String titulo;
  final String descripcion;
  final String estado;
  final String? fechaLimiteCierre;
  final String reportadoNombre;
  final String fechaCreacion;

  const HallazgoModel({
    required this.id,
    required this.expediente,
    required this.tipo,
    required this.nivelCriticidad,
    required this.titulo,
    required this.descripcion,
    required this.estado,
    this.fechaLimiteCierre,
    required this.reportadoNombre,
    required this.fechaCreacion,
  });

  factory HallazgoModel.fromJson(Map<String, dynamic> j) => HallazgoModel(
        id:               j['id']?.toString() ?? '',
        expediente:       j['expediente']?.toString() ?? '',
        tipo:             j['tipo'] ?? '',
        nivelCriticidad:  j['nivel_criticidad'] ?? '',
        titulo:           j['titulo'] ?? '',
        descripcion:      j['descripcion'] ?? '',
        estado:           j['estado'] ?? '',
        fechaLimiteCierre: j['fecha_limite_cierre']?.toString(),
        reportadoNombre:  j['reportado_nombre'] ?? '',
        fechaCreacion:    j['fecha_creacion'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'expediente':       expediente,
        'tipo':             tipo,
        'nivel_criticidad': nivelCriticidad,
        'titulo':           titulo,
        'descripcion':      descripcion,
        'estado':           estado,
        if (fechaLimiteCierre != null) 'fecha_limite_cierre': fechaLimiteCierre,
      };
}


class CertificacionModel {
  final String id;
  final String numero;
  final String clienteNombre;
  final String tipoNombre;
  final String codigoVerificacion;
  final String fechaEmision;
  final String fechaVencimiento;
  final String estado;
  final int? diasParaVencer;
  final String? certificadoPdf;

  const CertificacionModel({
    required this.id,
    required this.numero,
    required this.clienteNombre,
    required this.tipoNombre,
    required this.codigoVerificacion,
    required this.fechaEmision,
    required this.fechaVencimiento,
    required this.estado,
    this.diasParaVencer,
    this.certificadoPdf,
  });

  factory CertificacionModel.fromJson(Map<String, dynamic> j) => CertificacionModel(
        id:                  j['id']?.toString() ?? '',
        numero:              j['numero'] ?? '',
        clienteNombre:       j['cliente_nombre'] ?? '',
        tipoNombre:          j['tipo_nombre'] ?? '',
        codigoVerificacion:  j['codigo_verificacion'] ?? '',
        fechaEmision:        j['fecha_emision'] ?? '',
        fechaVencimiento:    j['fecha_vencimiento'] ?? '',
        estado:              j['estado'] ?? '',
        diasParaVencer:      j['dias_para_vencer'] as int?,
        certificadoPdf:      j['certificado_pdf']?.toString(),
      );
}


class MensajeModel {
  final String id;
  final String rol;
  final String contenido;
  final int tokensUsados;
  final String fecha;

  const MensajeModel({
    required this.id,
    required this.rol,
    required this.contenido,
    required this.tokensUsados,
    required this.fecha,
  });

  factory MensajeModel.fromJson(Map<String, dynamic> j) => MensajeModel(
        id:           j['id']?.toString() ?? '',
        rol:          j['rol'] ?? '',
        contenido:    j['contenido'] ?? '',
        tokensUsados: j['tokens_usados'] ?? 0,
        fecha:        j['fecha'] ?? '',
      );
}


class BitacoraModel {
  final String id;
  final String tipoUsuario;
  final String usuarioNombre;
  final String accion;
  final String descripcion;
  final String entidadAfectada;
  final String fecha;

  const BitacoraModel({
    required this.id,
    required this.tipoUsuario,
    required this.usuarioNombre,
    required this.accion,
    required this.descripcion,
    required this.entidadAfectada,
    required this.fecha,
  });

  factory BitacoraModel.fromJson(Map<String, dynamic> j) => BitacoraModel(
        id:               j['id']?.toString() ?? '',
        tipoUsuario:      j['tipo_usuario'] ?? '',
        usuarioNombre:    j['usuario_nombre'] ?? 'Sistema',
        accion:           j['accion'] ?? '',
        descripcion:      j['descripcion'] ?? '',
        entidadAfectada:  j['entidad_afectada'] ?? '',
        fecha:            j['fecha'] ?? '',
      );
}


class DashboardModel {
  final int clientesActivos;
  final int expedientesActivos;

  final int expedientesBorrador;
  final int expedientesCompletados;
  final int certificacionesVigentes;
  final int certificacionesPorVencer;
  final int hallazgosCriticosAbiertos;
  final List<Map<String, dynamic>> expedientesPorEstado;

  const DashboardModel({
    required this.clientesActivos,
    required this.expedientesActivos,
    this.expedientesBorrador = 0,
    required this.expedientesCompletados,
    required this.certificacionesVigentes,
    required this.certificacionesPorVencer,
    required this.hallazgosCriticosAbiertos,
    required this.expedientesPorEstado,
  });

  factory DashboardModel.fromJson(Map<String, dynamic> j) => DashboardModel(


        clientesActivos:           j['clientes_activos'] as int? ?? 0,
        expedientesActivos:        j['expedientes_activos'] ?? 0,
        expedientesBorrador:       j['expedientes_borrador'] ?? 0,
        expedientesCompletados:    j['expedientes_completados'] ?? 0,
        certificacionesVigentes:   j['certificaciones_vigentes'] ?? 0,
        certificacionesPorVencer:  j['certificaciones_por_vencer'] ?? 0,
        hallazgosCriticosAbiertos: j['hallazgos_criticos_abiertos'] ?? 0,
        expedientesPorEstado:      List<Map<String, dynamic>>.from(
            j['expedientes_por_estado'] ?? []),
      );
}


class ChecklistEjecucionModel {
  final String id;
  final String expedienteId;

  final String itemId;

  final String descripcion;
  final String estado;
  final String? observacion;

  const ChecklistEjecucionModel({
    required this.id,
    required this.expedienteId,
    required this.itemId,
    required this.descripcion,
    required this.estado,
    this.observacion,
  });

  factory ChecklistEjecucionModel.fromJson(Map<String, dynamic> j) =>
      ChecklistEjecucionModel(
        id:           j['id']?.toString() ?? '',
        expedienteId: j['expediente']?.toString() ?? '',
        itemId:       j['item']?.toString() ?? '',
        descripcion:  j['item_descripcion'] ?? j['descripcion'] ?? '',
        estado:       j['estado'] ?? 'PENDIENTE',
        observacion:  j['observacion']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'estado': estado,
        if (observacion != null) 'observacion': observacion,
      };
}
