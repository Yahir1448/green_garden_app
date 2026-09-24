/// Modelo de datos que representa un cliente / trabajo agendado:
/// nombre del cliente, lugar, fecha, precio acordado, el servicio
/// enlazado (opcional), el estado del trabajo (pendiente, realizado
/// pero sin cobrar, o ya pagado), y si es parte de una serie
/// recurrente (semanal/mensual).
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

/// Frecuencia con la que se repite un trabajo recurrente.
enum Recurrencia { semanal, mensual }

extension RecurrenciaLabel on Recurrencia {
  String get label {
    switch (this) {
      case Recurrencia.semanal:
        return 'Semanal';
      case Recurrencia.mensual:
        return 'Mensual';
    }
  }

  /// Calcula la fecha del siguiente trabajo a partir de la fecha del
  /// actual, según esta frecuencia.
  DateTime siguienteFecha(DateTime fecha) {
    switch (this) {
      case Recurrencia.semanal:
        return fecha.add(const Duration(days: 7));
      case Recurrencia.mensual:
        // DateTime normaliza automáticamente si el mes siguiente no
        // tiene ese día (ej. 31 de enero -> ~3 de marzo). Es un caso
        // borde poco común y aceptable para este propósito.
        return DateTime(fecha.year, fecha.month + 1, fecha.day);
    }
  }
}

/// Un servicio agendado dentro de un trabajo (un cliente puede tener
/// varios en la misma visita, ej. "Corte de césped" + "Poda de
/// arbustos"). Guarda el id del catálogo si vino de ahí (opcional,
/// null si fue escrito a mano como "Personalizado"), el nombre y el
/// precio acordado para ese servicio en particular.
class ServicioAgendado {
  String? servicioId;
  String nombre;
  double precio;

  ServicioAgendado({
    this.servicioId,
    required this.nombre,
    required this.precio,
  });

  Map<String, dynamic> toMap() {
    return {
      'servicio_id': servicioId,
      'nombre': nombre,
      'precio': precio,
    };
  }

  factory ServicioAgendado.fromMap(Map<String, dynamic> map) {
    return ServicioAgendado(
      servicioId: map['servicio_id'] as String?,
      nombre: map['nombre'] as String? ?? '',
      precio: (map['precio'] as num?)?.toDouble() ?? 0,
    );
  }
}

class Customer {
  final String id;
  String nombre;
  String lugar;
  DateTime fecha;

  /// Suma de los precios de [servicios]. Se guarda como columna aparte
  /// (en vez de ser un getter) para que Finanzas y las tarjetas de
  /// cliente puedan leerlo sin recalcular, pero SIEMPRE se recalcula en
  /// [CustomerService] antes de guardar, nunca se edita a mano.
  double precio;

  /// Todos los servicios agendados en este mismo trabajo/visita.
  List<ServicioAgendado> servicios;

  /// Nombre combinado de todos los servicios, ej. "Corte de césped +
  /// Poda de arbustos". Es un getter (no se guarda) para que todo el
  /// código que ya leía `cliente.servicioNombre` (notificaciones,
  /// tarjeta de cliente, historial, mensaje de cobro) siga funcionando
  /// sin cambios.
  String get servicioNombre =>
      servicios.isEmpty ? '' : servicios.map((s) => s.nombre).join(' + ');

  /// Estado del trabajo y datos del cobro.
  EstadoTrabajo estado;
  MetodoPago? metodoPago;
  DateTime? fechaPago;

  /// Id del movimiento creado en Finanzas al cobrar, para poder
  /// eliminarlo si se deshace el cobro o se elimina el cliente.
  String? financeEntryId;

  /// Si no es null, este trabajo se repite automáticamente: al
  /// marcarlo como realizado, se genera el siguiente con esta misma
  /// frecuencia.
  Recurrencia? recurrencia;

  /// Id del primer trabajo de la serie recurrente a la que pertenece
  /// este cliente. Null si este ES el primero de su serie (o si nunca
  /// fue parte de una). Se usa para agrupar el "historial de
  /// servicios" de una serie completa.
  String? grupoRecurrenteId;

  Customer({
    required this.id,
    required this.nombre,
    required this.lugar,
    required this.fecha,
    required this.precio,
    List<ServicioAgendado>? servicios,
    this.estado = EstadoTrabajo.pendiente,
    this.metodoPago,
    this.fechaPago,
    this.financeEntryId,
    this.recurrencia,
    this.grupoRecurrenteId,
  }) : servicios = servicios ?? [];

  /// Id que identifica a toda la serie recurrente de este cliente
  /// (su propio id, si es el primero, o el id heredado si es una
  /// ocurrencia generada automáticamente).
  String get idDeSerie => grupoRecurrenteId ?? id;

  /// Copia el cliente reemplazando solo los campos indicados. Los
  /// campos de estado/cobro no editables desde el formulario general
  /// se conservan automáticamente.
  Customer copyWith({
    String? nombre,
    String? lugar,
    DateTime? fecha,
    double? precio,
    List<ServicioAgendado>? servicios,
    Recurrencia? recurrencia,
    bool limpiarRecurrencia = false,
  }) {
    return Customer(
      id: id,
      nombre: nombre ?? this.nombre,
      lugar: lugar ?? this.lugar,
      fecha: fecha ?? this.fecha,
      precio: precio ?? this.precio,
      servicios: servicios ?? this.servicios,
      estado: estado,
      metodoPago: metodoPago,
      fechaPago: fechaPago,
      financeEntryId: financeEntryId,
      recurrencia: limpiarRecurrencia ? null : (recurrencia ?? this.recurrencia),
      grupoRecurrenteId: grupoRecurrenteId,
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
      'servicios': servicios.map((s) => s.toMap()).toList(),
      'estado': estado.name,
      'metodo_pago': metodoPago?.name,
      'fecha_pago': fechaPago?.toIso8601String(),
      'finance_entry_id': financeEntryId,
      'recurrencia': recurrencia?.name,
      'grupo_recurrente_id': grupoRecurrenteId,
    };
  }

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'] as String,
      nombre: map['nombre'] as String,
      lugar: map['lugar'] as String,
      fecha: DateTime.tryParse(map['fecha'] as String? ?? '') ?? DateTime.now(),
      precio: (map['precio'] as num).toDouble(),
      servicios: _serviciosDesdeMapa(map),
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
      recurrencia: map['recurrencia'] != null
          ? Recurrencia.values.firstWhere(
              (r) => r.name == map['recurrencia'],
              orElse: () => Recurrencia.mensual,
            )
          : null,
      grupoRecurrenteId: map['grupo_recurrente_id'] as String?,
    );
  }
}

/// Lee la columna `servicios` (jsonb) de una fila de Supabase. Si viene
/// vacía pero la fila todavía tiene los campos viejos
/// `servicio_nombre`/`precio` (de antes de la migración a múltiples
/// servicios), arma un único [ServicioAgendado] con esos datos para no
/// perder información de trabajos ya guardados.
List<ServicioAgendado> _serviciosDesdeMapa(Map<String, dynamic> map) {
  final crudo = map['servicios'];
  if (crudo is List && crudo.isNotEmpty) {
    return crudo
        .map((item) => ServicioAgendado.fromMap(item as Map<String, dynamic>))
        .toList();
  }

  final nombreLegacy = map['servicio_nombre'] as String?;
  if (nombreLegacy != null && nombreLegacy.isNotEmpty) {
    return [
      ServicioAgendado(
        servicioId: map['servicio_id'] as String?,
        nombre: nombreLegacy,
        precio: (map['precio'] as num?)?.toDouble() ?? 0,
      ),
    ];
  }

  return [];
}