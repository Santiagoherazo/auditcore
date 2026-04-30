class Endpoints {
  // Auth
  static const login   = 'auth/login/';
  static const refresh = 'auth/refresh/';
  static const logout  = 'auth/logout/';

  // Usuarios
  static const usuarios  = 'usuarios/';
  static const usuarioMe = 'usuarios/me/';
  static String usuarioDesactivar(String id) => 'usuarios/$id/desactivar/';

  // Clientes
  static const clientes = 'clientes/';
  // Draft (formulario multi-paso Redis → PostgreSQL)
  static const clienteDraft              = 'clientes/draft/';
  static String clienteDraftUpdate(String id)  => 'clientes/draft/$id/';
  static String clienteDraftCommit(String id)  => 'clientes/draft/$id/commit/';
  static String cliente(String id)             => 'clientes/$id/';
  static String clienteDashboard(String id)    => 'clientes/$id/dashboard/';
  static String clienteCambiarEstado(String id)=> 'clientes/$id/cambiar-estado/';

  // Tipos de auditoría
  static const tiposAuditoria = 'tipos-auditoria/';
  static String tipoAuditoria(String id) => 'tipos-auditoria/$id/';

  // Expedientes
  static const expedientes = 'expedientes/';
  static String expediente(String id)         => 'expedientes/$id/';
  static String expedienteBitacora(String id) => 'expedientes/$id/bitacora/';
  static String expedienteDashboard(String id)=> 'expedientes/$id/dashboard/';
  static String expedienteCambiarEstado(String id) => 'expedientes/$id/cambiar_estado/';

  // Hallazgos
  static const hallazgos = 'hallazgos/';
  static String hallazgo(String id) => 'hallazgos/$id/';

  // Evidencias
  static const evidencias = 'evidencias/';

  // Checklist
  static const checklist = 'checklist/';
  static String checklistItem(String id) => 'checklist/$id/';

  // Documentos
  static const documentos = 'documentos/';
  static String documento(String id)       => 'documentos/$id/';
  static String documentoRevisar(String id)=> 'documentos/$id/revisar/';

  // Certificaciones
  static const certificaciones       = 'certificaciones/';
  static const certificacionVerificar= 'certificaciones/verificar/';
  static String certificacion(String id)        => 'certificaciones/$id/';
  static String certificacionPdf(String id)     => 'certificaciones/$id/generar_pdf/';

  // Chatbot
  static const conversaciones = 'chatbot/conversaciones/';
  static String conversacion(String id)         => 'chatbot/conversaciones/$id/';
  static String enviarMensaje(String id)        => 'chatbot/conversaciones/$id/enviar_mensaje/';

  // Visitas agendadas
  static const visitas = 'visitas/';
  static String visita(String id) => 'visitas/$id/';

  // MFA
  static const mfaSetup = 'auth/mfa/';

  // Dashboard global
  static const dashboard = 'dashboard/';
}
