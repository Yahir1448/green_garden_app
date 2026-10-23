import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'sync_queue_service.dart';

/// Singleton que sabe si el teléfono tiene conexión a internet en este
/// momento (wifi o datos móviles) y avisa a quien esté escuchando
/// (`ChangeNotifier`) cada vez que cambia.
///
/// Cuando detecta que se pasó de "sin conexión" a "con conexión",
/// dispara automáticamente [SyncQueueService.procesarPendientes] para
/// que los cambios hechos offline se suban solos, sin que el usuario
/// tenga que hacer nada.
class ConnectivityService extends ChangeNotifier {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;

  bool _online = true;
  bool get isOnline => _online;

  bool _inicializado = false;

  /// Debe llamarse una sola vez, muy al inicio de `main()`, antes de
  /// `runApp`.
  Future<void> inicializar() async {
    if (_inicializado) return;
    _inicializado = true;

    try {
      final resultado = await _connectivity.checkConnectivity();
      _online = _hayConexion(resultado);
    } catch (e) {
      debugPrint('No se pudo revisar la conexión inicial: $e');
    }

    _sub = _connectivity.onConnectivityChanged.listen((resultado) {
      final ahoraOnline = _hayConexion(resultado);
      final volvioLaConexion = ahoraOnline && !_online;
      if (ahoraOnline != _online) {
        _online = ahoraOnline;
        notifyListeners();
      }
      if (volvioLaConexion) {
        SyncQueueService.instance.procesarPendientes();
      }
    });

    notifyListeners();
  }

  bool _hayConexion(List<ConnectivityResult> resultado) =>
      resultado.any((r) => r != ConnectivityResult.none);

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}