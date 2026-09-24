import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/customer.dart';
import '../models/inventory_item.dart';

/// Servicio centralizado de notificaciones locales de Green Garden.
///
/// Es un singleton para que cualquier servicio (Inventario, Clientes,
/// Facturas) pueda disparar avisos sin depender de un widget en
/// pantalla. Todo corre en el propio teléfono del usuario: no se usa
/// ningún servidor ni servicio push externo.
///
/// Los recordatorios programados con [zonedSchedule] los dispara el
/// propio sistema operativo (AlarmManager en Android, Notification
/// Center en iOS), así que llegan aunque la app esté completamente
/// cerrada.
///
/// Avisos que genera:
/// - Stock bajo en inventario.
/// - Recordatorio de un trabajo agendado: 2 días antes, 1 día antes
///   y el mismo día.
/// - Cobro pendiente, más un recordatorio recurrente cada 7 días
///   mientras siga sin cobrarse.
/// - Confirmación cuando un cobro queda registrado.
/// - Confirmación cuando se genera una factura.
/// - Confirmación cuando se genera automáticamente el siguiente
///   trabajo de una serie recurrente.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _listo = false;

  static const AndroidNotificationChannel _canalGeneral =
      AndroidNotificationChannel(
    'green_garden_general',
    'Avisos generales',
    description: 'Facturas generadas y cobros registrados',
    importance: Importance.defaultImportance,
  );

  static const AndroidNotificationChannel _canalTrabajos =
      AndroidNotificationChannel(
    'green_garden_trabajos',
    'Trabajos y cobros',
    description:
        'Recordatorios de trabajos agendados y de cobros pendientes',
    importance: Importance.high,
  );

  static const AndroidNotificationChannel _canalInventario =
      AndroidNotificationChannel(
    'green_garden_inventario',
    'Inventario',
    description: 'Avisos de stock bajo',
    importance: Importance.high,
  );

  static const NotificationDetails _detallesTrabajos = NotificationDetails(
    android: AndroidNotificationDetails(
      'green_garden_trabajos',
      'Trabajos y cobros',
      channelDescription:
          'Recordatorios de trabajos agendados y de cobros pendientes',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  static const NotificationDetails _detallesGeneral = NotificationDetails(
    android: AndroidNotificationDetails(
      'green_garden_general',
      'Avisos generales',
      channelDescription: 'Facturas generadas y cobros registrados',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
  );

  static const NotificationDetails _detallesInventario = NotificationDetails(
    android: AndroidNotificationDetails(
      'green_garden_inventario',
      'Inventario',
      channelDescription: 'Avisos de stock bajo',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  /// Días antes del trabajo en que se manda un recordatorio.
  ///
  /// 2 = en 2 días
  /// 1 = mañana
  /// 0 = hoy
  static const List<int> _etapasRecordatorioTrabajo = [2, 1, 0];

  /// Cada cuánto se repite el recordatorio de un cobro pendiente.
  static const Duration _intervaloRecordatorioCobro = Duration(days: 7);

  /// Artículos por los que ya se avisó que están bajos de stock.
  final Set<String> _stockAvisado = {};

  /// Inicializa el plugin, crea los canales de Android y pide permisos.
  Future<void> inicializar() async {
    if (_listo) return;

    // Inicializar base de datos de zonas horarias.
    tz_data.initializeTimeZones();

    try {
      // flutter_timezone >= 5 devuelve TimezoneInfo.
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();

      // Necesitamos el identificador IANA como String.
      final nombreZona = timezoneInfo.identifier;

      tz.setLocalLocation(tz.getLocation(nombreZona));

      debugPrint('Zona horaria configurada: $nombreZona');
    } catch (e) {
      debugPrint('No se pudo fijar la zona horaria local: $e');
    }

    const inicializacionAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const inicializacionIOS = DarwinInitializationSettings();

    const configuracion = InitializationSettings(
      android: inicializacionAndroid,
      iOS: inicializacionIOS,
    );

    // flutter_local_notifications >= 20 usa parámetros nombrados.
    await _plugin.initialize(
      settings: configuracion,
    );

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidImpl != null) {
      await androidImpl.createNotificationChannel(_canalGeneral);
      await androidImpl.createNotificationChannel(_canalTrabajos);
      await androidImpl.createNotificationChannel(_canalInventario);
    }

    await solicitarPermisos();

    _listo = true;
  }

  /// Pide permiso de notificaciones.
  Future<bool> solicitarPermisos() async {
    if (Platform.isIOS || Platform.isMacOS) {
      final iosImpl = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

      final resultado = await iosImpl?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );

      return resultado ?? false;
    }

    if (Platform.isAndroid) {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      final permitido =
          await androidImpl?.requestNotificationsPermission() ?? false;

      return permitido;
    }

    return true;
  }

  // ---------------------------------------------------------------
  // Inventario: stock bajo
  // ---------------------------------------------------------------

  int _idStock(String itemId) => ('stock_$itemId').hashCode & 0x7fffffff;

  /// Revisa un artículo y avisa si está en o por debajo del stock mínimo.
  Future<void> revisarStockBajo(InventoryItem item) async {
    if (!item.bajoStock) {
      _stockAvisado.remove(item.id);
      return;
    }

    if (_stockAvisado.contains(item.id)) return;

    _stockAvisado.add(item.id);

    final cantidadTexto = item.cantidad.toStringAsFixed(
      item.cantidad % 1 == 0 ? 0 : 1,
    );

    await _plugin.show(
      id: _idStock(item.id),
      title: 'Stock bajo: ${item.nombre}',
      body:
          'Quedan $cantidadTexto ${item.unidad}. '
          'Considera reabastecer pronto.',
      notificationDetails: _detallesInventario,
    );
  }

  /// Revisa una lista completa de artículos.
  Future<void> revisarStockBajoLista(
    List<InventoryItem> items,
  ) async {
    for (final item in items) {
      await revisarStockBajo(item);
    }
  }

  // ---------------------------------------------------------------
  // Clientes: recordatorios de trabajos agendados
  // ---------------------------------------------------------------

  int _idTrabajo(String clienteId, int diasAntes) =>
      ('trabajo_${clienteId}_$diasAntes').hashCode & 0x7fffffff;

  String _tituloEtapa(int diasAntes) {
    switch (diasAntes) {
      case 2:
        return 'Trabajo en 2 días';
      case 1:
        return 'Trabajo mañana';
      default:
        return 'Trabajo hoy';
    }
  }

  /// Programa los 3 recordatorios:
  ///
  /// - 2 días antes
  /// - 1 día antes
  /// - mismo día
  ///
  /// Todos a las 8:00 a. m.
  Future<void> programarRecordatoriosTrabajo(
    Customer cliente,
  ) async {
    await cancelarRecordatoriosTrabajo(cliente.id);

    final ahora = tz.TZDateTime.now(tz.local);

    final lugar =
        cliente.lugar.isNotEmpty ? ' en ${cliente.lugar}' : '';

    final servicio = cliente.servicioNombre.isNotEmpty
        ? ' (${cliente.servicioNombre})'
        : '';

    for (final diasAntes in _etapasRecordatorioTrabajo) {
      final fechaAviso =
          cliente.fecha.subtract(Duration(days: diasAntes));

      final horario = tz.TZDateTime(
        tz.local,
        fechaAviso.year,
        fechaAviso.month,
        fechaAviso.day,
        8,
      );

      if (horario.isBefore(ahora)) continue;

      await _plugin.zonedSchedule(
        id: _idTrabajo(cliente.id, diasAntes),
        title: '${_tituloEtapa(diasAntes)}: ${cliente.nombre}',
        body:
            'Trabajo$servicio$lugar el '
            '${cliente.fecha.day.toString().padLeft(2, '0')}/'
            '${cliente.fecha.month.toString().padLeft(2, '0')}.',
        scheduledDate: horario,
        notificationDetails: _detallesTrabajos,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  /// Cancela las 3 etapas del recordatorio de trabajo.
  Future<void> cancelarRecordatoriosTrabajo(
    String clienteId,
  ) async {
    for (final diasAntes in _etapasRecordatorioTrabajo) {
      await _plugin.cancel(
        id: _idTrabajo(clienteId, diasAntes),
      );
    }
  }

  /// Reprograma los recordatorios de todos los trabajos pendientes.
  Future<void> reprogramarTrabajosPendientes(
    List<Customer> clientes,
  ) async {
    for (final cliente in clientes) {
      if (cliente.estado == EstadoTrabajo.pendiente) {
        await programarRecordatoriosTrabajo(cliente);
      }
    }
  }

  // ---------------------------------------------------------------
  // Clientes: cobros
  // ---------------------------------------------------------------

  int _idCobroInmediato(String clienteId) =>
      ('cobro_$clienteId').hashCode & 0x7fffffff;

  int _idCobroSemanal(String clienteId) =>
      ('cobro_semanal_$clienteId').hashCode & 0x7fffffff;

  /// Aviso inmediato de que un trabajo se marcó como realizado.
  Future<void> avisarCobroPendiente(Customer cliente) async {
    await _plugin.show(
      id: _idCobroInmediato(cliente.id),
      title: 'Cobro pendiente: ${cliente.nombre}',
      body:
          'El trabajo se marcó como realizado. '
          'Falta cobrar \$${cliente.precio.toStringAsFixed(2)}.',
      notificationDetails: _detallesTrabajos,
    );
  }

  /// Programa el recordatorio recurrente de cobro pendiente.
  ///
  /// Se repite cada 7 días hasta que se cancele.
  Future<void> iniciarRecordatorioCobroSemanal(
    Customer cliente,
  ) async {
    await detenerRecordatorioCobroSemanal(cliente.id);

    final primeraOcurrencia = tz.TZDateTime.now(tz.local).add(
      _intervaloRecordatorioCobro,
    );

    await _plugin.zonedSchedule(
      id: _idCobroSemanal(cliente.id),
      title: 'Sigue pendiente el cobro: ${cliente.nombre}',
      body:
          'Aún no se ha cobrado '
          '\$${cliente.precio.toStringAsFixed(2)} '
          'de este trabajo.',
      scheduledDate: primeraOcurrencia,
      notificationDetails: _detallesTrabajos,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  Future<void> detenerRecordatorioCobroSemanal(
    String clienteId,
  ) async {
    await _plugin.cancel(
      id: _idCobroSemanal(clienteId),
    );
  }

  /// Aviso de confirmación cuando un cobro queda registrado.
  Future<void> avisarCobroRegistrado(
    Customer cliente,
  ) async {
    final metodo = cliente.metodoPago != null
        ? ' con ${cliente.metodoPago!.label}'
        : '';

    await _plugin.show(
      id: _idCobroInmediato(cliente.id),
      title: 'Cobro registrado: ${cliente.nombre}',
      body:
          'Se registró el cobro de '
          '\$${cliente.precio.toStringAsFixed(2)}$metodo.',
      notificationDetails: _detallesGeneral,
    );
  }

  Future<void> cancelarAvisoCobro(String clienteId) async {
    await _plugin.cancel(
      id: _idCobroInmediato(clienteId),
    );
  }

  // ---------------------------------------------------------------
  // Clientes: servicios recurrentes
  // ---------------------------------------------------------------

  /// Aviso de confirmación cuando se genera automáticamente el
  /// siguiente trabajo de una serie recurrente.
  Future<void> avisarTrabajoRecurrenteGenerado(Customer nuevo) async {
    final dia = nuevo.fecha.day.toString().padLeft(2, '0');
    final mes = nuevo.fecha.month.toString().padLeft(2, '0');

    await _plugin.show(
      // Rango propio (2,000,000+) para no chocar con los otros ids,
      // que se generan por hashCode.
      id: 2000000 + (nuevo.id.hashCode & 0xfffff),
      title: 'Siguiente trabajo agendado: ${nuevo.nombre}',
      body: 'Se generó automáticamente para el $dia/$mes, por ser recurrente.',
      notificationDetails: _detallesGeneral,
    );
  }

  // ---------------------------------------------------------------
  // Facturas
  // ---------------------------------------------------------------

  /// Aviso de confirmación cuando se genera una factura.
  Future<void> avisarFacturaGenerada({
    required int numero,
    required String clienteNombre,
  }) async {
    await _plugin.show(
      id: 1000000 + numero,
      title: 'Factura #$numero generada',
      body: 'Se generó la factura de $clienteNombre.',
      notificationDetails: _detallesGeneral,
    );
  }

  // ---------------------------------------------------------------
  // Limpieza
  // ---------------------------------------------------------------

  /// Cancela todo lo relacionado con un cliente.
  Future<void> cancelarTodoDeCliente(
    String clienteId,
  ) async {
    await cancelarRecordatoriosTrabajo(clienteId);
    await cancelarAvisoCobro(clienteId);
    await detenerRecordatorioCobroSemanal(clienteId);
  }

  /// Cancela absolutamente todas las notificaciones.
  Future<void> limpiarTodo() async {
    await _plugin.cancelAll();
    _stockAvisado.clear();
  }
}