import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/business_profile.dart';

/// Servicio encargado del perfil del negocio (nombre comercial,
/// operador, teléfono, correo), respaldado por la tabla
/// `perfil_negocio` de Supabase. Cada usuario tiene un único perfil.
class BusinessProfileService extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;
  static const String _tabla = 'perfil_negocio';

  BusinessProfile perfil = BusinessProfile();
  bool cargando = false;

  /// Descarga el perfil del usuario autenticado. Si todavía no existe
  /// (primera vez), deja los campos vacíos salvo el correo, que se
  /// prellena con el de la cuenta como valor de partida.
  Future<void> cargar() async {
    cargando = true;
    notifyListeners();
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;

      final fila = await _client
          .from(_tabla)
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (fila != null) {
        perfil = BusinessProfile.fromMap(fila);
      } else {
        perfil = BusinessProfile(correo: _client.auth.currentUser?.email ?? '');
      }
    } catch (e) {
      debugPrint('Error cargando perfil de negocio: $e');
    } finally {
      cargando = false;
      notifyListeners();
    }
  }

  /// Vacía los datos en memoria (al cerrar sesión).
  void limpiar() {
    perfil = BusinessProfile();
    notifyListeners();
  }

  Future<void> guardar({
    required String nombreComercial,
    required String operador,
    required String telefono,
    required String correo,
  }) async {
    final userId = _client.auth.currentUser!.id;
    try {
      await _client.from(_tabla).upsert({
        'user_id': userId,
        'nombre_comercial': nombreComercial,
        'operador': operador,
        'telefono': telefono,
        'correo': correo,
        'updated_at': DateTime.now().toIso8601String(),
      });
      perfil = BusinessProfile(
        nombreComercial: nombreComercial,
        operador: operador,
        telefono: telefono,
        correo: correo,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Error guardando perfil de negocio: $e');
      rethrow;
    }
  }
}