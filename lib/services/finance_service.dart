import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/finance_entry.dart';

/// Servicio encargado de administrar los movimientos financieros
/// (ingresos y egresos), respaldado por la tabla `finanzas` de
/// Supabase.
class FinanceService extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;
  static const String _tabla = 'finanzas';

  List<FinanceEntry> _entries = [];
  bool cargando = false;

  /// Lista de solo lectura de todos los movimientos, del más reciente
  /// al más antiguo.
  List<FinanceEntry> get entries {
    final lista = List<FinanceEntry>.from(_entries);
    lista.sort((a, b) => b.fecha.compareTo(a.fecha));
    return List.unmodifiable(lista);
  }

  /// Movimientos filtrados por tipo (ingreso o egreso).
  List<FinanceEntry> porTipo(TipoMovimiento tipo) =>
      entries.where((e) => e.tipo == tipo).toList();

  double get totalIngresos => _entries
      .where((e) => e.tipo == TipoMovimiento.ingreso)
      .fold(0.0, (suma, e) => suma + e.monto);

  double get totalEgresos => _entries
      .where((e) => e.tipo == TipoMovimiento.egreso)
      .fold(0.0, (suma, e) => suma + e.monto);

  double get balance => totalIngresos - totalEgresos;

  /// Descarga los movimientos del usuario autenticado.
  Future<void> cargar() async {
    cargando = true;
    notifyListeners();
    try {
      final data = await _client.from(_tabla).select();
      _entries = (data as List)
          .map((fila) => FinanceEntry.fromMap(fila as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error cargando finanzas: $e');
    } finally {
      cargando = false;
      notifyListeners();
    }
  }

  /// Vacía los datos en memoria (al cerrar sesión).
  void limpiar() {
    _entries = [];
    notifyListeners();
  }

  /// Agrega un nuevo movimiento y devuelve su id (lo necesita el
  /// módulo de Clientes para enlazar un cobro a su movimiento).
  Future<String> agregarMovimiento({
    required String descripcion,
    required TipoMovimiento tipo,
    required double monto,
    required DateTime fecha,
    String categoria = '',
  }) async {
    try {
      final fila = await _client
          .from(_tabla)
          .insert({
            'descripcion': descripcion,
            'tipo': tipo.name,
            'monto': monto,
            'fecha': _soloFecha(fecha),
            'categoria': categoria,
          })
          .select()
          .single();
      final creado = FinanceEntry.fromMap(fila);
      _entries.add(creado);
      notifyListeners();
      return creado.id;
    } catch (e) {
      debugPrint('Error agregando movimiento: $e');
      rethrow;
    }
  }

  Future<void> actualizarMovimiento(
    String id, {
    required String descripcion,
    required TipoMovimiento tipo,
    required double monto,
    required DateTime fecha,
    String categoria = '',
  }) async {
    try {
      await _client.from(_tabla).update({
        'descripcion': descripcion,
        'tipo': tipo.name,
        'monto': monto,
        'fecha': _soloFecha(fecha),
        'categoria': categoria,
      }).eq('id', id);

      final index = _entries.indexWhere((e) => e.id == id);
      if (index != -1) {
        _entries[index] = _entries[index].copyWith(
          descripcion: descripcion,
          tipo: tipo,
          monto: monto,
          fecha: fecha,
          categoria: categoria,
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error actualizando movimiento: $e');
      rethrow;
    }
  }

  Future<void> eliminarMovimiento(String id) async {
    try {
      await _client.from(_tabla).delete().eq('id', id);
      _entries.removeWhere((e) => e.id == id);
      notifyListeners();
    } catch (e) {
      debugPrint('Error eliminando movimiento: $e');
      rethrow;
    }
  }

  /// La columna `fecha` en Supabase es de tipo `date` (sin hora), así
  /// que enviamos solo "YYYY-MM-DD".
  String _soloFecha(DateTime fecha) => fecha.toIso8601String().split('T').first;
}