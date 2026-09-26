import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/service_item.dart';

/// Servicio encargado de administrar el catálogo de servicios,
/// respaldado por la tabla `servicios` de Supabase.
class ServiceCatalogService extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;
  static const String _tabla = 'servicios';

  List<ServiceItem> _servicios = [];
  bool cargando = false;

  /// Lista de solo lectura de todos los servicios, ordenada por nombre.
  List<ServiceItem> get servicios {
    final lista = List<ServiceItem>.from(_servicios);
    lista.sort((a, b) => a.nombre.compareTo(b.nombre));
    return List.unmodifiable(lista);
  }

  /// Busca un servicio por su id. Devuelve null si no existe (por
  /// ejemplo, si el servicio fue eliminado del catálogo después de
  /// haberse enlazado a un cliente).
  ServiceItem? buscarPorId(String? id) {
    if (id == null) return null;
    for (final servicio in _servicios) {
      if (servicio.id == id) return servicio;
    }
    return null;
  }

  /// Descarga el catálogo del usuario autenticado.
  Future<void> cargar() async {
    cargando = true;
    notifyListeners();
    try {
      final data = await _client.from(_tabla).select();
      _servicios = (data as List)
          .map((fila) => ServiceItem.fromMap(fila as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error cargando servicios: $e');
    } finally {
      cargando = false;
      notifyListeners();
    }
  }

  /// Vacía los datos en memoria (al cerrar sesión).
  void limpiar() {
    _servicios = [];
    notifyListeners();
  }

  Future<void> agregarServicio({
    required String nombre,
    required String descripcion,
    required double precio,
    List<RecetaInsumo> receta = const [],
  }) async {
    try {
      final fila = await _client
          .from(_tabla)
          .insert({
            'nombre': nombre,
            'descripcion': descripcion,
            'precio': precio,
            'receta': receta.map((r) => r.toMap()).toList(),
          })
          .select()
          .single();
      _servicios.add(ServiceItem.fromMap(fila));
      notifyListeners();
    } catch (e) {
      debugPrint('Error agregando servicio: $e');
      rethrow;
    }
  }

  /// [receta] es opcional: si se omite (null), la receta actual del
  /// servicio no se toca. Se pasa explícitamente solo desde
  /// RecetasScreen, que es donde se configura.
  Future<void> actualizarServicio(
    String id, {
    required String nombre,
    required String descripcion,
    required double precio,
    List<RecetaInsumo>? receta,
  }) async {
    try {
      final actualizacion = <String, dynamic>{
        'nombre': nombre,
        'descripcion': descripcion,
        'precio': precio,
      };
      if (receta != null) {
        actualizacion['receta'] = receta.map((r) => r.toMap()).toList();
      }
      await _client.from(_tabla).update(actualizacion).eq('id', id);

      final index = _servicios.indexWhere((s) => s.id == id);
      if (index != -1) {
        _servicios[index] = _servicios[index].copyWith(
          nombre: nombre,
          descripcion: descripcion,
          precio: precio,
          receta: receta,
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error actualizando servicio: $e');
      rethrow;
    }
  }

  Future<void> eliminarServicio(String id) async {
    try {
      await _client.from(_tabla).delete().eq('id', id);
      _servicios.removeWhere((s) => s.id == id);
      notifyListeners();
    } catch (e) {
      debugPrint('Error eliminando servicio: $e');
      rethrow;
    }
  }
}