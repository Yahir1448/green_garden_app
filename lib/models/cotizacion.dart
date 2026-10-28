/// Una línea de servicio dentro de una cotización: qué tarifa se usó
/// (si alguna), el tamaño y distancia reales del trabajo, el costo de
/// insumos, y el precio ya calculado para esa línea (mano de obra +
/// transporte + insumos).
library;

class ServicioCotizado {
  /// Id de la [TarifaServicio] usada para calcular esta línea. Null si
  /// se ingresó el precio de mano de obra a mano ("Personalizado" sin
  /// tarifa configurada).
  String? tarifaId;
  String servicioNombre;
  double m2;
  double km;
  double costoInsumos;

  /// Parte del precio que corresponde al costo por distancia (los km
  /// que se pasan del radio base de la tarifa). Ya está incluido en
  /// [precio]; se guarda aparte para poder desglosarlo en el PDF.
  double costoDistancia;

  /// Solo lectura: para cotizaciones guardadas con una versión anterior,
  /// donde el pago de ayudantes iba dentro del servicio. Ahora los
  /// ayudantes se guardan aparte (ver [AyudanteCotizado]).
  double costoAyudantes;

  /// Precio total de esta línea: mano de obra + transporte (calculado
  /// con la tarifa, o ingresado a mano) + insumos. NO incluye margen
  /// de rentabilidad todavía; eso se aplica sobre el total de la
  /// cotización.
  double precio;

  ServicioCotizado({
    this.tarifaId,
    required this.servicioNombre,
    required this.m2,
    required this.km,
    required this.costoInsumos,
    this.costoDistancia = 0,
    this.costoAyudantes = 0,
    required this.precio,
  });

  Map<String, dynamic> toMap() {
    return {
      'tarifa_id': tarifaId,
      'servicio_nombre': servicioNombre,
      'm2': m2,
      'km': km,
      'costo_insumos': costoInsumos,
      'costo_distancia': costoDistancia,
      'precio': precio,
    };
  }

  factory ServicioCotizado.fromMap(Map<String, dynamic> map) {
    return ServicioCotizado(
      tarifaId: map['tarifa_id'] as String?,
      servicioNombre: map['servicio_nombre'] as String? ?? '',
      m2: (map['m2'] as num?)?.toDouble() ?? 0,
      km: (map['km'] as num?)?.toDouble() ?? 0,
      costoInsumos: (map['costo_insumos'] as num?)?.toDouble() ?? 0,
      costoDistancia: (map['costo_distancia'] as num?)?.toDouble() ?? 0,
      costoAyudantes: (map['costo_ayudantes'] as num?)?.toDouble() ?? 0,
      precio: (map['precio'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Un ayudante que se contrata para el trabajo (personal extra). Va aparte
/// de los servicios: tiene su propio costo y aparece por separado en la
/// cotización. Se guarda dentro de la misma columna `lineas` de la
/// cotización, marcado con `tipo: ayudante`, así que no necesita ninguna
/// columna nueva en la base de datos.
class AyudanteCotizado {
  String descripcion;
  double costo;

  AyudanteCotizado({required this.descripcion, required this.costo});

  Map<String, dynamic> toMap() {
    return {
      'tipo': 'ayudante',
      'descripcion': descripcion,
      'costo': costo,
    };
  }

  factory AyudanteCotizado.fromMap(Map<String, dynamic> map) {
    return AyudanteCotizado(
      descripcion: map['descripcion'] as String? ?? 'Ayudante',
      costo: (map['costo'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Estado de una cotización guardada.
enum EstadoCotizacion {
  pendiente, // calculada, todavía no se le agendó un trabajo al cliente
  agendada, // el cliente aceptó y ya se agendó como trabajo
}

extension EstadoCotizacionLabel on EstadoCotizacion {
  String get label {
    switch (this) {
      case EstadoCotizacion.pendiente:
        return 'Pendiente';
      case EstadoCotizacion.agendada:
        return 'Agendada';
    }
  }
}

/// Una cotización/presupuesto guardado: uno o más servicios, el margen
/// de rentabilidad aplicado, y el costo/precio totales ya calculados.
/// Se puede retomar más adelante para no volver a escribir todos los
/// datos, y "convertir" en un cliente agendado si se acepta.
class Cotizacion {
  final String id;
  String nombreCliente;
  String lugar;
  List<ServicioCotizado> servicios;

  /// Ayudantes contratados para el trabajo (aparte de los servicios).
  List<AyudanteCotizado> ayudantes;

  /// % de rentabilidad deseado sobre el precio final (ej. 30 = 30%).
  double margenRentabilidad;

  /// Suma de los precios de [servicios] más el pago de [ayudantes], SIN
  /// margen aplicado.
  double costoTotal;

  /// Precio final ya con el margen de rentabilidad aplicado; es el
  /// monto que se le cotiza al cliente.
  double precioTotal;

  EstadoCotizacion estado;
  DateTime creadaEn;

  Cotizacion({
    required this.id,
    this.nombreCliente = '',
    this.lugar = '',
    List<ServicioCotizado>? servicios,
    List<AyudanteCotizado>? ayudantes,
    this.margenRentabilidad = 0,
    required this.costoTotal,
    required this.precioTotal,
    this.estado = EstadoCotizacion.pendiente,
    required this.creadaEn,
  })  : servicios = servicios ?? [],
        ayudantes = ayudantes ?? [];

  Map<String, dynamic> toMap() {
    return {
      'nombre_cliente': nombreCliente,
      'lugar': lugar,
      'lineas': [
        ...servicios.map((s) => s.toMap()),
        ...ayudantes.map((a) => a.toMap()),
      ],
      'margen_rentabilidad': margenRentabilidad,
      'costo_total': costoTotal,
      'precio_total': precioTotal,
      'estado': estado.name,
    };
  }

  factory Cotizacion.fromMap(Map<String, dynamic> map) {
    final lineas = ((map['lineas'] as List?) ?? [])
        .map((item) => item as Map<String, dynamic>)
        .toList();
    return Cotizacion(
      id: map['id'] as String,
      nombreCliente: map['nombre_cliente'] as String? ?? '',
      lugar: map['lugar'] as String? ?? '',
      servicios: lineas
          .where((l) => l['tipo'] != 'ayudante')
          .map(ServicioCotizado.fromMap)
          .toList(),
      ayudantes: lineas
          .where((l) => l['tipo'] == 'ayudante')
          .map(AyudanteCotizado.fromMap)
          .toList(),
      margenRentabilidad: (map['margen_rentabilidad'] as num?)?.toDouble() ?? 0,
      costoTotal: (map['costo_total'] as num?)?.toDouble() ?? 0,
      precioTotal: (map['precio_total'] as num?)?.toDouble() ?? 0,
      estado: EstadoCotizacion.values.firstWhere(
        (e) => e.name == map['estado'],
        orElse: () => EstadoCotizacion.pendiente,
      ),
      creadaEn: DateTime.tryParse(map['creada_en'] as String? ?? '') ?? DateTime.now(),
    );
  }
}