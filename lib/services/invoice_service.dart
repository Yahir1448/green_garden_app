import 'package:supabase_flutter/supabase_flutter.dart';

/// Servicio encargado de asignar el número consecutivo de cada
/// factura y dejar un registro mínimo en la tabla `facturas` de
/// Supabase (no guarda el PDF en sí, solo el consecutivo y a qué
/// cliente/monto corresponde).
class InvoiceService {
  final SupabaseClient _client = Supabase.instance.client;
  static const String _tabla = 'facturas';

  Future<int> _siguienteNumero() async {
    final data = await _client
        .from(_tabla)
        .select('numero')
        .order('numero', ascending: false)
        .limit(1);
    final lista = data as List;
    if (lista.isEmpty) return 1;
    return (lista.first['numero'] as int) + 1;
  }

  /// Reserva el siguiente número de factura y lo registra enlazado al
  /// cliente correspondiente. Devuelve el número asignado.
  Future<int> registrarFactura({
    required String clienteId,
    required double monto,
  }) async {
    final numero = await _siguienteNumero();
    await _client.from(_tabla).insert({
      'cliente_id': clienteId,
      'numero': numero,
      'fecha_emision': DateTime.now().toIso8601String().split('T').first,
      'monto': monto,
    });
    return numero;
  }
}