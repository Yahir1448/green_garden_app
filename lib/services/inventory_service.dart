import 'package:flutter/foundation.dart';

import '../models/inventory_item.dart';

/// Servicio encargado de administrar el inventario de herramientas e
/// insumos. Se comporta como un "microservicio" interno de la app: toda
/// la lógica de negocio (crear, actualizar, eliminar, consultar) vive
/// aquí, separada de las vistas. Las pantallas solo consumen esta clase.
///
/// Al extender [ChangeNotifier], cualquier widget puede escucharlo con
/// un [ListenableBuilder] y reconstruirse automáticamente cuando los
/// datos cambian, sin necesidad de paquetes externos de manejo de estado.
class InventoryService extends ChangeNotifier {
  final List<InventoryItem> _items = [
    InventoryItem(
      id: '1',
      nombre: 'Pala de jardín',
      categoria: ItemCategoria.herramienta,
      cantidad: 3,
      unidad: 'unidades',
      stockMinimo: 1,
    ),
    InventoryItem(
      id: '2',
      nombre: 'Tijeras de podar',
      categoria: ItemCategoria.herramienta,
      cantidad: 2,
      unidad: 'unidades',
      stockMinimo: 1,
    ),
    InventoryItem(
      id: '3',
      nombre: 'Fertilizante orgánico',
      categoria: ItemCategoria.insumo,
      cantidad: 4,
      unidad: 'kg',
      stockMinimo: 2,
    ),
    InventoryItem(
      id: '4',
      nombre: 'Semillas de lechuga',
      categoria: ItemCategoria.insumo,
      cantidad: 1,
      unidad: 'bolsas',
      stockMinimo: 2,
    ),
  ];

  /// Lista de solo lectura de todos los artículos.
  List<InventoryItem> get items => List.unmodifiable(_items);

  /// Artículos filtrados por categoría.
  List<InventoryItem> porCategoria(ItemCategoria categoria) =>
      _items.where((item) => item.categoria == categoria).toList();

  /// Cantidad de artículos que están en o por debajo del stock mínimo.
  int get totalBajoStock => _items.where((i) => i.bajoStock).length;

  /// Agrega un nuevo artículo al inventario.
  void agregarItem(InventoryItem item) {
    _items.add(item);
    notifyListeners();
  }

  /// Reemplaza un artículo existente (identificado por [id]) con los
  /// nuevos datos de [actualizado].
  void actualizarItem(String id, InventoryItem actualizado) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index != -1) {
      _items[index] = actualizado;
      notifyListeners();
    }
  }

  /// Ajusta la cantidad disponible de un artículo (positivo para sumar,
  /// negativo para restar), sin bajar de cero.
  void ajustarCantidad(String id, double delta) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index != -1) {
      final actual = _items[index];
      final nuevaCantidad = (actual.cantidad + delta).clamp(0, double.infinity);
      _items[index] = actual.copyWith(cantidad: nuevaCantidad.toDouble());
      notifyListeners();
    }
  }

  /// Elimina un artículo del inventario.
  void eliminarItem(String id) {
    _items.removeWhere((item) => item.id == id);
    notifyListeners();
  }
}