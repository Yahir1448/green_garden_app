import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/biometric_service.dart';
import '../services/business_profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/business_logo.dart';
import '../widgets/theme_toggle_button.dart';

/// Una opción de color de marca dentro de la paleta que se ofrece en
/// esta pantalla.
class _OpcionColor {
  final String etiqueta;
  final Color color;

  /// Hex a guardar. Null = usar el verde por defecto de Green Garden
  /// (es decir, "restablecer" el color de marca).
  final String? hex;

  const _OpcionColor({required this.etiqueta, required this.color, this.hex});
}

const List<_OpcionColor> _paletaColores = [
  _OpcionColor(
    etiqueta: 'Green Garden (por defecto)',
    color: AppColors.darkGreen,
    hex: null,
  ),
  _OpcionColor(etiqueta: 'Verde bosque', color: Color(0xFF2E7D32), hex: '#2E7D32'),
  _OpcionColor(etiqueta: 'Verde azulado', color: Color(0xFF00695C), hex: '#00695C'),
  _OpcionColor(etiqueta: 'Azul', color: Color(0xFF0D47A1), hex: '#0D47A1'),
  _OpcionColor(etiqueta: 'Morado', color: Color(0xFF4527A0), hex: '#4527A0'),
  _OpcionColor(etiqueta: 'Rosa', color: Color(0xFFAD1457), hex: '#AD1457'),
  _OpcionColor(etiqueta: 'Rojo', color: Color(0xFFB71C1C), hex: '#B71C1C'),
  _OpcionColor(etiqueta: 'Naranja', color: Color(0xFFE65100), hex: '#E65100'),
  _OpcionColor(etiqueta: 'Mostaza', color: Color(0xFFF9A825), hex: '#F9A825'),
  _OpcionColor(etiqueta: 'Tierra', color: Color(0xFF3E2723), hex: '#3E2723'),
  _OpcionColor(etiqueta: 'Gris azulado', color: Color(0xFF455A64), hex: '#455A64'),
  _OpcionColor(etiqueta: 'Negro', color: Color(0xFF212121), hex: '#212121'),
];

/// Pantalla para editar los datos del negocio (nombre comercial,
/// operador, teléfono, correo), y también su marca visual: el logo
/// que reemplaza la hoja por defecto en el login y el navbar, y el
/// color con el que se pinta toda la app.
class BusinessProfileScreen extends StatefulWidget {
  final BusinessProfileService service;

  const BusinessProfileScreen({super.key, required this.service});

  @override
  State<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends State<BusinessProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _operadorCtrl;
  late final TextEditingController _telefonoCtrl;
  late final TextEditingController _correoCtrl;
  bool _guardando = false;
  bool _subiendoLogo = false;

  /// Color de marca elegido en esta pantalla (en hex). Se guarda junto
  /// con el resto del formulario, al presionar "Guardar". Null =
  /// verde por defecto de Green Garden.
  String? _colorSeleccionado;

  @override
  void initState() {
    super.initState();
    final perfil = widget.service.perfil;
    _nombreCtrl = TextEditingController(text: perfil.nombreComercial);
    _operadorCtrl = TextEditingController(text: perfil.operador);
    _telefonoCtrl = TextEditingController(text: perfil.telefono);
    _correoCtrl = TextEditingController(text: perfil.correo);
    _colorSeleccionado = perfil.colorPrimario;
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _operadorCtrl.dispose();
    _telefonoCtrl.dispose();
    _correoCtrl.dispose();
    super.dispose();
  }

  /// Abre la galería para elegir un logo nuevo, lo sube a Supabase
  /// Storage y guarda el perfil de inmediato con la nueva URL (a
  /// diferencia del color, que se guarda junto con el resto del
  /// formulario, subir un logo ya es una acción explícita y completa
  /// por sí sola).
  Future<void> _cambiarLogo() async {
    final XFile? imagen = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (imagen == null) return;

    setState(() => _subiendoLogo = true);
    try {
      final url = await widget.service.subirLogo(imagen);
      await widget.service.guardar(
        nombreComercial: _nombreCtrl.text.trim(),
        operador: _operadorCtrl.text.trim(),
        telefono: _telefonoCtrl.text.trim(),
        correo: _correoCtrl.text.trim(),
        logoUrl: url,
        colorPrimario: _colorSeleccionado,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logo actualizado')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo subir el logo. Intenta de nuevo.')),
        );
      }
    } finally {
      if (mounted) setState(() => _subiendoLogo = false);
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);
    try {
      await widget.service.guardar(
        nombreComercial: _nombreCtrl.text.trim(),
        operador: _operadorCtrl.text.trim(),
        telefono: _telefonoCtrl.text.trim(),
        correo: _correoCtrl.text.trim(),
        logoUrl: widget.service.perfil.logoUrl,
        colorPrimario: _colorSeleccionado,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Datos del negocio guardados')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo guardar. Revisa tu conexión.')),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Widget _seccionLogo() {
    return ListenableBuilder(
      listenable: widget.service,
      builder: (context, _) {
        return Column(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundColor:
                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  child: BusinessLogo(
                    logoUrl: widget.service.perfil.logoUrl,
                    size: 72,
                    iconoPorDefecto: Icons.eco,
                  ),
                ),
                if (_subiendoLogo)
                  const CircularProgressIndicator(strokeWidth: 2),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _subiendoLogo ? null : _cambiarLogo,
              icon: const Icon(Icons.image_outlined),
              label: Text(
                widget.service.perfil.logoUrl == null
                    ? 'Subir logo'
                    : 'Cambiar logo',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _seccionColor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Color de marca',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Se usa en toda la app. El color se ajusta automáticamente '
          'para verse bien tanto en modo claro como oscuro.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _paletaColores.map((opcion) {
            final seleccionado = _colorSeleccionado == opcion.hex;
            return Tooltip(
              message: opcion.etiqueta,
              child: GestureDetector(
                onTap: () => setState(() => _colorSeleccionado = opcion.hex),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: opcion.color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: seleccionado
                          ? Theme.of(context).colorScheme.onSurface
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: seleccionado
                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi negocio'),
        actions: const [ThemeToggleButton()],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _seccionLogo(),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              _seccionColor(),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              Text(
                'Seguridad',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              const _BiometricSwitchTile(),
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 16),
              Text(
                'Estos datos aparecen en el encabezado de cada factura que generes.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre comercial'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _operadorCtrl,
                decoration: const InputDecoration(labelText: 'Operador responsable'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _telefonoCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Teléfono'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _correoCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Correo'),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Interruptor "Acceso con huella o rostro". Para activarlo se pide
/// primero la huella/rostro, así se confirma que el teléfono realmente
/// lo tiene configurado y que quien lo activa es el dueño. Cambia al
/// momento: no depende del botón "Guardar" del formulario.
///
/// El interruptor siempre se puede tocar: si el teléfono no puede
/// verificar la identidad, se muestra el motivo en vez de quedarse
/// inactivo sin explicación.
class _BiometricSwitchTile extends StatefulWidget {
  const _BiometricSwitchTile();

  @override
  State<_BiometricSwitchTile> createState() => _BiometricSwitchTileState();
}

class _BiometricSwitchTileState extends State<_BiometricSwitchTile> {
  final BiometricService _bio = BiometricService.instance;

  bool? _disponible; // null = todavía comprobando
  late bool _activada = _bio.activada;
  bool _trabajando = false;

  @override
  void initState() {
    super.initState();
    _comprobar();
  }

  Future<void> _comprobar() async {
    final disponible = await _bio.disponible();
    if (mounted) setState(() => _disponible = disponible);
  }

  void _avisar(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), duration: const Duration(seconds: 6)),
    );
  }

  Future<void> _cambiar(bool activar) async {
    setState(() => _trabajando = true);

    if (activar) {
      if (!await _bio.disponible()) {
        _avisar(_bio.ultimoError ??
            'Este teléfono no puede verificar tu identidad.');
      } else {
        final ok = await _bio.autenticar(
          'Confirma tu identidad para activar el acceso biométrico',
        );
        if (ok) {
          await _bio.activar();
        } else if (_bio.ultimoError != null) {
          _avisar(_bio.ultimoError!);
        }
      }
    } else {
      await _bio.desactivar();
    }

    if (mounted) {
      setState(() {
        _activada = _bio.activada;
        _trabajando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: const Icon(Icons.fingerprint),
      title: const Text('Acceso con huella o rostro'),
      subtitle: Text(
        _disponible == false
            ? 'No disponible. Toca el interruptor para ver el motivo.'
            : 'Pide tu huella o rostro al abrir la app.',
      ),
      value: _activada,
      onChanged: _trabajando ? null : _cambiar,
    );
  }
}