import 'package:flutter/material.dart';

import '../theme/theme_controller.dart';

/// Botón reutilizable para alternar entre modo claro y oscuro.
/// Colócalo en el `actions` del `AppBar` de cualquier pantalla y quedará
/// sincronizado automáticamente con el resto de la app.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance.modeNotifier,
      builder: (context, mode, _) {
        final esOscuro = mode == ThemeMode.dark;
        return IconButton(
          tooltip: esOscuro ? 'Cambiar a modo claro' : 'Cambiar a modo oscuro',
          icon: Icon(esOscuro ? Icons.light_mode : Icons.dark_mode),
          onPressed: ThemeController.instance.toggle,
        );
      },
    );
  }
}