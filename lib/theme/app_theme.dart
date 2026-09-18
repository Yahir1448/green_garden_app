import 'package:flutter/material.dart';

/// Paleta de colores por defecto de Green Garden (verde lima, blanco y
/// verde oscuro). Se usa mientras un negocio no haya elegido su propio
/// color de marca en "Mi negocio".
class AppColors {
  static const Color limeGreen = Color(0xFF9ACD32);
  static const Color darkGreen = Color(0xFF1B4D2E);
  static const Color white = Color(0xFFFFFFFF);

  // Tonos de apoyo derivados de la paleta principal.
  static const Color darkGreenSurface = Color(0xFF0F2E1B);
  static const Color limeGreenSoft = Color(0xFFE3F2C1);
}

/// Temas claro y oscuro de la aplicación.
///
/// En vez de colores fijos, se construyen a partir de UN solo "color
/// semilla" (el color de marca que cada negocio elige en su perfil).
/// [ColorScheme.fromSeed] genera automáticamente todas las variantes
/// necesarias (fondo, texto, superficies, contraste, etc.) tanto para
/// modo claro como oscuro a partir de ese único color — así evitamos
/// tener que definir y pelear manualmente con el contraste de cada
/// tono para cada negocio distinto.
///
/// Si el negocio no ha elegido un color propio, se usa el verde por
/// defecto de Green Garden ([AppColors.darkGreen]) como semilla.
class AppTheme {
  AppTheme._();

  /// Color de marca por defecto, usado cuando el negocio no ha
  /// elegido uno propio.
  static const Color colorMarcaPorDefecto = AppColors.darkGreen;

  static ThemeData light([Color? colorMarca]) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: colorMarca ?? colorMarcaPorDefecto,
      brightness: Brightness.light,
    );
    return _construir(colorScheme, Brightness.light);
  }

  static ThemeData dark([Color? colorMarca]) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: colorMarca ?? colorMarcaPorDefecto,
      brightness: Brightness.dark,
    );
    return _construir(colorScheme, Brightness.dark);
  }

  static ThemeData _construir(ColorScheme colorScheme, Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.secondary,
        foregroundColor: colorScheme.onSecondary,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.15)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(colorScheme.primary),
        trackColor:
            WidgetStateProperty.all(colorScheme.primary.withValues(alpha: 0.4)),
      ),
    );
  }
}