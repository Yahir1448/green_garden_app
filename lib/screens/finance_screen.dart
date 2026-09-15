import 'package:flutter/material.dart';

import '../models/finance_entry.dart';
import '../services/finance_service.dart';
import '../theme/app_theme.dart';
import '../widgets/finance_chart.dart';
import '../widgets/theme_toggle_button.dart';

/// Pantalla de finanzas: muestra el balance general (ingresos, egresos
/// y balance neto) y permite administrar cada movimiento.
class FinanceScreen extends StatefulWidget {
  final FinanceService service;

  const FinanceScreen({super.key, required this.service});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _abrirFormulario({FinanceEntry? entry}) async {
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
        child: _FinanceFormSheet(
          service: widget.service,
          entry: entry,
        ),
      ),
    );
  }

  void _confirmarEliminar(FinanceEntry entry) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar movimiento'),
        content: Text('¿Deseas eliminar "${entry.descripcion}"?'),
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
                await widget.service.eliminarMovimiento(entry.id);
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
        title: const Text('Finanzas'),
        actions: const [ThemeToggleButton()],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.limeGreen,
          indicatorWeight: 3,
          labelColor: Theme.of(context).appBarTheme.foregroundColor,
          unselectedLabelColor:
              Theme.of(context).appBarTheme.foregroundColor?.withValues(alpha: 0.65),
          tabs: const [
            Tab(text: 'Todos'),
            Tab(text: 'Ingresos'),
            Tab(text: 'Egresos'),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: widget.service,
        builder: (context, _) {
          return Column(
            children: [
              _ResumenBalance(service: widget.service),
              FinanceChart(service: widget.service),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _ListaMovimientos(
                      entries: widget.service.entries,
                      onTap: (e) => _abrirFormulario(entry: e),
                      onDelete: _confirmarEliminar,
                    ),
                    _ListaMovimientos(
                      entries: widget.service.porTipo(TipoMovimiento.ingreso),
                      onTap: (e) => _abrirFormulario(entry: e),
                      onDelete: _confirmarEliminar,
                    ),
                    _ListaMovimientos(
                      entries: widget.service.porTipo(TipoMovimiento.egreso),
                      onTap: (e) => _abrirFormulario(entry: e),
                      onDelete: _confirmarEliminar,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo movimiento'),
      ),
    );
  }
}

/// Tarjeta de resumen con ingresos totales, egresos totales y balance.
class _ResumenBalance extends StatelessWidget {
  final FinanceService service;

  const _ResumenBalance({required this.service});

  @override
  Widget build(BuildContext context) {
    final balance = service.balance;
    final colorBalance = balance >= 0 ? AppColors.darkGreen : Colors.redAccent;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: _MiniResumenCard(
              titulo: 'Ingresos',
              monto: service.totalIngresos,
              color: AppColors.limeGreen,
              icono: Icons.arrow_upward,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MiniResumenCard(
              titulo: 'Egresos',
              monto: service.totalEgresos,
              color: Colors.redAccent,
              icono: Icons.arrow_downward,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MiniResumenCard(
              titulo: 'Balance',
              monto: balance,
              color: colorBalance,
              icono: Icons.account_balance_wallet,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniResumenCard extends StatelessWidget {
  final String titulo;
  final double monto;
  final Color color;
  final IconData icono;

  const _MiniResumenCard({
    required this.titulo,
    required this.monto,
    required this.color,
    required this.icono,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, color: color, size: 20),
            const SizedBox(height: 6),
            Text(
              titulo,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '\$${monto.toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListaMovimientos extends StatelessWidget {
  final List<FinanceEntry> entries;
  final ValueChanged<FinanceEntry> onTap;
  final ValueChanged<FinanceEntry> onDelete;

  const _ListaMovimientos({
    required this.entries,
    required this.onTap,
    required this.onDelete,
  });

  String _formatearFecha(DateTime fecha) {
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    return '$dia/$mes/${fecha.year}';
  }

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(
        child: Text(
          'No hay movimientos registrados aquí todavía.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final esIngreso = entry.tipo == TipoMovimiento.ingreso;
        final color = esIngreso ? AppColors.darkGreen : Colors.redAccent;
        final signo = esIngreso ? '+' : '-';

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            onTap: () => onTap(entry),
            leading: CircleAvatar(
              backgroundColor: (esIngreso ? AppColors.limeGreen : Colors.redAccent)
                  .withValues(alpha: 0.2),
              child: Icon(
                esIngreso ? Icons.arrow_upward : Icons.arrow_downward,
                color: color,
              ),
            ),
            title: Text(entry.descripcion),
            subtitle: Text(
              entry.categoria.isNotEmpty
                  ? '${entry.categoria} • ${_formatearFecha(entry.fecha)}'
                  : _formatearFecha(entry.fecha),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$signo\$${entry.monto.toStringAsFixed(2)}',
                  style: TextStyle(fontWeight: FontWeight.bold, color: color),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => onDelete(entry),
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

/// Formulario para crear o editar un movimiento financiero.
class _FinanceFormSheet extends StatefulWidget {
  final FinanceService service;
  final FinanceEntry? entry;

  const _FinanceFormSheet({required this.service, this.entry});

  @override
  State<_FinanceFormSheet> createState() => _FinanceFormSheetState();
}

class _FinanceFormSheetState extends State<_FinanceFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _descripcionCtrl;
  late final TextEditingController _montoCtrl;
  late final TextEditingController _categoriaCtrl;
  late TipoMovimiento _tipo;
  late DateTime _fecha;

  bool get _esEdicion => widget.entry != null;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _descripcionCtrl = TextEditingController(text: entry?.descripcion ?? '');
    _montoCtrl = TextEditingController(
      text: entry != null ? entry.monto.toString() : '',
    );
    _categoriaCtrl = TextEditingController(text: entry?.categoria ?? '');
    _tipo = entry?.tipo ?? TipoMovimiento.ingreso;
    _fecha = entry?.fecha ?? DateTime.now();
  }

  @override
  void dispose() {
    _descripcionCtrl.dispose();
    _montoCtrl.dispose();
    _categoriaCtrl.dispose();
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

  bool _guardando = false;

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    final descripcion = _descripcionCtrl.text.trim();
    final monto = double.parse(_montoCtrl.text.trim());
    final categoria = _categoriaCtrl.text.trim();

    setState(() => _guardando = true);

    try {
      if (_esEdicion) {
        await widget.service.actualizarMovimiento(
          widget.entry!.id,
          descripcion: descripcion,
          tipo: _tipo,
          monto: monto,
          fecha: _fecha,
          categoria: categoria,
        );
      } else {
        await widget.service.agregarMovimiento(
          descripcion: descripcion,
          tipo: _tipo,
          monto: monto,
          fecha: _fecha,
          categoria: categoria,
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
                _esEdicion ? 'Editar movimiento' : 'Nuevo movimiento',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              SegmentedButton<TipoMovimiento>(
                segments: const [
                  ButtonSegment(
                    value: TipoMovimiento.ingreso,
                    label: Text('Ingreso'),
                    icon: Icon(Icons.arrow_upward),
                  ),
                  ButtonSegment(
                    value: TipoMovimiento.egreso,
                    label: Text('Egreso'),
                    icon: Icon(Icons.arrow_downward),
                  ),
                ],
                selected: {_tipo},
                onSelectionChanged: (nuevaSeleccion) {
                  setState(() => _tipo = nuevaSeleccion.first);
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descripcionCtrl,
                decoration: const InputDecoration(labelText: 'Descripción'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty)
                        ? 'Ingresa una descripción'
                        : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _montoCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Monto',
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
              const SizedBox(height: 12),
              TextFormField(
                controller: _categoriaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Categoría (opcional)',
                ),
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