import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/customer.dart';

/// Guarda y lee en `shared_preferences` la última lista de clientes
/// conocida, para poder mostrar la pantalla de Clientes/Agenda aunque
/// el teléfono no tenga conexión en ese momento.
///
/// Es de solo clientes por ahora (el módulo con el que arrancamos el
/// modo offline). Si más adelante se agrega caché para Inventario o
/// Finanzas, lo natural es sumar aquí un método `guardarX`/`leerX` por
/// módulo, en vez de crear un servicio nuevo por cada uno.
class LocalCacheService {
  static const String _claveClientes = 'cache_clientes';

  static Future<void> guardarClientes(List<Customer> clientes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = clientes.map((c) => c.toMap()).toList();
      await prefs.setString(_claveClientes, jsonEncode(data));
    } catch (e) {
      debugPrint('Error guardando la caché de clientes: $e');
    }
  }

  static Future<List<Customer>> leerClientes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final crudo = prefs.getString(_claveClientes);
      if (crudo == null) return [];
      final lista = jsonDecode(crudo) as List;
      return lista
          .map((e) => Customer.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      debugPrint('Error leyendo la caché de clientes: $e');
      return [];
    }
  }

  /// Borra la caché (al cerrar sesión).
  static Future<void> limpiarClientes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_claveClientes);
    } catch (e) {
      debugPrint('Error limpiando la caché de clientes: $e');
    }
  }
}