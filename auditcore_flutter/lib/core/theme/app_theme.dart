import 'package:flutter/material.dart';

// ── Paleta de colores ────────────────────────────────────────────────────
class AppColors {
  // Primarios
  static const sidebar     = Color(0xFF0F172A);
  static const sidebarHov  = Color(0xFF1E293B);
  static const sidebarAct  = Color(0x403B82F6);
  static const sidebarText = Color(0xFFA8B4C8);
  static const accent      = Color(0xFF2563EB);
  static const accentLight = Color(0xFFEFF6FF);
  static const accentDark  = Color(0xFF1E40AF);

  // Superficies
  static const white   = Color(0xFFFFFFFF);
  static const bg      = Color(0xFFF8FAFC);
  static const surface = Color(0xFFFFFFFF);
  static const border  = Color(0xFFE2E8F0);

  // Semánticos
  static const success   = Color(0xFF15803D);
  static const successBg = Color(0xFFDCFCE7);
  static const warning   = Color(0xFFA16207);
  static const warningBg = Color(0xFFFEF9C3);
  static const danger    = Color(0xFFB91C1C);
  static const dangerBg  = Color(0xFFFEE2E2);
  static const info      = Color(0xFF1D4ED8);
  static const infoBg    = Color(0xFFEFF6FF);

  // Texto
  static const textPrimary   = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF475569);
  static const textTertiary  = Color(0xFF94A3B8);

  // Aliases de compatibilidad
  static const navy         = Color(0xFF0F172A);
  static const blue         = Color(0xFF2563EB);
  static const sky          = Color(0xFFEFF6FF);
  static const dark         = Color(0xFF0F172A);
  static const gray50       = Color(0xFFF8FAFC);
  static const gray100      = Color(0xFFF1F5F9);
  static const gray300      = Color(0xFFCBD5E1);
  static const gray500      = Color(0xFF64748B);
  static const gray700      = Color(0xFF334155);
  static const successLight = Color(0xFFDCFCE7);
  static const dangerLight  = Color(0xFFFEE2E2);
  static const warningLight = Color(0xFFFEF9C3);
  static const infoLight    = Color(0xFFEFF6FF);
}

// ── Extensiones de estado ────────────────────────────────────────────────
extension EstadoStyle on String {
  Color get badgeColor {
    switch (toUpperCase()) {
      case 'ACTIVO': case 'VIGENTE': case 'CUMPLE': case 'APROBADO':
      case 'CERRADO': case 'COMPLETADO':
        return AppColors.success;
      case 'EN_EJECUCION': case 'EN_CURSO': case 'EN_REVISION':
        return AppColors.info;
      case 'BORRADOR': case 'PENDIENTE': case 'POR_VENCER':
        return AppColors.warning;
      case 'CRITICO': case 'NO_CUMPLE': case 'RECHAZADO':
      case 'VENCIDA': case 'CANCELADO':
        return AppColors.danger;
      default: return AppColors.textTertiary;
    }
  }

  Color get badgeBg {
    switch (toUpperCase()) {
      case 'ACTIVO': case 'VIGENTE': case 'CUMPLE': case 'APROBADO':
      case 'CERRADO': case 'COMPLETADO':
        return AppColors.successBg;
      case 'EN_EJECUCION': case 'EN_CURSO': case 'EN_REVISION':
        return AppColors.infoBg;
      case 'BORRADOR': case 'PENDIENTE': case 'POR_VENCER':
        return AppColors.warningBg;
      case 'CRITICO': case 'NO_CUMPLE': case 'RECHAZADO':
      case 'VENCIDA': case 'CANCELADO':
        return AppColors.dangerBg;
      default: return const Color(0xFFF1F5F9);
    }
  }

  String get badgeLabel {
    switch (toUpperCase()) {
      case 'BORRADOR':     return 'Borrador';
      case 'ACTIVO':       return 'Activo';
      case 'EN_EJECUCION': return 'En ejecución';
      case 'COMPLETADO':   return 'Completado';
      case 'CANCELADO':    return 'Cancelado';
      case 'SUSPENDIDO':   return 'Suspendido';
      case 'VIGENTE':      return 'Vigente';
      case 'POR_VENCER':   return 'Por vencer';
      case 'VENCIDA':      return 'Vencida';
      case 'CRITICO':      return 'Crítico';
      case 'MAYOR':        return 'Mayor';
      case 'MENOR':        return 'Menor';
      case 'INFORMATIVO':  return 'Informativo';
      case 'ABIERTO':      return 'Abierto';
      case 'CERRADO':      return 'Cerrado';
      case 'PENDIENTE':    return 'Pendiente';
      case 'APROBADO':     return 'Aprobado';
      case 'RECHAZADO':    return 'Rechazado';
      default: return this;
    }
  }

  Color get colorEstado      => badgeColor;
  Color get colorFondoEstado => badgeBg;
}

// ── Tema principal ───────────────────────────────────────────────────────
class AppTheme {
  static const _borderRadius = 8.0;
  static const _borderSide   = BorderSide(color: AppColors.border, width: 0.5);

  static OutlineInputBorder _inputBorder([BorderSide? side]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(_borderRadius),
        borderSide: side ?? _borderSide,
      );

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      primary: AppColors.accent,
      surface: AppColors.surface,
      error: AppColors.danger,
    ),
    scaffoldBackgroundColor: AppColors.bg,
    fontFamily: 'Roboto',

    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.white,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        letterSpacing: -0.2,
      ),
      iconTheme: IconThemeData(color: AppColors.textSecondary, size: 20),
      toolbarHeight: 56,
    ),

    cardTheme: CardThemeData(
      color: AppColors.white,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: _borderSide,
      ),
      margin: EdgeInsets.zero,
    ),

    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 0.5,
      space: 0,
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.white,
        disabledBackgroundColor: AppColors.border,
        disabledForegroundColor: AppColors.textTertiary,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_borderRadius)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        side: _borderSide,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_borderRadius)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accent,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ),

    // FIX: InputDecoration completo — todos los bordes definidos para
    // evitar null check crashes en Flutter Web con Material3.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border:             _inputBorder(),
      enabledBorder:      _inputBorder(),
      disabledBorder:     _inputBorder(const BorderSide(color: AppColors.border, width: 0.5)),
      focusedBorder:      _inputBorder(const BorderSide(color: AppColors.accent, width: 1.5)),
      errorBorder:        _inputBorder(const BorderSide(color: AppColors.danger, width: 0.5)),
      focusedErrorBorder: _inputBorder(const BorderSide(color: AppColors.danger, width: 1.5)),
      labelStyle: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
      hintStyle:  const TextStyle(fontSize: 13, color: AppColors.textTertiary),
      errorStyle: const TextStyle(fontSize: 11, color: AppColors.danger),
      prefixIconColor: AppColors.textTertiary,
      suffixIconColor: AppColors.textTertiary,
    ),

    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      dense: true,
      minLeadingWidth: 0,
      titleTextStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
      subtitleTextStyle: TextStyle(
        fontSize: 12,
        color: AppColors.textSecondary,
      ),
    ),

    chipTheme: ChipThemeData(
      labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),

    tabBarTheme: const TabBarThemeData(
      labelColor: AppColors.accent,
      unselectedLabelColor: AppColors.textSecondary,
      indicatorColor: AppColors.accent,
      indicatorSize: TabBarIndicatorSize.label,
      labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      unselectedLabelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
      dividerColor: AppColors.border,
    ),

    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.white,
      selectedItemColor: AppColors.accent,
      unselectedItemColor: AppColors.textTertiary,
      elevation: 0,
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      unselectedLabelStyle: TextStyle(fontSize: 11),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.sidebar,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),

    // Asegurar que DropdownMenu y otros widgets no tengan colores nulos
    dropdownMenuTheme: DropdownMenuThemeData(
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        border:             _inputBorder(),
        enabledBorder:      _inputBorder(),
        focusedBorder:      _inputBorder(const BorderSide(color: AppColors.accent, width: 1.5)),
        errorBorder:        _inputBorder(const BorderSide(color: AppColors.danger, width: 0.5)),
        focusedErrorBorder: _inputBorder(const BorderSide(color: AppColors.danger, width: 1.5)),
      ),
    ),
  );
}
