import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../models/cotizacion.dart';
import '../models/customer.dart';
import '../models/tarifa_servicio.dart';
import '../pdf/quote_pdf.dart';
import '../services/business_profile_service.dart';
import '../services/cotizacion_service.dart';
import '../services/customer_service.dart';
import '../services/finance_service.dart';
import '../services/inventory_service.dart';
import '../services/invoice_service.dart';
import '../services/service_catalog_service.dart';
import '../services/tarifa_service.dart';
import '../theme/app_theme.dart';
import '../widgets/theme_toggle_button.dart';
import 'customer_screen.dart';
import 'tarifas_screen.dart';

/// Pantalla del Cotizador: calcula presupuestos para agendar clientes
/// tomando en cuenta el tamaño del trabajo (m²), la distancia a
/// recorrer (km), el costo de insumos y un margen de rentabilidad
/// deseado, usando las tarifas configuradas en [TarifasScreen]. Cada
/// cotización puede tener varios servicios, se puede guardar para
/// retomarla después, y si el cliente la acepta, un botón la manda
/// directo al formulario de "Nuevo cliente" ya con todo prellenado.
class CotizadorScreen extends StatefulWidget {
  final TarifaService tarifaService;
  final CotizacionService cotizacionService;
  final ServiceCatalogService serviceCatalogService;
  final CustomerService customerService;
  final FinanceService financeService;
  final BusinessProfileService businessProfileService;
  final InvoiceService invoiceService;
  final InventoryService inventoryService;

  const CotizadorScreen({
    super.key,
    required this.tarifaService,
    required this.cotizacionService,
    required this.serviceCatalogService,
    required this.customerService,
    required this.financeService,
    required this.businessProfileService,
    required this.invoiceService,
    required this.inventoryService,
  });

  @override
  State<CotizadorScreen> createState() => _CotizadorScreenState();
}

class _CotizadorScreenState extends State<CotizadorScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final GlobalKey<_CalculadoraFormState> _formKey = GlobalKey<_CalculadoraFormState>();

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

  void _cargarEnCalculadora(Cotizacion cotizacion) {
    _formKey.currentState?.cargarCotizacion(cotizacion);
    _tabController.animateTo(0);
  }

  void _confirmarEliminar(Cotizacion cotizacion) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar cotización'),
        content: Text(
          '¿Deseas eliminar la cotización de '
          '"${cotizacion.nombreCliente.isNotEmpty ? cotizacion.nombreCliente : 'este trabajo'}"?',
        ),
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
                await widget.cotizacionService.eliminarCotizacion(cotizacion.id);
                navigator.pop();
              } catch (e) {
                mensajero.showSnackBar(
                  const SnackBar(content: Text('No se pudo eliminar. Intenta de nuevo.')),
                );
              }
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  String _formatearFecha(DateTime fecha) {
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    return '$dia/$mes/${fecha.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cotizador'),
        actions: [
          const ThemeToggleButton(),
          IconButton(
            tooltip: 'Tarifas',
            icon: const Icon(Icons.tune),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TarifasScreen(
                    service: widget.tarifaService,
                    serviceCatalog: widget.serviceCatalogService,
                  ),
                ),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.limeGreen,
          indicatorWeight: 3,
          labelColor: Theme.of(context).appBarTheme.foregroundColor,
          unselectedLabelColor:
              Theme.of(context).appBarTheme.foregroundColor?.withValues(alpha: 0.65),
          tabs: const [
            Tab(text: 'Cotizador'),
            Tab(text: 'Guardadas'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _CalculadoraForm(
            key: _formKey,
            tarifaService: widget.tarifaService,
            cotizacionService: widget.cotizacionService,
            customerService: widget.customerService,
            serviceCatalogService: widget.serviceCatalogService,
            financeService: widget.financeService,
            businessProfileService: widget.businessProfileService,
            invoiceService: widget.invoiceService,
            inventoryService: widget.inventoryService,
          ),
          ListenableBuilder(
            listenable: widget.cotizacionService,
            builder: (context, _) {
              final cotizaciones = widget.cotizacionService.cotizaciones;
              if (cotizaciones.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No hay cotizaciones guardadas todavía. Calcula una en '
                      'la pestaña "Cotizador" y guárdala para retomarla '
                      'después.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                itemCount: cotizaciones.length,
                itemBuilder: (context, index) {
                  final cotizacion = cotizaciones[index];
                  final esAgendada = cotizacion.estado == EstadoCotizacion.agendada;
                  final colorEstado = esAgendada ? AppColors.darkGreen : Colors.orange;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      onTap: () => _cargarEnCalculadora(cotizacion),
                      leading: CircleAvatar(
                        backgroundColor: colorEstado.withValues(alpha: 0.2),
                        child: Icon(
                          esAgendada ? Icons.event_available : Icons.request_quote_outlined,
                          color: colorEstado,
                        ),
                      ),
                      title: Text(
                        cotizacion.nombreCliente.isNotEmpty
                            ? cotizacion.nombreCliente
                            : 'Sin nombre de cliente',
                      ),
                      subtitle: Text(
                        '${cotizacion.servicios.length} servicio(s) · '
                        '${_formatearFecha(cotizacion.creadaEn)}'
                        '${cotizacion.lugar.isNotEmpty ? '\n${cotizacion.lugar}' : ''}',
                      ),
                      isThreeLine: cotizacion.lugar.isNotEmpty,
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '\$${cotizacion.precioTotal.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                cotizacion.estado.label,
                                style: TextStyle(fontSize: 12, color: colorEstado),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => _confirmarEliminar(cotizacion),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Una fila del formulario: un servicio dentro de la cotización en
/// edición. Si [tarifaId] es null, la fila está en modo "Personalizado"
/// y la mano de obra + transporte se escribe a mano en vez de
/// calcularse con una tarifa.
class _FilaCotizacion {
  String? tarifaId;
  final TextEditingController nombreCtrl;
  final TextEditingController m2Ctrl;
  final TextEditingController kmCtrl;
  final TextEditingController manoObraManualCtrl;
  final TextEditingController insumosCtrl;

  _FilaCotizacion({
    this.tarifaId,
    String nombreInicial = '',
    String m2Inicial = '',
    String kmInicial = '',
    String manoObraManualInicial = '',
    String insumosInicial = '',
  })  : nombreCtrl = TextEditingController(text: nombreInicial),
        m2Ctrl = TextEditingController(text: m2Inicial),
        kmCtrl = TextEditingController(text: kmInicial),
        manoObraManualCtrl = TextEditingController(text: manoObraManualInicial),
        insumosCtrl = TextEditingController(text: insumosInicial);

  void dispose() {
    nombreCtrl.dispose();
    m2Ctrl.dispose();
    kmCtrl.dispose();
    manoObraManualCtrl.dispose();
    insumosCtrl.dispose();
  }
}

/// Un ayudante contratado para el trabajo. Va aparte de los servicios.
class _FilaAyudante {
  final TextEditingController descripcionCtrl;
  final TextEditingController costoCtrl;

  _FilaAyudante({String descripcionInicial = '', String costoInicial = ''})
      : descripcionCtrl = TextEditingController(text: descripcionInicial),
        costoCtrl = TextEditingController(text: costoInicial);

  void dispose() {
    descripcionCtrl.dispose();
    costoCtrl.dispose();
  }
}

/// El formulario de cálculo en sí: lista de servicios a cotizar, el
/// margen de rentabilidad, y el desglose de costo/precio en vivo.
/// Expone [cargarCotizacion] para que la pantalla contenedora pueda
/// retomar una cotización guardada desde la pestaña "Guardadas".
class _CalculadoraForm extends StatefulWidget {
  final TarifaService tarifaService;
  final CotizacionService cotizacionService;
  final CustomerService customerService;
  final ServiceCatalogService serviceCatalogService;
  final FinanceService financeService;
  final BusinessProfileService businessProfileService;
  final InvoiceService invoiceService;
  final InventoryService inventoryService;

  const _CalculadoraForm({
    super.key,
    required this.tarifaService,
    required this.cotizacionService,
    required this.customerService,
    required this.serviceCatalogService,
    required this.financeService,
    required this.businessProfileService,
    required this.invoiceService,
    required this.inventoryService,
  });

  @override
  State<_CalculadoraForm> createState() => _CalculadoraFormState();
}

class _CalculadoraFormState extends State<_CalculadoraForm> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nombreClienteCtrl = TextEditingController();
  final TextEditingController _lugarCtrl = TextEditingController();
  final TextEditingController _margenCtrl = TextEditingController(text: '30');
  final List<_FilaCotizacion> _filas = [];
  final List<_FilaAyudante> _ayudantes = [];
  String? _cotizacionIdActual;
  bool _guardando = false;
  bool _agendando = false;

  @override
  void initState() {
    super.initState();
    _margenCtrl.addListener(_onCambio);
    _agregarFila();
  }

  @override
  void dispose() {
    _nombreClienteCtrl.dispose();
    _lugarCtrl.dispose();
    _margenCtrl.dispose();
    for (final fila in _filas) {
      fila.dispose();
    }
    for (final ayudante in _ayudantes) {
      ayudante.dispose();
    }
    super.dispose();
  }

  void _onCambio() => setState(() {});

  void _agregarFila({
    String? tarifaId,
    String nombreInicial = '',
    String m2Inicial = '',
    String kmInicial = '',
    String manoObraManualInicial = '',
    String insumosInicial = '',
  }) {
    final fila = _FilaCotizacion(
      tarifaId: tarifaId,
      nombreInicial: nombreInicial,
      m2Inicial: m2Inicial,
      kmInicial: kmInicial,
      manoObraManualInicial: manoObraManualInicial,
      insumosInicial: insumosInicial,
    );
    for (final ctrl in [
      fila.m2Ctrl,
      fila.kmCtrl,
      fila.manoObraManualCtrl,
      fila.insumosCtrl,
    ]) {
      ctrl.addListener(_onCambio);
    }
    setState(() => _filas.add(fila));
  }

  void _eliminarFila(int index) {
    if (_filas.length <= 1) return; // siempre queda al menos 1 fila
    setState(() {
      final fila = _filas.removeAt(index);
      fila.dispose();
    });
  }

  void _agregarAyudante({String descripcion = '', String costo = ''}) {
    final ayudante = _FilaAyudante(descripcionInicial: descripcion, costoInicial: costo);
    ayudante.costoCtrl.addListener(_onCambio);
    setState(() => _ayudantes.add(ayudante));
  }

  void _eliminarAyudante(int index) {
    setState(() {
      final ayudante = _ayudantes.removeAt(index);
      ayudante.dispose();
    });
  }

  /// Al elegir una tarifa del dropdown en una fila (o "Personalizado"),
  /// actualiza el nombre sugerido y limpia el precio manual si aplica.
  void _seleccionarTarifaEnFila(int index, TarifaServicio? tarifa) {
    setState(() {
      final fila = _filas[index];
      fila.tarifaId = tarifa?.id;
      if (tarifa != null) {
        fila.nombreCtrl.text = tarifa.servicioNombre;
      } else {
        fila.nombreCtrl.clear();
        fila.manoObraManualCtrl.clear();
      }
    });
  }

  /// Costo de mano de obra + transporte + insumos de una fila (sin
  /// margen todavía).
  double _subtotalDeFila(_FilaCotizacion fila) {
    final insumos = double.tryParse(fila.insumosCtrl.text.trim()) ?? 0;
    if (fila.tarifaId != null) {
      final tarifa = widget.tarifaService.buscarPorId(fila.tarifaId);
      if (tarifa == null) return insumos;
      final m2 = double.tryParse(fila.m2Ctrl.text.trim()) ?? 0;
      final km = double.tryParse(fila.kmCtrl.text.trim()) ?? 0;
      return tarifa.calcularCosto(m2: m2, km: km) + insumos;
    }
    final manual = double.tryParse(fila.manoObraManualCtrl.text.trim()) ?? 0;
    return manual + insumos;
  }

  /// Parte del costo de una fila que corresponde a la distancia: los km
  /// que se pasan del radio base de la tarifa, por su precio por km extra.
  double _distanciaDeFila(_FilaCotizacion fila) {
    if (fila.tarifaId == null) return 0;
    final tarifa = widget.tarifaService.buscarPorId(fila.tarifaId);
    if (tarifa == null) return 0;
    final km = double.tryParse(fila.kmCtrl.text.trim()) ?? 0;
    return km > tarifa.kmBase ? (km - tarifa.kmBase) * tarifa.precioPorKmExtra : 0;
  }

  /// Suma de lo que se pagará a los ayudantes.
  double get _costoAyudantes => _ayudantes.fold<double>(
        0,
        (suma, a) => suma + (double.tryParse(a.costoCtrl.text.trim()) ?? 0),
      );

  /// Costo total: servicios + ayudantes (sin margen todavía).
  double get _costoTotal =>
      _filas.fold<double>(0, (suma, fila) => suma + _subtotalDeFila(fila)) +
      _costoAyudantes;

  double get _margen => double.tryParse(_margenCtrl.text.trim()) ?? 0;

  /// Precio final ya con el margen de rentabilidad aplicado sobre el
  /// precio (no un simple recargo sobre el costo): si el margen es
  /// 30%, la ganancia es el 30% de lo que se le cobra al cliente.
  double get _precioFinal {
    final margen = _margen.clamp(0, 99);
    if (margen <= 0) return _costoTotal;
    return _costoTotal / (1 - margen / 100);
  }

  /// Carga una cotización guardada dentro del formulario para
  /// retomarla (editarla o agendarla), reemplazando lo que hubiera.
  void cargarCotizacion(Cotizacion cotizacion) {
    for (final fila in _filas) {
      fila.dispose();
    }
    for (final ayudante in _ayudantes) {
      ayudante.dispose();
    }
    setState(() {
      _cotizacionIdActual = cotizacion.id;
      _nombreClienteCtrl.text = cotizacion.nombreCliente;
      _lugarCtrl.text = cotizacion.lugar;
      _margenCtrl.text = cotizacion.margenRentabilidad.toString();
      _filas.clear();
      _ayudantes.clear();
    });
    for (final linea in cotizacion.servicios) {
      // Si la tarifa usada en su momento ya no existe (se borró desde
      // "Tarifas"), la fila cae a modo "Personalizado" con el precio
      // que ya tenía, en vez de referenciar un id inexistente.
      final tarifaVigente = widget.tarifaService.buscarPorId(linea.tarifaId);
      _agregarFila(
        tarifaId: tarifaVigente?.id,
        nombreInicial: linea.servicioNombre,
        m2Inicial: linea.m2 > 0 ? linea.m2.toString() : '',
        kmInicial: linea.km > 0 ? linea.km.toString() : '',
        manoObraManualInicial:
            tarifaVigente == null
                ? (linea.precio - linea.costoInsumos - linea.costoAyudantes).toString()
                : '',
        insumosInicial: linea.costoInsumos > 0 ? linea.costoInsumos.toString() : '',
      );
    }
    for (final ayudante in cotizacion.ayudantes) {
      _agregarAyudante(
        descripcion: ayudante.descripcion,
        costo: ayudante.costo.toString(),
      );
    }
    // Cotizaciones guardadas con una versión anterior, donde el pago del
    // ayudante iba dentro del servicio: ahora aparece como ayudante aparte.
    for (final linea in cotizacion.servicios) {
      if (linea.costoAyudantes > 0) {
        _agregarAyudante(
          descripcion: 'Ayudante',
          costo: linea.costoAyudantes.toString(),
        );
      }
    }
    if (_filas.isEmpty) _agregarFila();
  }

  List<ServicioCotizado> _construirLineas() {
    return _filas.map((fila) {
      final tarifa = widget.tarifaService.buscarPorId(fila.tarifaId);
      final nombre = tarifa?.servicioNombre ?? fila.nombreCtrl.text.trim();
      return ServicioCotizado(
        tarifaId: fila.tarifaId,
        servicioNombre: nombre.isEmpty ? 'Servicio' : nombre,
        m2: tarifa != null ? (double.tryParse(fila.m2Ctrl.text.trim()) ?? 0) : 0,
        km: tarifa != null ? (double.tryParse(fila.kmCtrl.text.trim()) ?? 0) : 0,
        costoInsumos: double.tryParse(fila.insumosCtrl.text.trim()) ?? 0,
        costoDistancia: _distanciaDeFila(fila),
        precio: _subtotalDeFila(fila),
      );
    }).toList();
  }

  /// Ayudantes con pago mayor a cero (los renglones vacíos se ignoran).
  List<AyudanteCotizado> _construirAyudantes() {
    final lista = <AyudanteCotizado>[];
    for (final a in _ayudantes) {
      final costo = double.tryParse(a.costoCtrl.text.trim()) ?? 0;
      if (costo <= 0) continue;
      final descripcion = a.descripcionCtrl.text.trim();
      lista.add(AyudanteCotizado(
        descripcion: descripcion.isEmpty ? 'Ayudante' : descripcion,
        costo: costo,
      ));
    }
    return lista;
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      final lineas = _construirLineas();
      if (_cotizacionIdActual != null) {
        await widget.cotizacionService.actualizarCotizacion(
          _cotizacionIdActual!,
          nombreCliente: _nombreClienteCtrl.text.trim(),
          lugar: _lugarCtrl.text.trim(),
          servicios: lineas,
          margenRentabilidad: _margen,
          costoTotal: _costoTotal,
          precioTotal: _precioFinal,
          ayudantes: _construirAyudantes(),
        );
      } else {
        final creada = await widget.cotizacionService.guardarCotizacion(
          nombreCliente: _nombreClienteCtrl.text.trim(),
          lugar: _lugarCtrl.text.trim(),
          servicios: lineas,
          margenRentabilidad: _margen,
          costoTotal: _costoTotal,
          precioTotal: _precioFinal,
          ayudantes: _construirAyudantes(),
        );
        _cotizacionIdActual = creada.id;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cotización guardada')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo guardar. Intenta de nuevo.')),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  /// Reparte el precio final (ya con margen) proporcionalmente entre
  /// las líneas según su peso en el costo, para que el cliente quede
  /// agendado con el mismo desglose de servicios que se le cotizó.
  List<ServicioAgendado> _serviciosParaAgendar(List<ServicioCotizado> lineas) {
    if (lineas.isEmpty) return [];
    final precioFinal = _precioFinal;
    // Los ayudantes no son un servicio: su costo ya está dentro del precio
    // final, así que se reparte entre los servicios según su peso.
    final base = lineas.fold<double>(0, (suma, l) => suma + l.precio);
    if (base <= 0) {
      final porLinea = precioFinal / lineas.length;
      return lineas
          .map((l) => ServicioAgendado(nombre: l.servicioNombre, precio: porLinea))
          .toList();
    }
    return lineas
        .map(
          (l) => ServicioAgendado(
            nombre: l.servicioNombre,
            precio: (l.precio / base) * precioFinal,
          ),
        )
        .toList();
  }

  bool _compartiendo = false;

  Future<void> _compartirCotizacion() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _compartiendo = true);
    try {
      final lineas = _construirLineas();
      final bytes = await QuotePdf.generar(
        nombreCliente: _nombreClienteCtrl.text.trim(),
        lugar: _lugarCtrl.text.trim(),
        servicios: lineas,
        ayudantes: _construirAyudantes(),
        precioTotal: _precioFinal,
        perfil: widget.businessProfileService.perfil,
      );
      final ahora = DateTime.now();
      final fecha = '${ahora.year}-'
          '${ahora.month.toString().padLeft(2, '0')}-'
          '${ahora.day.toString().padLeft(2, '0')}_'
          '${ahora.hour.toString().padLeft(2, '0')}'
          '${ahora.minute.toString().padLeft(2, '0')}';
      // Abre el selector nativo de apps (WhatsApp, correo, etc.) con el
      // PDF de la cotización listo para enviar.
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'cotizacion_$fecha.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo generar la cotización. Intenta de nuevo.')),
        );
      }
    } finally {
      if (mounted) setState(() => _compartiendo = false);
    }
  }

  Future<void> _agendar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_filas.isEmpty) return;

    setState(() => _agendando = true);
    try {
      final lineas = _construirLineas();
      String id;
      if (_cotizacionIdActual != null) {
        await widget.cotizacionService.actualizarCotizacion(
          _cotizacionIdActual!,
          nombreCliente: _nombreClienteCtrl.text.trim(),
          lugar: _lugarCtrl.text.trim(),
          servicios: lineas,
          margenRentabilidad: _margen,
          costoTotal: _costoTotal,
          precioTotal: _precioFinal,
          ayudantes: _construirAyudantes(),
        );
        id = _cotizacionIdActual!;
      } else {
        final creada = await widget.cotizacionService.guardarCotizacion(
          nombreCliente: _nombreClienteCtrl.text.trim(),
          lugar: _lugarCtrl.text.trim(),
          servicios: lineas,
          margenRentabilidad: _margen,
          costoTotal: _costoTotal,
          precioTotal: _precioFinal,
          ayudantes: _construirAyudantes(),
        );
        id = creada.id;
        _cotizacionIdActual = id;
      }
      await widget.cotizacionService.marcarAgendada(id);

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CustomerScreen(
            service: widget.customerService,
            serviceCatalog: widget.serviceCatalogService,
            financeService: widget.financeService,
            businessProfileService: widget.businessProfileService,
            invoiceService: widget.invoiceService,
            inventoryService: widget.inventoryService,
            prellenado: ClientePrellenado(
              nombre: _nombreClienteCtrl.text.trim(),
              lugar: _lugarCtrl.text.trim(),
              servicios: _serviciosParaAgendar(lineas),
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo agendar. Intenta de nuevo.')),
        );
      }
    } finally {
      if (mounted) setState(() => _agendando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _nombreClienteCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre del cliente',
                helperText: 'Puedes dejarlo vacío y completarlo después.',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _lugarCtrl,
              decoration: const InputDecoration(
                labelText: 'Lugar del trabajo',
                helperText: 'Dirección o zona. Puedes completarla después.',
              ),
            ),
            const SizedBox(height: 20),
            Text('Servicios a cotizar', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ..._filas.asMap().entries.map((entry) {
              final index = entry.key;
              final fila = entry.value;
              final tieneTarifa = fila.tarifaId != null;
              final subtotal = _subtotalDeFila(fila);
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ListenableBuilder(
                              listenable: widget.tarifaService,
                              builder: (context, _) {
                                final tarifas = widget.tarifaService.tarifas;
                                return DropdownButtonFormField<String?>(
                                  initialValue: fila.tarifaId,
                                  decoration:
                                      const InputDecoration(labelText: 'Servicio'),
                                  items: [
                                    const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('Otro servicio (precio manual)'),
                                    ),
                                    ...tarifas.map(
                                      (t) => DropdownMenuItem<String?>(
                                        value: t.id,
                                        child: Text(t.servicioNombre),
                                      ),
                                    ),
                                  ],
                                  onChanged: (id) => _seleccionarTarifaEnFila(
                                    index,
                                    widget.tarifaService.buscarPorId(id),
                                  ),
                                );
                              },
                            ),
                          ),
                          if (_filas.length > 1) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              tooltip: 'Quitar este servicio',
                              onPressed: () => _eliminarFila(index),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (!tieneTarifa) ...[
                        TextFormField(
                          controller: fila.nombreCtrl,
                          decoration: const InputDecoration(labelText: 'Nombre del servicio'),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty) ? 'Requerido' : null,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: fila.manoObraManualCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Mano de obra y transporte',
                            helperText: 'Lo que cobras por el trabajo, sin contar insumos.',
                            prefixText: '\$ ',
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return 'Requerido';
                            if (double.tryParse(value.trim()) == null) return 'Inválido';
                            return null;
                          },
                        ),
                      ] else ...[
                        TextFormField(
                          controller: fila.m2Ctrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Área del terreno (m²)',
                            helperText: 'Metros cuadrados que vas a trabajar.',
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return 'Requerido';
                            if (double.tryParse(value.trim()) == null) return 'Inválido';
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: fila.kmCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Distancia hasta el cliente (km)',
                            helperText:
                                'Desde tu punto de salida. Si no hay traslado, déjalo vacío.',
                            helperMaxLines: 2,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return null;
                            if (double.tryParse(value.trim()) == null) return 'Inválido';
                            return null;
                          },
                        ),
                      ],
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: fila.insumosCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Costo de insumos',
                          helperText:
                              'Materiales que gastas en este servicio. Si no usas, déjalo vacío.',
                          helperMaxLines: 2,
                          prefixText: '\$ ',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return null;
                          if (double.tryParse(value.trim()) == null) return 'Inválido';
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Costo de este servicio: \$${subtotal.toStringAsFixed(2)}',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _agregarFila(),
                icon: const Icon(Icons.add),
                label: const Text('Agregar otro servicio'),
              ),
            ),
            const SizedBox(height: 8),
            Text('Ayudantes', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              'Personal extra que contratas para este trabajo. '
              'Aparece por separado en la cotización.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            ..._ayudantes.asMap().entries.map((entry) {
              final index = entry.key;
              final ayudante = entry.value;
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: ayudante.descripcionCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Nombre o tarea',
                            helperText: 'Ej. Juan, ayudante de poda',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: ayudante.costoCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Pago',
                            prefixText: '\$ ',
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return null;
                            if (double.tryParse(value.trim()) == null) return 'Inválido';
                            return null;
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        tooltip: 'Quitar este ayudante',
                        onPressed: () => _eliminarAyudante(index),
                      ),
                    ],
                  ),
                ),
              );
            }),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _agregarAyudante(),
                icon: const Icon(Icons.add),
                label: const Text('Agregar ayudante'),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _margenCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Ganancia deseada',
                suffixText: '%',
                helperText: 'Ej. 30 = de cada \$100 que cobras, \$30 son tu ganancia.',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'Requerido';
                final numero = double.tryParse(value.trim());
                if (numero == null) return 'Inválido';
                if (numero < 0 || numero >= 100) return 'Debe estar entre 0 y 99';
                return null;
              },
            ),
            const SizedBox(height: 16),
            Card(
              color: AppColors.limeGreenSoft.withValues(alpha: 0.25),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Costo total'),
                        Text('\$${_costoTotal.toStringAsFixed(2)}'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Precio a cotizar', style: Theme.of(context).textTheme.titleMedium),
                        Text(
                          '\$${_precioFinal.toStringAsFixed(2)}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.darkGreen,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _agendando ? null : _agendar,
              icon: _agendando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.event_available),
              label: const Text('Agendar con esta cotización'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _guardando ? null : _guardar,
                    icon: _guardando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_cotizacionIdActual != null ? 'Actualizar' : 'Guardar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _compartiendo ? null : _compartirCotizacion,
                    icon: _compartiendo
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.share),
                    label: const Text('Compartir'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}