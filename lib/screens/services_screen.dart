import 'package:flutter/material.dart';

import '../models/service_item.dart';
import '../services/service_catalog_service.dart';
import '../theme/app_theme.dart';
import '../widgets/theme_toggle_button.dart';

/// Pantalla del catálogo de servicios ofrecidos. Permite crear,
/// eliminar y editar cada servicio (nombre, descripción y precio).
class ServicesScreen extends StatefulWidget {
  final ServiceCatalogService service;

  const ServicesScreen({super.key, required this.service});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  Future<void> _abrirFormulario({ServiceItem? servicio}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _ServiceFormSheet(
          service: widget.service,
          servicio: servicio,
        ),
      ),
    );
  }

  void _confirmarEliminar(ServiceItem servicio) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar servicio'),
        content: Text(
          '¿Deseas eliminar "${servicio.nombre}" del catálogo? '
          'Los clientes que ya lo tengan enlazado conservarán el nombre '
          'y precio con el que se agendaron.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              final navigator = Navigator.of(context);
              final mensajero = ScaffoldMessenger.of(context);
              try {
                await widget.service.eliminarServicio(servicio.id);
                navigator.pop();
              } catch (e) {
                mensajero.showSnackBar(
                  const SnackBar(content: Text('No se pudo eliminar. Intenta de nuevo.')),
                );
              }
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Servicios'),
        actions: const [ThemeToggleButton()],
      ),
      body: ListenableBuilder(
        listenable: widget.service,
        builder: (context, _) {
          final servicios = widget.service.servicios;

          if (servicios.isEmpty) {
            return Center(
              child: Text(
                'Aún no hay servicios en el catálogo.\nToca "Nuevo servicio" para agregar uno.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: servicios.length,
            itemBuilder: (context, index) {
              final servicio = servicios[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  onTap: () => _abrirFormulario(servicio: servicio),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.limeGreen.withValues(alpha: 0.25),
                    child: const Icon(Icons.handyman, color: AppColors.darkGreen),
                  ),
                  title: Text(servicio.nombre),
                  subtitle: servicio.descripcion.isNotEmpty
                      ? Text(servicio.descripcion)
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '\$${servicio.precio.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _confirmarEliminar(servicio),
                        tooltip: 'Eliminar',
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo servicio'),
      ),
    );
  }
}

/// Formulario para crear o editar un servicio (incluye editar el precio).
class _ServiceFormSheet extends StatefulWidget {
  final ServiceCatalogService service;
  final ServiceItem? servicio;

  const _ServiceFormSheet({required this.service, this.servicio});

  @override
  State<_ServiceFormSheet> createState() => _ServiceFormSheetState();
}

class _ServiceFormSheetState extends State<_ServiceFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _descripcionCtrl;
  late final TextEditingController _precioCtrl;

  bool get _esEdicion => widget.servicio != null;

  @override
  void initState() {
    super.initState();
    final servicio = widget.servicio;
    _nombreCtrl = TextEditingController(text: servicio?.nombre ?? '');
    _descripcionCtrl = TextEditingController(text: servicio?.descripcion ?? '');
    _precioCtrl = TextEditingController(
      text: servicio != null ? servicio.precio.toString() : '',
    );
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _descripcionCtrl.dispose();
    _precioCtrl.dispose();
    super.dispose();
  }

  bool _guardando = false;

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    final nombre = _nombreCtrl.text.trim();
    final descripcion = _descripcionCtrl.text.trim();
    final precio = double.parse(_precioCtrl.text.trim());

    setState(() => _guardando = true);

    try {
      if (_esEdicion) {
        await widget.service.actualizarServicio(
          widget.servicio!.id,
          nombre: nombre,
          descripcion: descripcion,
          precio: precio,
        );
      } else {
        await widget.service.agregarServicio(
          nombre: nombre,
          descripcion: descripcion,
          precio: precio,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo guardar. Revisa tu conexión.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.limeGreenSoft,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Text(
                _esEdicion ? 'Editar servicio' : 'Nuevo servicio',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty)
                        ? 'Ingresa un nombre'
                        : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descripcionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Descripción (opcional)',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _precioCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Precio',
                  prefixText: '\$ ',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Requerido';
                  }
                  if (double.tryParse(value.trim()) == null) {
                    return 'Número inválido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_esEdicion ? 'Guardar cambios' : 'Agregar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}