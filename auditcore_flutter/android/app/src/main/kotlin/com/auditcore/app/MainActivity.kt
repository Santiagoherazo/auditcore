package com.auditcore.app

import io.flutter.embedding.android.FlutterActivity

/**
 * MainActivity de AuditCore.
 *
 * Hereda de FlutterActivity directamente — toda la lógica de la app
 * está en Flutter (Dart). No se necesita código nativo adicional.
 *
 * Los plugins nativos (flutter_secure_storage, file_picker, etc.)
 * se registran automáticamente vía el mecanismo de auto-registration
 * de Flutter al momento de build.
 */
class MainActivity : FlutterActivity()
