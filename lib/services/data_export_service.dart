import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Resultado de una exportación lista para compartir.
class ResultadoExportacion {
  /// Contenido del archivo .zip.
  final Uint8List zip;

  /// Nombre sugerido, ej. `green_garden_datos_2026-10-26.zip`.
  final String nombreArchivo;

  /// Cantidad de registros exportados por módulo (etiqueta -> filas).
  final Map<String, int> filasPorModulo;

  /// Módulos que no se pudieron descargar (la exportación quedó
  /// incompleta). Vacío si todo salió bien.
  final List<String> omitidos;

  const ResultadoExportacion({
    required this.zip,
    required this.nombreArchivo,
    required this.filasPorModulo,
    required this.omitidos,
  });
}

enum _Tipo { texto, fecha, dinero, numero }

/// Una columna "presentable": título en español, tipo de dato y de dónde
/// sale el valor (una clave de la fila o un cálculo).
class _Col {
  final String titulo;
  final _Tipo tipo;
  final String? clave;
  final Object? Function(Map<String, dynamic> fila)? calcular;

  _Col(this.titulo, this.tipo, {this.clave, this.calcular});
}

class _TablaExportable {
  final String tabla; // nombre de la tabla en Supabase
  final String archivo; // nombre base del CSV
  final String etiqueta; // nombre del módulo / de la hoja de Excel
  final List<_Col> columnas;
  final int ordenarPor; // índice de la columna por la que se ordena
  final bool descendente;

  _TablaExportable({
    required this.tabla,
    required this.archivo,
    required this.etiqueta,
    required this.columnas,
    this.ordenarPor = 0,
    this.descendente = false,
  });
}

class _Hoja {
  final String nombre;
  final List<_Col> columnas;
  final List<List<Object?>> filas;

  _Hoja(this.nombre, this.columnas, this.filas);
}

/// Genera un archivo .zip con todos los datos del usuario autenticado:
///
/// - `mis_datos.xlsx`: un libro de Excel con una hoja por módulo, con
///   columnas en español, anchos ajustados, filtros y formato de fechas
///   y montos. Es lo que el usuario abre para leer su información.
/// - `datos_completos.json`: todo, con su estructura original
///   (portabilidad completa).
/// - `csv/*.csv`: la misma información en texto plano.
/// - `LEEME.txt`: explicación breve del contenido.
///
/// Los datos se descargan directamente de Supabase (con paginación,
/// para no quedarse en el límite de filas por consulta). Las políticas
/// de seguridad (RLS) garantizan que solo se descarguen las filas del
/// propio usuario.
class DataExportService {
  static const int _tamanoPagina = 500;

  /// Nombres de los módulos exportables, en orden (para mostrarlos en
  /// la pantalla).
  static List<String> get etiquetas => _tablas.map((t) => t.etiqueta).toList();

  static final List<_TablaExportable> _tablas = [
    _TablaExportable(
      tabla: 'clientes',
      archivo: 'clientes',
      etiqueta: 'Clientes y trabajos',
      ordenarPor: 2,
      descendente: true,
      columnas: [
        _Col('Cliente', _Tipo.texto, clave: 'nombre'),
        _Col('Lugar', _Tipo.texto, clave: 'lugar'),
        _Col('Fecha del trabajo', _Tipo.fecha, clave: 'fecha'),
        _Col('Servicios', _Tipo.texto,
            calcular: (f) => _nombresDe(f['servicios']) ?? f['servicio_nombre']),
        _Col('Precio', _Tipo.dinero, clave: 'precio'),
        _Col('Estado', _Tipo.texto,
            calcular: (f) => _traducir(f['estado'], const {
                  'pendiente': 'Pendiente',
                  'realizado': 'Por cobrar',
                  'pagado': 'Pagado',
                })),
        _Col('Método de pago', _Tipo.texto,
            calcular: (f) => _traducir(f['metodo_pago'], const {
                  'yappy': 'Yappy',
                  'efectivo': 'Efectivo',
                })),
        _Col('Fecha de pago', _Tipo.fecha, clave: 'fecha_pago'),
        _Col('Recurrencia', _Tipo.texto,
            calcular: (f) => _traducir(f['recurrencia'], const {
                  'semanal': 'Semanal',
                  'mensual': 'Mensual',
                })),
      ],
    ),
    _TablaExportable(
      tabla: 'inventario',
      archivo: 'inventario',
      etiqueta: 'Inventario',
      columnas: [
        _Col('Artículo', _Tipo.texto, clave: 'nombre'),
        _Col('Categoría', _Tipo.texto,
            calcular: (f) => _traducir(f['categoria'], const {
                  'herramienta': 'Herramienta',
                  'insumo': 'Insumo',
                })),
        _Col('Cantidad', _Tipo.numero, clave: 'cantidad'),
        _Col('Unidad', _Tipo.texto, clave: 'unidad'),
        _Col('Stock mínimo', _Tipo.numero, clave: 'stock_minimo'),
        _Col('Notas', _Tipo.texto, clave: 'notas'),
        _Col('Última actualización', _Tipo.fecha, clave: 'actualizado_en'),
      ],
    ),
    _TablaExportable(
      tabla: 'finanzas',
      archivo: 'finanzas',
      etiqueta: 'Ingresos y gastos',
      descendente: true,
      columnas: [
        _Col('Fecha', _Tipo.fecha, clave: 'fecha'),
        _Col('Descripción', _Tipo.texto, clave: 'descripcion'),
        _Col('Tipo', _Tipo.texto,
            calcular: (f) => _traducir(f['tipo'], const {
                  'ingreso': 'Ingreso',
                  'egreso': 'Egreso',
                })),
        _Col('Categoría', _Tipo.texto, clave: 'categoria'),
        _Col('Monto', _Tipo.dinero, clave: 'monto'),
      ],
    ),
    _TablaExportable(
      tabla: 'servicios',
      archivo: 'servicios',
      etiqueta: 'Catálogo de servicios',
      columnas: [
        _Col('Servicio', _Tipo.texto, clave: 'nombre'),
        _Col('Descripción', _Tipo.texto, clave: 'descripcion'),
        _Col('Precio', _Tipo.dinero, clave: 'precio'),
        _Col('Insumos que consume', _Tipo.texto,
            calcular: (f) => _insumosDe(f['receta'])),
      ],
    ),
    _TablaExportable(
      tabla: 'tarifas_servicios',
      archivo: 'tarifas',
      etiqueta: 'Tarifas del cotizador',
      columnas: [
        _Col('Servicio', _Tipo.texto, clave: 'servicio_nombre'),
        _Col('m² mínimo', _Tipo.numero, clave: 'm2_min'),
        _Col('m² máximo', _Tipo.numero, clave: 'm2_max'),
        _Col('Precio base', _Tipo.dinero, clave: 'precio_base'),
        _Col('Precio por m² extra', _Tipo.dinero, clave: 'precio_por_m2_extra'),
        _Col('Km incluidos', _Tipo.numero, clave: 'km_base'),
        _Col('Precio por km extra', _Tipo.dinero, clave: 'precio_por_km_extra'),
      ],
    ),
    _TablaExportable(
      tabla: 'cotizaciones',
      archivo: 'cotizaciones',
      etiqueta: 'Cotizaciones',
      descendente: true,
      columnas: [
        _Col('Fecha', _Tipo.fecha, clave: 'creada_en'),
        _Col('Cliente', _Tipo.texto, clave: 'nombre_cliente'),
        _Col('Lugar', _Tipo.texto, clave: 'lugar'),
        _Col('Servicios', _Tipo.texto, calcular: (f) => _nombresDe(f['lineas'])),
        _Col('Costo total', _Tipo.dinero, clave: 'costo_total'),
        _Col('Ganancia deseada (%)', _Tipo.numero, clave: 'margen_rentabilidad'),
        _Col('Precio cotizado', _Tipo.dinero, clave: 'precio_total'),
        _Col('Estado', _Tipo.texto,
            calcular: (f) => _traducir(f['estado'], const {
                  'pendiente': 'Pendiente',
                  'agendada': 'Agendada',
                })),
      ],
    ),
  ];

  static Future<ResultadoExportacion> generar() async {
    final client = Supabase.instance.client;
    final datos = <String, List<Map<String, dynamic>>>{};
    final omitidos = <String>[];

    for (final t in _tablas) {
      try {
        datos[t.tabla] = await _descargar(client, t.tabla);
      } catch (e) {
        debugPrint('Error exportando ${t.tabla}: $e');
        omitidos.add(t.etiqueta);
      }
    }

    if (datos.isEmpty) {
      throw Exception('No se pudo descargar ningún dato.');
    }

    final ahora = DateTime.now();
    final fecha = _fechaIso(ahora);

    final archivos = <String, List<int>>{};
    final filasPorModulo = <String, int>{};
    final hojas = <_Hoja>[];

    for (final t in _tablas) {
      final crudas = datos[t.tabla];
      if (crudas == null) continue;
      filasPorModulo[t.etiqueta] = crudas.length;
      hojas.add(_Hoja(t.etiqueta, t.columnas, _prepararFilas(t, crudas)));
    }

    // 1) Libro de Excel (lo que el usuario abre para leer).
    archivos['mis_datos.xlsx'] = _construirXlsx(hojas, ahora);

    // 2) JSON completo (portabilidad).
    final json = const JsonEncoder.withIndent('  ').convert({
      'aplicacion': 'Green Garden',
      'generado_en': ahora.toIso8601String(),
      'datos': datos,
    });
    archivos['datos_completos.json'] = utf8.encode(json);

    // 3) CSV limpios (solo módulos con registros).
    for (var i = 0; i < hojas.length; i++) {
      final hoja = hojas[i];
      if (hoja.filas.isEmpty) continue;
      final archivo = _tablas.firstWhere((t) => t.etiqueta == hoja.nombre).archivo;
      archivos['csv/$archivo.csv'] = [
        0xEF, 0xBB, 0xBF, // BOM UTF-8: para que Excel lea bien los acentos.
        ...utf8.encode(_aCsv(hoja)),
      ];
    }

    // 4) Explicación.
    archivos['LEEME.txt'] = utf8.encode(_leeme(fecha, filasPorModulo, omitidos));

    return ResultadoExportacion(
      zip: _construirZip(archivos, ahora),
      nombreArchivo: 'green_garden_datos_$fecha.zip',
      filasPorModulo: filasPorModulo,
      omitidos: omitidos,
    );
  }

  // ---------------------------------------------------------------
  // Descarga
  // ---------------------------------------------------------------

  static Future<List<Map<String, dynamic>>> _descargar(
    SupabaseClient client,
    String tabla,
  ) async {
    final filas = <Map<String, dynamic>>[];
    var desde = 0;
    while (true) {
      final data = await client
          .from(tabla)
          .select()
          .order('id')
          .range(desde, desde + _tamanoPagina - 1);
      final lote = (data as List)
          .map((f) => Map<String, dynamic>.from(f as Map))
          .toList();
      for (final fila in lote) {
        fila.remove('user_id'); // dato interno, no es del usuario
      }
      filas.addAll(lote);
      if (lote.length < _tamanoPagina) break;
      desde += _tamanoPagina;
    }
    return filas;
  }

  // ---------------------------------------------------------------
  // Preparación de datos (traducción a algo legible)
  // ---------------------------------------------------------------

  static List<List<Object?>> _prepararFilas(
    _TablaExportable t,
    List<Map<String, dynamic>> crudas,
  ) {
    final filas = crudas
        .map((f) => t.columnas.map((c) => _valor(c, f)).toList())
        .toList();
    filas.sort((a, b) {
      final c = _comparar(a[t.ordenarPor], b[t.ordenarPor]);
      return t.descendente ? -c : c;
    });
    return filas;
  }

  static Object? _valor(_Col c, Map<String, dynamic> fila) {
    final crudo = c.calcular != null ? c.calcular!(fila) : fila[c.clave];
    if (c.tipo == _Tipo.texto) {
      if (crudo == null) return null;
      final s = crudo.toString();
      return s.isEmpty ? null : s;
    }
    if (c.tipo == _Tipo.fecha) {
      return _aFecha(crudo);
    }
    if (crudo is num) return crudo;
    if (crudo is String) return double.tryParse(crudo);
    return null;
  }

  static DateTime? _aFecha(dynamic valor) {
    if (valor == null) return null;
    final d = DateTime.tryParse(valor.toString());
    if (d == null) return null;
    final local = d.isUtc ? d.toLocal() : d;
    return DateTime(local.year, local.month, local.day);
  }

  static String? _traducir(dynamic valor, Map<String, String> tabla) {
    if (valor == null) return null;
    final s = valor.toString();
    return tabla[s] ?? s;
  }

  /// "Corte de césped + Poda de arbustos" a partir de una lista de
  /// objetos con `nombre` o `servicio_nombre`.
  static String? _nombresDe(dynamic lista) {
    if (lista is! List || lista.isEmpty) return null;
    final nombres = lista
        .map((e) {
          if (e is Map) {
            return (e['nombre'] ?? e['servicio_nombre'] ?? '').toString();
          }
          return e.toString();
        })
        .where((s) => s.isNotEmpty)
        .toList();
    return nombres.isEmpty ? null : nombres.join(' + ');
  }

  /// "Fertilizante (2), Semillas (1.5)" a partir de la receta de un
  /// servicio.
  static String? _insumosDe(dynamic lista) {
    if (lista is! List || lista.isEmpty) return null;
    final partes = lista.map((e) {
      if (e is! Map) return e.toString();
      final nombre = (e['inventario_nombre'] ?? '').toString();
      final cantidad = e['cantidad'];
      if (nombre.isEmpty) return '';
      if (cantidad is num) return '$nombre (${_numTexto(cantidad)})';
      return nombre;
    }).where((s) => s.isNotEmpty);
    final texto = partes.join(', ');
    return texto.isEmpty ? null : texto;
  }

  static int _comparar(Object? a, Object? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    if (a is DateTime && b is DateTime) return a.compareTo(b);
    if (a is num && b is num) return a.compareTo(b);
    return a.toString().toLowerCase().compareTo(b.toString().toLowerCase());
  }

  static String _numTexto(num n) {
    return n == n.roundToDouble() ? n.toInt().toString() : n.toString();
  }

  // ---------------------------------------------------------------
  // CSV
  // ---------------------------------------------------------------

  static String _aCsv(_Hoja hoja) {
    final buffer = StringBuffer()
      ..write(hoja.columnas.map((c) => _escapar(c.titulo)).join(','))
      ..write('\r\n');

    for (final fila in hoja.filas) {
      final celdas = <String>[];
      for (var i = 0; i < hoja.columnas.length; i++) {
        celdas.add(_escapar(_textoCsv(fila[i], hoja.columnas[i].tipo)));
      }
      buffer
        ..write(celdas.join(','))
        ..write('\r\n');
    }
    return buffer.toString();
  }

  static String _textoCsv(Object? valor, _Tipo tipo) {
    if (valor == null) return '';
    if (valor is DateTime) return _fechaIso(valor);
    if (valor is num) {
      return tipo == _Tipo.dinero ? valor.toStringAsFixed(2) : _numTexto(valor);
    }
    return valor.toString();
  }

  static String _escapar(String texto) {
    if (texto.contains(',') ||
        texto.contains('"') ||
        texto.contains('\n') ||
        texto.contains('\r')) {
      return '"${texto.replaceAll('"', '""')}"';
    }
    return texto;
  }

  // ---------------------------------------------------------------
  // LEEME
  // ---------------------------------------------------------------

  static String _leeme(
    String fecha,
    Map<String, int> filasPorModulo,
    List<String> omitidos,
  ) {
    final b = StringBuffer()
      ..writeln('GREEN GARDEN - EXPORTACION DE DATOS')
      ..writeln('Fecha de la exportacion: $fecha')
      ..writeln()
      ..writeln('Contenido de este archivo:')
      ..writeln('- mis_datos.xlsx: libro de Excel con una hoja por modulo. Es el')
      ..writeln('  archivo para leer y consultar tu informacion.')
      ..writeln('- datos_completos.json: todos tus datos con su estructura original.')
      ..writeln('  Es el formato recomendado para llevarlos a otro sistema.')
      ..writeln('- carpeta csv/: la misma informacion en texto plano (una hoja por modulo).')
      ..writeln()
      ..writeln('Registros exportados:');
    filasPorModulo.forEach((modulo, total) {
      b.writeln('- $modulo: $total');
    });
    if (omitidos.isNotEmpty) {
      b
        ..writeln()
        ..writeln('ATENCION: no se pudieron descargar estos modulos y NO estan incluidos:');
      for (final m in omitidos) {
        b.writeln('- $m');
      }
      b.writeln('Vuelve a exportar con buena conexion para obtenerlos.');
    }
    b
      ..writeln()
      ..writeln('Notas:')
      ..writeln('- El Excel y los CSV muestran las columnas mas utiles; el JSON contiene')
      ..writeln('  absolutamente todos los campos.')
      ..writeln('- Los trabajos o cambios hechos sin conexion y todavia sin sincronizar')
      ..writeln('  no aparecen aqui. Sincroniza antes de exportar.')
      ..writeln('- Los datos de tu negocio (nombre, logotipo) y las facturas PDF')
      ..writeln('  no forman parte de esta exportacion.');
    return b.toString();
  }

  static String _fechaIso(DateTime f) {
    final m = f.month.toString().padLeft(2, '0');
    final d = f.day.toString().padLeft(2, '0');
    return '${f.year}-$m-$d';
  }

  // ---------------------------------------------------------------
  // XLSX (libro de Excel, sin dependencias externas)
  // ---------------------------------------------------------------

  // Índices de estilo (ver _estilosXml).
  static const int _estEncabezado = 1;
  static const int _estTexto = 2;
  static const int _estFecha = 3;
  static const int _estDinero = 4;
  static const int _estNumero = 5;

  static final RegExp _caracteresInvalidosXml =
      RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]');

  static String _xml(String s) {
    return s
        .replaceAll(_caracteresInvalidosXml, '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  /// A, B, ... Z, AA, AB ...
  static String _letra(int indice) {
    var n = indice + 1;
    var s = '';
    while (n > 0) {
      final r = (n - 1) % 26;
      s = String.fromCharCode(65 + r) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  /// Días desde el 30/12/1899 (el "cero" de las fechas de Excel).
  static int _serieExcel(DateTime d) {
    return DateTime.utc(d.year, d.month, d.day)
        .difference(DateTime.utc(1899, 12, 30))
        .inDays;
  }

  static String _nombreHoja(String nombre) {
    var limpio = nombre.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
    if (limpio.length > 31) limpio = limpio.substring(0, 31);
    return limpio.isEmpty ? 'Hoja' : limpio;
  }

  static double _anchoColumna(_Hoja hoja, int i) {
    final col = hoja.columnas[i];
    if (col.tipo == _Tipo.fecha) return 14;
    if (col.tipo == _Tipo.dinero) return 15;
    var mayor = col.titulo.length;
    for (final fila in hoja.filas) {
      final v = fila[i];
      if (v == null) continue;
      final texto = v is num ? _numTexto(v) : v.toString();
      // Con varias líneas, cuenta solo la más larga.
      for (final linea in texto.split('\n')) {
        if (linea.length > mayor) mayor = linea.length;
      }
    }
    final ancho = (mayor + 3).toDouble();
    if (ancho < 12) return 12;
    if (ancho > 48) return 48;
    return ancho;
  }

  static String _hojaXml(_Hoja hoja) {
    final nCols = hoja.columnas.length;
    final ultimaFila = hoja.filas.length + 1;
    final ultimaColumna = _letra(nCols - 1);

    final b = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
      ..write('<sheetViews><sheetView workbookViewId="0">')
      ..write('<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>')
      ..write('</sheetView></sheetViews>')
      ..write('<sheetFormatPr defaultRowHeight="15"/>')
      ..write('<cols>');
    for (var i = 0; i < nCols; i++) {
      b.write('<col min="${i + 1}" max="${i + 1}" width="${_anchoColumna(hoja, i)}" customWidth="1"/>');
    }
    b.write('</cols><sheetData>');

    // Encabezado.
    b.write('<row r="1" ht="30" customHeight="1">');
    for (var i = 0; i < nCols; i++) {
      b.write('<c r="${_letra(i)}1" s="$_estEncabezado" t="inlineStr">'
          '<is><t>${_xml(hoja.columnas[i].titulo)}</t></is></c>');
    }
    b.write('</row>');

    // Datos.
    for (var f = 0; f < hoja.filas.length; f++) {
      final fila = hoja.filas[f];
      final r = f + 2;
      b.write('<row r="$r">');
      for (var i = 0; i < nCols; i++) {
        final ref = '${_letra(i)}$r';
        final valor = fila[i];
        final tipo = hoja.columnas[i].tipo;
        if (valor == null) {
          b.write('<c r="$ref" s="$_estTexto"/>');
        } else if (valor is DateTime) {
          b.write('<c r="$ref" s="$_estFecha"><v>${_serieExcel(valor)}</v></c>');
        } else if (valor is num) {
          final estilo = tipo == _Tipo.dinero ? _estDinero : _estNumero;
          b.write('<c r="$ref" s="$estilo"><v>$valor</v></c>');
        } else {
          b.write('<c r="$ref" s="$_estTexto" t="inlineStr">'
              '<is><t xml:space="preserve">${_xml(valor.toString())}</t></is></c>');
        }
      }
      b.write('</row>');
    }

    b
      ..write('</sheetData>')
      ..write('<autoFilter ref="A1:$ultimaColumna$ultimaFila"/>')
      ..write('</worksheet>');
    return b.toString();
  }

  static const String _estilosXml = r'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<numFmts count="2"><numFmt numFmtId="164" formatCode="&quot;$&quot;#,##0.00"/><numFmt numFmtId="165" formatCode="dd/mm/yyyy"/></numFmts>
<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts>
<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF1B4D2E"/><bgColor indexed="64"/></patternFill></fill></fills>
<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left style="thin"><color rgb="FFD0D0D0"/></left><right style="thin"><color rgb="FFD0D0D0"/></right><top style="thin"><color rgb="FFD0D0D0"/></top><bottom style="thin"><color rgb="FFD0D0D0"/></bottom><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="6">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>
<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
<xf numFmtId="165" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="top"/></xf>
<xf numFmtId="164" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1" applyAlignment="1"><alignment vertical="top"/></xf>
<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment horizontal="right" vertical="top"/></xf>
</cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>''';

  static Uint8List _construirXlsx(List<_Hoja> hojas, DateTime ahora) {
    const ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
    const nsRel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
    const nsPaquete = 'http://schemas.openxmlformats.org/package/2006/relationships';
    const cabecera = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';

    final tipos = StringBuffer()
      ..write(cabecera)
      ..write('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">')
      ..write('<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>')
      ..write('<Default Extension="xml" ContentType="application/xml"/>')
      ..write('<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>')
      ..write('<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>');
    for (var i = 0; i < hojas.length; i++) {
      tipos.write('<Override PartName="/xl/worksheets/sheet${i + 1}.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
    }
    tipos.write('</Types>');

    final relRaiz = '$cabecera<Relationships xmlns="$nsPaquete">'
        '<Relationship Id="rId1" '
        'Type="$nsRel/officeDocument" '
        'Target="xl/workbook.xml"/></Relationships>';

    final libro = StringBuffer()
      ..write(cabecera)
      ..write('<workbook xmlns="$ns" xmlns:r="$nsRel"><sheets>');
    final relLibro = StringBuffer()
      ..write(cabecera)
      ..write('<Relationships xmlns="$nsPaquete">');
    for (var i = 0; i < hojas.length; i++) {
      libro.write('<sheet name="${_xml(_nombreHoja(hojas[i].nombre))}" '
          'sheetId="${i + 1}" r:id="rId${i + 1}"/>');
      relLibro.write('<Relationship Id="rId${i + 1}" '
          'Type="$nsRel/worksheet" '
          'Target="worksheets/sheet${i + 1}.xml"/>');
    }
    libro.write('</sheets></workbook>');
    relLibro.write('<Relationship Id="rId${hojas.length + 1}" '
        'Type="$nsRel/styles" Target="styles.xml"/></Relationships>');

    final archivos = <String, List<int>>{
      '[Content_Types].xml': utf8.encode(tipos.toString()),
      '_rels/.rels': utf8.encode(relRaiz),
      'xl/workbook.xml': utf8.encode(libro.toString()),
      'xl/_rels/workbook.xml.rels': utf8.encode(relLibro.toString()),
      'xl/styles.xml': utf8.encode(_estilosXml),
    };
    for (var i = 0; i < hojas.length; i++) {
      archivos['xl/worksheets/sheet${i + 1}.xml'] = utf8.encode(_hojaXml(hojas[i]));
    }
    return _construirZip(archivos, ahora);
  }

  // ---------------------------------------------------------------
  // ZIP (sin compresión, sin dependencias externas)
  // ---------------------------------------------------------------

  static final List<int> _tablaCrc = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
    return c;
  });

  static int _crc32(List<int> datos) {
    var c = 0xFFFFFFFF;
    for (final byte in datos) {
      c = _tablaCrc[(c ^ byte) & 0xFF] ^ (c >> 8);
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  static void _u16(BytesBuilder b, int v) {
    b.addByte(v & 0xFF);
    b.addByte((v >> 8) & 0xFF);
  }

  static void _u32(BytesBuilder b, int v) {
    _u16(b, v & 0xFFFF);
    _u16(b, (v >> 16) & 0xFFFF);
  }

  static Uint8List _construirZip(Map<String, List<int>> archivos, DateTime ahora) {
    final hora = (ahora.hour << 11) | (ahora.minute << 5) | (ahora.second ~/ 2);
    final fecha = ((ahora.year - 1980) << 9) | (ahora.month << 5) | ahora.day;

    final cuerpo = BytesBuilder();
    final directorio = BytesBuilder();

    archivos.forEach((nombre, datos) {
      final nombreBytes = utf8.encode(nombre);
      final crc = _crc32(datos);
      final posicion = cuerpo.length;

      // Cabecera local del archivo.
      _u32(cuerpo, 0x04034b50);
      _u16(cuerpo, 20); // versión necesaria
      _u16(cuerpo, 0x0800); // nombres en UTF-8
      _u16(cuerpo, 0); // sin compresión
      _u16(cuerpo, hora);
      _u16(cuerpo, fecha);
      _u32(cuerpo, crc);
      _u32(cuerpo, datos.length);
      _u32(cuerpo, datos.length);
      _u16(cuerpo, nombreBytes.length);
      _u16(cuerpo, 0);
      cuerpo.add(nombreBytes);
      cuerpo.add(datos);

      // Entrada en el directorio central.
      _u32(directorio, 0x02014b50);
      _u16(directorio, 20);
      _u16(directorio, 20);
      _u16(directorio, 0x0800);
      _u16(directorio, 0);
      _u16(directorio, hora);
      _u16(directorio, fecha);
      _u32(directorio, crc);
      _u32(directorio, datos.length);
      _u32(directorio, datos.length);
      _u16(directorio, nombreBytes.length);
      _u16(directorio, 0);
      _u16(directorio, 0);
      _u16(directorio, 0);
      _u16(directorio, 0);
      _u32(directorio, 0);
      _u32(directorio, posicion);
      directorio.add(nombreBytes);
    });

    final inicioDirectorio = cuerpo.length;
    final bytesDirectorio = directorio.toBytes();
    cuerpo.add(bytesDirectorio);

    // Fin del directorio central.
    _u32(cuerpo, 0x06054b50);
    _u16(cuerpo, 0);
    _u16(cuerpo, 0);
    _u16(cuerpo, archivos.length);
    _u16(cuerpo, archivos.length);
    _u32(cuerpo, bytesDirectorio.length);
    _u32(cuerpo, inicioDirectorio);
    _u16(cuerpo, 0);

    return cuerpo.toBytes();
  }
}