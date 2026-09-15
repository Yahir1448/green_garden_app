import 'package:flutter/material.dart';

import '../models/inventory_item.dart';
import '../services/inventory_service.dart';
import '../theme/app_theme.dart';
import '../widgets/theme_toggle_button.dart';

/// Pantalla que muestra el inventario de herramientas e insumos.
/// Permite ver, agregar, editar, ajustar cantidades y eliminar artículos.
class InventoryScreen extends StatefulWidget {
  final InventoryService service;

  const InventoryScreen({super.key, required this.service});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _abrirFormulario({InventoryItem? item}) async {
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
        child: _ItemFormSheet(
          service: widget.service,
          item: item,
        ),
      ),
    );
  }

  void _confirmarEliminar(InventoryItem item) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar artículo'),
        content: Text('¿Deseas eliminar "${item.nombre}" del inventario?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              final navigator = Navigator.of(context);
              try {
                await widget.service.eliminarItem(item.id);
                navigator.pop();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No se pudo eliminar. Intenta de nuevo.')),
                  );
                }
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
        title: const Text('Inventario'),
        actions: const [ThemeToggleButton()],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.limeGreen,
          indicatorWeight: 3,
          // Antes solo se definía labelColor: al no fijar
          // unselectedLabelColor, Flutter usaba un gris por defecto
          // (pensado para fondos claros) que se perdía contra el verde
          // oscuro del AppBar en modo claro. Ahora ambos colores se
          // derivan del mismo foregroundColor del AppBar, así que
          // siempre contrastan bien en los dos temas.
          labelColor: Theme.of(context).appBarTheme.foregroundColor,
          unselectedLabelColor:
              Theme.of(context).appBarTheme.foregroundColor?.withValues(alpha: 0.65),
          tabs: const [
            Tab(text: 'Herramientas'),
            Tab(text: 'Insumos'),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: widget.service,
        builder: (context, _) {
          return TabBarView(
            controller: _tabController,
            children: [
              _ListaItems(
                items: widget.service.porCategoria(ItemCategoria.herramienta),
                onTap: (item) => _abrirFormulario(item: item),
                onDelete: _confirmarEliminar,
                onAjustar: widget.service.ajustarCantidad,
              ),
              _ListaItems(
                items: widget.service.porCategoria(ItemCategoria.insumo),
                onTap: (item) => _abrirFormulario(item: item),
                onDelete: _confirmarEliminar,
                onAjustar: widget.service.ajustarCantidad,
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo artículo'),
      ),
    );
  }
}

class _ListaItems extends StatelessWidget {
  final List<InventoryItem> items;
  final ValueChanged<InventoryItem> onTap;
  final ValueChanged<InventoryItem> onDelete;
  final Future<void> Function(String id, double delta) onAjustar;

  const _ListaItems({
    required this.items,
    required this.onTap,
    required this.onDelete,
    required this.onAjustar,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          'Aún no hay artículos en esta categoría.\nToca "Nuevo artículo" para agregar uno.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            onTap: () => onTap(item),
            leading: CircleAvatar(
              backgroundColor: item.bajoStock
                  ? Colors.redAccent.withValues(alpha: 0.15)
                  : AppColors.limeGreen.withValues(alpha: 0.25),
              child: Icon(
                item.categoria == ItemCategoria.herramienta
                    ? Icons.build
                    : Icons.eco,
                color: item.bajoStock ? Colors.redAccent : AppColors.darkGreen,
              ),
            ),
            title: Text(item.nombre),
            subtitle: Text(
              '${item.cantidad.toStringAsFixed(item.cantidad % 1 == 0 ? 0 : 1)} '
              '${item.unidad}'
              '${item.bajoStock ? '  •  Stock bajo' : ''}',
              style: TextStyle(
                color: item.bajoStock ? Colors.redAccent : null,
                fontWeight: item.bajoStock ? FontWeight.bold : null,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => onAjustar(item.id, -1),
                  tooltip: 'Restar 1',
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => onAjustar(item.id, 1),
                  tooltip: 'Sumar 1',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => onDelete(item),
                  tooltip: 'Eliminar',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Formulario para crear o editar un artículo del inventario.
class _ItemFormSheet extends StatefulWidget {
  final InventoryService service;
  final InventoryItem? item;

  const _ItemFormSheet({required this.service, this.item});

  @override
  State<_ItemFormSheet> createState() => _ItemFormSheetState();
}

class _ItemFormSheetState extends State<_ItemFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _cantidadCtrl;
  late final TextEditingController _unidadCtrl;
  late final TextEditingController _stockMinimoCtrl;
  late final TextEditingController _notasCtrl;
  late ItemCategoria _categoria;

  bool get _esEdicion => widget.item != null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _nombreCtrl = TextEditingController(text: item?.nombre ?? '');
    _cantidadCtrl = TextEditingController(
      text: item != null ? item.cantidad.toString() : '',
    );
    _unidadCtrl = TextEditingController(text: item?.unidad ?? 'unidades');
    _stockMinimoCtrl = TextEditingController(
      text: item != null ? item.stockMinimo.toString() : '0',
    );
    _notasCtrl = TextEditingController(text: item?.notas ?? '');
    _categoria = item?.categoria ?? ItemCategoria.herramienta;
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _cantidadCtrl.dispose();
    _unidadCtrl.dispose();
    _stockMinimoCtrl.dispose();
    _notasCtrl.dispose();
    super.dispose();
  }

  bool _guardando = false;

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    final nombre = _nombreCtrl.text.trim();
    final cantidad = double.parse(_cantidadCtrl.text.trim());
    final unidad = _unidadCtrl.text.trim();
    final stockMinimo = double.tryParse(_stockMinimoCtrl.text.trim()) ?? 0;
    final notas = _notasCtrl.text.trim();

    setState(() => _guardando = true);

    try {
      if (_esEdicion) {
        await widget.service.actualizarItem(
          widget.item!.id,
          nombre: nombre,
          categoria: _categoria,
          cantidad: cantidad,
          unidad: unidad,
          stockMinimo: stockMinimo,
          notas: notas,
        );
      } else {
        await widget.service.agregarItem(
          nombre: nombre,
          categoria: _categoria,
          cantidad: cantidad,
          unidad: unidad,
          stockMinimo: stockMinimo,
          notas: notas,
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
                _esEdicion ? 'Editar artículo' : 'Nuevo artículo',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              SegmentedButton<ItemCategoria>(
                segments: const [
                  ButtonSegment(
                    value: ItemCategoria.herramienta,
                    label: Text('Herramienta'),
                    icon: Icon(Icons.build),
                  ),
                  ButtonSegment(
                    value: ItemCategoria.insumo,
                    label: Text('Insumo'),
                    icon: Icon(Icons.eco),
                  ),
                ],
                selected: {_categoria},
                onSelectionChanged: (nuevaSeleccion) {
                  setState(() => _categoria = nuevaSeleccion.first);
                },
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
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _cantidadCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Cantidad'),
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
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _unidadCtrl,
                      decoration: const InputDecoration(labelText: 'Unidad'),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                              ? 'Requerido'
                              : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _stockMinimoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Stock mínimo (alerta)',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notasCtrl,
                decoration: const InputDecoration(labelText: 'Notas (opcional)'),
                maxLines: 2,
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