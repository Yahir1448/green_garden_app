/// Modelo de datos que representa un servicio ofrecido (ej. "Poda de
/// jardín", "Corte de césped"), con su descripción, precio base y la
/// "receta" de insumos que consume cada vez que se realiza (usada para
/// descontar el inventario automáticamente).
library;

/// Un insumo del inventario que consume un servicio, y cuánta cantidad
/// se usa cada vez que ese servicio se realiza.
class RecetaInsumo {
  String inventarioId;

  /// Nombre "congelado" del insumo al momento de configurar la receta,
  /// para poder mostrarlo aunque el artículo se elimine del inventario
  /// después.
  String inventarioNombre;
  double cantidad;

  RecetaInsumo({
    required this.inventarioId,
    required this.inventarioNombre,
    required this.cantidad,
  });

  Map<String, dynamic> toMap() {
    return {
      'inventario_id': inventarioId,
      'inventario_nombre': inventarioNombre,
      'cantidad': cantidad,
    };
  }

  factory RecetaInsumo.fromMap(Map<String, dynamic> map) {
    return RecetaInsumo(
      inventarioId: map['inventario_id'] as String,
      inventarioNombre: map['inventario_nombre'] as String? ?? '',
      cantidad: (map['cantidad'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ServiceItem {
  final String id;
  String nombre;
  String descripcion;
  double precio;

  /// Insumos que se descuentan del inventario cada vez que se marca
  /// como realizado un trabajo con este servicio. Vacía si no se ha
  /// configurado (no descuenta nada).
  List<RecetaInsumo> receta;

  ServiceItem({
    required this.id,
    required this.nombre,
    this.descripcion = '',
    required this.precio,
    List<RecetaInsumo>? receta,
  }) : receta = receta ?? [];

  ServiceItem copyWith({
    String? nombre,
    String? descripcion,
    double? precio,
    List<RecetaInsumo>? receta,
  }) {
    return ServiceItem(
      id: id,
      nombre: nombre ?? this.nombre,
      descripcion: descripcion ?? this.descripcion,
      precio: precio ?? this.precio,
      receta: receta ?? this.receta,
    );
  }

  /// Convierte el servicio a un mapa con las mismas columnas que la
  /// tabla `servicios` en Supabase.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'descripcion': descripcion,
      'precio': precio,
      'receta': receta.map((r) => r.toMap()).toList(),
    };
  }

  factory ServiceItem.fromMap(Map<String, dynamic> map) {
    return ServiceItem(
      id: map['id'] as String,
      nombre: map['nombre'] as String,
      descripcion: map['descripcion'] as String? ?? '',
      precio: (map['precio'] as num).toDouble(),
      receta: ((map['receta'] as List?) ?? [])
          .map((item) => RecetaInsumo.fromMap(item as Map<String, dynamic>))
          .toList(),
    );
  }
}