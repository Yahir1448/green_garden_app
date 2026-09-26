import 'package:flutter/material.dart';

import '../models/inventory_item.dart';
import '../models/service_item.dart';
import '../services/inventory_service.dart';
import '../services/service_catalog_service.dart';
import '../theme/app_theme.dart';

/// Pantalla para configurar, por cada servicio del catálogo, qué
/// insumos del inventario consume y en qué cantidad. Esa "receta" es
/// la que se usa para descontar automáticamente el inventario cuando
/// se marca un trabajo con ese servicio como realizado.
class RecetasScreen extends StatelessWidget {
  final ServiceCatalogService serviceCatalog;
  final InventoryService inventoryService;

  const RecetasScreen({
    super.key,
    required this.serviceCatalog,
    required this.inventoryService,
  });

  Future<void> _editarReceta(BuildContext context, ServiceItem servicio) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _RecetaFormSheet(
          serviceCatalog: serviceCatalog,
          inventoryService: inventoryService,
          servicio: servicio,
        ),
      ),
    );
  }

  String _resumenReceta(ServiceItem servicio) {
    if (servicio.receta.isEmpty) return 'Sin insumos configurados';
    return servicio.receta.map((r) {
      final cantidadTexto = r.cantidad == r.cantidad.truncateToDouble()
          ? r.cantidad.toStringAsFixed(0)
          : r.cantidad.toStringAsFixed(2);
      return '$cantidadTexto ${r.inventarioNombre}';
    }).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Insumos por servicio')),
      body: ListenableBuilder(
        listenable: serviceCatalog,
        builder: (context, _) {
          final servicios = serviceCatalog.servicios;
          if (servicios.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Todavía no tienes servicios en tu catálogo. Agrega uno '
                  'primero en "Servicios" antes de configurar sus insumos.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
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
                  onTap: () => _editarReceta(context, servicio),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.limeGreenSoft.withValues(alpha: 0.3),
                    child: const Icon(Icons.grass),
                  ),
                  title: Text(servicio.nombre),
                  subtitle: Text(_resumenReceta(servicio)),
                  trailing: const Icon(Icons.chevron_right),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Una fila del formulario: un insumo del inventario y la cantidad que
/// consume el servicio cada vez que se realiza.
class _FilaInsumo {
  String? inventarioId;
  final TextEditingController cantidadCtrl;

  _FilaInsumo({this.inventarioId, String cantidadInicial = ''})
      : cantidadCtrl = TextEditingController(text: cantidadInicial);

  void dispose() => cantidadCtrl.dispose();
}

class _RecetaFormSheet extends StatefulWidget {
  final ServiceCatalogService serviceCatalog;
  final InventoryService inventoryService;
  final ServiceItem servicio;

  const _RecetaFormSheet({
    required this.serviceCatalog,
    required this.inventoryService,
    required this.servicio,
  });

  @override
  State<_RecetaFormSheet> createState() => _RecetaFormSheetState();
}

class _RecetaFormSheetState extends State<_RecetaFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final List<_FilaInsumo> _filas = [];
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    for (final r in widget.servicio.receta) {
      _filas.add(_FilaInsumo(inventarioId: r.inventarioId, cantidadInicial: r.cantidad.toString()));
    }
  }

  @override
  void dispose() {
    for (final fila in _filas) {
      fila.dispose();
    }
    super.dispose();
  }

  void _agregarFila() => setState(() => _filas.add(_FilaInsumo()));

  void _eliminarFila(int index) {
    setState(() {
      final fila = _filas.removeAt(index);
      fila.dispose();
    });
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    final receta = <RecetaInsumo>[];
    for (final fila in _filas) {
      InventoryItem? item;
      for (final i in widget.inventoryService.items) {
        if (i.id == fila.inventarioId) {
          item = i;
          break;
        }
      }
      if (item == null) continue;
      receta.add(RecetaInsumo(
        inventarioId: item.id,
        inventarioNombre: item.nombre,
        cantidad: double.tryParse(fila.cantidadCtrl.text.trim()) ?? 0,
      ));
    }

    setState(() => _guardando = true);
    try {
      await widget.serviceCatalog.actualizarServicio(
        widget.servicio.id,
        nombre: widget.servicio.nombre,
        descripcion: widget.servicio.descripcion,
        precio: widget.servicio.precio,
        receta: receta,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo guardar. Intenta de nuevo.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hayInsumos = widget.inventoryService.items.isNotEmpty;
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
              Text('Insumos de "${widget.servicio.nombre}"', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Cada vez que marques un trabajo con este servicio como '
                'realizado, se descontará automáticamente esta cantidad de '
                'cada insumo del inventario.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              if (_filas.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Este servicio no descuenta ningún insumo todavía.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ..._filas.asMap().entries.map((entry) {
                final index = entry.key;
                final fila = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: ListenableBuilder(
                          listenable: widget.inventoryService,
                          builder: (context, _) {
                            final items = widget.inventoryService.items;
                            return DropdownButtonFormField<String?>(
                              initialValue: fila.inventarioId,
                              decoration: const InputDecoration(labelText: 'Insumo'),
                              items: items
                                  .map(
                                    (i) => DropdownMenuItem<String?>(
                                      value: i.id,
                                      child: Text('${i.nombre} (${i.unidad})'),
                                    ),
                                  )
                                  .toList(),
                              validator: (value) => value == null ? 'Elige un insumo' : null,
                              onChanged: (id) => setState(() => fila.inventarioId = id),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: fila.cantidadCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Cantidad'),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return 'Requerido';
                            if (double.tryParse(value.trim()) == null) return 'Inválido';
                            return null;
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        tooltip: 'Quitar',
                        onPressed: () => _eliminarFila(index),
                      ),
                    ],
                  ),
                );
              }),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: hayInsumos ? _agregarFila : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar insumo'),
                ),
              ),
              if (!hayInsumos)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Agrega artículos en "Inventario" antes de poder configurar insumos aquí.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.orange),
                  ),
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
                    : const Text('Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}