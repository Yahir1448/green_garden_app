import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/connectivity_service.dart';
import '../services/data_export_service.dart';
import '../theme/app_theme.dart';

/// Permite al usuario descargar una copia de sus datos (portabilidad).
/// Genera un .zip con un libro de Excel, un JSON completo y archivos
/// CSV, y abre el menú de compartir del teléfono para guardarlo o
/// enviarlo.
class ExportDataScreen extends StatefulWidget {
  const ExportDataScreen({super.key});

  @override
  State<ExportDataScreen> createState() => _ExportDataScreenState();
}

class _ExportDataScreenState extends State<ExportDataScreen> {
  bool _exportando = false;
  String? _error;
  ResultadoExportacion? _ultimo;

  static const Map<String, IconData> _iconos = {
    'Clientes y trabajos': Icons.people_alt_outlined,
    'Inventario': Icons.inventory_2_outlined,
    'Ingresos y gastos': Icons.payments_outlined,
    'Catálogo de servicios': Icons.design_services_outlined,
    'Tarifas del cotizador': Icons.calculate_outlined,
    'Cotizaciones': Icons.request_quote_outlined,
  };

  Future<void> _exportar() async {
    if (!ConnectivityService.instance.isOnline) {
      setState(() {
        _error = 'Necesitas conexión a internet para exportar tus datos.';
      });
      return;
    }

    setState(() {
      _exportando = true;
      _error = null;
    });

    try {
      final resultado = await DataExportService.generar();
      if (!mounted) return;
      setState(() => _ultimo = resultado);

      final caja = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(resultado.zip, mimeType: 'application/zip')],
          fileNameOverrides: [resultado.nombreArchivo],
          title: 'Mis datos de Green Garden',
          sharePositionOrigin:
              caja == null ? null : caja.localToGlobal(Offset.zero) & caja.size,
        ),
      );
    } catch (e) {
      debugPrint('Error exportando datos: $e');
      if (mounted) {
        setState(() {
          _error = 'No se pudo exportar. Revisa tu conexión e intenta de nuevo.';
        });
      }
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  /// Número de registros exportados de un módulo (null si todavía no se
  /// ha exportado nada).
  Widget? _contadorDe(String etiqueta) {
    final total = _ultimo?.filasPorModulo[etiqueta];
    return total == null ? null : _Contador('$total');
  }

  String _tamano(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final resultado = _ultimo;

    return Scaffold(
      appBar: AppBar(title: const Text('Exportar mis datos')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // ---- Cabecera ----
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.darkGreen,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.cloud_download_outlined,
                      color: Colors.white, size: 30),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tu información es tuya',
                        style: tema.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Descarga una copia de todos tus datos cuando quieras.',
                        style: tema.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ---- Estado: error / archivo listo ----
          if (_error != null) ...[
            _Aviso(
              icono: Icons.error_outline,
              color: tema.colorScheme.error,
              texto: _error!,
            ),
            const SizedBox(height: 16),
          ],
          if (resultado != null && _error == null) ...[
            _Aviso(
              icono: resultado.omitidos.isEmpty
                  ? Icons.check_circle_outline
                  : Icons.warning_amber_rounded,
              color: resultado.omitidos.isEmpty
                  ? AppColors.darkGreen
                  : Colors.orange.shade800,
              texto: resultado.omitidos.isEmpty
                  ? 'Archivo listo: ${resultado.nombreArchivo} '
                      '(${_tamano(resultado.zip.length)}). '
                      'Si no lo guardaste, toca el botón otra vez.'
                  : 'Archivo generado, pero no se pudo incluir: '
                      '${resultado.omitidos.join(', ')}. '
                      'Intenta de nuevo con buena conexión.',
            ),
            const SizedBox(height: 16),
          ],

          // ---- Qué recibes ----
          _Tarjeta(
            titulo: 'Qué recibes',
            hijos: const [
              _Fila(
                icono: Icons.table_chart_outlined,
                titulo: 'Libro de Excel',
                subtitulo: 'Una hoja por módulo, con filtros y listo para leer.',
              ),
              _Fila(
                icono: Icons.data_object,
                titulo: 'Copia completa (JSON)',
                subtitulo: 'Todos tus datos, para llevarlos a otro sistema.',
              ),
              _Fila(
                icono: Icons.description_outlined,
                titulo: 'Archivos CSV',
                subtitulo: 'La misma información en texto plano.',
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ---- Qué datos incluye ----
          _Tarjeta(
            titulo: 'Qué datos incluye',
            hijos: [
              for (final etiqueta in DataExportService.etiquetas)
                _Fila(
                  icono: _iconos[etiqueta] ?? Icons.table_chart_outlined,
                  titulo: etiqueta,
                  extremo: _contadorDe(etiqueta),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // ---- Nota ----
          _Aviso(
            icono: Icons.wifi,
            color: tema.colorScheme.primary,
            texto: 'Requiere conexión a internet. Si trabajaste sin conexión, '
                'espera a que se sincronice antes de exportar.',
            suave: true,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _exportando ? null : _exportar,
              icon: _exportando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.ios_share),
              label: Text(_exportando ? 'Preparando tus datos…' : 'Exportar y compartir'),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tarjeta con título y una lista de filas.
class _Tarjeta extends StatelessWidget {
  final String titulo;
  final List<Widget> hijos;

  const _Tarjeta({required this.titulo, required this.hijos});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: tema.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...hijos,
          ],
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String? subtitulo;
  final Widget? extremo;

  const _Fila({
    required this.icono,
    required this.titulo,
    this.subtitulo,
    this.extremo,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.darkGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icono, size: 20, color: AppColors.darkGreen),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: tema.textTheme.bodyLarge),
                if (subtitulo != null)
                  Text(subtitulo!, style: tema.textTheme.bodySmall),
              ],
            ),
          ),
          if (extremo != null) extremo!,
        ],
      ),
    );
  }
}

/// Número de registros exportados de un módulo.
class _Contador extends StatelessWidget {
  final String texto;

  const _Contador(this.texto);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.darkGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: AppColors.darkGreen,
        ),
      ),
    );
  }
}

/// Mensaje con ícono: error, éxito o nota informativa.
class _Aviso extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String texto;
  final bool suave;

  const _Aviso({
    required this.icono,
    required this.color,
    required this.texto,
    this.suave = false,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: suave ? 0.06 : 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Text(texto, style: tema.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}