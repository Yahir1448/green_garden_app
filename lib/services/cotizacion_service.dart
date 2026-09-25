import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cotizacion.dart';

/// Servicio encargado de guardar y administrar las cotizaciones
/// calculadas, respaldado por la tabla `cotizaciones` de Supabase. Así
/// el usuario puede retomar un presupuesto ya calculado sin volver a
/// escribir todos los datos, y llevar registro de cuáles se aceptaron.
class CotizacionService extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;
  static const String _tabla = 'cotizaciones';

  List<Cotizacion> _cotizaciones = [];
  bool cargando = false;

  /// De más reciente a más antigua.
  List<Cotizacion> get cotizaciones {
    final lista = List<Cotizacion>.from(_cotizaciones);
    lista.sort((a, b) => b.creadaEn.compareTo(a.creadaEn));
    return List.unmodifiable(lista);
  }

  Future<void> cargar() async {
    cargando = true;
    notifyListeners();
    try {
      final data = await _client.from(_tabla).select();
      _cotizaciones = (data as List)
          .map((fila) => Cotizacion.fromMap(fila as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error cargando cotizaciones: $e');
    } finally {
      cargando = false;
      notifyListeners();
    }
  }

  void limpiar() {
    _cotizaciones = [];
    notifyListeners();
  }

  Future<Cotizacion> guardarCotizacion({
    required String nombreCliente,
    required String lugar,
    required List<ServicioCotizado> servicios,
    required double margenRentabilidad,
    required double costoTotal,
    required double precioTotal,
  }) async {
    try {
      final fila = await _client
          .from(_tabla)
          .insert({
            'nombre_cliente': nombreCliente,
            'lugar': lugar,
            'lineas': servicios.map((s) => s.toMap()).toList(),
            'margen_rentabilidad': margenRentabilidad,
            'costo_total': costoTotal,
            'precio_total': precioTotal,
            'estado': EstadoCotizacion.pendiente.name,
          })
          .select()
          .single();
      final creada = Cotizacion.fromMap(fila);
      _cotizaciones.add(creada);
      notifyListeners();
      return creada;
    } catch (e) {
      debugPrint('Error guardando cotización: $e');
      rethrow;
    }
  }

  Future<void> actualizarCotizacion(
    String id, {
    required String nombreCliente,
    required String lugar,
    required List<ServicioCotizado> servicios,
    required double margenRentabilidad,
    required double costoTotal,
    required double precioTotal,
  }) async {
    try {
      await _client.from(_tabla).update({
        'nombre_cliente': nombreCliente,
        'lugar': lugar,
        'lineas': servicios.map((s) => s.toMap()).toList(),
        'margen_rentabilidad': margenRentabilidad,
        'costo_total': costoTotal,
        'precio_total': precioTotal,
      }).eq('id', id);

      final index = _cotizaciones.indexWhere((c) => c.id == id);
      if (index != -1) {
        final actual = _cotizaciones[index];
        actual.nombreCliente = nombreCliente;
        actual.lugar = lugar;
        actual.servicios = servicios;
        actual.margenRentabilidad = margenRentabilidad;
        actual.costoTotal = costoTotal;
        actual.precioTotal = precioTotal;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error actualizando cotización: $e');
      rethrow;
    }
  }

  /// Marca la cotización como aceptada por el cliente y ya agendada
  /// como trabajo (ver [CustomerService.agregarCliente]).
  Future<void> marcarAgendada(String id) async {
    try {
      await _client.from(_tabla).update({'estado': 'agendada'}).eq('id', id);
      final index = _cotizaciones.indexWhere((c) => c.id == id);
      if (index != -1) {
        _cotizaciones[index].estado = EstadoCotizacion.agendada;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error marcando cotización como agendada: $e');
      rethrow;
    }
  }

  Future<void> eliminarCotizacion(String id) async {
    try {
      await _client.from(_tabla).delete().eq('id', id);
      _cotizaciones.removeWhere((c) => c.id == id);
      notifyListeners();
    } catch (e) {
      debugPrint('Error eliminando cotización: $e');
      rethrow;
    }
  }
}