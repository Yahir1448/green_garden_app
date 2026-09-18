import 'package:flutter/material.dart';

/// Controlador central y global del tema de la app: modo claro/oscuro
/// y color de marca del negocio actual.
///
/// Al ser un singleton con [ValueNotifier]s, cualquier pantalla puede
/// leer o actualizar el tema sin necesidad de recibirlo por
/// parámetros (evita el "prop drilling") ni de agregar un paquete
/// externo de manejo de estado.
class ThemeController {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  final ValueNotifier<ThemeMode> modeNotifier = ValueNotifier(ThemeMode.light);

  /// Color de marca del negocio actual, elegido en "Mi negocio". Si es
  /// null, [AppTheme] usa el verde por defecto de Green Garden.
  final ValueNotifier<Color?> colorMarcaNotifier = ValueNotifier(null);

  ThemeMode get mode => modeNotifier.value;

  void toggle() {
    modeNotifier.value =
        modeNotifier.value == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
  }

  /// Actualiza el color de marca activo. Se llama cada vez que se
  /// carga o se guarda el perfil del negocio, para que toda la app
  /// (incluida la pantalla de login) se repinte con el color correcto.
  void actualizarColorMarca(Color? color) {
    colorMarcaNotifier.value = color;
  }
}