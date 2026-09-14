import 'package:flutter/material.dart';

import '../models/customer.dart';
import '../services/customer_service.dart';
import '../theme/app_theme.dart';
import '../widgets/theme_toggle_button.dart';

/// Pantalla que muestra y administra la lista de clientes: nombre,
/// lugar, fecha y precio acordado.
class CustomerScreen extends StatefulWidget {
  final CustomerService service;

  const CustomerScreen({super.key, required this.service});

  @override
  State<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends State<CustomerScreen> {
  Future<void> _abrirFormulario({Customer? cliente}) async {
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
        child: _CustomerFormSheet(
          service: widget.service,
          cliente: cliente,
        ),
      ),
    );
  }

  void _confirmarEliminar(Customer cliente) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar cliente'),
        content: Text('¿Deseas eliminar a "${cliente.nombre}" de la lista?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              widget.service.eliminarCliente(cliente.id);
              Navigator.pop(context);
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  String _formatearFecha(DateTime fecha) {
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    return '$dia/$mes/${fecha.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes'),
        actions: const [ThemeToggleButton()],
      ),
      body: ListenableBuilder(
        listenable: widget.service,
        builder: (context, _) {
          final clientes = widget.service.customers;

          if (clientes.isEmpty) {
            return Center(
              child: Text(
                'Aún no hay clientes registrados.\nToca "Nuevo cliente" para agregar uno.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: clientes.length,
            itemBuilder: (context, index) {
              final cliente = clientes[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  onTap: () => _abrirFormulario(cliente: cliente),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.limeGreen.withValues(alpha: 0.25),
                    child: const Icon(Icons.person, color: AppColors.darkGreen),
                  ),
                  title: Text(cliente.nombre),
                  subtitle: Text(
                    '${cliente.lugar}\n${_formatearFecha(cliente.fecha)}',
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '\$${cliente.precio.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      // El ListTile limita la altura de "trailing" a un
                      // máximo fijo (56px). Apilar el precio y el botón
                      // verticalmente (Column) seguía sin caber en ese
                      // espacio. Ponerlos en fila (Row) evita el
                      // problema por completo, ya que ambos comparten
                      // el mismo alto en vez de sumarse.
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _confirmarEliminar(cliente),
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
        icon: const Icon(Icons.person_add),
        label: const Text('Nuevo cliente'),
      ),
    );
  }
}

/// Formulario para crear o editar un cliente.
class _CustomerFormSheet extends StatefulWidget {
  final CustomerService service;
  final Customer? cliente;

  const _CustomerFormSheet({required this.service, this.cliente});

  @override
  State<_CustomerFormSheet> createState() => _CustomerFormSheetState();
}

class _CustomerFormSheetState extends State<_CustomerFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _lugarCtrl;
  late final TextEditingController _precioCtrl;
  late DateTime _fecha;

  bool get _esEdicion => widget.cliente != null;

  @override
  void initState() {
    super.initState();
    final cliente = widget.cliente;
    _nombreCtrl = TextEditingController(text: cliente?.nombre ?? '');
    _lugarCtrl = TextEditingController(text: cliente?.lugar ?? '');
    _precioCtrl = TextEditingController(
      text: cliente != null ? cliente.precio.toString() : '',
    );
    _fecha = cliente?.fecha ?? DateTime.now();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _lugarCtrl.dispose();
    _precioCtrl.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha() async {
    final seleccionada = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (seleccionada != null) {
      setState(() => _fecha = seleccionada);
    }
  }

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;

    final nombre = _nombreCtrl.text.trim();
    final lugar = _lugarCtrl.text.trim();
    final precio = double.parse(_precioCtrl.text.trim());

    if (_esEdicion) {
      final actualizado = widget.cliente!.copyWith(
        nombre: nombre,
        lugar: lugar,
        fecha: _fecha,
        precio: precio,
      );
      widget.service.actualizarCliente(widget.cliente!.id, actualizado);
    } else {
      final nuevo = Customer(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        nombre: nombre,
        lugar: lugar,
        fecha: _fecha,
        precio: precio,
      );
      widget.service.agregarCliente(nuevo);
    }

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final dia = _fecha.day.toString().padLeft(2, '0');
    final mes = _fecha.month.toString().padLeft(2, '0');
    final fechaTexto = '$dia/$mes/${_fecha.year}';

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
                _esEdicion ? 'Editar cliente' : 'Nuevo cliente',
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
                controller: _lugarCtrl,
                decoration: const InputDecoration(labelText: 'Lugar'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty)
                        ? 'Ingresa un lugar'
                        : null,
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _elegirFecha,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Fecha',
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(fechaTexto),
                ),
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
                onPressed: _guardar,
                child: Text(_esEdicion ? 'Guardar cambios' : 'Agregar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}