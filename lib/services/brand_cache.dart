import 'package:shared_preferences/shared_preferences.dart';

/// Guarda en el propio teléfono (no en Supabase) el último logo y color
/// de marca conocidos del negocio.
///
/// Existe por un motivo puntual: la pantalla de login/registro se
/// muestra ANTES de que haya una sesión activa, así que en ese momento
/// no se puede consultar el perfil del negocio en la base de datos
/// (las políticas de seguridad de Supabase requieren un usuario
/// autenticado). Como en la práctica cada teléfono queda dedicado a
/// un solo negocio, cachear localmente el último logo/color visto
/// permite mostrarlos también en el login, sin depender de ningún
/// servidor para eso.
class BrandCache {
  BrandCache._();
  static final BrandCache instance = BrandCache._();

  static const _claveLogo = 'brand_logo_url';
  static const _claveColor = 'brand_color_hex';

  String? _logoUrl;
  String? _colorHex;

  String? get logoUrl => _logoUrl;
  String? get colorHex => _colorHex;

  /// Carga los valores guardados en el teléfono a memoria. Se llama
  /// una vez, al arrancar la app (antes de runApp).
  Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    _logoUrl = prefs.getString(_claveLogo);
    _colorHex = prefs.getString(_claveColor);
  }

  /// Actualiza el logo/color cacheados (en memoria y en disco). Se
  /// llama cada vez que se carga o se guarda el perfil del negocio.
  Future<void> guardar({String? logoUrl, String? colorHex}) async {
    _logoUrl = logoUrl;
    _colorHex = colorHex;

    final prefs = await SharedPreferences.getInstance();

    if (logoUrl != null && logoUrl.isNotEmpty) {
      await prefs.setString(_claveLogo, logoUrl);
    } else {
      await prefs.remove(_claveLogo);
    }

    if (colorHex != null && colorHex.isNotEmpty) {
      await prefs.setString(_claveColor, colorHex);
    } else {
      await prefs.remove(_claveColor);
    }
  }
}