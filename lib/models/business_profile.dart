/// Datos del negocio que aparecen en el encabezado de cada factura.
/// Cada cuenta (usuario) tiene su propio perfil, así que si vendes la
/// app a otro negocio, cada quien ve su propia información en sus
/// facturas, no la tuya.
library;

class BusinessProfile {
  String nombreComercial;
  String operador;
  String telefono;
  String correo;

  BusinessProfile({
    this.nombreComercial = '',
    this.operador = '',
    this.telefono = '',
    this.correo = '',
  });

  bool get estaCompleto =>
      nombreComercial.isNotEmpty && operador.isNotEmpty;

  factory BusinessProfile.fromMap(Map<String, dynamic> map) {
    return BusinessProfile(
      nombreComercial: map['nombre_comercial'] as String? ?? '',
      operador: map['operador'] as String? ?? '',
      telefono: map['telefono'] as String? ?? '',
      correo: map['correo'] as String? ?? '',
    );
  }
}