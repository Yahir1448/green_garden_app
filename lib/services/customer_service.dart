import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/customer.dart';
import 'notification_service.dart';

/// Servicio encargado de administrar los clientes/trabajos agendados,
/// respaldado por la tabla `clientes` de Supabase.
///
/// Este servicio NO conoce nada de Finanzas a propósito (para mantener
/// los módulos independientes). Es la pantalla (CustomerScreen) quien
/// coordina: cuando se cobra un trabajo, crea el movimiento en
/// FinanceService y le pasa el id resultante a [marcarPagado] para
/// dejarlo enlazado.
///
/// Sí conoce a [NotificationService], porque los recordatorios de
/// trabajos agendados y los avisos de cobro están directamente
/// atados al ciclo de vida de un cliente (se crean, se reprograman o
/// se cancelan junto con él), sin importar desde qué pantalla se
/// dispare la acción.
///
/// También maneja los trabajos recurrentes: si un cliente tiene una
/// [Recurrencia] asignada, al marcarlo como realizado se genera
/// automáticamente el siguiente trabajo de la serie.
class CustomerService extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;
  static const String _tabla = 'clientes';

  List<Customer> _customers = [];
  bool cargando = false;

  /// Lista de solo lectura de todos los clientes, ordenada por fecha.
  List<Customer> get customers {
    final lista = List<Customer>.from(_customers);
    lista.sort((a, b) => a.fecha.compareTo(b.fecha));
    return List.unmodifiable(lista);
  }

  /// Clientes/trabajos filtrados por estado.
  List<Customer> porEstado(EstadoTrabajo estado) =>
      customers.where((c) => c.estado == estado).toList();

  /// Todos los trabajos (pasados y futuros) que pertenecen a la misma
  /// serie recurrente que [cliente], del más reciente al más antiguo.
  /// Si [cliente] nunca fue recurrente, la lista solo lo contiene a él.
  List<Customer> historialDe(Customer cliente) {
    final idSerie = cliente.idDeSerie;
    final lista =
        _customers.where((c) => c.idDeSerie == idSerie).toList();
    lista.sort((a, b) => b.fecha.compareTo(a.fecha));
    return lista;
  }

  Customer? _buscar(String id) {
    for (final cliente in _customers) {
      if (cliente.id == id) return cliente;
    }
    return null;
  }

  /// Descarga los clientes del usuario autenticado.
  Future<void> cargar() async {
    cargando = true;
    notifyListeners();
    try {
      final data = await _client.from(_tabla).select();
      _customers = (data as List)
          .map((fila) => Customer.fromMap(fila as Map<String, dynamic>))
          .toList();

      // Deja las alarmas de este dispositivo al día (por ejemplo, tras
      // reinstalar la app o iniciar sesión en un teléfono nuevo).
      await NotificationService.instance
          .reprogramarTrabajosPendientes(_customers);
      for (final cliente in _customers) {
        if (cliente.estado == EstadoTrabajo.realizado) {
          // Solo reinicia el recordatorio semanal recurrente; no
          // reenvía el aviso inmediato de "cobro pendiente" cada vez
          // que se abre la app.
          await NotificationService.instance
              .iniciarRecordatorioCobroSemanal(cliente);
        }
      }
    } catch (e) {
      debugPrint('Error cargando clientes: $e');
    } finally {
      cargando = false;
      notifyListeners();
    }
  }

  /// Vacía los datos en memoria (al cerrar sesión).
  void limpiar() {
    _customers = [];
    notifyListeners();
  }

  Future<void> agregarCliente({
    required String nombre,
    required String lugar,
    required DateTime fecha,
    required List<ServicioAgendado> servicios,
    Recurrencia? recurrencia,
  }) async {
    try {
      final precioTotal = _sumarServicios(servicios);
      final fila = await _client
          .from(_tabla)
          .insert({
            'nombre': nombre,
            'lugar': lugar,
            'fecha': _soloFecha(fecha),
            'precio': precioTotal,
            'servicios': servicios.map((s) => s.toMap()).toList(),
            'recurrencia': recurrencia?.name,
          })
          .select()
          .single();
      final creado = Customer.fromMap(fila);
      _customers.add(creado);
      notifyListeners();
      // Un cliente nuevo siempre arranca en estado "pendiente", así
      // que programamos sus recordatorios de una vez.
      await NotificationService.instance
          .programarRecordatoriosTrabajo(creado);
    } catch (e) {
      debugPrint('Error agregando cliente: $e');
      rethrow;
    }
  }

  Future<void> actualizarCliente(
    String id, {
    required String nombre,
    required String lugar,
    required DateTime fecha,
    required List<ServicioAgendado> servicios,
    Recurrencia? recurrencia,
  }) async {
    try {
      final precioTotal = _sumarServicios(servicios);
      await _client.from(_tabla).update({
        'nombre': nombre,
        'lugar': lugar,
        'fecha': _soloFecha(fecha),
        'precio': precioTotal,
        'servicios': servicios.map((s) => s.toMap()).toList(),
        'recurrencia': recurrencia?.name,
      }).eq('id', id);

      final cliente = _buscar(id);
      if (cliente != null) {
        cliente.nombre = nombre;
        cliente.lugar = lugar;
        cliente.fecha = fecha;
        cliente.precio = precioTotal;
        cliente.servicios = servicios;
        cliente.recurrencia = recurrencia;
        notifyListeners();
        // La fecha pudo haber cambiado: solo tiene sentido reprogramar
        // el recordatorio si el trabajo sigue pendiente.
        if (cliente.estado == EstadoTrabajo.pendiente) {
          await NotificationService.instance
              .programarRecordatoriosTrabajo(cliente);
        }
      }
    } catch (e) {
      debugPrint('Error actualizando cliente: $e');
      rethrow;
    }
  }

  /// Marca el trabajo como ya realizado (pendiente de cobro). Si el
  /// cliente es recurrente, genera automáticamente el siguiente
  /// trabajo de la serie.
  Future<void> marcarRealizado(String id) async {
    try {
      await _client.from(_tabla).update({'estado': 'realizado'}).eq('id', id);
      final cliente = _buscar(id);
      if (cliente != null) {
        cliente.estado = EstadoTrabajo.realizado;
        notifyListeners();
        // Ya no aplican los recordatorios de "trabajo agendado" y en
        // cambio arrancan los avisos de cobro pendiente.
        await NotificationService.instance
            .cancelarRecordatoriosTrabajo(cliente.id);
        await NotificationService.instance.avisarCobroPendiente(cliente);
        await NotificationService.instance
            .iniciarRecordatorioCobroSemanal(cliente);

        if (cliente.recurrencia != null) {
          await _generarSiguienteOcurrencia(cliente);
        }
      }
    } catch (e) {
      debugPrint('Error marcando trabajo como realizado: $e');
      rethrow;
    }
  }

  /// Crea el siguiente trabajo de una serie recurrente, heredando
  /// nombre, lugar, precio, servicio enlazado y la misma frecuencia,
  /// con la fecha que corresponda según [Recurrencia.siguienteFecha].
  Future<void> _generarSiguienteOcurrencia(Customer actual) async {
    try {
      final siguienteFecha = actual.recurrencia!.siguienteFecha(actual.fecha);

      final fila = await _client
          .from(_tabla)
          .insert({
            'nombre': actual.nombre,
            'lugar': actual.lugar,
            'fecha': _soloFecha(siguienteFecha),
            'precio': actual.precio,
            'servicios': actual.servicios.map((s) => s.toMap()).toList(),
            'recurrencia': actual.recurrencia!.name,
            'grupo_recurrente_id': actual.idDeSerie,
          })
          .select()
          .single();

      final nuevo = Customer.fromMap(fila);
      _customers.add(nuevo);
      notifyListeners();

      await NotificationService.instance.programarRecordatoriosTrabajo(nuevo);
      await NotificationService.instance.avisarTrabajoRecurrenteGenerado(nuevo);
    } catch (e) {
      debugPrint('Error generando el siguiente trabajo recurrente: $e');
      // No relanzamos: que falle la generación automática del
      // siguiente trabajo no debería impedir que el actual quede
      // marcado como realizado.
    }
  }

  /// Marca el trabajo como pagado, guardando el método de pago y el id
  /// del movimiento creado en Finanzas.
  Future<void> marcarPagado(
    String id, {
    required MetodoPago metodoPago,
    required String financeEntryId,
  }) async {
    final fechaPago = DateTime.now();
    try {
      await _client.from(_tabla).update({
        'estado': 'pagado',
        'metodo_pago': metodoPago.name,
        'fecha_pago': fechaPago.toIso8601String(),
        'finance_entry_id': financeEntryId,
      }).eq('id', id);

      final cliente = _buscar(id);
      if (cliente != null) {
        cliente.estado = EstadoTrabajo.pagado;
        cliente.metodoPago = metodoPago;
        cliente.fechaPago = fechaPago;
        cliente.financeEntryId = financeEntryId;
        notifyListeners();
        await NotificationService.instance.avisarCobroRegistrado(cliente);
        // Ya se cobró: se acabó el recordatorio semanal.
        await NotificationService.instance
            .detenerRecordatorioCobroSemanal(cliente.id);
      }
    } catch (e) {
      debugPrint('Error marcando trabajo como pagado: $e');
      rethrow;
    }
  }

  /// Deshace un cobro (por si se registró por error). No borra el
  /// movimiento en Finanzas; eso lo hace la pantalla usando el
  /// `financeEntryId` antes de llamar a este método.
  Future<void> revertirCobro(String id) async {
    try {
      await _client.from(_tabla).update({
        'estado': 'realizado',
        'metodo_pago': null,
        'fecha_pago': null,
        'finance_entry_id': null,
      }).eq('id', id);

      final cliente = _buscar(id);
      if (cliente != null) {
        cliente.estado = EstadoTrabajo.realizado;
        cliente.metodoPago = null;
        cliente.fechaPago = null;
        cliente.financeEntryId = null;
        notifyListeners();
        // Vuelve a quedar pendiente de cobro: reactiva ambos avisos.
        await NotificationService.instance.avisarCobroPendiente(cliente);
        await NotificationService.instance
            .iniciarRecordatorioCobroSemanal(cliente);
      }
    } catch (e) {
      debugPrint('Error revirtiendo cobro: $e');
      rethrow;
    }
  }

  Future<void> eliminarCliente(String id) async {
    try {
      await _client.from(_tabla).delete().eq('id', id);
      _customers.removeWhere((c) => c.id == id);
      notifyListeners();
      await NotificationService.instance.cancelarTodoDeCliente(id);
    } catch (e) {
      debugPrint('Error eliminando cliente: $e');
      rethrow;
    }
  }

  /// La columna `fecha` en Supabase es de tipo `date` (sin hora), así
  /// que enviamos solo "YYYY-MM-DD".
  String _soloFecha(DateTime fecha) => fecha.toIso8601String().split('T').first;

  /// Precio total de un trabajo: la suma de todos sus servicios
  /// agendados. Nunca se recibe como parámetro aparte para evitar que
  /// quede desincronizado de la lista real de servicios.
  double _sumarServicios(List<ServicioAgendado> servicios) =>
      servicios.fold<double>(0, (suma, s) => suma + s.precio);
}