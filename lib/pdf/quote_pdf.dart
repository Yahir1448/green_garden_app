import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/business_profile.dart';
import '../models/cotizacion.dart';

/// Genera el PDF de una cotización/presupuesto, con el mismo estilo
/// visual que la factura (ver `InvoicePdf`), para poder enviársela al
/// cliente por WhatsApp u otra app antes de que acepte el trabajo.
class QuotePdf {
  static const PdfColor _azul = PdfColor.fromInt(0xFF1F6FB2);
  static const PdfColor _verdeLima = PdfColor.fromInt(0xFF9ACD32);
  static const PdfColor _verdeOscuro = PdfColor.fromInt(0xFF1B4D2E);

  static String _formatearFecha(DateTime f) {
    final dia = f.day.toString().padLeft(2, '0');
    final mes = f.month.toString().padLeft(2, '0');
    return '$dia/$mes/${f.year}';
  }

  /// Genera los bytes del PDF, listos para compartir o imprimir con el
  /// paquete `printing`.
  static Future<Uint8List> generar({
    required String nombreCliente,
    required String lugar,
    required List<ServicioCotizado> servicios,
    required double margenRentabilidad,
    required double costoTotal,
    required double precioTotal,
    required BusinessProfile perfil,
  }) async {
    final doc = pw.Document();
    final fechaEmision = DateTime.now();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  'COTIZACIÓN DE SERVICIO – '
                  '${perfil.nombreComercial.isNotEmpty ? perfil.nombreComercial : "Mi Negocio"}',
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _azul),
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
                    child: _bloqueInfo('Datos de la Cotización', [
                      'Fecha: ${_formatearFecha(fechaEmision)}',
                      'Válida por 15 días a partir de esta fecha.',
                    ]),
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              _bloqueInfo('Datos del Cliente', [
                'Nombre del cliente: ${nombreCliente.isNotEmpty ? nombreCliente : "Por confirmar"}',
                'Dirección: ${lugar.isNotEmpty ? lugar : "Por confirmar"}',
              ]),
              pw.SizedBox(height: 18),
              pw.Text(
                'Detalle de Servicios',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _azul),
              ),
              pw.SizedBox(height: 6),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                columnWidths: const {
                  0: pw.FlexColumnWidth(3),
                  1: pw.FlexColumnWidth(1.2),
                  2: pw.FlexColumnWidth(1.2),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: _verdeLima),
                    children: [
                      _celda('Servicio', negrita: true, color: PdfColors.white),
                      _celda('Detalle', negrita: true, color: PdfColors.white),
                      _celda('Precio', negrita: true, color: PdfColors.white),
                    ],
                  ),
                  ...servicios.map(
                    (s) => pw.TableRow(
                      children: [
                        _celda(s.servicioNombre),
                        _celda(
                          s.m2 > 0 || s.km > 0
                              ? '${s.m2 > 0 ? "${s.m2.toStringAsFixed(0)} m²" : ""}'
                                  '${s.m2 > 0 && s.km > 0 ? " · " : ""}'
                                  '${s.km > 0 ? "${s.km.toStringAsFixed(0)} km" : ""}'
                              : '—',
                        ),
                        _celda('\$${s.precio.toStringAsFixed(2)}'),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 18),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Costo de referencia: \$${costoTotal.toStringAsFixed(2)}'),
                    if (margenRentabilidad > 0) ...[
                      pw.SizedBox(height: 3),
                      pw.Text('Margen aplicado: ${margenRentabilidad.toStringAsFixed(0)}%'),
                    ],
                    pw.SizedBox(height: 6),
                    pw.Text(
                      'Total cotizado: \$${precioTotal.toStringAsFixed(2)}',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13, color: _verdeOscuro),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 26),
              pw.Text(
                'Notas',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _azul),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Este presupuesto es un estimado y puede variar según las '
                'condiciones del lugar el día del trabajo.',
                style: const pw.TextStyle(fontSize: 10.5),
              ),
            ],
          );
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