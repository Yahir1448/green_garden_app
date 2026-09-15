/// Modelo de datos que representa un servicio ofrecido (ej. "Poda de
/// jardín", "Corte de césped"), con su descripción y precio base.
library;

class ServiceItem {
  final String id;
  String nombre;
  String descripcion;
  double precio;

  ServiceItem({
    required this.id,
    required this.nombre,
    this.descripcion = '',
    required this.precio,
  });

  ServiceItem copyWith({
    String? nombre,
    String? descripcion,
    double? precio,
  }) {
    return ServiceItem(
      id: id,
      nombre: nombre ?? this.nombre,
      descripcion: descripcion ?? this.descripcion,
      precio: precio ?? this.precio,
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
    };
  }

  factory ServiceItem.fromMap(Map<String, dynamic> map) {
    return ServiceItem(
      id: map['id'] as String,
      nombre: map['nombre'] as String,
      descripcion: map['descripcion'] as String? ?? '',
      precio: (map['precio'] as num).toDouble(),
    );
  }
}