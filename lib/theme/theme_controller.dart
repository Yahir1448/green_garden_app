import 'package:flutter/material.dart';

/// Controlador central y global del modo de tema (claro/oscuro).
///
/// Al ser un singleton con un [ValueNotifier], cualquier pantalla de la
/// app puede leer el modo actual o alternarlo sin necesidad de recibirlo
/// por parámetros (evita el "prop drilling") ni de agregar un paquete
/// externo de manejo de estado.
class ThemeController {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  final ValueNotifier<ThemeMode> modeNotifier = ValueNotifier(ThemeMode.light);

  ThemeMode get mode => modeNotifier.value;

  void toggle() {
    modeNotifier.value =
        modeNotifier.value == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
  }
}