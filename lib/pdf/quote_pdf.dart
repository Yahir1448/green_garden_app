import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/business_profile.dart';
import '../models/cotizacion.dart';

/// Un servicio con sus tres conceptos ya con el margen repartido.
class _ServicioRepartido {
  final ServicioCotizado origen;
  final double manoObra;
  final double distancia;
  final double insumos;

  _ServicioRepartido(this.origen, this.manoObra, this.distancia, this.insumos);

  double get total => manoObra + distancia + insumos;
}

/// Todos los conceptos de la cotización (servicios y ayudantes) con el
/// margen de ganancia ya repartido, de modo que la suma de todo es
/// exactamente el total a pagar.
class _Reparto {
  final List<_ServicioRepartido> servicios;
  final List<AyudanteCotizado> ayudantes;

  _Reparto(this.servicios, this.ayudantes);

  double get totalManoObra => servicios.fold<double>(0, (s, r) => s + r.manoObra);
  double get totalDistancia => servicios.fold<double>(0, (s, r) => s + r.distancia);
  double get totalInsumos => servicios.fold<double>(0, (s, r) => s + r.insumos);
  double get totalAyudantes => ayudantes.fold<double>(0, (s, a) => s + a.costo);
}

/// Genera el PDF de una cotización/presupuesto para el cliente.
///
/// Desglosa cada servicio en mano de obra, costo por distancia e
/// insumos, y muestra los ayudantes por separado, para que el cliente
/// entienda de qué se compone el precio. La ganancia no aparece como una
/// línea aparte: se reparte proporcionalmente entre todos los conceptos,
/// así que los importes siempre suman exactamente el total.
class QuotePdf {
  static const PdfColor _verdeOscuro = PdfColor.fromInt(0xFF1B4D2E);
  static const PdfColor _verdeLima = PdfColor.fromInt(0xFF9ACD32);
  static const PdfColor _fondoSuave = PdfColor.fromInt(0xFFF1F6EE);
  static const PdfColor _gris = PdfColor.fromInt(0xFF5F6B63);
  static const PdfColor _linea = PdfColor.fromInt(0xFFD5DDD3);

  static const int _diasValidez = 15;

  /// Genera los bytes del PDF, listos para compartir o imprimir con el
  /// paquete `printing`.
  static Future<Uint8List> generar({
    required String nombreCliente,
    required String lugar,
    required List<ServicioCotizado> servicios,
    List<AyudanteCotizado> ayudantes = const [],
    required double precioTotal,
    required BusinessProfile perfil,
  }) async {
    final doc = pw.Document();
    final hoy = DateTime.now();
    final validaHasta = hoy.add(const Duration(days: _diasValidez));
    final nombreNegocio =
        perfil.nombreComercial.isNotEmpty ? perfil.nombreComercial : 'Mi Negocio';
    final reparto = _repartir(servicios, ayudantes, precioTotal);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 40),
        footer: (context) => _pie(context, nombreNegocio),
        build: (context) => [
          _encabezado(nombreNegocio, hoy, validaHasta),
          pw.SizedBox(height: 14),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _bloque('Preparada por', [
                  if (perfil.operador.isNotEmpty) perfil.operador,
                  if (perfil.telefono.isNotEmpty) 'Tel. ${perfil.telefono}',
                  if (perfil.correo.isNotEmpty) perfil.correo,
                ]),
              ),
              pw.SizedBox(width: 20),
              pw.Expanded(
                child: _bloque('Preparada para', [
                  nombreCliente.isNotEmpty ? nombreCliente : 'Por confirmar',
                  lugar.isNotEmpty ? lugar : 'Dirección por confirmar',
                ]),
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          _titulo('Detalle de la cotización'),
          pw.SizedBox(height: 6),
          _tablaDetalle(reparto),
          pw.SizedBox(height: 14),
          _resumen(reparto),
          pw.SizedBox(height: 12),
          _cajaTotal(precioTotal),
          pw.SizedBox(height: 22),
          _condiciones(perfil),
        ],
      ),
    );

    return doc.save();
  }

  // ---------------------------------------------------------------
  // Cálculo
  // ---------------------------------------------------------------

  static double _redondear(double v) => (v * 100).roundToDouble() / 100;

  /// Reparte el margen de ganancia proporcionalmente entre todos los
  /// conceptos (mano de obra, distancia e insumos de cada servicio, y
  /// cada ayudante). El redondeo sobrante se le suma al concepto más
  /// grande para que todo sume exactamente [precioTotal].
  static _Reparto _repartir(
    List<ServicioCotizado> servicios,
    List<AyudanteCotizado> ayudantes,
    double precioTotal,
  ) {
    final costos = <double>[];
    for (final s in servicios) {
      final distancia = s.costoDistancia;
      final insumos = s.costoInsumos;
      final manoObra = s.precio - insumos - distancia;
      costos
        ..add(manoObra < 0 ? 0 : manoObra)
        ..add(distancia)
        ..add(insumos);
    }
    for (final a in ayudantes) {
      costos.add(a.costo);
    }

    final base = costos.fold<double>(0, (suma, c) => suma + c);
    final factor = base > 0 ? precioTotal / base : 1.0;
    final precios = costos.map((c) => _redondear(c * factor)).toList();

    if (base > 0 && precios.isNotEmpty) {
      final suma = precios.fold<double>(0, (a, b) => a + b);
      final diferencia = _redondear(precioTotal - suma);
      if (diferencia != 0) {
        var mayor = 0;
        for (var i = 1; i < costos.length; i++) {
          if (costos[i] > costos[mayor]) mayor = i;
        }
        precios[mayor] = _redondear(precios[mayor] + diferencia);
      }
    }

    final repartidos = <_ServicioRepartido>[];
    for (var i = 0; i < servicios.length; i++) {
      repartidos.add(_ServicioRepartido(
        servicios[i],
        precios[i * 3],
        precios[i * 3 + 1],
        precios[i * 3 + 2],
      ));
    }
    final ayudantesRepartidos = <AyudanteCotizado>[];
    for (var j = 0; j < ayudantes.length; j++) {
      ayudantesRepartidos.add(AyudanteCotizado(
        descripcion: ayudantes[j].descripcion,
        costo: precios[servicios.length * 3 + j],
      ));
    }
    return _Reparto(repartidos, ayudantesRepartidos);
  }

  // ---------------------------------------------------------------
  // Formato
  // ---------------------------------------------------------------

  static String _fecha(DateTime f) {
    final dia = f.day.toString().padLeft(2, '0');
    final mes = f.month.toString().padLeft(2, '0');
    return '$dia/$mes/${f.year}';
  }

  static String _dinero(double v) {
    final negativo = v < 0;
    final partes = v.abs().toStringAsFixed(2).split('.');
    final entero = partes[0];
    final miles = StringBuffer();
    for (var i = 0; i < entero.length; i++) {
      if (i > 0 && (entero.length - i) % 3 == 0) miles.write(',');
      miles.write(entero[i]);
    }
    return '${negativo ? "-" : ""}\$$miles.${partes[1]}';
  }

  static String _numero(double v) {
    return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
  }

  // ---------------------------------------------------------------
  // Piezas del documento
  // ---------------------------------------------------------------

  static pw.Widget _encabezado(
    String nombreNegocio,
    DateTime hoy,
    DateTime validaHasta,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(18),
      decoration: pw.BoxDecoration(
        color: _verdeOscuro,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  nombreNegocio,
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'COTIZACIÓN DE SERVICIOS',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: _verdeLima,
                  ),
                ),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'Fecha: ${_fecha(hoy)}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.white),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'Válida hasta: ${_fecha(validaHasta)}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _titulo(String texto) {
    return pw.Text(
      texto,
      style: pw.TextStyle(
        fontSize: 13,
        fontWeight: pw.FontWeight.bold,
        color: _verdeOscuro,
      ),
    );
  }

  static pw.Widget _bloque(String titulo, List<String> lineas) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _fondoSuave,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            titulo.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: _gris,
            ),
          ),
          pw.SizedBox(height: 5),
          ...lineas.map(
            (l) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Text(l, style: const pw.TextStyle(fontSize: 10.5)),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _celda(
    String texto, {
    bool negrita = false,
    PdfColor color = PdfColors.black,
    pw.Alignment alineacion = pw.Alignment.centerLeft,
    double tamano = 10,
    double izquierda = 8,
  }) {
    return pw.Container(
      alignment: alineacion,
      padding: pw.EdgeInsets.fromLTRB(izquierda, 7, 8, 7),
      child: pw.Text(
        texto,
        style: pw.TextStyle(
          fontSize: tamano,
          fontWeight: negrita ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color,
        ),
      ),
    );
  }

  static pw.TableBorder _bordeTabla() {
    return pw.TableBorder(
      bottom: pw.BorderSide(color: _linea, width: 0.8),
      horizontalInside: pw.BorderSide(color: _linea, width: 0.4),
    );
  }

  /// Fila que abre un grupo (un servicio, o los ayudantes) con su total.
  static pw.TableRow _filaGrupo(String concepto, String detalle, String importe) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: _fondoSuave),
      children: [
        _celda(concepto, negrita: true),
        _celda(detalle, color: _gris, tamano: 9.5),
        _celda(importe, negrita: true, alineacion: pw.Alignment.centerRight),
      ],
    );
  }

  /// Fila de un concepto dentro de un grupo, con sangría.
  static pw.TableRow _filaConcepto(String concepto, String detalle, String importe) {
    return pw.TableRow(
      children: [
        _celda(concepto, color: _gris, tamano: 9.5, izquierda: 22),
        _celda(detalle, color: _gris, tamano: 9.5),
        _celda(importe, tamano: 9.5, alineacion: pw.Alignment.centerRight),
      ],
    );
  }

  static pw.Widget _tablaDetalle(_Reparto reparto) {
    final filas = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _verdeOscuro),
        children: [
          _celda('Concepto', negrita: true, color: PdfColors.white, tamano: 9.5),
          _celda('Detalle', negrita: true, color: PdfColors.white, tamano: 9.5),
          _celda('Importe',
              negrita: true,
              color: PdfColors.white,
              tamano: 9.5,
              alineacion: pw.Alignment.centerRight),
        ],
      ),
    ];

    for (var i = 0; i < reparto.servicios.length; i++) {
      final r = reparto.servicios[i];
      final s = r.origen;
      final nombre = s.servicioNombre.isNotEmpty ? s.servicioNombre : 'Servicio';

      filas.add(_filaGrupo(
        '${i + 1}. $nombre',
        s.m2 > 0 ? '${_numero(s.m2)} m²' : '',
        _dinero(r.total),
      ));
      filas.add(_filaConcepto('Mano de obra del servicio', '', _dinero(r.manoObra)));
      if (s.km > 0 || r.distancia > 0) {
        filas.add(_filaConcepto(
          'Costo por distancia',
          s.km > 0 ? '${_numero(s.km)} km' : '',
          r.distancia > 0 ? _dinero(r.distancia) : 'Incluido',
        ));
      }
      if (r.insumos > 0) {
        filas.add(_filaConcepto('Costo de insumos', '', _dinero(r.insumos)));
      }
    }

    if (reparto.ayudantes.isNotEmpty) {
      filas.add(_filaGrupo('Ayudantes', '', _dinero(reparto.totalAyudantes)));
      for (final a in reparto.ayudantes) {
        filas.add(_filaConcepto(a.descripcion, '', _dinero(a.costo)));
      }
    }

    return pw.Table(
      border: _bordeTabla(),
      columnWidths: const {
        0: pw.FlexColumnWidth(5),
        1: pw.FlexColumnWidth(2.2),
        2: pw.FlexColumnWidth(1.8),
      },
      children: filas,
    );
  }

  /// Totales por tipo de concepto, para que el cliente vea de un vistazo
  /// en qué se va el precio.
  static pw.Widget _resumen(_Reparto reparto) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 270,
        padding: const pw.EdgeInsets.all(14),
        decoration: pw.BoxDecoration(
          color: _fondoSuave,
          border: pw.Border.all(color: _linea, width: 0.8),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'RESUMEN POR CONCEPTO',
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: _gris,
              ),
            ),
            pw.SizedBox(height: 6),
            _filaResumen('Mano de obra del servicio', _dinero(reparto.totalManoObra)),
            if (reparto.totalDistancia > 0)
              _filaResumen('Costo por distancia', _dinero(reparto.totalDistancia)),
            if (reparto.totalInsumos > 0)
              _filaResumen('Costo de insumos', _dinero(reparto.totalInsumos)),
            if (reparto.totalAyudantes > 0)
              _filaResumen('Ayudantes', _dinero(reparto.totalAyudantes)),
          ],
        ),
      ),
    );
  }

  static pw.Widget _filaResumen(String etiqueta, String valor) {
    const estilo = pw.TextStyle(fontSize: 10.5);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(etiqueta, style: estilo),
          pw.Text(valor, style: estilo),
        ],
      ),
    );
  }

  static pw.Widget _cajaTotal(double precioTotal) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 270,
        padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: pw.BoxDecoration(
          color: _verdeOscuro,
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              'TOTAL A PAGAR',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
            ),
            pw.Text(
              _dinero(precioTotal),
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
                color: _verdeLima,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _condiciones(BusinessProfile perfil) {
    final contacto = <String>[
      if (perfil.telefono.isNotEmpty) perfil.telefono,
      if (perfil.correo.isNotEmpty) perfil.correo,
    ];

    pw.Widget punto(String texto) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('-  ', style: const pw.TextStyle(fontSize: 9.5, color: _gris)),
            pw.Expanded(
              child: pw.Text(
                texto,
                style: const pw.TextStyle(fontSize: 9.5, color: _gris),
              ),
            ),
          ],
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _titulo('Condiciones'),
        pw.SizedBox(height: 6),
        punto('Cotización válida por $_diasValidez días a partir de la fecha de emisión.'),
        punto('Cada importe incluye los costos y gastos de ese concepto. El total a '
            'pagar es la suma de todos ellos.'),
        punto('Es un estimado y puede variar según las condiciones del lugar el '
            'día del trabajo.'),
        if (contacto.isNotEmpty)
          punto('Para aceptar esta cotización o resolver dudas, contáctanos: '
              '${contacto.join('  |  ')}.'),
      ],
    );
  }

  static pw.Widget _pie(pw.Context context, String nombreNegocio) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _linea, width: 0.6)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Gracias por confiar en $nombreNegocio',
            style: const pw.TextStyle(fontSize: 8.5, color: _gris),
          ),
          pw.Text(
            'Página ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8.5, color: _gris),
          ),
        ],
      ),
    );
  }
}