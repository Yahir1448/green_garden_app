import 'package:flutter/material.dart';

import '../models/inventory_item.dart';
import '../models/service_item.dart';
import '../services/inventory_service.dart';
import '../services/service_catalog_service.dart';
import '../theme/app_theme.dart';
import '../widgets/theme_toggle_button.dart';

/// Formatea una cantidad sin decimales si es entera (2 en vez de 2.00).
String _formatearCantidad(double valor) => valor == valor.truncateToDouble()
    ? valor.toStringAsFixed(0)
    : valor.toStringAsFixed(2);

/// Deja el consumo de un insumo en las recetas de los servicios tal
/// como indica [consumoPorServicio] (id de servicio -> cantidad que
/// consume cada vez que se realiza). Los servicios que ya tenían este
/// insumo y no aparecen en el mapa lo pierden; los que no cambian no
/// se tocan (no se hace ninguna llamada de red para ellos).
///
/// Para quitar el insumo de todas las recetas (por ejemplo, al
/// eliminarlo), pasa un mapa vacío.
Future<void> _actualizarRecetasDeInsumo(
  ServiceCatalogService serviceCatalog, {
  required String inventarioId,
  required String inventarioNombre,
  required Map<String, double> consumoPorServicio,
}) async {
  for (final servicio in serviceCatalog.servicios) {
    final actuales =
        servicio.receta.where((r) => r.inventarioId == inventarioId).toList();
    final cantidadNueva = consumoPorServicio[servicio.id];

    if (actuales.isEmpty && cantidadNueva == null) continue;
    if (actuales.length == 1 &&
        cantidadNueva != null &&
        actuales.first.cantidad == cantidadNueva &&
        actuales.first.inventarioNombre == inventarioNombre) {
      continue;
    }

    final nuevaReceta =
        servicio.receta.where((r) => r.inventarioId != inventarioId).toList();
    if (cantidadNueva != null) {
      nuevaReceta.add(RecetaInsumo(
        inventarioId: inventarioId,
        inventarioNombre: inventarioNombre,
        cantidad: cantidadNueva,
      ));
    }

    await serviceCatalog.actualizarServicio(
      servicio.id,
      nombre: servicio.nombre,
      descripcion: servicio.descripcion,
      precio: servicio.precio,
      receta: nuevaReceta,
    );
  }
}

/// Pantalla que muestra el inventario de herramientas e insumos.
/// Permite ver, agregar, editar, ajustar cantidades y eliminar artículos.
/// En los insumos también se configura qué servicios los consumen y en
/// qué cantidad (lo que antes se hacía en "Insumos por servicio").
class InventoryScreen extends StatefulWidget {
  final InventoryService service;
  final ServiceCatalogService serviceCatalog;

  const InventoryScreen({
    super.key,
    required this.service,
    required this.serviceCatalog,
  });

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
          serviceCatalog: widget.serviceCatalog,
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
              final mensajero = ScaffoldMessenger.of(context);
              try {
                await widget.service.eliminarItem(item.id);
              } catch (e) {
                mensajero.showSnackBar(
                  const SnackBar(content: Text('No se pudo eliminar. Intenta de nuevo.')),
                );
                return;
              }
              // Ya no existe: se quita de las recetas de los servicios
              // para no dejar consumos apuntando a un insumo inexistente.
              try {
                await _actualizarRecetasDeInsumo(
                  widget.serviceCatalog,
                  inventarioId: item.id,
                  inventarioNombre: item.nombre,
                  consumoPorServicio: const {},
                );
              } catch (e) {
                debugPrint('Error limpiando recetas de ${item.id}: $e');
              }
              navigator.pop();
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
        // También escucha el catálogo para que el "Se usa en…" de cada
        // insumo se actualice al cambiar las recetas.
        listenable: Listenable.merge([widget.service, widget.serviceCatalog]),
        builder: (context, _) {
          return TabBarView(
            controller: _tabController,
            children: [
              _ListaItems(
                items: widget.service.porCategoria(ItemCategoria.herramienta),
                serviceCatalog: widget.serviceCatalog,
                onTap: (item) => _abrirFormulario(item: item),
                onDelete: _confirmarEliminar,
                onAjustar: widget.service.ajustarCantidad,
              ),
              _ListaItems(
                items: widget.service.porCategoria(ItemCategoria.insumo),
                serviceCatalog: widget.serviceCatalog,
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
  final ServiceCatalogService serviceCatalog;
  final ValueChanged<InventoryItem> onTap;
  final ValueChanged<InventoryItem> onDelete;
  final Future<void> Function(String id, double delta) onAjustar;

  const _ListaItems({
    required this.items,
    required this.serviceCatalog,
    required this.onTap,
    required this.onDelete,
    required this.onAjustar,
  });

  /// Texto "Corte de césped (2), Fertilizado (1)" con los servicios
  /// que consumen este insumo, o null si no lo usa ninguno.
  String? _usoEnServicios(InventoryItem item) {
    if (item.categoria != ItemCategoria.insumo) return null;
    final usos = <String>[];
    for (final servicio in serviceCatalog.servicios) {
      for (final r in servicio.receta) {
        if (r.inventarioId == item.id) {
          usos.add('${servicio.nombre} (${_formatearCantidad(r.cantidad)})');
        }
      }
    }
    return usos.isEmpty ? null : usos.join(', ');
  }

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
        final uso = _usoEnServicios(item);
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
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.cantidad.toStringAsFixed(item.cantidad % 1 == 0 ? 0 : 1)} '
                  '${item.unidad}'
                  '${item.bajoStock ? '  •  Stock bajo' : ''}',
                  style: TextStyle(
                    color: item.bajoStock ? Colors.redAccent : null,
                    fontWeight: item.bajoStock ? FontWeight.bold : null,
                  ),
                ),
                if (uso != null)
                  Text(
                    'Se usa en: $uso',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
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

/// Una fila de "Consumo por servicio" en el formulario: un servicio del
/// catálogo y la cantidad de este insumo que gasta cada vez que se
/// realiza.
class _FilaConsumo {
  String? servicioId;
  final TextEditingController cantidadCtrl;

  _FilaConsumo({this.servicioId, String cantidadInicial = ''})
      : cantidadCtrl = TextEditingController(text: cantidadInicial);

  void dispose() => cantidadCtrl.dispose();
}

/// Formulario para crear o editar un artículo del inventario.
class _ItemFormSheet extends StatefulWidget {
  final InventoryService service;
  final ServiceCatalogService serviceCatalog;
  final InventoryItem? item;

  const _ItemFormSheet({
    required this.service,
    required this.serviceCatalog,
    this.item,
  });

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
  final List<_FilaConsumo> _consumos = [];

  /// Id del artículo ya guardado. Si guardar el consumo por servicio
  /// falla después de crear el artículo, un segundo intento actualiza
  /// ese mismo artículo en vez de crear un duplicado.
  String? _idGuardado;

  bool get _esEdicion => widget.item != null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _idGuardado = item?.id;
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

    // Precarga el consumo actual leyendo las recetas de los servicios.
    if (item != null) {
      for (final servicio in widget.serviceCatalog.servicios) {
        for (final r in servicio.receta) {
          if (r.inventarioId == item.id) {
            _consumos.add(_FilaConsumo(
              servicioId: servicio.id,
              cantidadInicial: r.cantidad.toString(),
            ));
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _cantidadCtrl.dispose();
    _unidadCtrl.dispose();
    _stockMinimoCtrl.dispose();
    _notasCtrl.dispose();
    for (final fila in _consumos) {
      fila.dispose();
    }
    super.dispose();
  }

  void _agregarConsumo() => setState(() => _consumos.add(_FilaConsumo()));

  void _eliminarConsumo(int index) {
    setState(() {
      final fila = _consumos.removeAt(index);
      fila.dispose();
    });
  }

  bool _guardando = false;

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    final nombre = _nombreCtrl.text.trim();
    final cantidad = double.parse(_cantidadCtrl.text.trim());
    final unidad = _unidadCtrl.text.trim();
    final stockMinimo = double.tryParse(_stockMinimoCtrl.text.trim()) ?? 0;
    final notas = _notasCtrl.text.trim();

    // Solo los insumos se consumen; si el artículo es una herramienta,
    // el mapa queda vacío y se limpia cualquier receta que lo tuviera.
    final consumoPorServicio = <String, double>{};
    if (_categoria == ItemCategoria.insumo) {
      for (final fila in _consumos) {
        final id = fila.servicioId;
        if (id == null) continue;
        consumoPorServicio[id] =
            double.tryParse(fila.cantidadCtrl.text.trim()) ?? 0;
      }
    }

    setState(() => _guardando = true);

    try {
      if (_idGuardado != null) {
        await widget.service.actualizarItem(
          _idGuardado!,
          nombre: nombre,
          categoria: _categoria,
          cantidad: cantidad,
          unidad: unidad,
          stockMinimo: stockMinimo,
          notas: notas,
        );
      } else {
        final creado = await widget.service.agregarItem(
          nombre: nombre,
          categoria: _categoria,
          cantidad: cantidad,
          unidad: unidad,
          stockMinimo: stockMinimo,
          notas: notas,
        );
        _idGuardado = creado.id;
      }

      await _actualizarRecetasDeInsumo(
        widget.serviceCatalog,
        inventarioId: _idGuardado!,
        inventarioNombre: nombre,
        consumoPorServicio: consumoPorServicio,
      );

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

  Widget _seccionConsumo(BuildContext context) {
    final tema = Theme.of(context);
    final hayServicios = widget.serviceCatalog.servicios.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Text('Consumo por servicio', style: tema.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Cada vez que marques un trabajo con ese servicio como '
          'realizado, se descontará esta cantidad del inventario '
          'automáticamente.',
          style: tema.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (_consumos.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Ningún servicio descuenta este insumo todavía.',
              style: tema.textTheme.bodyMedium,
            ),
          ),
        ..._consumos.asMap().entries.map((entry) {
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
                    listenable: widget.serviceCatalog,
                    builder: (context, _) {
                      final servicios = widget.serviceCatalog.servicios;
                      return DropdownButtonFormField<String?>(
                        isExpanded: true,
                        initialValue: fila.servicioId,
                        decoration: const InputDecoration(labelText: 'Servicio'),
                        items: servicios
                            .map(
                              (s) => DropdownMenuItem<String?>(
                                value: s.id,
                                child: Text(
                                  s.nombre,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        validator: (value) {
                          if (value == null) return 'Elige un servicio';
                          final repetidos = _consumos
                              .where((f) => f.servicioId == value)
                              .length;
                          return repetidos > 1 ? 'Ya agregado' : null;
                        },
                        onChanged: (id) => setState(() => fila.servicioId = id),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: fila.cantidadCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Cantidad'),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Requerido';
                      }
                      final numero = double.tryParse(value.trim());
                      if (numero == null) return 'Inválido';
                      if (numero <= 0) return 'Mayor a 0';
                      return null;
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: 'Quitar',
                  onPressed: () => _eliminarConsumo(index),
                ),
              ],
            ),
          );
        }),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: hayServicios ? _agregarConsumo : null,
            icon: const Icon(Icons.add),
            label: const Text('Agregar servicio'),
          ),
        ),
        if (!hayServicios)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Agrega servicios en "Servicios" antes de poder configurar su consumo aquí.',
              style: tema.textTheme.bodySmall?.copyWith(color: Colors.orange),
            ),
          ),
      ],
    );
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
                crossAxisAlignment: CrossAxisAlignment.start,
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
              if (_categoria == ItemCategoria.insumo) _seccionConsumo(context),
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