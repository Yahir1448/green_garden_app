/// Datos del negocio que aparecen en el encabezado de cada factura, y
/// que definen la marca visual de la app (logo y color) para este
/// negocio en particular.
///
/// Cada cuenta (usuario) tiene su propio perfil, así que si vendes la
/// app a otro negocio, cada quien ve su propia información en sus
/// facturas y su propia marca en la app, no la tuya.
library;

class BusinessProfile {
  String nombreComercial;
  String operador;
  String telefono;
  String correo;

  /// URL pública del logo subido a Supabase Storage. Null si el
  /// negocio todavía no ha subido uno (se usa el ícono por defecto).
  String? logoUrl;

  /// Color de marca del negocio, en hex (ej. "#1B4D2E"). Null si el
  /// negocio no eligió un color propio (se usa el verde por defecto
  /// de Green Garden).
  String? colorPrimario;

  BusinessProfile({
    this.nombreComercial = '',
    this.operador = '',
    this.telefono = '',
    this.correo = '',
    this.logoUrl,
    this.colorPrimario,
  });

  bool get estaCompleto =>
      nombreComercial.isNotEmpty && operador.isNotEmpty;

  factory BusinessProfile.fromMap(Map<String, dynamic> map) {
    return BusinessProfile(
      nombreComercial: map['nombre_comercial'] as String? ?? '',
      operador: map['operador'] as String? ?? '',
      telefono: map['telefono'] as String? ?? '',
      correo: map['correo'] as String? ?? '',
      logoUrl: map['logo_url'] as String?,
      colorPrimario: map['color_primario'] as String?,
    );
  }
}