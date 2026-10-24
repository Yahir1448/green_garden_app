import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show FocusManager;
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Acceso con huella o rostro como "candado" de la app.
///
/// La sesión de Supabase sigue guardada en el teléfono como siempre;
/// este servicio solo decide si hay que pedir la huella/rostro antes de
/// mostrar la app (al abrirla, y al volver tras más de unos segundos en
/// segundo plano). No guarda contraseñas ni tokens.
///
/// Importante: es un bloqueo de interfaz, no cifra los datos locales.
class BiometricService {
  BiometricService._();

  static final BiometricService instance = BiometricService._();

  static const String _kActivada = 'biometria_activada';
  static const String _kPreguntada = 'biometria_preguntada';

  final LocalAuthentication _auth = LocalAuthentication();

  bool _activada = false;
  bool _preguntada = false;

  /// El usuario activó el acceso biométrico.
  bool get activada => _activada;

  /// Ya se le ofreció activarlo (para no insistir en cada inicio).
  bool get yaPreguntada => _preguntada;

  /// true mientras la app está bloqueada esperando huella/rostro.
  final ValueNotifier<bool> bloqueada = ValueNotifier<bool>(false);

  /// true mientras el sistema muestra su diálogo biométrico. El diálogo
  /// provoca cambios de ciclo de vida en la app que no deben contarse
  /// como "salió de la app".
  bool ocupado = false;

  /// Mensaje legible del último intento fallido (null si no hubo).
  String? ultimoError;

  /// Lee las preferencias guardadas. Llamar en main() antes de runApp.
  Future<void> cargar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _activada = prefs.getBool(_kActivada) ?? false;
      _preguntada = prefs.getBool(_kPreguntada) ?? false;
    } catch (e) {
      debugPrint('No se pudieron leer las preferencias biométricas: $e');
    }
  }

  /// El teléfono puede verificar la identidad del usuario (huella,
  /// rostro o, como respaldo, el PIN/patrón de la pantalla de bloqueo).
  /// Si devuelve false, [ultimoError] explica el motivo.
  ///
  /// No se exige que haya una huella o rostro registrado: algunos
  /// teléfonos reportan una lista vacía de biometrías aunque sí tengan
  /// una, y con el PIN como respaldo el candado funciona igual.
  Future<bool> disponible() async {
    ultimoError = null;
    try {
      final soportado = await _auth.isDeviceSupported();
      if (!soportado) {
        ultimoError =
            'Este teléfono no tiene huella, rostro ni bloqueo de pantalla '
            'configurado. Configúralo en los ajustes del teléfono.';
      }
      return soportado;
    } catch (e) {
      debugPrint('Error comprobando biometría: $e');
      ultimoError = 'No se pudo consultar la biometría del teléfono: $e';
      return false;
    }
  }

  /// Muestra el diálogo del sistema. Devuelve true si el usuario se
  /// identificó. Permite el PIN/patrón del teléfono como respaldo, por
  /// si la huella falla o se bloquea por demasiados intentos.
  Future<bool> autenticar(String motivo) async {
    if (ocupado) return false;
    ocupado = true;
    ultimoError = null;
    try {
      return await _auth.authenticate(
        localizedReason: motivo,
        biometricOnly: false,
      );
    } on LocalAuthException catch (e) {
      debugPrint('Autenticación local fallida: ${e.code}');
      if (e.code == LocalAuthExceptionCode.biometricLockout) {
        ultimoError =
            'Demasiados intentos fallidos. Desbloquea con el PIN del '
            'teléfono o inicia sesión con tu contraseña.';
      } else {
        // Cancelar el diálogo no es un error: solo se informa el resto.
        final codigo = e.code.toString().split('.').last;
        if (codigo != 'userCanceled' && codigo != 'systemCanceled') {
          ultimoError = 'No se pudo verificar tu identidad ($codigo).';
        }
      }
      return false;
    } catch (e) {
      debugPrint('Error inesperado en la autenticación local: $e');
      ultimoError =
          'No se pudo usar la verificación biométrica en este teléfono: $e';
      return false;
    } finally {
      ocupado = false;
    }
  }

  Future<void> activar() async {
    _activada = true;
    await _guardar(_kActivada, true);
  }

  Future<void> desactivar() async {
    _activada = false;
    bloqueada.value = false;
    await _guardar(_kActivada, false);
  }

  Future<void> marcarPreguntada() async {
    _preguntada = true;
    await _guardar(_kPreguntada, true);
  }

  /// Bloquea la app (solo si el acceso biométrico está activado).
  void bloquear() {
    if (!_activada) return;
    // Cierra el teclado para que no quede abierto detrás del bloqueo.
    FocusManager.instance.primaryFocus?.unfocus();
    bloqueada.value = true;
  }

  void desbloquear() => bloqueada.value = false;

  /// Se llama al cerrar sesión: la preferencia es de la cuenta que
  /// estaba en uso, no de quien inicie sesión después en este teléfono.
  Future<void> reiniciar() async {
    _activada = false;
    _preguntada = false;
    bloqueada.value = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kActivada);
      await prefs.remove(_kPreguntada);
    } catch (e) {
      debugPrint('No se pudieron borrar las preferencias biométricas: $e');
    }
  }

  Future<void> _guardar(String clave, bool valor) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(clave, valor);
    } catch (e) {
      debugPrint('No se pudo guardar $clave: $e');
    }
  }
}