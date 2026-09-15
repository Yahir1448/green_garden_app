import 'package:flutter/material.dart';

import '../services/business_profile_service.dart';
import '../widgets/theme_toggle_button.dart';

/// Pantalla para editar los datos del negocio (nombre comercial,
/// operador, teléfono, correo) que aparecen en el encabezado de cada
/// factura generada.
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

  @override
  void initState() {
    super.initState();
    final perfil = widget.service.perfil;
    _nombreCtrl = TextEditingController(text: perfil.nombreComercial);
    _operadorCtrl = TextEditingController(text: perfil.operador);
    _telefonoCtrl = TextEditingController(text: perfil.telefono);
    _correoCtrl = TextEditingController(text: perfil.correo);
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _operadorCtrl.dispose();
    _telefonoCtrl.dispose();
    _correoCtrl.dispose();
    super.dispose();
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