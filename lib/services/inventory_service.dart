import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/inventory_item.dart';
import 'notification_service.dart';

/// Servicio encargado de administrar el inventario de herramientas e
/// insumos, respaldado por la tabla `inventario` de Supabase. Cada
/// usuario solo ve sus propias filas gracias a las políticas de
/// seguridad (RLS) definidas en `schema.sql`.
class InventoryService extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;
  static const String _tabla = 'inventario';

  List<InventoryItem> _items = [];
  bool cargando = false;

  /// Lista de solo lectura de todos los artículos (en memoria, ya
  /// sincronizados con Supabase).
  List<InventoryItem> get items => List.unmodifiable(_items);

  /// Artículos filtrados por categoría.
  List<InventoryItem> porCategoria(ItemCategoria categoria) =>
      _items.where((item) => item.categoria == categoria).toList();

  /// Cantidad de artículos que están en o por debajo del stock mínimo.
  int get totalBajoStock => _items.where((i) => i.bajoStock).length;

  /// Descarga el inventario del usuario autenticado. Se llama al
  /// iniciar sesión (ver `AuthGate` en main.dart).
  Future<void> cargar() async {
    cargando = true;
    notifyListeners();
    try {
      final data = await _client.from(_tabla).select();
      _items = (data as List)
          .map((fila) => InventoryItem.fromMap(fila as Map<String, dynamic>))
          .toList();
      // Avisa de una sola vez si algún artículo ya está bajo de stock
      // desde antes de abrir la app.
      await NotificationService.instance.revisarStockBajoLista(_items);
    } catch (e) {
      debugPrint('Error cargando inventario: $e');
    } finally {
      cargando = false;
      notifyListeners();
    }
  }

  /// Vacía los datos en memoria. Se llama al cerrar sesión para que la
  /// siguiente cuenta que inicie sesión en este dispositivo no vea
  /// datos de la cuenta anterior.
  void limpiar() {
    _items = [];
    notifyListeners();
  }

  /// Agrega un nuevo artículo. El id y el dueño (user_id) los asigna
  /// Supabase automáticamente. Devuelve el artículo creado (con su id)
  /// para poder enlazarlo, por ejemplo, a la receta de un servicio.
  Future<InventoryItem> agregarItem({
    required String nombre,
    required ItemCategoria categoria,
    required double cantidad,
    required String unidad,
    double stockMinimo = 0,
    String notas = '',
  }) async {
    try {
      final fila = await _client
          .from(_tabla)
          .insert({
            'nombre': nombre,
            'categoria': categoria.name,
            'cantidad': cantidad,
            'unidad': unidad,
            'stock_minimo': stockMinimo,
            'notas': notas,
            'actualizado_en': DateTime.now().toIso8601String(),
          })
          .select()
          .single();
      final creado = InventoryItem.fromMap(fila);
      _items.add(creado);
      notifyListeners();
      await NotificationService.instance.revisarStockBajo(creado);
      return creado;
    } catch (e) {
      debugPrint('Error agregando artículo: $e');
      rethrow;
    }
  }

  /// Actualiza un artículo existente.
  Future<void> actualizarItem(
    String id, {
    required String nombre,
    required ItemCategoria categoria,
    required double cantidad,
    required String unidad,
    double stockMinimo = 0,
    String notas = '',
  }) async {
    try {
      await _client.from(_tabla).update({
        'nombre': nombre,
        'categoria': categoria.name,
        'cantidad': cantidad,
        'unidad': unidad,
        'stock_minimo': stockMinimo,
        'notas': notas,
        'actualizado_en': DateTime.now().toIso8601String(),
      }).eq('id', id);

      final index = _items.indexWhere((item) => item.id == id);
      if (index != -1) {
        _items[index] = _items[index].copyWith(
          nombre: nombre,
          categoria: categoria,
          cantidad: cantidad,
          unidad: unidad,
          stockMinimo: stockMinimo,
          notas: notas,
        );
        notifyListeners();
        await NotificationService.instance.revisarStockBajo(_items[index]);
      }
    } catch (e) {
      debugPrint('Error actualizando artículo: $e');
      rethrow;
    }
  }

  /// Ajusta la cantidad disponible de un artículo (positivo para sumar,
  /// negativo para restar), sin bajar de cero.
  Future<void> ajustarCantidad(String id, double delta) async {
    final index = _items.indexWhere((item) => item.id == id);
    if (index == -1) return;

    final nuevaCantidad =
        (_items[index].cantidad + delta).clamp(0, double.infinity).toDouble();

    try {
      await _client.from(_tabla).update({
        'cantidad': nuevaCantidad,
        'actualizado_en': DateTime.now().toIso8601String(),
      }).eq('id', id);

      _items[index] = _items[index].copyWith(cantidad: nuevaCantidad);
      notifyListeners();
      await NotificationService.instance.revisarStockBajo(_items[index]);
    } catch (e) {
      debugPrint('Error ajustando cantidad: $e');
      rethrow;
    }
  }

  /// Elimina un artículo del inventario.
  Future<void> eliminarItem(String id) async {
    try {
      await _client.from(_tabla).delete().eq('id', id);
      _items.removeWhere((item) => item.id == id);
      notifyListeners();
    } catch (e) {
      debugPrint('Error eliminando artículo: $e');
      rethrow;
    }
  }
}