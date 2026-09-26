import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../models/customer.dart';
import '../models/finance_entry.dart';
import '../models/service_item.dart';
import '../pdf/invoice_pdf.dart';
import '../services/business_profile_service.dart';
import '../services/customer_service.dart';
import '../services/finance_service.dart';
import '../services/inventory_service.dart';
import '../services/invoice_service.dart';
import '../services/notification_service.dart';
import '../services/service_catalog_service.dart';
import '../theme/app_theme.dart';
import '../utils/inventario_descuento.dart';
import '../widgets/theme_toggle_button.dart';
import 'business_profile_screen.dart';

/// Datos con los que se puede prellenar el formulario de "Nuevo
/// cliente" cuando viene de una cotización aceptada en el Cotizador:
/// el nombre/lugar tentativos y los servicios ya cotizados (con sus
/// precios repartidos). El usuario solo tiene que confirmar la fecha y
/// guardar.
class ClientePrellenado {
  final String nombre;
  final String lugar;
  final List<ServicioAgendado> servicios;

  const ClientePrellenado({
    this.nombre = '',
    this.lugar = '',
    this.servicios = const [],
  });
}

/// Pantalla que muestra y administra la lista de clientes/trabajos:
/// nombre, lugar, fecha, precio, servicio enlazado y el estado del
/// trabajo (pendiente, por cobrar o pagado). Cobrar un trabajo crea
/// automáticamente un ingreso en el módulo de Finanzas.
class CustomerScreen extends StatefulWidget {
  final CustomerService service;
  final ServiceCatalogService serviceCatalog;
  final FinanceService financeService;
  final BusinessProfileService businessProfileService;
  final InvoiceService invoiceService;
  final InventoryService inventoryService;

  /// Si viene de una cotización aceptada en el Cotizador, abre el
  /// formulario de "Nuevo cliente" automáticamente con estos datos ya
  /// cargados.
  final ClientePrellenado? prellenado;

  const CustomerScreen({
    super.key,
    required this.service,
    required this.serviceCatalog,
    required this.financeService,
    required this.businessProfileService,
    required this.invoiceService,
    required this.inventoryService,
    this.prellenado,
  });

  @override
  State<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends State<CustomerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    if (widget.prellenado != null) {
      // Se espera al primer frame para poder abrir el bottom sheet con
      // un context ya montado.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _abrirFormulario(prellenado: widget.prellenado);
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _abrirFormulario({Customer? cliente, ClientePrellenado? prellenado}) async {
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
        child: _CustomerFormSheet(
          service: widget.service,
          serviceCatalog: widget.serviceCatalog,
          cliente: cliente,
          prellenado: prellenado,
        ),
      ),
    );
  }

  void _confirmarEliminar(Customer cliente) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar cliente'),
        content: Text('¿Deseas eliminar a "${cliente.nombre}" de la lista?'),
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
                // Si este trabajo ya tenía un cobro registrado en
                // Finanzas, lo eliminamos también para no dejar un
                // ingreso "huérfano" de un cliente que ya no existe.
                if (cliente.financeEntryId != null) {
                  await widget.financeService.eliminarMovimiento(cliente.financeEntryId!);
                }
                await widget.service.eliminarCliente(cliente.id);
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

  Future<void> _cobrar(Customer cliente) async {
    final metodo = await showDialog<MetodoPago>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cobrar a ${cliente.nombre}'),
        content: Text(
          'Monto a cobrar: \$${cliente.precio.toStringAsFixed(2)}\n\n¿Cómo pagó?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, MetodoPago.efectivo),
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Efectivo'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, MetodoPago.yappy),
            icon: const Icon(Icons.smartphone),
            label: const Text('Yappy'),
          ),
        ],
      ),
    );

    if (metodo == null) return;

    try {
      // Se crea el ingreso en Finanzas y se enlaza su id al cliente,
      // así ambos módulos quedan sincronizados sin acoplarse
      // directamente.
      final entryId = await widget.financeService.agregarMovimiento(
        descripcion: cliente.servicioNombre.isNotEmpty
            ? 'Cobro a ${cliente.nombre} - ${cliente.servicioNombre}'
            : 'Cobro a ${cliente.nombre}',
        tipo: TipoMovimiento.ingreso,
        monto: cliente.precio,
        fecha: DateTime.now(),
        categoria: metodo.label,
      );
      await widget.service.marcarPagado(
        cliente.id,
        metodoPago: metodo,
        financeEntryId: entryId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cobro registrado con ${metodo.label}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo registrar el cobro. Intenta de nuevo.')),
        );
      }
    }
  }

  /// Marca el trabajo como realizado y, de paso, descuenta del
  /// inventario los insumos que consuman los servicios agendados según
  /// su receta configurada (ver "Insumos por servicio").
  Future<void> _marcarRealizado(String id) async {
    try {
      await widget.service.marcarRealizado(id);
      Customer? cliente;
      for (final c in widget.service.customers) {
        if (c.id == id) {
          cliente = c;
          break;
        }
      }
      if (cliente != null) {
        await descontarInsumosDelTrabajo(
          servicios: cliente.servicios,
          serviceCatalog: widget.serviceCatalog,
          inventoryService: widget.inventoryService,
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

  Future<void> _deshacerCobro(Customer cliente) async {
    try {
      if (cliente.financeEntryId != null) {
        await widget.financeService.eliminarMovimiento(cliente.financeEntryId!);
      }
      await widget.service.revertirCobro(cliente.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo deshacer el cobro. Intenta de nuevo.')),
        );
      }
    }
  }

  Future<void> _generarFactura(Customer cliente) async {
    if (cliente.estado != EstadoTrabajo.pagado) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Solo se puede generar la factura de un trabajo ya pagado.'),
        ),
      );
      return;
    }

    final perfil = widget.businessProfileService.perfil;

    if (!perfil.estaCompleto) {
      if (!mounted) return;
      final irAConfigurar = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Completa los datos de tu negocio'),
          content: const Text(
            'Antes de generar tu primera factura, necesitas poner el '
            'nombre comercial y el operador responsable en "Mi negocio".',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ir a Mi negocio'),
            ),
          ],
        ),
      );
      if (irAConfigurar == true && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BusinessProfileScreen(service: widget.businessProfileService),
          ),
        );
      }
      return;
    }

    try {
      final numero = await widget.invoiceService.registrarFactura(
        clienteId: cliente.id,
        monto: cliente.precio,
      );
      final bytes = await InvoicePdf.generar(
        cliente: cliente,
        perfil: perfil,
        numeroFactura: numero,
      );

      if (!mounted) return;
      final accion = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Factura generada'),
          content: const Text('¿Qué deseas hacer con la factura?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'ver'),
              child: const Text('Ver / Imprimir'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, 'compartir'),
              icon: const Icon(Icons.share),
              label: const Text('Compartir'),
            ),
          ],
        ),
      );

      if (accion == 'compartir') {
        // Abre el selector nativo de apps (WhatsApp, correo, etc.) con
        // el PDF de la factura listo para enviar.
        await Printing.sharePdf(bytes: bytes, filename: 'factura_$numero.pdf');
      } else if (accion == 'ver') {
        await Printing.layoutPdf(onLayout: (_) async => bytes);
      }

      await NotificationService.instance.avisarFacturaGenerada(
        numero: numero,
        clienteNombre: cliente.nombre,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo generar la factura. Intenta de nuevo.')),
        );
      }
    }
  }

  String _formatearFecha(DateTime fecha) {
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    return '$dia/$mes/${fecha.year}';
  }

  /// Abre el historial de todos los trabajos de la serie recurrente a
  /// la que pertenece [cliente] (o solo el trabajo en sí, si nunca fue
  /// recurrente).
  void _verHistorial(Customer cliente) {
    final historial = widget.service.historialDe(cliente);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _HistorialClienteSheet(
        nombreCliente: cliente.nombre,
        historial: historial,
        formatearFecha: _formatearFecha,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes'),
        actions: const [ThemeToggleButton()],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.limeGreen,
          indicatorWeight: 3,
          labelColor: Theme.of(context).appBarTheme.foregroundColor,
          unselectedLabelColor:
              Theme.of(context).appBarTheme.foregroundColor?.withValues(alpha: 0.65),
          tabs: const [
            Tab(text: 'Pendientes'),
            Tab(text: 'Por cobrar'),
            Tab(text: 'Historial'),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: widget.service,
        builder: (context, _) {
          return TabBarView(
            controller: _tabController,
            children: [
              _ListaClientes(
                clientes: widget.service.porEstado(EstadoTrabajo.pendiente),
                formatearFecha: _formatearFecha,
                onTap: (c) => _abrirFormulario(cliente: c),
                onDelete: _confirmarEliminar,
                onMarcarRealizado: _marcarRealizado,
                onCobrar: _cobrar,
                onDeshacerCobro: _deshacerCobro,
                onGenerarFactura: _generarFactura,
                onVerHistorial: _verHistorial,
              ),
              _ListaClientes(
                clientes: widget.service.porEstado(EstadoTrabajo.realizado),
                formatearFecha: _formatearFecha,
                onTap: (c) => _abrirFormulario(cliente: c),
                onDelete: _confirmarEliminar,
                onMarcarRealizado: _marcarRealizado,
                onCobrar: _cobrar,
                onDeshacerCobro: _deshacerCobro,
                onGenerarFactura: _generarFactura,
                onVerHistorial: _verHistorial,
              ),
              _ListaClientes(
                clientes: widget.service.porEstado(EstadoTrabajo.pagado),
                formatearFecha: _formatearFecha,
                onTap: (c) => _abrirFormulario(cliente: c),
                onDelete: _confirmarEliminar,
                onMarcarRealizado: _marcarRealizado,
                onCobrar: _cobrar,
                onDeshacerCobro: _deshacerCobro,
                onGenerarFactura: _generarFactura,
                onVerHistorial: _verHistorial,
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.person_add),
        label: const Text('Nuevo cliente'),
      ),
    );
  }
}

class _ListaClientes extends StatelessWidget {
  final List<Customer> clientes;
  final String Function(DateTime) formatearFecha;
  final ValueChanged<Customer> onTap;
  final ValueChanged<Customer> onDelete;
  final ValueChanged<String> onMarcarRealizado;
  final ValueChanged<Customer> onCobrar;
  final ValueChanged<Customer> onDeshacerCobro;
  final ValueChanged<Customer> onGenerarFactura;
  final ValueChanged<Customer> onVerHistorial;

  const _ListaClientes({
    required this.clientes,
    required this.formatearFecha,
    required this.onTap,
    required this.onDelete,
    required this.onMarcarRealizado,
    required this.onCobrar,
    required this.onDeshacerCobro,
    required this.onGenerarFactura,
    required this.onVerHistorial,
  });

  Color _colorEstado(EstadoTrabajo estado) {
    switch (estado) {
      case EstadoTrabajo.pendiente:
        return Colors.orange;
      case EstadoTrabajo.realizado:
        return Colors.blueGrey;
      case EstadoTrabajo.pagado:
        return AppColors.darkGreen;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (clientes.isEmpty) {
      return Center(
        child: Text(
          'No hay clientes en esta categoría todavía.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      itemCount: clientes.length,
      itemBuilder: (context, index) {
        final cliente = clientes[index];
        final colorEstado = _colorEstado(cliente.estado);

        final subtitulo = StringBuffer();
        if (cliente.servicioNombre.isNotEmpty) {
          subtitulo.write('${cliente.servicioNombre} • ');
        }
        subtitulo.write(cliente.lugar);
        subtitulo.write('\n${formatearFecha(cliente.fecha)}');
        if (cliente.estado == EstadoTrabajo.pagado && cliente.metodoPago != null) {
          subtitulo.write(
            ' • Pagado con ${cliente.metodoPago!.label}'
            '${cliente.fechaPago != null ? " el ${formatearFecha(cliente.fechaPago!)}" : ""}',
          );
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  onTap: () => onTap(cliente),
                  leading: CircleAvatar(
                    backgroundColor: colorEstado.withValues(alpha: 0.2),
                    child: Icon(Icons.person, color: colorEstado),
                  ),
                  title: Text(cliente.nombre),
                  subtitle: Text(subtitulo.toString()),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '\$${cliente.precio.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (cliente.estado == EstadoTrabajo.pagado) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.receipt_long_outlined, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => onGenerarFactura(cliente),
                          tooltip: 'Generar factura',
                        ),
                      ],
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.history, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => onVerHistorial(cliente),
                        tooltip: 'Historial de este cliente',
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => onDelete(cliente),
                        tooltip: 'Eliminar',
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8, right: 8),
                  child: Row(
                    children: [
                      Chip(
                        label: Text(cliente.estado.label),
                        backgroundColor: colorEstado.withValues(alpha: 0.15),
                        labelStyle: TextStyle(color: colorEstado, fontSize: 12),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      if (cliente.recurrencia != null) ...[
                        const SizedBox(width: 6),
                        Chip(
                          avatar: const Icon(Icons.repeat, size: 14),
                          label: Text(cliente.recurrencia!.label),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                      const Spacer(),
                      if (cliente.estado == EstadoTrabajo.pendiente)
                        TextButton.icon(
                          onPressed: () => onMarcarRealizado(cliente.id),
                          icon: const Icon(Icons.check_circle_outline, size: 18),
                          label: const Text('Marcar realizado'),
                        ),
                      if (cliente.estado == EstadoTrabajo.realizado)
                        FilledButton.icon(
                          onPressed: () => onCobrar(cliente),
                          icon: const Icon(Icons.attach_money, size: 18),
                          label: const Text('Cobrar'),
                        ),
                      if (cliente.estado == EstadoTrabajo.pagado)
                        TextButton.icon(
                          onPressed: () => onDeshacerCobro(cliente),
                          icon: const Icon(Icons.undo, size: 18),
                          label: const Text('Deshacer cobro'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Hoja que muestra el historial de trabajos de un cliente (todos los
/// de su misma serie recurrente, o solo él si nunca fue recurrente),
/// del más reciente al más antiguo.
class _HistorialClienteSheet extends StatelessWidget {
  final String nombreCliente;
  final List<Customer> historial;
  final String Function(DateTime) formatearFecha;

  const _HistorialClienteSheet({
    required this.nombreCliente,
    required this.historial,
    required this.formatearFecha,
  });

  Color _colorEstado(EstadoTrabajo estado) {
    switch (estado) {
      case EstadoTrabajo.pendiente:
        return Colors.orange;
      case EstadoTrabajo.realizado:
        return Colors.blueGrey;
      case EstadoTrabajo.pagado:
        return AppColors.darkGreen;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
              'Historial de $nombreCliente',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              historial.length == 1
                  ? '1 trabajo registrado'
                  : '${historial.length} trabajos registrados',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: historial.length,
                itemBuilder: (context, index) {
                  final trabajo = historial[index];
                  final color = _colorEstado(trabajo.estado);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: color.withValues(alpha: 0.2),
                        child: Icon(Icons.work_outline, color: color),
                      ),
                      title: Text(formatearFecha(trabajo.fecha)),
                      subtitle: Text(
                        trabajo.servicioNombre.isNotEmpty
                            ? '${trabajo.servicioNombre} • ${trabajo.lugar}'
                            : trabajo.lugar,
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '\$${trabajo.precio.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            trabajo.estado.label,
                            style: TextStyle(color: color, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Formulario para crear o editar un cliente.
class _CustomerFormSheet extends StatefulWidget {
  final CustomerService service;
  final ServiceCatalogService serviceCatalog;
  final Customer? cliente;
  final ClientePrellenado? prellenado;

  const _CustomerFormSheet({
    required this.service,
    required this.serviceCatalog,
    this.cliente,
    this.prellenado,
  });

  @override
  State<_CustomerFormSheet> createState() => _CustomerFormSheetState();
}

/// Una fila del formulario: un servicio agendado en edición. Si
/// [servicioId] es null, la fila está en modo "Personalizado" y el
/// nombre se escribe a mano en [nombreCtrl]; si no, el nombre viene
/// del catálogo y [nombreCtrl] solo se usa para mostrarlo/enviarlo.
class _FilaServicio {
  String? servicioId;
  final TextEditingController nombreCtrl;
  final TextEditingController precioCtrl;

  _FilaServicio({
    this.servicioId,
    String nombreInicial = '',
    String precioInicial = '',
  })  : nombreCtrl = TextEditingController(text: nombreInicial),
        precioCtrl = TextEditingController(text: precioInicial);

  void dispose() {
    nombreCtrl.dispose();
    precioCtrl.dispose();
  }
}

class _CustomerFormSheetState extends State<_CustomerFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _lugarCtrl;
  late DateTime _fecha;
  final List<_FilaServicio> _filas = [];
  bool _esRecurrente = false;
  Recurrencia _recurrencia = Recurrencia.mensual;

  bool get _esEdicion => widget.cliente != null;

  /// Suma en vivo de los precios de todas las filas.
  double get _total {
    double suma = 0;
    for (final fila in _filas) {
      suma += double.tryParse(fila.precioCtrl.text.trim()) ?? 0;
    }
    return suma;
  }

  @override
  void initState() {
    super.initState();
    final cliente = widget.cliente;
    final prellenado = widget.prellenado;
    _nombreCtrl = TextEditingController(text: cliente?.nombre ?? prellenado?.nombre ?? '');
    _lugarCtrl = TextEditingController(text: cliente?.lugar ?? prellenado?.lugar ?? '');
    _fecha = cliente?.fecha ?? DateTime.now();
    _esRecurrente = cliente?.recurrencia != null;
    _recurrencia = cliente?.recurrencia ?? Recurrencia.mensual;

    final serviciosIniciales = cliente?.servicios ?? prellenado?.servicios ?? const [];
    if (serviciosIniciales.isNotEmpty) {
      for (final s in serviciosIniciales) {
        _agregarFila(
          servicioId: s.servicioId,
          nombreInicial: s.nombre,
          precioInicial: s.precio.toStringAsFixed(2),
        );
      }
    } else {
      _agregarFila();
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _lugarCtrl.dispose();
    for (final fila in _filas) {
      fila.dispose();
    }
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

  /// Agrega una fila de servicio nueva (vacía, "Personalizado" por
  /// defecto) o precargada con los valores indicados.
  void _agregarFila({
    String? servicioId,
    String nombreInicial = '',
    String precioInicial = '',
  }) {
    final fila = _FilaServicio(
      servicioId: servicioId,
      nombreInicial: nombreInicial,
      precioInicial: precioInicial,
    );
    // El total mostrado depende de cada precioCtrl: nos suscribimos
    // para recalcularlo en vivo mientras el usuario escribe.
    fila.precioCtrl.addListener(_onCambioPrecio);
    setState(() => _filas.add(fila));
  }

  void _eliminarFila(int index) {
    if (_filas.length <= 1) return; // siempre queda al menos 1 fila
    setState(() {
      final fila = _filas.removeAt(index);
      fila.precioCtrl.removeListener(_onCambioPrecio);
      fila.dispose();
    });
  }

  void _onCambioPrecio() => setState(() {});

  /// Al elegir un servicio del catálogo en una fila (o "Personalizado"),
  /// actualiza esa fila: nombre y precio sugerido si viene del
  /// catálogo, o la limpia para que el usuario escriba el nombre a
  /// mano si elige "Personalizado".
  void _seleccionarServicioEnFila(int index, ServiceItem? servicio) {
    setState(() {
      final fila = _filas[index];
      fila.servicioId = servicio?.id;
      if (servicio != null) {
        fila.nombreCtrl.text = servicio.nombre;
        // Sugerimos el precio del catálogo, pero el usuario puede
        // ajustarlo libremente después (por ejemplo, si cobra distinto
        // por distancia o tamaño del trabajo).
        fila.precioCtrl.text = servicio.precio.toString();
      } else {
        fila.nombreCtrl.clear();
      }
    });
  }

  bool _guardando = false;

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    final nombre = _nombreCtrl.text.trim();
    final lugar = _lugarCtrl.text.trim();

    final servicios = _filas.map((fila) {
      final nombreServicio = fila.servicioId != null
          ? (widget.serviceCatalog.buscarPorId(fila.servicioId)?.nombre ??
              fila.nombreCtrl.text.trim())
          : fila.nombreCtrl.text.trim();
      return ServicioAgendado(
        servicioId: fila.servicioId,
        nombre: nombreServicio,
        precio: double.tryParse(fila.precioCtrl.text.trim()) ?? 0,
      );
    }).toList();

    setState(() => _guardando = true);

    try {
      if (_esEdicion) {
        await widget.service.actualizarCliente(
          widget.cliente!.id,
          nombre: nombre,
          lugar: lugar,
          fecha: _fecha,
          servicios: servicios,
          recurrencia: _esRecurrente ? _recurrencia : null,
        );
      } else {
        await widget.service.agregarCliente(
          nombre: nombre,
          lugar: lugar,
          fecha: _fecha,
          servicios: servicios,
          recurrencia: _esRecurrente ? _recurrencia : null,
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
                _esEdicion ? 'Editar cliente' : 'Nuevo cliente',
                style: Theme.of(context).textTheme.titleLarge,
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
              TextFormField(
                controller: _lugarCtrl,
                decoration: const InputDecoration(labelText: 'Lugar'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty)
                        ? 'Ingresa un lugar'
                        : null,
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
              const SizedBox(height: 16),
              Text('Servicios', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              ..._filas.asMap().entries.map((entry) {
                final index = entry.key;
                final fila = entry.value;
                final esPersonalizado = fila.servicioId == null;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ListenableBuilder(
                              listenable: widget.serviceCatalog,
                              builder: (context, _) {
                                final catalogo = widget.serviceCatalog.servicios;
                                return DropdownButtonFormField<String?>(
                                  initialValue: fila.servicioId,
                                  decoration: const InputDecoration(
                                    labelText: 'Servicio',
                                  ),
                                  items: [
                                    const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('Personalizado'),
                                    ),
                                    ...catalogo.map(
                                      (s) => DropdownMenuItem<String?>(
                                        value: s.id,
                                        child: Text(s.nombre),
                                      ),
                                    ),
                                  ],
                                  onChanged: (id) => _seleccionarServicioEnFila(
                                    index,
                                    widget.serviceCatalog.buscarPorId(id),
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
                      Row(
                        children: [
                          if (esPersonalizado) ...[
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: fila.nombreCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Nombre del servicio',
                                ),
                                validator: (value) =>
                                    (value == null || value.trim().isEmpty)
                                        ? 'Requerido'
                                        : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            flex: esPersonalizado ? 2 : 1,
                            child: TextFormField(
                              controller: fila.precioCtrl,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Precio',
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
                          ),
                        ],
                      ),
                    ],
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
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total', style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    '\$${_total.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Servicio recurrente'),
                subtitle: const Text(
                  'Al marcarlo como realizado, se agenda automáticamente '
                  'el siguiente trabajo.',
                ),
                value: _esRecurrente,
                onChanged: (valor) => setState(() => _esRecurrente = valor),
              ),
              if (_esRecurrente) ...[
                const SizedBox(height: 4),
                SegmentedButton<Recurrencia>(
                  segments: const [
                    ButtonSegment(
                      value: Recurrencia.semanal,
                      label: Text('Semanal'),
                    ),
                    ButtonSegment(
                      value: Recurrencia.mensual,
                      label: Text('Mensual'),
                    ),
                  ],
                  selected: {_recurrencia},
                  onSelectionChanged: (nuevaSeleccion) {
                    setState(() => _recurrencia = nuevaSeleccion.first);
                  },
                ),
              ],
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