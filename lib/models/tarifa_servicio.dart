/// Tarifa configurada para un servicio (o una tarifa "Personalizada"
/// genérica si [servicioId] es null), usada por el Cotizador para
/// calcular el precio de mano de obra según el tamaño del trabajo (m²)
/// y de transporte según la distancia (km) recorrida desde el punto de
/// salida.
///
/// Ejemplo real: "cortar, barrer y recoger césped" en un terreno de
/// 450 a 600 m², dentro de un radio de 20 km del punto de salida,
/// cuesta $25. Si el terreno es más grande o la distancia es mayor, se
/// suma un extra por cada m²/km que se pase de esos límites.
library;

class TarifaServicio {
  final String id;

  /// Id del servicio del catálogo al que está vinculada esta tarifa
  /// (opcional). Null si es una tarifa general/personalizada.
  String? servicioId;
  String servicioNombre;

  /// Rango de m² que ya cubre el precio base (ej. 450 a 600).
  double m2Min;
  double m2Max;

  /// Precio de mano de obra + transporte para un trabajo dentro del
  /// rango de m² Y dentro del radio base de km (sin insumos).
  double precioBase;

  /// Se suma por cada m² que se pase de [m2Max].
  double precioPorM2Extra;

  /// Radio (en km) desde el punto de salida que ya incluye el precio
  /// base.
  double kmBase;

  /// Se suma por cada km que se pase de [kmBase].
  double precioPorKmExtra;

  TarifaServicio({
    required this.id,
    this.servicioId,
    required this.servicioNombre,
    required this.m2Min,
    required this.m2Max,
    required this.precioBase,
    required this.precioPorM2Extra,
    required this.kmBase,
    required this.precioPorKmExtra,
  });

  /// Calcula el costo de mano de obra + transporte (sin insumos) para
  /// un trabajo de [m2] metros cuadrados a [km] de distancia del punto
  /// de salida.
  double calcularCosto({required double m2, required double km}) {
    final m2Extra = m2 > m2Max ? (m2 - m2Max) : 0.0;
    final kmExtra = km > kmBase ? (km - kmBase) : 0.0;
    return precioBase + (m2Extra * precioPorM2Extra) + (kmExtra * precioPorKmExtra);
  }

  Map<String, dynamic> toMap() {
    return {
      'servicio_id': servicioId,
      'servicio_nombre': servicioNombre,
      'm2_min': m2Min,
      'm2_max': m2Max,
      'precio_base': precioBase,
      'precio_por_m2_extra': precioPorM2Extra,
      'km_base': kmBase,
      'precio_por_km_extra': precioPorKmExtra,
    };
  }

  factory TarifaServicio.fromMap(Map<String, dynamic> map) {
    return TarifaServicio(
      id: map['id'] as String,
      servicioId: map['servicio_id'] as String?,
      servicioNombre: map['servicio_nombre'] as String? ?? '',
      m2Min: (map['m2_min'] as num?)?.toDouble() ?? 0,
      m2Max: (map['m2_max'] as num?)?.toDouble() ?? 0,
      precioBase: (map['precio_base'] as num?)?.toDouble() ?? 0,
      precioPorM2Extra: (map['precio_por_m2_extra'] as num?)?.toDouble() ?? 0,
      kmBase: (map['km_base'] as num?)?.toDouble() ?? 0,
      precioPorKmExtra: (map['precio_por_km_extra'] as num?)?.toDouble() ?? 0,
    );
  }
}