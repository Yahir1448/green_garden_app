import 'package:flutter/material.dart';

/// Muestra el logo del negocio (desde una URL) o, si no hay logo
/// configurado todavía, un ícono por defecto.
///
/// [size] es un límite MÁXIMO de ancho y alto: el logo nunca lo supera
/// (evita que una imagen muy grande deforme la pantalla), pero se
/// muestra completo y sin recortar, cualquiera sea su proporción
/// original (con [BoxFit.contain], no [BoxFit.cover]).
class BusinessLogo extends StatelessWidget {
  final String? logoUrl;
  final double size;
  final IconData iconoPorDefecto;
  final Color? colorIcono;

  const BusinessLogo({
    super.key,
    required this.logoUrl,
    this.size = 40,
    this.iconoPorDefecto = Icons.eco,
    this.colorIcono,
  });

  @override
  Widget build(BuildContext context) {
    final url = logoUrl;

    if (url == null || url.isEmpty) {
      return Icon(
        iconoPorDefecto,
        size: size,
        color: colorIcono ?? Theme.of(context).colorScheme.primary,
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => Icon(
          iconoPorDefecto,
          size: size,
          color: colorIcono ?? Theme.of(context).colorScheme.primary,
        ),
        loadingBuilder: (context, child, progreso) {
          if (progreso == null) return child;
          return Center(
            child: SizedBox(
              width: size * 0.4,
              height: size * 0.4,
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
      ),
    );
  }
}