import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/customer.dart';
import 'connectivity_service.dart';
import 'local_cache_service.dart';
import 'notification_service.dart';
import 'sync_queue_service.dart';

/// Servicio encargado de administrar los clientes/trabajos agendados,
/// respaldado por la tabla `clientes` de Supabase.
///
/// Este servicio NO conoce nada de Finanzas a propósito (para mantener
/// los módulos independientes). Es la pantalla (CustomerScreen) quien
/// coordina: cuando se cobra un trabajo, crea el movimiento en
/// FinanceService y le pasa el id resultante a [marcarPagado] para
/// dejarlo enlazado. Por esa misma razón, el cobro hecho sin conexión
/// se coordina en `main.dart` (que sí conoce a ambos servicios) y no
/// aquí; ver el manejador `'cobro_pendiente'`.
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
///
/// --- Modo sin conexión ---
/// Antes de cada operación que toca solo la tabla `clientes` (crear,
/// editar, marcar realizado) se revisa [ConnectivityService.isOnline].
/// Si no hay conexión: el cambio se aplica de una vez en memoria (y en
/// la caché local, para que sobreviva a cerrar la app) y se encola en
/// [SyncQueueService] para reproducirse contra Supabase apenas vuelva
/// la señal. Un cliente creado sin conexión recibe un id temporal
/// (`local_...`); al sincronizar se reemplaza por el id real que
/// devuelve Supabase.
///
/// Eliminar un cliente y deshacer un cobro siguen requiriendo
/// conexión por ahora: son acciones poco frecuentes que además pueden
/// tocar un movimiento ya existente en Finanzas, y no vale la pena
/// arriesgar una inconsistencia entre módulos por un caso raro.
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

  bool get _online => ConnectivityService.instance.isOnline;

  /// Debe llamarse una sola vez al iniciar la app (ver main.dart) para
  /// que esta instancia sepa reproducir sus propias operaciones
  /// pendientes cuando vuelva la conexión.
  void registrarManejadoresSync() {
    final cola = SyncQueueService.instance;
    cola.registrarManejador('cliente_crear', _sincronizarCrear);
    cola.registrarManejador('cliente_actualizar', _sincronizarActualizar);
    cola.registrarManejador(
      'cliente_marcar_realizado',
      _sincronizarMarcarRealizado,
    );
  }

  /// Descarga los clientes del usuario autenticado. Sin conexión, carga
  /// en cambio la última copia guardada localmente.
  Future<void> cargar() async {
    cargando = true;
    notifyListeners();
    try {
      if (!_online) {
        _customers = await LocalCacheService.leerClientes();
        return;
      }

      final data = await _client.from(_tabla).select();
      _customers = (data as List)
          .map((fila) => Customer.fromMap(fila as Map<String, dynamic>))
          .toList();
      await LocalCacheService.guardarClientes(_customers);

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
      // Si falló por falta de red (o cualquier otra razón) y todavía
      // no hay nada en memoria, muestra al menos la última copia local
      // conocida en vez de dejar la pantalla vacía.
      if (_customers.isEmpty) {
        _customers = await LocalCacheService.leerClientes();
      }
    } finally {
      cargando = false;
      notifyListeners();
    }
  }

  /// Vacía los datos en memoria (al cerrar sesión).
  void limpiar() {
    _customers = [];
    notifyListeners();
    LocalCacheService.limpiarClientes();
  }

  Future<void> agregarCliente({
    required String nombre,
    required String lugar,
    required DateTime fecha,
    required List<ServicioAgendado> servicios,
    Recurrencia? recurrencia,
  }) async {
    final precioTotal = _sumarServicios(servicios);

    if (!_online) {
      final idLocal = 'local_${DateTime.now().microsecondsSinceEpoch}';
      final creado = Customer(
        id: idLocal,
        nombre: nombre,
        lugar: lugar,
        fecha: fecha,
        precio: precioTotal,
        servicios: servicios,
        recurrencia: recurrencia,
      );
      _customers.add(creado);
      notifyListeners();
      await LocalCacheService.guardarClientes(_customers);
      await SyncQueueService.instance.encolar('cliente_crear', {
        'idLocal': idLocal,
        'nombre': nombre,
        'lugar': lugar,
        'fecha': _soloFecha(fecha),
        'precio': precioTotal,
        'servicios': servicios.map((s) => s.toMap()).toList(),
        'recurrencia': recurrencia?.name,
        'grupoRecurrenteId': null,
      });
      await NotificationService.instance.programarRecordatoriosTrabajo(creado);
      return;
    }

    try {
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
      await LocalCacheService.guardarClientes(_customers);
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
    final precioTotal = _sumarServicios(servicios);
    final cliente = _buscar(id);
    if (cliente == null) return;

    if (!_online) {
      cliente.nombre = nombre;
      cliente.lugar = lugar;
      cliente.fecha = fecha;
      cliente.precio = precioTotal;
      cliente.servicios = servicios;
      cliente.recurrencia = recurrencia;
      notifyListeners();
      await LocalCacheService.guardarClientes(_customers);
      // Si `id` es un id temporal (`local_...`) de un cliente que
      // todavía no se sincroniza, esto igual funciona: la cola procesa
      // primero el 'cliente_crear' correspondiente (se encoló antes) y
      // reemplaza automáticamente ese id temporal por el real antes de
      // llegar a esta operación (ver `actualizarReferenciaId`).
      await SyncQueueService.instance.encolar('cliente_actualizar', {
        'clienteId': id,
        'nombre': nombre,
        'lugar': lugar,
        'fecha': _soloFecha(fecha),
        'servicios': servicios.map((s) => s.toMap()).toList(),
        'recurrencia': recurrencia?.name,
      });
      if (cliente.estado == EstadoTrabajo.pendiente) {
        await NotificationService.instance
            .programarRecordatoriosTrabajo(cliente);
      }
      return;
    }

    try {
      await _client.from(_tabla).update({
        'nombre': nombre,
        'lugar': lugar,
        'fecha': _soloFecha(fecha),
        'precio': precioTotal,
        'servicios': servicios.map((s) => s.toMap()).toList(),
        'recurrencia': recurrencia?.name,
      }).eq('id', id);

      cliente.nombre = nombre;
      cliente.lugar = lugar;
      cliente.fecha = fecha;
      cliente.precio = precioTotal;
      cliente.servicios = servicios;
      cliente.recurrencia = recurrencia;
      notifyListeners();
      await LocalCacheService.guardarClientes(_customers);
      // La fecha pudo haber cambiado: solo tiene sentido reprogramar
      // el recordatorio si el trabajo sigue pendiente.
      if (cliente.estado == EstadoTrabajo.pendiente) {
        await NotificationService.instance
            .programarRecordatoriosTrabajo(cliente);
      }
    } catch (e) {
      debugPrint('Error actualizando cliente: $e');
      rethrow;
    }
  }

  /// Marca el trabajo como ya realizado (pendiente de cobro). Si el
  /// cliente es recurrente, genera automáticamente el siguiente
  /// trabajo de la serie (también sin conexión, si hace falta).
  Future<void> marcarRealizado(String id) async {
    final cliente = _buscar(id);
    if (cliente == null) return;

    if (!_online) {
      cliente.estado = EstadoTrabajo.realizado;
      notifyListeners();
      await LocalCacheService.guardarClientes(_customers);
      await SyncQueueService.instance
          .encolar('cliente_marcar_realizado', {'clienteId': id});

      await NotificationService.instance
          .cancelarRecordatoriosTrabajo(cliente.id);
      await NotificationService.instance.avisarCobroPendiente(cliente);
      await NotificationService.instance
          .iniciarRecordatorioCobroSemanal(cliente);

      if (cliente.recurrencia != null) {
        await _generarSiguienteOcurrenciaOffline(cliente);
      }
      return;
    }

    try {
      await _client.from(_tabla).update({'estado': 'realizado'}).eq('id', id);
      cliente.estado = EstadoTrabajo.realizado;
      notifyListeners();
      await LocalCacheService.guardarClientes(_customers);
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
      await LocalCacheService.guardarClientes(_customers);

      await NotificationService.instance.programarRecordatoriosTrabajo(nuevo);
      await NotificationService.instance.avisarTrabajoRecurrenteGenerado(nuevo);
    } catch (e) {
      debugPrint('Error generando el siguiente trabajo recurrente: $e');
      // No relanzamos: que falle la generación automática del
      // siguiente trabajo no debería impedir que el actual quede
      // marcado como realizado.
    }
  }

  /// Igual que [_generarSiguienteOcurrencia], pero para cuando no hay
  /// conexión: crea el siguiente trabajo con un id temporal y lo deja
  /// encolado para subirlo a Supabase más adelante.
  Future<void> _generarSiguienteOcurrenciaOffline(Customer actual) async {
    final siguienteFecha = actual.recurrencia!.siguienteFecha(actual.fecha);
    final idLocal = 'local_${DateTime.now().microsecondsSinceEpoch}';
    final nuevo = Customer(
      id: idLocal,
      nombre: actual.nombre,
      lugar: actual.lugar,
      fecha: siguienteFecha,
      precio: actual.precio,
      servicios: actual.servicios,
      recurrencia: actual.recurrencia,
      grupoRecurrenteId: actual.idDeSerie,
    );
    _customers.add(nuevo);
    notifyListeners();
    await LocalCacheService.guardarClientes(_customers);

    await SyncQueueService.instance.encolar('cliente_crear', {
      'idLocal': idLocal,
      'nombre': nuevo.nombre,
      'lugar': nuevo.lugar,
      'fecha': _soloFecha(nuevo.fecha),
      'precio': nuevo.precio,
      'servicios': nuevo.servicios.map((s) => s.toMap()).toList(),
      'recurrencia': nuevo.recurrencia?.name,
      'grupoRecurrenteId': nuevo.grupoRecurrenteId,
    });

    await NotificationService.instance.programarRecordatoriosTrabajo(nuevo);
    await NotificationService.instance.avisarTrabajoRecurrenteGenerado(nuevo);
  }

  /// Marca el trabajo como pagado, guardando el método de pago y el id
  /// del movimiento creado en Finanzas. Este método asume que ya hay
  /// conexión (el cobro hecho sin conexión se coordina en main.dart,
  /// que actualiza primero la UI de forma optimista con
  /// [marcarPagadoOptimista] y llama a este método real más tarde, ya
  /// con el id real del movimiento en Finanzas).
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
        await LocalCacheService.guardarClientes(_customers);
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

  /// Actualiza el estado del cliente a "pagado" solo en memoria y en la
  /// caché local, para que la UI se sienta instantánea al cobrar sin
  /// conexión. El cobro real (crear el movimiento en Finanzas y guardar
  /// su id aquí con [marcarPagado]) queda pendiente en la cola de
  /// sincronización hasta que vuelva la señal.
  void marcarPagadoOptimista(String id, MetodoPago metodoPago) {
    final cliente = _buscar(id);
    if (cliente == null) return;
    cliente.estado = EstadoTrabajo.pagado;
    cliente.metodoPago = metodoPago;
    cliente.fechaPago = DateTime.now();
    notifyListeners();
    LocalCacheService.guardarClientes(_customers);
  }

  /// Deshace un cobro (por si se registró por error). No borra el
  /// movimiento en Finanzas; eso lo hace la pantalla usando el
  /// `financeEntryId` antes de llamar a este método.
  ///
  /// Requiere conexión: revertir un cobro normalmente implica también
  /// borrar el movimiento ya creado en Finanzas, y por ahora se prefiere
  /// no arriesgar una inconsistencia entre módulos por esta acción poco
  /// frecuente.
  Future<void> revertirCobro(String id) async {
    if (!_online) {
      throw Exception('Se necesita conexión a internet para deshacer un cobro.');
    }
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
        await LocalCacheService.guardarClientes(_customers);
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

  /// Requiere conexión, por la misma razón que [revertirCobro]: puede
  /// implicar borrar un movimiento ya existente en Finanzas.
  Future<void> eliminarCliente(String id) async {
    if (!_online) {
      throw Exception('Se necesita conexión a internet para eliminar un cliente.');
    }
    try {
      await _client.from(_tabla).delete().eq('id', id);
      _customers.removeWhere((c) => c.id == id);
      notifyListeners();
      await LocalCacheService.guardarClientes(_customers);
      await NotificationService.instance.cancelarTodoDeCliente(id);
    } catch (e) {
      debugPrint('Error eliminando cliente: $e');
      rethrow;
    }
  }

  // --- Manejadores de sincronización (se ejecutan solos al volver la
  // conexión; ver registrarManejadoresSync) ---

  Future<void> _sincronizarCrear(Map<String, dynamic> payload) async {
    final idLocal = payload['idLocal'] as String;
    final servicios = (payload['servicios'] as List)
        .map((s) => ServicioAgendado.fromMap(Map<String, dynamic>.from(s as Map)))
        .toList();

    final fila = await _client
        .from(_tabla)
        .insert({
          'nombre': payload['nombre'],
          'lugar': payload['lugar'],
          'fecha': payload['fecha'],
          'precio': payload['precio'],
          'servicios': servicios.map((s) => s.toMap()).toList(),
          'recurrencia': payload['recurrencia'],
          'grupo_recurrente_id': payload['grupoRecurrenteId'],
        })
        .select()
        .single();
    final creado = Customer.fromMap(fila);

    // Reemplaza el registro local temporal por el real ya sincronizado
    // (conservando su lugar en la lista no es necesario: customers ya
    // se reordena por fecha al leerse).
    _customers.removeWhere((c) => c.id == idLocal);
    _customers.add(creado);
    await LocalCacheService.guardarClientes(_customers);
    notifyListeners();

    // Si mientras estaba offline también se editó, se marcó como
    // realizado, etc., esos otros pendientes en la cola todavía
    // apuntan al id temporal: los actualizamos para que encuentren el
    // cliente real.
    await SyncQueueService.instance.actualizarReferenciaId(idLocal, creado.id);
  }

  Future<void> _sincronizarActualizar(Map<String, dynamic> payload) async {
    final id = payload['clienteId'] as String;
    final servicios = (payload['servicios'] as List)
        .map((s) => ServicioAgendado.fromMap(Map<String, dynamic>.from(s as Map)))
        .toList();
    final precioTotal = _sumarServicios(servicios);

    await _client.from(_tabla).update({
      'nombre': payload['nombre'],
      'lugar': payload['lugar'],
      'fecha': payload['fecha'],
      'precio': precioTotal,
      'servicios': servicios.map((s) => s.toMap()).toList(),
      'recurrencia': payload['recurrencia'],
    }).eq('id', id);
    // El estado en memoria ya se actualizó de forma optimista al
    // encolar la operación; aquí solo confirmamos contra Supabase.
  }

  Future<void> _sincronizarMarcarRealizado(Map<String, dynamic> payload) async {
    final id = payload['clienteId'] as String;
    await _client.from(_tabla).update({'estado': 'realizado'}).eq('id', id);
    // El estado, los avisos y la generación del siguiente trabajo
    // recurrente (si aplica) ya se resolvieron en el momento en que se
    // marcó offline; aquí solo confirmamos contra Supabase.
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