import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/business_profile.dart';
import '../theme/theme_controller.dart';
import '../utils/color_utils.dart';
import 'brand_cache.dart';

/// Servicio encargado del perfil del negocio (nombre comercial,
/// operador, teléfono, correo, logo y color de marca), respaldado por
/// la tabla `perfil_negocio` y el bucket `logos` de Supabase Storage.
/// Cada usuario tiene un único perfil.
class BusinessProfileService extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;
  static const String _tabla = 'perfil_negocio';
  static const String _bucketLogos = 'logos';

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
      await _sincronizarMarca();
    } catch (e) {
      debugPrint('Error cargando perfil de negocio: $e');
    } finally {
      cargando = false;
      notifyListeners();
    }
  }

  /// Vacía los datos en memoria (al cerrar sesión). Se deja el logo y
  /// color cacheados en el teléfono tal cual, para que la pantalla de
  /// login siga mostrando la marca de este dispositivo hasta que la
  /// siguiente cuenta que inicie sesión cargue la suya.
  void limpiar() {
    perfil = BusinessProfile();
    notifyListeners();
  }

  Future<void> guardar({
    required String nombreComercial,
    required String operador,
    required String telefono,
    required String correo,
    String? logoUrl,
    String? colorPrimario,
  }) async {
    final userId = _client.auth.currentUser!.id;
    try {
      await _client.from(_tabla).upsert({
        'user_id': userId,
        'nombre_comercial': nombreComercial,
        'operador': operador,
        'telefono': telefono,
        'correo': correo,
        'logo_url': logoUrl,
        'color_primario': colorPrimario,
        'updated_at': DateTime.now().toIso8601String(),
      });
      perfil = BusinessProfile(
        nombreComercial: nombreComercial,
        operador: operador,
        telefono: telefono,
        correo: correo,
        logoUrl: logoUrl,
        colorPrimario: colorPrimario,
      );
      notifyListeners();
      await _sincronizarMarca();
    } catch (e) {
      debugPrint('Error guardando perfil de negocio: $e');
      rethrow;
    }
  }

  /// Sube una imagen elegida de la galería como logo del negocio, al
  /// bucket `logos` de Supabase Storage, y devuelve su URL pública
  /// (con un parámetro de versión para evitar que quede cacheada una
  /// imagen vieja). No guarda el perfil por sí sola: quien llame a
  /// este método debe luego llamar a [guardar] con la URL resultante.
  Future<String> subirLogo(XFile imagen) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('No hay una sesión activa.');
    }

    final bytes = await imagen.readAsBytes();
    final extension =
        imagen.name.contains('.') ? imagen.name.split('.').last.toLowerCase() : 'jpg';
    final ruta = '$userId/logo.$extension';

    await _client.storage.from(_bucketLogos).uploadBinary(
          ruta,
          bytes,
          fileOptions: FileOptions(
            contentType: 'image/$extension',
            upsert: true,
          ),
        );

    final urlBase = _client.storage.from(_bucketLogos).getPublicUrl(ruta);
    // Evita que el teléfono muestre una versión vieja del logo
    // cacheada por el navegador/Image.network.
    return '$urlBase?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Actualiza el [ThemeController] (para repintar la app al momento)
  /// y el [BrandCache] (para que la pantalla de login la recuerde)
  /// con el logo y color actuales del perfil.
  Future<void> _sincronizarMarca() async {
    ThemeController.instance.actualizarColorMarca(colorFromHex(perfil.colorPrimario));
    await BrandCache.instance.guardar(
      logoUrl: perfil.logoUrl,
      colorHex: perfil.colorPrimario,
    );
  }
}