import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/finance_entry.dart';
import '../services/finance_service.dart';
import '../theme/app_theme.dart';

/// Escala de tiempo con la que se agrupan los movimientos en la
/// gráfica.
enum Granularidad { dia, semana, mes }

/// Un período (día, semana o mes) con sus totales de ingresos y
/// egresos ya sumados.
class _Periodo {
  final String etiqueta;
  final DateTime inicio;
  final DateTime fin;
  double ingresos = 0;
  double egresos = 0;

  _Periodo({required this.etiqueta, required this.inicio, required this.fin});

  void agregar(FinanceEntry entry) {
    if (entry.tipo == TipoMovimiento.ingreso) {
      ingresos += entry.monto;
    } else {
      egresos += entry.monto;
    }
  }

  double get balance => ingresos - egresos;
}

const List<String> _mesesAbrev = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun',
  'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
];

const List<String> _diasAbrev = [
  'lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom',
];

/// Gráfica de barras de ingresos vs. egresos, con selector de escala
/// (día/semana/mes) y una comparación automática contra el período
/// inmediatamente anterior.
class FinanceChart extends StatefulWidget {
  final FinanceService service;

  const FinanceChart({super.key, required this.service});

  @override
  State<FinanceChart> createState() => _FinanceChartState();
}

class _FinanceChartState extends State<FinanceChart> {
  Granularidad _granularidad = Granularidad.mes;

  List<_Periodo> _construirPeriodos() {
    final entries = widget.service.entries;
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);

    late final List<_Periodo> periodos;
    switch (_granularidad) {
      case Granularidad.dia:
        periodos = List.generate(7, (i) {
          final fecha = hoy.subtract(Duration(days: 6 - i));
          return _Periodo(
            etiqueta: '${_diasAbrev[fecha.weekday - 1]} ${fecha.day}',
            inicio: fecha,
            fin: fecha,
          );
        });
        break;
      case Granularidad.semana:
        final inicioSemanaActual = hoy.subtract(Duration(days: hoy.weekday - 1));
        periodos = List.generate(8, (i) {
          final inicio = inicioSemanaActual.subtract(Duration(days: 7 * (7 - i)));
          final fin = inicio.add(const Duration(days: 6));
          return _Periodo(
            etiqueta: '${inicio.day} ${_mesesAbrev[inicio.month - 1]}',
            inicio: inicio,
            fin: fin,
          );
        });
        break;
      case Granularidad.mes:
        periodos = List.generate(6, (i) {
          final fechaMes = DateTime(hoy.year, hoy.month - (5 - i), 1);
          final fin = DateTime(fechaMes.year, fechaMes.month + 1, 0);
          return _Periodo(
            etiqueta: _mesesAbrev[fechaMes.month - 1],
            inicio: fechaMes,
            fin: fin,
          );
        });
        break;
    }

    for (final entry in entries) {
      final fechaEntry = DateTime(entry.fecha.year, entry.fecha.month, entry.fecha.day);
      for (final periodo in periodos) {
        if (!fechaEntry.isBefore(periodo.inicio) && !fechaEntry.isAfter(periodo.fin)) {
          periodo.agregar(entry);
          break;
        }
      }
    }

    return periodos;
  }

  Widget _buildComparacion(List<_Periodo> periodos) {
    if (periodos.length < 2) return const SizedBox.shrink();

    final actual = periodos.last;
    final anterior = periodos[periodos.length - 2];
    final diferencia = actual.balance - anterior.balance;

    String texto;
    IconData icono;
    Color color;

    if (anterior.balance == 0) {
      if (actual.balance == 0) {
        texto = 'Sin movimientos que comparar todavía';
        icono = Icons.remove;
        color = Colors.grey;
      } else {
        final subio = actual.balance > 0;
        texto = subio ? 'Mejoró frente al período anterior' : 'Empeoró frente al período anterior';
        icono = subio ? Icons.trending_up : Icons.trending_down;
        color = subio ? AppColors.darkGreen : Colors.redAccent;
      }
    } else {
      final variacion = (diferencia / anterior.balance.abs()) * 100;
      final subio = diferencia >= 0;
      texto = '${subio ? '+' : ''}${variacion.toStringAsFixed(0)}% vs. período anterior';
      icono = subio ? Icons.trending_up : Icons.trending_down;
      color = subio ? AppColors.darkGreen : Colors.redAccent;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, color: color, size: 18),
        const SizedBox(width: 4),
        Text(
          texto,
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final periodos = _construirPeriodos();

    final maxValor = periodos.fold<double>(
      0,
      (max, p) => [max, p.ingresos, p.egresos].reduce((a, b) => a > b ? a : b),
    );
    final maxY = maxValor <= 0 ? 10.0 : maxValor * 1.25;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Ingresos vs. egresos',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _buildComparacion(periodos),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<Granularidad>(
              segments: const [
                ButtonSegment(value: Granularidad.dia, label: Text('Día')),
                ButtonSegment(value: Granularidad.semana, label: Text('Semana')),
                ButtonSegment(value: Granularidad.mes, label: Text('Mes')),
              ],
              selected: {_granularidad},
              onSelectionChanged: (nuevaSeleccion) {
                setState(() => _granularidad = nuevaSeleccion.first);
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxY,
                  barTouchData: BarTouchData(enabled: true),
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 42,
                        getTitlesWidget: (value, meta) => Text(
                          '\$${value.toInt()}',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= periodos.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              periodos[index].etiqueta,
                              style: const TextStyle(fontSize: 10),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: List.generate(periodos.length, (i) {
                    final p = periodos[i];
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: p.ingresos,
                          color: AppColors.limeGreen,
                          width: 8,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        BarChartRodData(
                          toY: p.egresos,
                          color: Colors.redAccent,
                          width: 8,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _leyenda(color: AppColors.limeGreen, texto: 'Ingresos'),
                const SizedBox(width: 16),
                _leyenda(color: Colors.redAccent, texto: 'Egresos'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _leyenda({required Color color, required String texto}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(texto, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}