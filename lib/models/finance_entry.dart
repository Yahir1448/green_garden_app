/// Modelo de datos que representa un movimiento financiero:
/// un ingreso o un egreso, con descripción, monto, fecha y categoría.
library;

/// Tipo de movimiento financiero.
enum TipoMovimiento { ingreso, egreso }

extension TipoMovimientoLabel on TipoMovimiento {
  String get label {
    switch (this) {
      case TipoMovimiento.ingreso:
        return 'Ingreso';
      case TipoMovimiento.egreso:
        return 'Egreso';
    }
  }
}

class FinanceEntry {
  final String id;
  String descripcion;
  TipoMovimiento tipo;
  double monto;
  DateTime fecha;
  String categoria;

  FinanceEntry({
    required this.id,
    required this.descripcion,
    required this.tipo,
    required this.monto,
    required this.fecha,
    this.categoria = '',
  });

  FinanceEntry copyWith({
    String? descripcion,
    TipoMovimiento? tipo,
    double? monto,
    DateTime? fecha,
    String? categoria,
  }) {
    return FinanceEntry(
      id: id,
      descripcion: descripcion ?? this.descripcion,
      tipo: tipo ?? this.tipo,
      monto: monto ?? this.monto,
      fecha: fecha ?? this.fecha,
      categoria: categoria ?? this.categoria,
    );
  }

  /// Convierte el movimiento a un mapa con las mismas columnas
  /// (snake_case, aunque aquí no hay diferencia) que la tabla
  /// `finanzas` en Supabase.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'descripcion': descripcion,
      'tipo': tipo.name,
      'monto': monto,
      'fecha': fecha.toIso8601String().split('T').first,
      'categoria': categoria,
    };
  }

  factory FinanceEntry.fromMap(Map<String, dynamic> map) {
    return FinanceEntry(
      id: map['id'] as String,
      descripcion: map['descripcion'] as String,
      tipo: TipoMovimiento.values.firstWhere(
        (t) => t.name == map['tipo'],
        orElse: () => TipoMovimiento.egreso,
      ),
      monto: (map['monto'] as num).toDouble(),
      fecha: DateTime.tryParse(map['fecha'] as String? ?? '') ?? DateTime.now(),
      categoria: map['categoria'] as String? ?? '',
    );
  }
}