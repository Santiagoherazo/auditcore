class Endpoints {

  static const login   = 'auth/login/';
  static const refresh = 'auth/refresh/';
  static const logout  = 'auth/logout/';


  static const usuarios  = 'usuarios/';
  static const usuarioMe = 'usuarios/me/';
  static String usuarioDesactivar(String id) => 'usuarios/$id/desactivar/';


  static const clientes = 'clientes/';

  static const clienteDraft              = 'clientes/draft/';
  static String clienteDraftUpdate(String id)  => 'clientes/draft/$id/';
  static String clienteDraftCommit(String id)  => 'clientes/draft/$id/commit/';
  static String cliente(String id)             => 'clientes/$id/';
  static String clienteDashboard(String id)    => 'clientes/$id/dashboard/';
  static String clienteCambiarEstado(String id)=> 'clientes/$id/cambiar-estado/';


  static const tiposAuditoria = 'tipos-auditoria/';
  static String tipoAuditoria(String id) => 'tipos-auditoria/$id/';
  static const tiposAuditoriaFases = 'tipos-auditoria-fases/';
  static String tipoAuditoriaFase(String id) => 'tipos-auditoria-fases/$id/';
  static const tiposAuditoriaChecklist = 'tipos-auditoria-checklist/';
  static String tipoAuditoriaChecklistItem(String id) => 'tipos-auditoria-checklist/$id/';
  static const tiposAuditoriaDocumentos = 'tipos-auditoria-documentos/';
  static String tipoAuditoriaDocumento(String id) => 'tipos-auditoria-documentos/$id/';
  static const administracionSeed = 'administracion/seed/';


  static const expedientes = 'expedientes/';
  static String expediente(String id)         => 'expedientes/$id/';
  static String expedienteBitacora(String id) => 'expedientes/$id/bitacora/';
  static String expedienteDashboard(String id)=> 'expedientes/$id/dashboard/';
  static String expedienteCambiarEstado(String id) => 'expedientes/$id/cambiar_estado/';


  static const hallazgos = 'hallazgos/';
  static String hallazgo(String id) => 'hallazgos/$id/';


  static const evidencias = 'evidencias/';


  static const checklist = 'checklist/';
  static String checklistItem(String id) => 'checklist/$id/';


  static const documentos = 'documentos/';
  static String documento(String id)       => 'documentos/$id/';
  static String documentoRevisar(String id)=> 'documentos/$id/revisar/';


  static const certificaciones       = 'certificaciones/';
  static const certificacionVerificar= 'certificaciones/verificar/';
  static String certificacion(String id)        => 'certificaciones/$id/';
  static String certificacionPdf(String id)     => 'certificaciones/$id/generar_pdf/';


  static const conversaciones = 'chatbot/conversaciones/';
  static String conversacion(String id)         => 'chatbot/conversaciones/$id/';
  static String enviarMensaje(String id)        => 'chatbot/conversaciones/$id/enviar_mensaje/';


  static const visitas = 'visitas/';
  static String visita(String id) => 'visitas/$id/';


  static const mfaSetup = 'auth/mfa/';


  static const dashboard = 'dashboard/';
}
