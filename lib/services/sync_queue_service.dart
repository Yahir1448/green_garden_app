import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Una operación pendiente de sincronizar con Supabase: qué tipo de
/// operación es (para saber quién debe procesarla) y los datos
/// necesarios para repetirla ([payload]).
class SyncQueueItem {
  final String id;
  final String tipo;
  final Map<String, dynamic> payload;
  final DateTime creado;

  SyncQueueItem({
    required this.id,
    required this.tipo,
    required this.payload,
    required this.creado,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'tipo': tipo,
        'payload': payload,
        'creado': creado.toIso8601String(),
      };

  factory SyncQueueItem.fromMap(Map<String, dynamic> map) => SyncQueueItem(
        id: map['id'] as String,
        tipo: map['tipo'] as String,
        payload: Map<String, dynamic>.from(map['payload'] as Map),
        creado: DateTime.tryParse(map['creado'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Función que sabe reproducir contra Supabase una operación de un
/// [tipo] concreto, a partir de su `payload`. La registra el servicio
/// dueño de esa operación (ver `registrarManejador`).
typedef ManejadorSync = Future<void> Function(Map<String, dynamic> payload);

/// Cola genérica de operaciones hechas sin conexión, pendientes de
/// subir a Supabase. No sabe nada de clientes, facturas ni inventario:
/// cada servicio (CustomerService, etc.) o coordinador (main.dart, para
/// operaciones que cruzan varios módulos, como el cobro) registra sus
/// propios manejadores para los tipos que le pertenecen.
///
/// Persiste en `shared_preferences` como JSON, así que sobrevive a
/// cerrar la app sin haber recuperado conexión.
class SyncQueueService extends ChangeNotifier {
  SyncQueueService._();
  static final SyncQueueService instance = SyncQueueService._();

  static const String _clave = 'sync_queue_pendientes';

  List<SyncQueueItem> _pendientes = [];
  final Map<String, ManejadorSync> _manejadores = {};
  bool sincronizando = false;

  List<SyncQueueItem> get pendientes => List.unmodifiable(_pendientes);
  int get cantidadPendiente => _pendientes.length;

  /// Debe llamarse una sola vez al inicio de `main()`, para recuperar
  /// lo que haya quedado pendiente de una sesión anterior.
  Future<void> cargar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final crudo = prefs.getString(_clave);
      if (crudo == null) return;
      final lista = jsonDecode(crudo) as List;
      _pendientes = lista
          .map((e) => SyncQueueItem.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Error cargando la cola de sincronización: $e');
    }
  }

  Future<void> _guardar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _clave,
        jsonEncode(_pendientes.map((e) => e.toMap()).toList()),
      );
    } catch (e) {
      debugPrint('Error guardando la cola de sincronización: $e');
    }
  }

  /// Cada servicio registra aquí, una sola vez al iniciar la app, cómo
  /// reproducir sus propios tipos de operación.
  void registrarManejador(String tipo, ManejadorSync manejador) {
    _manejadores[tipo] = manejador;
  }

  /// Agrega una operación a la cola (se llama al hacer una acción sin
  /// conexión) y la guarda de inmediato en disco.
  Future<void> encolar(String tipo, Map<String, dynamic> payload) async {
    final item = SyncQueueItem(
      id: '${DateTime.now().microsecondsSinceEpoch}_${_pendientes.length}',
      tipo: tipo,
      payload: payload,
      creado: DateTime.now(),
    );
    _pendientes.add(item);
    await _guardar();
    notifyListeners();
  }

  /// Cuando un `id` temporal generado offline (por ejemplo, un cliente
  /// creado sin conexión) se reemplaza por el `id` real que devolvió
  /// Supabase al sincronizar, cualquier otra operación pendiente que
  /// todavía apunte al `id` viejo (por ejemplo, "marcar realizado" en
  /// ese mismo cliente) se actualiza para que encuentre el registro
  /// correcto.
  Future<void> actualizarReferenciaId(String idViejo, String idNuevo) async {
    var cambio = false;
    for (final item in _pendientes) {
      if (item.payload['clienteId'] == idViejo) {
        item.payload['clienteId'] = idNuevo;
        cambio = true;
      }
    }
    if (cambio) {
      await _guardar();
      notifyListeners();
    }
  }

  /// Recorre la cola en orden e intenta reproducir cada operación. Las
  /// que fallan (por ejemplo, si se perdió la conexión a la mitad) se
  /// quedan en la cola para el siguiente intento; las que no tienen
  /// manejador todavía registrado también se conservan tal cual.
  Future<void> procesarPendientes() async {
    if (sincronizando || _pendientes.isEmpty) return;
    sincronizando = true;
    notifyListeners();

    final restantes = <SyncQueueItem>[];
    for (final item in List<SyncQueueItem>.from(_pendientes)) {
      final manejador = _manejadores[item.tipo];
      if (manejador == null) {
        restantes.add(item);
        continue;
      }
      try {
        await manejador(item.payload);
      } catch (e) {
        debugPrint('Error sincronizando "${item.tipo}": $e');
        restantes.add(item);
      }
    }

    _pendientes = restantes;
    await _guardar();
    sincronizando = false;
    notifyListeners();
  }

  /// Vacía la cola (al cerrar sesión, para que no se mezclen cambios
  /// pendientes de una cuenta con los de otra en el mismo teléfono).
  void limpiar() {
    _pendientes = [];
    _guardar();
    notifyListeners();
  }
}