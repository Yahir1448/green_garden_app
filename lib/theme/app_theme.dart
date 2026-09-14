import 'package:flutter/material.dart';

/// Paleta de colores central de la app: verde lima, blanco y verde oscuro.
/// Definir los colores aquí (y no repetidos en cada pantalla) permite
/// mantener la identidad visual consistente y fácil de ajustar.
class AppColors {
  static const Color limeGreen = Color(0xFF9ACD32);
  static const Color darkGreen = Color(0xFF1B4D2E);
  static const Color white = Color(0xFFFFFFFF);

  // Tonos de apoyo derivados de la paleta principal.
  static const Color darkGreenSurface = Color(0xFF0F2E1B);
  static const Color limeGreenSoft = Color(0xFFE3F2C1);
}

/// Temas claro y oscuro de la aplicación, construidos a partir de la
/// paleta definida en [AppColors].
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.darkGreen,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.darkGreen,
      secondary: AppColors.limeGreen,
      surface: AppColors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkGreen,
        foregroundColor: AppColors.white,
        elevation: 0,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.limeGreen,
        foregroundColor: AppColors.darkGreen,
      ),
      cardTheme: CardThemeData(
        color: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.limeGreenSoft),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(AppColors.limeGreen),
        trackColor: WidgetStateProperty.all(AppColors.darkGreen.withValues(alpha: 0.4)),
      ),
    );
  }

  static ThemeData get dark {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.limeGreen,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.limeGreen,
      secondary: AppColors.darkGreen,
      surface: AppColors.darkGreenSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF0A1F12),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkGreenSurface,
        foregroundColor: AppColors.limeGreen,
        elevation: 0,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.limeGreen,
        foregroundColor: AppColors.darkGreen,
      ),
      cardTheme: CardThemeData(
        color: AppColors.darkGreenSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.limeGreen.withValues(alpha: 0.3)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(AppColors.limeGreen),
        trackColor: WidgetStateProperty.all(AppColors.white.withValues(alpha: 0.3)),
      ),
    );
  }
}