/// Modelo de datos que representa un cliente / trabajo agendado:
/// nombre del cliente, lugar, fecha, precio acordado, el servicio
/// enlazado (opcional) y el estado del trabajo (pendiente, realizado
/// pero sin cobrar, o ya pagado).
library;

/// Estado de un trabajo agendado con un cliente.
enum EstadoTrabajo {
  pendiente, // aún no se realiza el servicio
  realizado, // el servicio ya se hizo, pero no se ha cobrado
  pagado, // ya se hizo y ya se cobró
}

extension EstadoTrabajoLabel on EstadoTrabajo {
  String get label {
    switch (this) {
      case EstadoTrabajo.pendiente:
        return 'Pendiente';
      case EstadoTrabajo.realizado:
        return 'Por cobrar';
      case EstadoTrabajo.pagado:
        return 'Pagado';
    }
  }
}

/// Forma en la que el cliente pagó (esta app no procesa pagos, solo
/// registra cómo se cobró).
enum MetodoPago { yappy, efectivo }

extension MetodoPagoLabel on MetodoPago {
  String get label {
    switch (this) {
      case MetodoPago.yappy:
        return 'Yappy';
      case MetodoPago.efectivo:
        return 'Efectivo';
    }
  }
}

class Customer {
  final String id;
  String nombre;
  String lugar;
  DateTime fecha;
  double precio;

  /// Id y nombre "congelado" del servicio del catálogo enlazado a este
  /// trabajo (opcional). Ver [ServiceItem].
  String? servicioId;
  String servicioNombre;

  /// Estado del trabajo y datos del cobro.
  EstadoTrabajo estado;
  MetodoPago? metodoPago;
  DateTime? fechaPago;

  /// Id del movimiento creado en Finanzas al cobrar, para poder
  /// eliminarlo si se deshace el cobro o se elimina el cliente.
  String? financeEntryId;

  Customer({
    required this.id,
    required this.nombre,
    required this.lugar,
    required this.fecha,
    required this.precio,
    this.servicioId,
    this.servicioNombre = '',
    this.estado = EstadoTrabajo.pendiente,
    this.metodoPago,
    this.fechaPago,
    this.financeEntryId,
  });

  /// Copia el cliente reemplazando solo los campos indicados. Los
  /// campos de estado/cobro no editables desde el formulario general
  /// se conservan automáticamente.
  Customer copyWith({
    String? nombre,
    String? lugar,
    DateTime? fecha,
    double? precio,
    String? servicioId,
    bool limpiarServicio = false,
    String? servicioNombre,
  }) {
    return Customer(
      id: id,
      nombre: nombre ?? this.nombre,
      lugar: lugar ?? this.lugar,
      fecha: fecha ?? this.fecha,
      precio: precio ?? this.precio,
      servicioId: limpiarServicio ? null : (servicioId ?? this.servicioId),
      servicioNombre:
          limpiarServicio ? '' : (servicioNombre ?? this.servicioNombre),
      estado: estado,
      metodoPago: metodoPago,
      fechaPago: fechaPago,
      financeEntryId: financeEntryId,
    );
  }

  /// Convierte el cliente a un mapa con las mismas columnas (snake_case)
  /// que la tabla `clientes` en Supabase.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'lugar': lugar,
      'fecha': fecha.toIso8601String().split('T').first,
      'precio': precio,
      'servicio_id': servicioId,
      'servicio_nombre': servicioNombre,
      'estado': estado.name,
      'metodo_pago': metodoPago?.name,
      'fecha_pago': fechaPago?.toIso8601String(),
      'finance_entry_id': financeEntryId,
    };
  }

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'] as String,
      nombre: map['nombre'] as String,
      lugar: map['lugar'] as String,
      fecha: DateTime.tryParse(map['fecha'] as String? ?? '') ?? DateTime.now(),
      precio: (map['precio'] as num).toDouble(),
      servicioId: map['servicio_id'] as String?,
      servicioNombre: map['servicio_nombre'] as String? ?? '',
      estado: EstadoTrabajo.values.firstWhere(
        (e) => e.name == map['estado'],
        orElse: () => EstadoTrabajo.pendiente,
      ),
      metodoPago: map['metodo_pago'] != null
          ? MetodoPago.values.firstWhere((m) => m.name == map['metodo_pago'])
          : null,
      fechaPago: map['fecha_pago'] != null
          ? DateTime.tryParse(map['fecha_pago'] as String)
          : null,
      financeEntryId: map['finance_entry_id'] as String?,
    );
  }
}