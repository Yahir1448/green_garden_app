import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/tarifa_servicio.dart';

/// Servicio encargado de administrar las tarifas configuradas para el
/// Cotizador, respaldado por la tabla `tarifas_servicios` de Supabase.
/// Se configuran una sola vez (o cada vez que cambien tus precios) y
/// después el Cotizador las usa para calcular presupuestos sin tener
/// que volver a escribir la fórmula cada vez.
class TarifaService extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;
  static const String _tabla = 'tarifas_servicios';

  List<TarifaServicio> _tarifas = [];
  bool cargando = false;

  List<TarifaServicio> get tarifas => List.unmodifiable(_tarifas);

  TarifaServicio? buscarPorId(String? id) {
    if (id == null) return null;
    for (final tarifa in _tarifas) {
      if (tarifa.id == id) return tarifa;
    }
    return null;
  }

  Future<void> cargar() async {
    cargando = true;
    notifyListeners();
    try {
      final data = await _client.from(_tabla).select();
      _tarifas = (data as List)
          .map((fila) => TarifaServicio.fromMap(fila as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error cargando tarifas: $e');
    } finally {
      cargando = false;
      notifyListeners();
    }
  }

  void limpiar() {
    _tarifas = [];
    notifyListeners();
  }

  Future<void> agregarTarifa({
    String? servicioId,
    required String servicioNombre,
    required double m2Min,
    required double m2Max,
    required double precioBase,
    required double precioPorM2Extra,
    required double kmBase,
    required double precioPorKmExtra,
  }) async {
    try {
      final fila = await _client
          .from(_tabla)
          .insert({
            'servicio_id': servicioId,
            'servicio_nombre': servicioNombre,
            'm2_min': m2Min,
            'm2_max': m2Max,
            'precio_base': precioBase,
            'precio_por_m2_extra': precioPorM2Extra,
            'km_base': kmBase,
            'precio_por_km_extra': precioPorKmExtra,
          })
          .select()
          .single();
      _tarifas.add(TarifaServicio.fromMap(fila));
      notifyListeners();
    } catch (e) {
      debugPrint('Error agregando tarifa: $e');
      rethrow;
    }
  }

  Future<void> actualizarTarifa(
    String id, {
    String? servicioId,
    required String servicioNombre,
    required double m2Min,
    required double m2Max,
    required double precioBase,
    required double precioPorM2Extra,
    required double kmBase,
    required double precioPorKmExtra,
  }) async {
    try {
      await _client.from(_tabla).update({
        'servicio_id': servicioId,
        'servicio_nombre': servicioNombre,
        'm2_min': m2Min,
        'm2_max': m2Max,
        'precio_base': precioBase,
        'precio_por_m2_extra': precioPorM2Extra,
        'km_base': kmBase,
        'precio_por_km_extra': precioPorKmExtra,
      }).eq('id', id);

      final index = _tarifas.indexWhere((t) => t.id == id);
      if (index != -1) {
        _tarifas[index] = TarifaServicio(
          id: id,
          servicioId: servicioId,
          servicioNombre: servicioNombre,
          m2Min: m2Min,
          m2Max: m2Max,
          precioBase: precioBase,
          precioPorM2Extra: precioPorM2Extra,
          kmBase: kmBase,
          precioPorKmExtra: precioPorKmExtra,
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error actualizando tarifa: $e');
      rethrow;
    }
  }

  Future<void> eliminarTarifa(String id) async {
    try {
      await _client.from(_tabla).delete().eq('id', id);
      _tarifas.removeWhere((t) => t.id == id);
      notifyListeners();
    } catch (e) {
      debugPrint('Error eliminando tarifa: $e');
      rethrow;
    }
  }
}