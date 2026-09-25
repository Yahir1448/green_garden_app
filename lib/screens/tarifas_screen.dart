import 'package:flutter/material.dart';

import '../models/service_item.dart';
import '../models/tarifa_servicio.dart';
import '../services/service_catalog_service.dart';
import '../services/tarifa_service.dart';
import '../theme/app_theme.dart';

/// Pantalla donde el usuario configura, una sola vez (o cada vez que
/// cambien sus precios), las tarifas que el Cotizador usa para
/// calcular presupuestos: precio base para un rango de tamaño (m²) y
/// radio de distancia (km), más el costo extra por cada m²/km que se
/// pase de esos límites.
class TarifasScreen extends StatelessWidget {
  final TarifaService service;
  final ServiceCatalogService serviceCatalog;

  const TarifasScreen({
    super.key,
    required this.service,
    required this.serviceCatalog,
  });

  Future<void> _abrirFormulario(BuildContext context, {TarifaServicio? tarifa}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _TarifaFormSheet(
          service: service,
          serviceCatalog: serviceCatalog,
          tarifa: tarifa,
        ),
      ),
    );
  }

  void _confirmarEliminar(BuildContext context, TarifaServicio tarifa) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar tarifa'),
        content: Text('¿Deseas eliminar la tarifa de "${tarifa.servicioNombre}"?'),
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
                await service.eliminarTarifa(tarifa.id);
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
      appBar: AppBar(title: const Text('Tarifas del cotizador')),
      body: ListenableBuilder(
        listenable: service,
        builder: (context, _) {
          final tarifas = service.tarifas;
          if (tarifas.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Todavía no configuras ninguna tarifa. Agrega una para '
                  'poder calcular presupuestos en el Cotizador.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: tarifas.length,
            itemBuilder: (context, index) {
              final tarifa = tarifas[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  onTap: () => _abrirFormulario(context, tarifa: tarifa),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.limeGreenSoft.withValues(alpha: 0.3),
                    child: const Icon(Icons.request_quote_outlined),
                  ),
                  title: Text(tarifa.servicioNombre),
                  subtitle: Text(
                    '${tarifa.m2Min.toStringAsFixed(0)}–${tarifa.m2Max.toStringAsFixed(0)} m² '
                    'dentro de ${tarifa.kmBase.toStringAsFixed(0)} km: '
                    '\$${tarifa.precioBase.toStringAsFixed(2)}\n'
                    '+\$${tarifa.precioPorM2Extra.toStringAsFixed(2)}/m² extra '
                    '· +\$${tarifa.precioPorKmExtra.toStringAsFixed(2)}/km extra',
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Eliminar',
                    onPressed: () => _confirmarEliminar(context, tarifa),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(context),
        icon: const Icon(Icons.add),
        label: const Text('Nueva tarifa'),
      ),
    );
  }
}

/// Formulario para crear o editar una tarifa.
class _TarifaFormSheet extends StatefulWidget {
  final TarifaService service;
  final ServiceCatalogService serviceCatalog;
  final TarifaServicio? tarifa;

  const _TarifaFormSheet({
    required this.service,
    required this.serviceCatalog,
    this.tarifa,
  });

  @override
  State<_TarifaFormSheet> createState() => _TarifaFormSheetState();
}

class _TarifaFormSheetState extends State<_TarifaFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _m2MinCtrl;
  late final TextEditingController _m2MaxCtrl;
  late final TextEditingController _precioBaseCtrl;
  late final TextEditingController _precioM2ExtraCtrl;
  late final TextEditingController _kmBaseCtrl;
  late final TextEditingController _precioKmExtraCtrl;
  String? _servicioIdSeleccionado;

  bool get _esEdicion => widget.tarifa != null;

  @override
  void initState() {
    super.initState();
    final tarifa = widget.tarifa;
    _servicioIdSeleccionado = tarifa?.servicioId;
    _nombreCtrl = TextEditingController(text: tarifa?.servicioNombre ?? '');
    _m2MinCtrl = TextEditingController(text: tarifa != null ? tarifa.m2Min.toString() : '');
    _m2MaxCtrl = TextEditingController(text: tarifa != null ? tarifa.m2Max.toString() : '');
    _precioBaseCtrl =
        TextEditingController(text: tarifa != null ? tarifa.precioBase.toString() : '');
    _precioM2ExtraCtrl =
        TextEditingController(text: tarifa != null ? tarifa.precioPorM2Extra.toString() : '');
    _kmBaseCtrl = TextEditingController(text: tarifa != null ? tarifa.kmBase.toString() : '');
    _precioKmExtraCtrl =
        TextEditingController(text: tarifa != null ? tarifa.precioPorKmExtra.toString() : '');
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _m2MinCtrl.dispose();
    _m2MaxCtrl.dispose();
    _precioBaseCtrl.dispose();
    _precioM2ExtraCtrl.dispose();
    _kmBaseCtrl.dispose();
    _precioKmExtraCtrl.dispose();
    super.dispose();
  }

  void _seleccionarServicio(ServiceItem? servicio) {
    setState(() {
      _servicioIdSeleccionado = servicio?.id;
      if (servicio != null) {
        _nombreCtrl.text = servicio.nombre;
      }
    });
  }

  String? _requerido(String? value) =>
      (value == null || value.trim().isEmpty) ? 'Requerido' : null;

  String? _numeroValido(String? value) {
    if (value == null || value.trim().isEmpty) return 'Requerido';
    if (double.tryParse(value.trim()) == null) return 'Número inválido';
    return null;
  }

  bool _guardando = false;

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    final nombre = _nombreCtrl.text.trim();
    final m2Min = double.parse(_m2MinCtrl.text.trim());
    final m2Max = double.parse(_m2MaxCtrl.text.trim());
    final precioBase = double.parse(_precioBaseCtrl.text.trim());
    final precioM2Extra = double.parse(_precioM2ExtraCtrl.text.trim());
    final kmBase = double.parse(_kmBaseCtrl.text.trim());
    final precioKmExtra = double.parse(_precioKmExtraCtrl.text.trim());

    setState(() => _guardando = true);
    try {
      if (_esEdicion) {
        await widget.service.actualizarTarifa(
          widget.tarifa!.id,
          servicioId: _servicioIdSeleccionado,
          servicioNombre: nombre,
          m2Min: m2Min,
          m2Max: m2Max,
          precioBase: precioBase,
          precioPorM2Extra: precioM2Extra,
          kmBase: kmBase,
          precioPorKmExtra: precioKmExtra,
        );
      } else {
        await widget.service.agregarTarifa(
          servicioId: _servicioIdSeleccionado,
          servicioNombre: nombre,
          m2Min: m2Min,
          m2Max: m2Max,
          precioBase: precioBase,
          precioPorM2Extra: precioM2Extra,
          kmBase: kmBase,
          precioPorKmExtra: precioKmExtra,
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
                _esEdicion ? 'Editar tarifa' : 'Nueva tarifa',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              ListenableBuilder(
                listenable: widget.serviceCatalog,
                builder: (context, _) {
                  final servicios = widget.serviceCatalog.servicios;
                  return DropdownButtonFormField<String?>(
                    initialValue: _servicioIdSeleccionado,
                    decoration: const InputDecoration(
                      labelText: 'Vincular a un servicio del catálogo (opcional)',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('General / personalizado'),
                      ),
                      ...servicios.map(
                        (s) => DropdownMenuItem<String?>(value: s.id, child: Text(s.nombre)),
                      ),
                    ],
                    onChanged: (id) =>
                        _seleccionarServicio(widget.serviceCatalog.buscarPorId(id)),
                  );
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre de la tarifa'),
                validator: _requerido,
              ),
              const SizedBox(height: 16),
              Text('Rango de tamaño base', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _m2MinCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'm² mínimo'),
                      validator: _numeroValido,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _m2MaxCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'm² máximo'),
                      validator: _numeroValido,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _precioBaseCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Precio base (dentro del rango y del radio)',
                  prefixText: '\$ ',
                ),
                validator: _numeroValido,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _precioM2ExtraCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Extra por cada m² que se pase del máximo',
                  prefixText: '\$ ',
                ),
                validator: _numeroValido,
              ),
              const SizedBox(height: 16),
              Text('Radio de distancia base', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              TextFormField(
                controller: _kmBaseCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Radio incluido en el precio base (km)',
                ),
                validator: _numeroValido,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _precioKmExtraCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Extra por cada km que se pase del radio',
                  prefixText: '\$ ',
                ),
                validator: _numeroValido,
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
                    : Text(_esEdicion ? 'Guardar cambios' : 'Agregar tarifa'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}