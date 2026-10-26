import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/business_profile.dart';
import '../models/customer.dart';

/// Genera el PDF de una factura de servicio, siguiendo el mismo
/// diseño de la plantilla en Word que ya usaba el negocio: título
/// azul, secciones de "Información de la Empresa", "Datos de la
/// Factura", "Datos del Cliente", tabla de detalle con encabezado
/// verde, totales, notas y firma del operador.
class InvoicePdf {
  static const PdfColor _azul = PdfColor.fromInt(0xFF1F6FB2);
  static const PdfColor _verdeLima = PdfColor.fromInt(0xFF9ACD32);
  static const PdfColor _verdeOscuro = PdfColor.fromInt(0xFF1B4D2E);

  /// Construye el número de factura visible, ej. "GGS-0007", usando
  /// las iniciales del nombre comercial del negocio.
  static String _numeroFacturaTexto(BusinessProfile perfil, int numero) {
    final palabras = perfil.nombreComercial
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    final iniciales = palabras.isEmpty
        ? 'FAC'
        : palabras.map((p) => p[0].toUpperCase()).take(4).join();
    return '$iniciales-${numero.toString().padLeft(4, '0')}';
  }

  static String _formatearFecha(DateTime f) {
    final dia = f.day.toString().padLeft(2, '0');
    final mes = f.month.toString().padLeft(2, '0');
    return '$dia/$mes/${f.year}';
  }

  /// Genera los bytes del PDF, listos para previsualizar, compartir o
  /// imprimir con el paquete `printing`.
  static Future<Uint8List> generar({
    required Customer cliente,
    required BusinessProfile perfil,
    required int numeroFactura,
  }) async {
    final doc = pw.Document();
    final fechaEmision = DateTime.now();
    final numeroTexto = _numeroFacturaTexto(perfil, numeroFactura);

    final notaEstado = switch (cliente.estado) {
      EstadoTrabajo.pagado =>
        'Pagado con ${cliente.metodoPago?.label ?? "método no especificado"}'
            '${cliente.fechaPago != null ? " el ${_formatearFecha(cliente.fechaPago!)}" : ""}.',
      EstadoTrabajo.realizado => 'Servicio realizado, pendiente de pago.',
      EstadoTrabajo.pendiente => 'Servicio agendado, pendiente de realizar y de pago.',
    };

    doc.addPage(
      // MultiPage (en vez de Page): con varios servicios la tabla puede
      // crecer y, si no cabe en una hoja, continúa en la siguiente en
      // lugar de lanzar un error.
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(32),
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        build: (context) {
          return [
              pw.Center(
                child: pw.Text(
                  'FACTURA DE SERVICIO – '
                  '${perfil.nombreComercial.isNotEmpty ? perfil.nombreComercial : "Mi Negocio"}',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: _azul,
                  ),
                ),
              ),
              pw.SizedBox(height: 18),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: _bloqueInfo('Información de la Empresa', [
                      'Nombre comercial: ${perfil.nombreComercial}',
                      'Operador responsable: ${perfil.operador}',
                      'Teléfono: ${perfil.telefono}',
                      'Correo: ${perfil.correo}',
                    ]),
                  ),
                  pw.SizedBox(width: 24),
                  pw.Expanded(
                    child: _bloqueInfo('Datos de la Factura', [
                      'Número de factura: $numeroTexto',
                      'Fecha de emisión: ${_formatearFecha(fechaEmision)}',
                      'Fecha del servicio: ${_formatearFecha(cliente.fecha)}',
                    ]),
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              _bloqueInfo('Datos del Cliente', [
                'Nombre del cliente: ${cliente.nombre}',
                'Dirección: ${cliente.lugar}',
              ]),
              pw.SizedBox(height: 18),
              pw.Text(
                'Detalle del Servicio',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _azul),
              ),
              pw.SizedBox(height: 6),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                columnWidths: const {
                  0: pw.FlexColumnWidth(3),
                  1: pw.FlexColumnWidth(1),
                  2: pw.FlexColumnWidth(1.5),
                  3: pw.FlexColumnWidth(1.5),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: _verdeLima),
                    children: [
                      _celda('Descripción', negrita: true, color: PdfColors.white),
                      _celda('Cantidad', negrita: true, color: PdfColors.white),
                      _celda('Precio Unitario', negrita: true, color: PdfColors.white),
                      _celda('Subtotal', negrita: true, color: PdfColors.white),
                    ],
                  ),
                  // Una fila por cada servicio del trabajo, con su propio
                  // precio. Si por alguna razón no hay servicios (trabajos
                  // muy antiguos), se muestra una sola fila con el total.
                  if (cliente.servicios.isEmpty)
                    pw.TableRow(
                      children: [
                        _celda('Servicio'),
                        _celda('1'),
                        _celda('\$${cliente.precio.toStringAsFixed(2)}'),
                        _celda('\$${cliente.precio.toStringAsFixed(2)}'),
                      ],
                    )
                  else
                    for (final servicio in cliente.servicios)
                      pw.TableRow(
                        children: [
                          _celda(servicio.nombre.isNotEmpty ? servicio.nombre : 'Servicio'),
                          _celda('1'),
                          _celda('\$${servicio.precio.toStringAsFixed(2)}'),
                          _celda('\$${servicio.precio.toStringAsFixed(2)}'),
                        ],
                      ),
                ],
              ),
              pw.SizedBox(height: 18),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Subtotal: \$${cliente.precio.toStringAsFixed(2)}'),
                    pw.SizedBox(height: 3),
                    pw.Text('Descuentos: \$0.00'),
                    pw.SizedBox(height: 3),
                    pw.Text('Impuesto: \$0.00'),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      'Total a pagar: \$${cliente.precio.toStringAsFixed(2)}',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13, color: _verdeOscuro),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 22),
              pw.Text(
                'Notas',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _azul),
              ),
              pw.SizedBox(height: 4),
              pw.Text(notaEstado, style: const pw.TextStyle(fontSize: 10.5)),
              pw.SizedBox(height: 4),
              pw.Text(
                'Este documento no es una factura fiscal y no tiene validez '
                'tributaria; es únicamente un comprobante del servicio prestado.',
                style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 26),
              pw.Text(
                'Firma del Operador',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _azul),
              ),
              pw.SizedBox(height: 4),
              pw.Text('Nombre: ${perfil.operador}', style: const pw.TextStyle(fontSize: 10.5)),
              pw.SizedBox(height: 20),
              pw.Text('Firma: ___________________________', style: const pw.TextStyle(fontSize: 10.5)),
          ];
        },
      ),
    );

    return doc.save();
  }

  static pw.Widget _bloqueInfo(String titulo, List<String> lineas) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          titulo,
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _azul),
        ),
        pw.SizedBox(height: 4),
        ...lineas.map(
          (l) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Text(l, style: const pw.TextStyle(fontSize: 10.5)),
          ),
        ),
      ],
    );
  }

  static pw.Widget _celda(String texto, {bool negrita = false, PdfColor color = PdfColors.black}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        texto,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: negrita ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color,
        ),
      ),
    );
  }
}