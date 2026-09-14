/// Modelo de datos que representa un artículo del inventario:
/// puede ser una herramienta (ej. pala, tijeras de podar) o un
/// insumo (ej. fertilizante, semillas).
library;

/// Categoría a la que pertenece un artículo del inventario.
enum ItemCategoria {
  herramienta,
  insumo,
}

extension ItemCategoriaLabel on ItemCategoria {
  String get label {
    switch (this) {
      case ItemCategoria.herramienta:
        return 'Herramienta';
      case ItemCategoria.insumo:
        return 'Insumo';
    }
  }
}

/// Representa un único artículo (herramienta o insumo) del inventario.
class InventoryItem {
  final String id;
  String nombre;
  ItemCategoria categoria;
  double cantidad;
  String unidad; // ej. "unidades", "kg", "litros", "bolsas"
  double stockMinimo; // umbral para alertar bajo stock
  String notas;
  DateTime ultimaActualizacion;

  InventoryItem({
    required this.id,
    required this.nombre,
    required this.categoria,
    required this.cantidad,
    required this.unidad,
    this.stockMinimo = 0,
    this.notas = '',
    DateTime? ultimaActualizacion,
  }) : ultimaActualizacion = ultimaActualizacion ?? DateTime.now();

  /// Indica si el artículo está en o por debajo del stock mínimo definido.
  bool get bajoStock => cantidad <= stockMinimo;

  /// Crea una copia del artículo reemplazando únicamente los campos indicados.
  InventoryItem copyWith({
    String? nombre,
    ItemCategoria? categoria,
    double? cantidad,
    String? unidad,
    double? stockMinimo,
    String? notas,
  }) {
    return InventoryItem(
      id: id,
      nombre: nombre ?? this.nombre,
      categoria: categoria ?? this.categoria,
      cantidad: cantidad ?? this.cantidad,
      unidad: unidad ?? this.unidad,
      stockMinimo: stockMinimo ?? this.stockMinimo,
      notas: notas ?? this.notas,
      ultimaActualizacion: DateTime.now(),
    );
  }

  /// Utilidad para (de)serializar, útil si más adelante se agrega
  /// persistencia local (ej. shared_preferences, sqlite, un backend, etc).
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'categoria': categoria.name,
      'cantidad': cantidad,
      'unidad': unidad,
      'stockMinimo': stockMinimo,
      'notas': notas,
      'ultimaActualizacion': ultimaActualizacion.toIso8601String(),
    };
  }

  factory InventoryItem.fromMap(Map<String, dynamic> map) {
    return InventoryItem(
      id: map['id'] as String,
      nombre: map['nombre'] as String,
      categoria: ItemCategoria.values.firstWhere(
        (c) => c.name == map['categoria'],
        orElse: () => ItemCategoria.insumo,
      ),
      cantidad: (map['cantidad'] as num).toDouble(),
      unidad: map['unidad'] as String,
      stockMinimo: (map['stockMinimo'] as num?)?.toDouble() ?? 0,
      notas: map['notas'] as String? ?? '',
      ultimaActualizacion: DateTime.tryParse(
            map['ultimaActualizacion'] as String? ?? '',
          ) ??
          DateTime.now(),
    );
  }
}