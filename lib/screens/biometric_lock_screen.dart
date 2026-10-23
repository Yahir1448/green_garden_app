import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/biometric_service.dart';
import '../services/brand_cache.dart';
import '../theme/app_theme.dart';
import '../widgets/business_logo.dart';

/// Se coloca en `MaterialApp.builder` para que el bloqueo quede por
/// ENCIMA de todas las pantallas, incluidas las que se abrieron sobre
/// el dashboard (inventario, clientes, etc.). Así no hay forma de ver
/// ni tocar la app mientras está bloqueada, y las pantallas de abajo
/// conservan su estado (formularios a medias, scroll, etc.).
class BiometricLockOverlay extends StatelessWidget {
  final Widget child;

  const BiometricLockOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: BiometricService.instance.bloqueada,
      builder: (context, bloqueada, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            // Mientras está bloqueada, los lectores de pantalla tampoco
            // deben poder leer lo que hay debajo.
            ExcludeSemantics(excluding: bloqueada, child: child),
            if (bloqueada) const Positioned.fill(child: BiometricLockScreen()),
          ],
        );
      },
    );
  }
}

/// Pantalla de bloqueo: pide huella/rostro automáticamente al aparecer
/// y ofrece reintentar o cerrar sesión.
class BiometricLockScreen extends StatefulWidget {
  const BiometricLockScreen({super.key});

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen> {
  bool _verificando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Lanza el diálogo del sistema en cuanto se dibuja la pantalla.
    WidgetsBinding.instance.addPostFrameCallback((_) => _desbloquear());
  }

  Future<void> _desbloquear() async {
    if (_verificando) return;
    setState(() {
      _verificando = true;
      _error = null;
    });

    final bio = BiometricService.instance;
    final ok = await bio.autenticar('Desbloquea Green Garden');

    if (ok) {
      // Al desbloquear, esta pantalla se retira sola: no tocar más estado.
      bio.desbloquear();
      return;
    }

    if (!mounted) return;
    setState(() {
      _verificando = false;
      _error = bio.ultimoError ??
          'No se pudo verificar tu identidad. Toca "Desbloquear" para '
              'intentar de nuevo.';
    });
  }

  Future<void> _cerrarSesion() async {
    // El listener de sesión en AuthGate quita el bloqueo y muestra el
    // login.
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                    style: tema.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Desbloquea la app para continuar',
                    textAlign: TextAlign.center,
                    style: tema.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 32),
                  Icon(
                    Icons.fingerprint,
                    size: 72,
                    color: tema.colorScheme.primary,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _verificando ? null : _desbloquear,
                    icon: const Icon(Icons.lock_open),
                    label: const Text('Desbloquear'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _verificando ? null : _cerrarSesion,
                    child: const Text('Cerrar sesión e ingresar con contraseña'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}