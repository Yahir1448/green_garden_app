import 'package:flutter/material.dart';

/// Muestra el logo del negocio (desde una URL) o, si no hay logo
/// configurado todavía, un ícono por defecto. Se usa en la pantalla de
/// login/registro, en el navbar del dashboard y en "Mi negocio".
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 4),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Icon(
          iconoPorDefecto,
          size: size,
          color: colorIcono ?? Theme.of(context).colorScheme.primary,
        ),
        loadingBuilder: (context, child, progreso) {
          if (progreso == null) return child;
          return SizedBox(
            width: size,
            height: size,
            child: const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
      ),
    );
  }
}