/// Modelo de datos que representa un cliente / trabajo agendado:
/// nombre del cliente, lugar, fecha y precio acordado.
library;

class Customer {
  final String id;
  String nombre;
  String lugar;
  DateTime fecha;
  double precio;

  Customer({
    required this.id,
    required this.nombre,
    required this.lugar,
    required this.fecha,
    required this.precio,
  });

  Customer copyWith({
    String? nombre,
    String? lugar,
    DateTime? fecha,
    double? precio,
  }) {
    return Customer(
      id: id,
      nombre: nombre ?? this.nombre,
      lugar: lugar ?? this.lugar,
      fecha: fecha ?? this.fecha,
      precio: precio ?? this.precio,
    );
  }

  /// Utilidad para (de)serializar, útil si más adelante se agrega
  /// persistencia local o un backend.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'lugar': lugar,
      'fecha': fecha.toIso8601String(),
      'precio': precio,
    };
  }

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'] as String,
      nombre: map['nombre'] as String,
      lugar: map['lugar'] as String,
      fecha: DateTime.tryParse(map['fecha'] as String? ?? '') ?? DateTime.now(),
      precio: (map['precio'] as num).toDouble(),
    );
  }
}