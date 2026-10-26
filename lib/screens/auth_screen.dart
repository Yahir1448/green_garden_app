import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/brand_cache.dart';
import '../theme/app_theme.dart';
import '../widgets/business_logo.dart';
import 'terms_screen.dart';

/// Indica que el usuario está en pleno proceso de recuperar su
/// contraseña.
///
/// Verificar el código del correo (`verifyOTP`) abre una sesión de
/// Supabase. Sin esta marca, `AuthGate` vería "hay sesión" y llevaría
/// al usuario directo al dashboard, antes de que alcance a escribir su
/// contraseña nueva. Mientras [activa] sea true, `AuthGate` mantiene
/// visible la pantalla de acceso (`AuthScreen`).
class RecoveryState {
  RecoveryState._();

  static final ValueNotifier<bool> activa = ValueNotifier<bool>(false);
}

/// Pantalla de acceso: permite iniciar sesión, crear una cuenta nueva o
/// recuperar la contraseña, con correo y contraseña usando Supabase
/// Auth. Cada cuenta ve únicamente sus propios datos (inventario,
/// clientes, finanzas, servicios), gracias a las políticas de
/// seguridad definidas en `schema.sql`.
///
/// Recuperación de contraseña (por código):
/// 1. "¿Olvidaste tu contraseña?" envía un correo con un código.
/// 2. La pantalla pide el código y la nueva contraseña.
/// 3. Se verifica el código (`verifyOTP`, que abre sesión) y se guarda
///    la contraseña nueva (`updateUser`).
/// Para que funcione, la plantilla "Reset Password" de Supabase debe
/// incluir `{{ .Token }}`.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  static const int _segundosEntreReenvios = 60;

  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _codigoCtrl = TextEditingController();
  final _nuevaCtrl = TextEditingController();
  final _confirmarCtrl = TextEditingController();

  bool _esRegistro = false;
  bool _cargando = false;
  String? _error;

  // Recuperación de contraseña.
  bool _modoCodigo = false;
  bool _codigoVerificado = false;
  bool _verNueva = false;
  int _segundosReenvio = 0;
  Timer? _timerReenvio;

  @override
  void dispose() {
    _timerReenvio?.cancel();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _codigoCtrl.dispose();
    _nuevaCtrl.dispose();
    _confirmarCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (!_formKey.currentState!.validate()) return;

    // Crear cuenta exige aceptar los Términos y Condiciones: se muestra
    // el texto completo con "Rechazar" / "Aceptar". Si se rechaza (o se
    // vuelve atrás), no se llama a Supabase y la cuenta no se crea.
    if (_esRegistro) {
      final aceptado = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => const TermsScreen(modo: ModoTerminos.decision),
        ),
      );
      if (!mounted) return;
      if (aceptado != true) {
        setState(() {
          _error = 'Para crear una cuenta es necesario aceptar los '
              'Términos y Condiciones y la Política de Privacidad.';
        });
        return;
      }
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    try {
      if (_esRegistro) {
        await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
          // Queda registrado en la cuenta qué versión de los términos se
          // aceptó y cuándo.
          data: metadatosAceptacion(),
        );

        if (mounted) {
          setState(() {
            _error = null;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Cuenta creada. Revisa tu correo si se requiere confirmación, '
                'o inicia sesión directamente.',
              ),
            ),
          );
        }
      } else {
        await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: password,
        );

        // Si el inicio de sesión es exitoso, el listener de sesión en
        // main.dart se encarga de navegar automáticamente al home.
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(
        () => _error = 'Ocurrió un error inesperado. Intenta de nuevo.',
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// Abre los términos en modo lectura (desde el formulario de registro).
  void _verTerminos() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TermsScreen()),
    );
  }

  // ---------------------------------------------------------------
  // Recuperación de contraseña
  // ---------------------------------------------------------------

  /// Traduce los mensajes más comunes de Supabase en este flujo.
  String _traducirError(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('expired') || (m.contains('token') && m.contains('invalid'))) {
      return 'El código es incorrecto o ya venció. Pide uno nuevo.';
    }
    if (m.contains('different from the old password')) {
      return 'La nueva contraseña debe ser distinta a la anterior.';
    }
    if (m.contains('rate limit') || e.statusCode == '429') {
      return 'Demasiados intentos. Espera un momento e intenta de nuevo.';
    }
    return e.message;
  }

  void _iniciarEsperaReenvio() {
    _timerReenvio?.cancel();
    setState(() => _segundosReenvio = _segundosEntreReenvios);
    _timerReenvio = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_segundosReenvio <= 1) {
        t.cancel();
        setState(() => _segundosReenvio = 0);
      } else {
        setState(() => _segundosReenvio--);
      }
    });
  }

  /// Pide el correo con el código. Devuelve true si se envió.
  Future<bool> _pedirCodigo(String email) async {
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      return true;
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = _traducirError(e));
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = 'Ocurrió un error inesperado. Intenta de nuevo.',
        );
      }
    }
    return false;
  }

  /// Paso 1: envía el código y pasa a la pantalla donde se escribe.
  Future<void> _recuperarContrasena() async {
    final email = _emailCtrl.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _error = 'Ingresa tu correo electrónico primero';
      });
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    final enviado = await _pedirCodigo(email);

    if (!mounted) return;
    setState(() => _cargando = false);

    if (enviado) {
      _codigoCtrl.clear();
      _nuevaCtrl.clear();
      _confirmarCtrl.clear();
      setState(() {
        _modoCodigo = true;
        _codigoVerificado = false;
      });
      _iniciarEsperaReenvio();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Te enviamos un código de verificación a tu correo.'),
        ),
      );
    }
  }

  Future<void> _reenviarCodigo() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    final enviado = await _pedirCodigo(_emailCtrl.text.trim());

    if (!mounted) return;
    setState(() => _cargando = false);

    if (enviado) {
      _iniciarEsperaReenvio();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Te enviamos un código nuevo.')),
      );
    }
  }

  /// Paso 2: verifica el código y guarda la contraseña nueva.
  Future<void> _cambiarContrasena() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _cargando = true;
      _error = null;
    });

    final auth = Supabase.instance.client.auth;

    try {
      if (!_codigoVerificado) {
        // verifyOTP abre una sesión. Esta marca evita que AuthGate lleve
        // al usuario al dashboard antes de que cambie su contraseña.
        RecoveryState.activa.value = true;
        await auth.verifyOTP(
          email: _emailCtrl.text.trim(),
          token: _codigoCtrl.text.trim(),
          type: OtpType.recovery,
        );
        // El código solo sirve una vez: si guardar la contraseña falla
        // (por ejemplo, es igual a la anterior), el reintento se salta
        // este paso.
        _codigoVerificado = true;
      }

      await auth.updateUser(UserAttributes(password: _nuevaCtrl.text));

      // El aviso se muestra antes de soltar el bloqueo: el
      // ScaffoldMessenger vive en MaterialApp y el mensaje se mantiene
      // visible ya en el dashboard.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contraseña actualizada.')),
        );
      }
      RecoveryState.activa.value = false;
    } on AuthException catch (e) {
      if (!_codigoVerificado) RecoveryState.activa.value = false;
      if (mounted) setState(() => _error = _traducirError(e));
    } catch (e) {
      if (!_codigoVerificado) RecoveryState.activa.value = false;
      if (mounted) {
        setState(
          () => _error = 'Ocurrió un error inesperado. Intenta de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// Sale de la recuperación y vuelve al inicio de sesión. Si el código
  /// ya se había verificado, hay una sesión abierta que se cierra para
  /// no dejar entrar sin haber cambiado la contraseña.
  Future<void> _cancelarRecuperacion() async {
    final yaVerificado = _codigoVerificado;

    _timerReenvio?.cancel();
    setState(() {
      _modoCodigo = false;
      _codigoVerificado = false;
      _segundosReenvio = 0;
      _error = null;
      _codigoCtrl.clear();
      _nuevaCtrl.clear();
      _confirmarCtrl.clear();
    });

    if (yaVerificado) {
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (e) {
        debugPrint('No se pudo cerrar la sesión de recuperación: $e');
      }
    }
    RecoveryState.activa.value = false;
  }

  // ---------------------------------------------------------------
  // Interfaz
  // ---------------------------------------------------------------

  List<Widget> _errorWidgets() {
    if (_error == null) return const [];
    return [
      const SizedBox(height: 12),
      Text(
        _error!,
        style: const TextStyle(color: Colors.redAccent),
      ),
    ];
  }

  List<Widget> _contenidoAcceso() {
    return [
      TextFormField(
        controller: _emailCtrl,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(
          labelText: 'Correo electrónico',
          prefixIcon: Icon(Icons.email_outlined),
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Ingresa tu correo';
          }

          if (!value.contains('@')) {
            return 'Correo inválido';
          }

          return null;
        },
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _passwordCtrl,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: 'Contraseña',
          prefixIcon: Icon(Icons.lock_outline),
        ),
        validator: (value) {
          if (value == null || value.length < 6) {
            return 'Mínimo 6 caracteres';
          }

          return null;
        },
      ),
      if (_esRegistro) ...[
        const SizedBox(height: 12),
        Text(
          'Al crear tu cuenta se te pedirá aceptar los Términos y '
          'Condiciones y la Política de Privacidad.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        TextButton(
          onPressed: _cargando ? null : _verTerminos,
          child: const Text('Leer Términos y Política de Privacidad'),
        ),
      ],
      ..._errorWidgets(),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: _cargando ? null : _enviar,
        child: _cargando
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              )
            : Text(
                _esRegistro ? 'Crear cuenta' : 'Iniciar sesión',
              ),
      ),
      if (!_esRegistro) ...[
        const SizedBox(height: 8),
        TextButton(
          onPressed: _cargando ? null : _recuperarContrasena,
          child: const Text(
            '¿Olvidaste tu contraseña?',
          ),
        ),
      ],
      const SizedBox(height: 12),
      TextButton(
        onPressed: _cargando
            ? null
            : () => setState(() {
                  _esRegistro = !_esRegistro;
                  _error = null;
                }),
        child: Text(
          _esRegistro
              ? '¿Ya tienes cuenta? Inicia sesión'
              : '¿No tienes cuenta? Regístrate',
        ),
      ),
    ];
  }

  List<Widget> _contenidoRecuperacion() {
    final tema = Theme.of(context);

    return [
      Text(
        _codigoVerificado
            ? 'Código verificado. Elige tu nueva contraseña.'
            : 'Enviamos un código a ${_emailCtrl.text.trim()}. Escríbelo '
                'aquí y elige tu nueva contraseña. Si no lo ves, revisa la '
                'carpeta de spam.',
        textAlign: TextAlign.center,
        style: tema.textTheme.bodySmall,
      ),
      const SizedBox(height: 20),
      if (!_codigoVerificado) ...[
        TextFormField(
          controller: _codigoCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          decoration: const InputDecoration(
            labelText: 'Código de verificación',
            prefixIcon: Icon(Icons.pin_outlined),
          ),
          validator: (value) {
            if (value == null || value.trim().length < 6) {
              return 'Ingresa el código que recibiste por correo';
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
      ],
      TextFormField(
        controller: _nuevaCtrl,
        obscureText: !_verNueva,
        decoration: InputDecoration(
          labelText: 'Nueva contraseña',
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            icon: Icon(
              _verNueva ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            ),
            tooltip: _verNueva ? 'Ocultar' : 'Mostrar',
            onPressed: () => setState(() => _verNueva = !_verNueva),
          ),
        ),
        validator: (value) {
          if (value == null || value.length < 6) {
            return 'Mínimo 6 caracteres';
          }
          return null;
        },
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _confirmarCtrl,
        obscureText: !_verNueva,
        decoration: const InputDecoration(
          labelText: 'Confirmar contraseña',
          prefixIcon: Icon(Icons.lock_outline),
        ),
        validator: (value) {
          if (value != _nuevaCtrl.text) {
            return 'Las contraseñas no coinciden';
          }
          return null;
        },
      ),
      ..._errorWidgets(),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: _cargando ? null : _cambiarContrasena,
        child: _cargando
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Cambiar contraseña'),
      ),
      if (!_codigoVerificado) ...[
        const SizedBox(height: 8),
        TextButton(
          onPressed: (_cargando || _segundosReenvio > 0) ? null : _reenviarCodigo,
          child: Text(
            _segundosReenvio > 0
                ? 'Reenviar código (${_segundosReenvio}s)'
                : 'Reenviar código',
          ),
        ),
      ],
      const SizedBox(height: 4),
      TextButton(
        onPressed: _cargando ? null : _cancelarRecuperacion,
        child: const Text('Volver a iniciar sesión'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final String subtitulo;
    if (_modoCodigo) {
      subtitulo = 'Recupera tu contraseña';
    } else if (_esRegistro) {
      subtitulo = 'Crea tu cuenta para empezar';
    } else {
      subtitulo = 'Inicia sesión para continuar';
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo del negocio, si ya se configuró uno en "Mi
                    // negocio" (cacheado localmente en este teléfono);
                    // si no, se muestra la hoja por defecto.
                    BusinessLogo(
                      logoUrl: BrandCache.instance.logoUrl,
                      size: 64,
                      iconoPorDefecto: Icons.eco,
                      colorIcono: AppColors.darkGreen,
                    ),

                    const SizedBox(height: 12),

                    Text(
                      'Green Garden',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),

                    const SizedBox(height: 4),

                    Text(
                      subtitulo,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),

                    const SizedBox(height: 32),

                    if (_modoCodigo)
                      ..._contenidoRecuperacion()
                    else
                      ..._contenidoAcceso(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}