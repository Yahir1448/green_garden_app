import 'package:flutter/material.dart';

/// Convierte un string hex (ej. "#1B4D2E" o "1B4D2E") a [Color].
/// Devuelve null si el string es nulo, vacío o inválido.
Color? colorFromHex(String? hex) {
  if (hex == null || hex.trim().isEmpty) return null;

  var codigo = hex.trim().replaceAll('#', '');
  if (codigo.length == 6) codigo = 'FF$codigo'; // agrega alpha opaco

  final valor = int.tryParse(codigo, radix: 16);
  if (valor == null) return null;

  return Color(valor);
}

/// Convierte un [Color] a un string hex de 6 dígitos (sin alpha),
/// ej. "#1B4D2E".
String colorToHex(Color color) {
  final argb = color.toARGB32();
  final rgb = argb.toRadixString(16).padLeft(8, '0').substring(2);
  return '#${rgb.toUpperCase()}';
}