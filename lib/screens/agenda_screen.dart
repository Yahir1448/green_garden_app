import 'package:flutter/material.dart';

import '../models/customer.dart';
import '../services/customer_service.dart';
import '../services/inventory_service.dart';
import '../services/service_catalog_service.dart';
import '../theme/app_theme.dart';
import '../utils/inventario_descuento.dart';
import '../widgets/offline_banner.dart';

/// Vista de calendario/agenda: un mes a la vez, con un punto en los
/// días que tienen al menos un trabajo agendado. Al tocar un día se ve
/// la lista de trabajos de esa fecha, con la opción de marcarlos como
/// realizados directamente desde aquí.
class AgendaScreen extends StatefulWidget {
  final CustomerService customerService;
  final ServiceCatalogService serviceCatalogService;
  final InventoryService inventoryService;

  const AgendaScreen({
    super.key,
    required this.customerService,
    required this.serviceCatalogService,
    required this.inventoryService,
  });

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  late DateTime _mesActual;
  late DateTime _diaSeleccionado;

  static const List<String> _nombresMeses = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];
  static const List<String> _nombresDias = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    _mesActual = DateTime(hoy.year, hoy.month);
    _diaSeleccionado = DateTime(hoy.year, hoy.month, hoy.day);
  }

  bool _mismoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<Customer> _trabajosDe(DateTime dia) {
    return widget.customerService.customers
        .where((c) => _mismoDia(c.fecha, dia))
        .toList();
  }

  void _cambiarMes(int delta) {
    setState(() {
      _mesActual = DateTime(_mesActual.year, _mesActual.month + delta);
    });
  }

  void _seleccionarDia(DateTime dia) {
    setState(() => _diaSeleccionado = dia);
  }

  Color _colorEstado(EstadoTrabajo estado) {
    switch (estado) {
      case EstadoTrabajo.pendiente:
        return Colors.blueGrey;
      case EstadoTrabajo.realizado:
        return Colors.orange;
      case EstadoTrabajo.pagado:
        return AppColors.darkGreen;
    }
  }

  Future<void> _marcarRealizado(Customer cliente) async {
    try {
      await widget.customerService.marcarRealizado(cliente.id);
      await descontarInsumosDelTrabajo(
        servicios: cliente.servicios,
        serviceCatalog: widget.serviceCatalogService,
        inventoryService: widget.inventoryService,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${cliente.nombre}: trabajo marcado como realizado')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo actualizar. Intenta de nuevo.')),
        );
      }
    }
  }

  /// Arma la cuadrícula de celdas del mes (incluye días en blanco al
  /// inicio para que la semana empiece en lunes).
  List<DateTime?> _celdasDelMes() {
    final primerDia = DateTime(_mesActual.year, _mesActual.month, 1);
    final diasEnMes = DateTime(_mesActual.year, _mesActual.month + 1, 0).day;
    final espaciosVacios = primerDia.weekday - 1; // lunes = 1

    final celdas = <DateTime?>[
      ...List<DateTime?>.filled(espaciosVacios, null),
      for (var d = 1; d <= diasEnMes; d++) DateTime(_mesActual.year, _mesActual.month, d),
    ];
    while (celdas.length % 7 != 0) {
      celdas.add(null);
    }
    return celdas;
  }

  @override
  Widget build(BuildContext context) {
    final celdas = _celdasDelMes();
    final trabajosDelDia = _trabajosDe(_diaSeleccionado)
      ..sort((a, b) => a.estado.index.compareTo(b.estado.index));
    final hoy = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: const Text('Agenda')),
      body: ListenableBuilder(
        listenable: widget.customerService,
        builder: (context, _) {
          return Column(
            children: [
              const OfflineBanner(),
              // Encabezado con el mes y flechas de navegación.
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _cambiarMes(-1),
                    ),
                    Text(
                      '${_nombresMeses[_mesActual.month - 1]} ${_mesActual.year}',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => _cambiarMes(1),
                    ),
                  ],
                ),
              ),
              // Encabezado de días de la semana.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: _nombresDias
                      .map(
                        (d) => Expanded(
                          child: Center(
                            child: Text(
                              d,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 4),
              // Cuadrícula del mes.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: GridView.count(
                  crossAxisCount: 7,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: celdas.map((dia) {
                    if (dia == null) return const SizedBox.shrink();

                    final esHoy = _mismoDia(dia, hoy);
                    final esSeleccionado = _mismoDia(dia, _diaSeleccionado);
                    final trabajos = _trabajosDe(dia);

                    return Padding(
                      padding: const EdgeInsets.all(2),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _seleccionarDia(dia),
                        child: Container(
                          decoration: BoxDecoration(
                            color: esSeleccionado
                                ? Theme.of(context).colorScheme.primary
                                : (esHoy
                                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
                                    : null),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${dia.day}',
                                style: TextStyle(
                                  color: esSeleccionado
                                      ? Theme.of(context).colorScheme.onPrimary
                                      : null,
                                  fontWeight: esHoy ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              const SizedBox(height: 2),
                              if (trabajos.isNotEmpty)
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: esSeleccionado
                                        ? Theme.of(context).colorScheme.onPrimary
                                        : AppColors.limeGreen,
                                  ),
                                )
                              else
                                const SizedBox(height: 5),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const Divider(height: 24),
              // Lista de trabajos del día seleccionado.
              Expanded(
                child: trabajosDelDia.isEmpty
                    ? Center(
                        child: Text(
                          'No hay trabajos agendados este día.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                        itemCount: trabajosDelDia.length,
                        itemBuilder: (context, index) {
                          final cliente = trabajosDelDia[index];
                          final color = _colorEstado(cliente.estado);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: color.withValues(alpha: 0.15),
                                child: Icon(Icons.eco_outlined, color: color),
                              ),
                              title: Text(cliente.nombre),
                              subtitle: Text(
                                '${cliente.lugar}'
                                '${cliente.servicioNombre.isNotEmpty ? '\n${cliente.servicioNombre}' : ''}',
                              ),
                              isThreeLine: cliente.servicioNombre.isNotEmpty,
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '\$${cliente.precio.toStringAsFixed(2)}',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    cliente.estado.label,
                                    style: TextStyle(fontSize: 12, color: color),
                                  ),
                                  if (cliente.estado == EstadoTrabajo.pendiente)
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: const Size(0, 28),
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: () => _marcarRealizado(cliente),
                                      child: const Text('Marcar realizado'),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}