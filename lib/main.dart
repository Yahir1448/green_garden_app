import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/customer.dart';
import 'models/finance_entry.dart';
import 'screens/agenda_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/biometric_lock_screen.dart';
import 'screens/business_profile_screen.dart';
import 'screens/cotizador_screen.dart';
import 'screens/customer_screen.dart';
import 'screens/export_data_screen.dart';
import 'screens/finance_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/services_screen.dart';
import 'services/biometric_service.dart';
import 'services/brand_cache.dart';
import 'services/business_profile_service.dart';
import 'services/connectivity_service.dart';
import 'services/cotizacion_service.dart';
import 'services/customer_service.dart';
import 'services/finance_service.dart';
import 'services/inventory_service.dart';
import 'services/invoice_service.dart';
import 'services/notification_service.dart';
import 'services/service_catalog_service.dart';
import 'services/sync_queue_service.dart';
import 'services/tarifa_service.dart';
import 'supabase/supabase_config.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'utils/color_utils.dart';
import 'widgets/business_logo.dart';
import 'widgets/theme_toggle_button.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Conecta la app con tu proyecto de Supabase. Rellena las
  // credenciales en lib/supabase/supabase_config.dart antes de correr
  // la app.
  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    publishableKey: SupabaseConfig.supabaseAnonKey,
  );

  // Notificaciones locales (stock bajo, trabajos agendados, cobros y
  // facturas). No depende de ningún servidor externo: se apoya en los
  // datos que ya vienen de Supabase.
  await NotificationService.instance.inicializar();

  // Carga el último logo/color de marca conocidos en este teléfono,
  // para que ya se vean correctamente desde la pantalla de login,
  // antes incluso de que haya una sesión activa.
  await BrandCache.instance.cargar();
  ThemeController.instance.actualizarColorMarca(
    colorFromHex(BrandCache.instance.colorHex),
  );

  // Modo sin conexión: recupera lo que haya quedado pendiente de
  // sincronizar de una sesión anterior, y empieza a vigilar el estado
  // de la red. Los "manejadores" que saben reproducir cada tipo de
  // operación pendiente se registran más abajo, en _MyAppState, una
  // vez que los servicios ya existen.
  await SyncQueueService.instance.cargar();
  await ConnectivityService.instance.inicializar();

  // Acceso con huella/rostro: si está activado y ya hay una sesión
  // guardada, la app arranca bloqueada. Se decide aquí, antes de runApp,
  // para que el primer cuadro que se dibuje ya sea el bloqueo.
  await BiometricService.instance.cargar();
  if (BiometricService.instance.activada &&
      Supabase.instance.client.auth.currentSession != null) {
    BiometricService.instance.bloquear();
  }

  runApp(const MyApp());
}

/// Punto de entrada y "orquestador" central de la app.
///
/// Aquí es donde se instancian los servicios (la capa que en esta
/// arquitectura funciona como microservicios internos: inventario,
/// clientes, finanzas, catálogo de servicios, y a futuro otros
/// módulos), respaldados por Supabase. El tema claro/oscuro y el color
/// de marca no viven en este widget: se manejan de forma global en
/// [ThemeController].
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Instancias centrales de los "microservicios" de la app. Se crean
  // una sola vez aquí y se pasan hacia las pantallas que las necesiten.
  final InventoryService _inventoryService = InventoryService();
  final CustomerService _customerService = CustomerService();
  final FinanceService _financeService = FinanceService();
  final ServiceCatalogService _serviceCatalogService = ServiceCatalogService();
  final BusinessProfileService _businessProfileService = BusinessProfileService();
  final InvoiceService _invoiceService = InvoiceService();
  final TarifaService _tarifaService = TarifaService();
  final CotizacionService _cotizacionService = CotizacionService();

  @override
  void initState() {
    super.initState();

    // CustomerService sabe reproducir sus propias operaciones (crear,
    // editar, marcar realizado) sin ayuda de nadie más.
    _customerService.registrarManejadoresSync();

    // El cobro hecho sin conexión sí necesita coordinación entre dos
    // módulos (crear el ingreso en Finanzas y luego enlazarlo al
    // cliente), así que ese manejador vive aquí, que es el único lugar
    // que conoce a ambos servicios.
    SyncQueueService.instance.registrarManejador('cobro_pendiente', (payload) async {
      final entryId = await _financeService.agregarMovimiento(
        descripcion: payload['descripcion'] as String,
        tipo: TipoMovimiento.ingreso,
        monto: (payload['monto'] as num).toDouble(),
        fecha: DateTime.parse(payload['fecha'] as String),
        categoria: payload['categoria'] as String,
      );
      await _customerService.marcarPagado(
        payload['clienteId'] as String,
        metodoPago: MetodoPago.values.firstWhere(
          (m) => m.name == payload['metodoPago'],
        ),
        financeEntryId: entryId,
      );
    });

    // Si la app se cerró estando sin conexión y se vuelve a abrir ya
    // con señal, la transición "sin conexión -> con conexión" no
    // vuelve a dispararse sola (ya estaba online desde el arranque),
    // así que forzamos un intento aquí para no dejar nada esperando.
    if (ConnectivityService.instance.isOnline) {
      SyncQueueService.instance.procesarPendientes();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance.modeNotifier,
      builder: (context, themeMode, _) {
        return ValueListenableBuilder<Color?>(
          valueListenable: ThemeController.instance.colorMarcaNotifier,
          builder: (context, colorMarca, _) {
            return MaterialApp(
              title: 'Green Garden',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light(colorMarca),
              darkTheme: AppTheme.dark(colorMarca),
              themeMode: themeMode,
              // Capa de bloqueo biométrico por ENCIMA de todas las
              // pantallas (incluidas las abiertas sobre el dashboard).
              builder: (context, child) => BiometricLockOverlay(
                child: child ?? const SizedBox.shrink(),
              ),
              // AuthGate decide si mostrar el login o el dashboard según
              // haya o no una sesión activa de Supabase, y se encarga de
              // cargar/limpiar los datos de cada servicio en el momento
              // correcto.
              home: AuthGate(
                inventoryService: _inventoryService,
                customerService: _customerService,
                financeService: _financeService,
                serviceCatalogService: _serviceCatalogService,
                businessProfileService: _businessProfileService,
                invoiceService: _invoiceService,
                tarifaService: _tarifaService,
                cotizacionService: _cotizacionService,
              ),
            );
          },
        );
      },
    );
  }
}

/// Escucha los cambios de sesión de Supabase Auth y muestra la
/// pantalla de login o el dashboard principal según corresponda.
///
/// También es responsable de:
/// - Descargar los datos de todos los módulos justo después de iniciar
///   sesión (`cargar()` en cada servicio).
/// - Vaciar los datos en memoria al cerrar sesión (`limpiar()`), para
///   que si otra persona inicia sesión con otra cuenta en el mismo
///   teléfono, no vea ningún dato de la cuenta anterior. Esto incluye
///   cancelar todas las notificaciones pendientes.
class AuthGate extends StatefulWidget {
  final InventoryService inventoryService;
  final CustomerService customerService;
  final FinanceService financeService;
  final ServiceCatalogService serviceCatalogService;
  final BusinessProfileService businessProfileService;
  final InvoiceService invoiceService;
  final TarifaService tarifaService;
  final CotizacionService cotizacionService;

  const AuthGate({
    super.key,
    required this.inventoryService,
    required this.customerService,
    required this.financeService,
    required this.serviceCatalogService,
    required this.businessProfileService,
    required this.invoiceService,
    required this.tarifaService,
    required this.cotizacionService,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  late final StreamSubscription<AuthState> _authSub;
  bool _autenticado = false;
  bool _cargandoInicial = false;

  /// Tiempo en segundo plano a partir del cual se vuelve a pedir la
  /// huella/rostro al regresar a la app.
  static const Duration _tiempoParaBloquear = Duration(seconds: 30);
  DateTime? _pausadoEn;

  /// Hay que ofrecer activar el acceso biométrico (una sola vez).
  bool _ofertaBiometriaPendiente = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    final sesionActual = Supabase.instance.client.auth.currentSession;
    _autenticado = sesionActual != null;
    if (_autenticado) {
      _cargarTodo();
      // Quien ya tenía la sesión abierta también recibe la oferta.
      final bio = BiometricService.instance;
      if (!bio.activada && !bio.yaPreguntada) {
        _ofertaBiometriaPendiente = true;
      }
    }

    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final haySesion = data.session != null;
      if (haySesion && !_autenticado) {
        _cargarTodo();
        // En la recuperación de contraseña no se ofrece en ese momento.
        if (!RecoveryState.activa.value) _ofertaBiometriaPendiente = true;
      } else if (!haySesion && _autenticado) {
        _limpiarTodo();
        // La preferencia biométrica es de la cuenta que se va.
        BiometricService.instance.reiniciar();
      }
      if (mounted) setState(() => _autenticado = haySesion);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub.cancel();
    super.dispose();
  }

  /// Vuelve a bloquear la app si estuvo en segundo plano más de
  /// [_tiempoParaBloquear].
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bio = BiometricService.instance;
    // Mientras el sistema muestra su diálogo de huella, los cambios de
    // ciclo de vida que provoca no cuentan como "salir de la app".
    if (!_autenticado || !bio.activada || bio.ocupado) return;

    if (state == AppLifecycleState.paused) {
      _pausadoEn ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final desde = _pausadoEn;
      _pausadoEn = null;
      if (desde != null &&
          DateTime.now().difference(desde) > _tiempoParaBloquear) {
        bio.bloquear();
      }
    }
  }

  void _programarOfertaBiometria() {
    if (!_ofertaBiometriaPendiente) return;
    _ofertaBiometriaPendiente = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => _ofrecerBiometria());
  }

  Future<void> _ofrecerBiometria() async {
    final bio = BiometricService.instance;
    if (!mounted || bio.activada || bio.yaPreguntada) return;
    if (!await bio.disponible()) return;
    if (!mounted) return;

    final activar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Activar acceso con huella o rostro?'),
        content: const Text(
          'Al abrir la app te pediremos tu huella o rostro, para que nadie '
          'más pueda entrar si tiene tu teléfono. Puedes desactivarlo '
          'cuando quieras.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Activar'),
          ),
        ],
      ),
    );

    await bio.marcarPreguntada();
    if (activar != true) return;

    final ok = await bio.autenticar(
      'Confirma tu identidad para activar el acceso biométrico',
    );
    if (ok) await bio.activar();
  }

  Future<void> _cargarTodo() async {
    setState(() => _cargandoInicial = true);
    await Future.wait([
      widget.inventoryService.cargar(),
      widget.customerService.cargar(),
      widget.financeService.cargar(),
      widget.serviceCatalogService.cargar(),
      widget.businessProfileService.cargar(),
      widget.tarifaService.cargar(),
      widget.cotizacionService.cargar(),
    ]);
    if (mounted) setState(() => _cargandoInicial = false);
  }

  void _limpiarTodo() {
    widget.inventoryService.limpiar();
    widget.customerService.limpiar();
    widget.financeService.limpiar();
    widget.serviceCatalogService.limpiar();
    widget.businessProfileService.limpiar();
    widget.tarifaService.limpiar();
    widget.cotizacionService.limpiar();
    // Evita que la próxima cuenta que inicie sesión en este teléfono
    // reciba avisos programados, o intente sincronizar cambios
    // pendientes, con datos de la cuenta anterior.
    NotificationService.instance.limpiarTodo();
    SyncQueueService.instance.limpiar();
  }

  @override
  Widget build(BuildContext context) {
    // Mientras se recupera la contraseña hay sesión (el código la abre),
    // pero el usuario todavía debe poner su contraseña nueva: se queda
    // en AuthScreen hasta que RecoveryState.activa vuelva a false.
    return ValueListenableBuilder<bool>(
      valueListenable: RecoveryState.activa,
      builder: (context, enRecuperacion, _) {
        if (!_autenticado || enRecuperacion) {
          return const AuthScreen();
        }

        if (_cargandoInicial) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        _programarOfertaBiometria();

        return HomePage(
          inventoryService: widget.inventoryService,
          customerService: widget.customerService,
          financeService: widget.financeService,
          serviceCatalogService: widget.serviceCatalogService,
          businessProfileService: widget.businessProfileService,
          invoiceService: widget.invoiceService,
          tarifaService: widget.tarifaService,
          cotizacionService: widget.cotizacionService,
        );
      },
    );
  }
}

/// Pantalla principal (dashboard) de la app. Desde aquí se accede a
/// cada módulo/microservicio disponible. La estructura permite agregar
/// más tarjetas para futuros módulos fácilmente.
class HomePage extends StatelessWidget {
  final InventoryService inventoryService;
  final CustomerService customerService;
  final FinanceService financeService;
  final ServiceCatalogService serviceCatalogService;
  final BusinessProfileService businessProfileService;
  final InvoiceService invoiceService;
  final TarifaService tarifaService;
  final CotizacionService cotizacionService;

  const HomePage({
    super.key,
    required this.inventoryService,
    required this.customerService,
    required this.financeService,
    required this.serviceCatalogService,
    required this.businessProfileService,
    required this.invoiceService,
    required this.tarifaService,
    required this.cotizacionService,
  });

  Future<void> _cerrarSesion(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(10),
          child: ListenableBuilder(
            listenable: businessProfileService,
            builder: (context, _) => BusinessLogo(
              logoUrl: businessProfileService.perfil.logoUrl,
              size: 28,
              iconoPorDefecto: Icons.eco,
              colorIcono: Theme.of(context).appBarTheme.foregroundColor,
            ),
          ),
        ),
        title: const Text('Green Garden'),
        actions: [
          const ThemeToggleButton(),
          IconButton(
            tooltip: 'Mi negocio',
            icon: const Icon(Icons.storefront_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BusinessProfileScreen(service: businessProfileService),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Exportar mis datos',
            icon: const Icon(Icons.download_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ExportDataScreen()),
              );
            },
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () => _cerrarSesion(context),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          children: [
            _ModuleCard(
              icon: Icons.inventory_2,
              label: 'Inventario',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => InventoryScreen(
                      service: inventoryService,
                      serviceCatalog: serviceCatalogService,
                    ),
                  ),
                );
              },
            ),
            _ModuleCard(
              icon: Icons.people_alt,
              label: 'Clientes',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CustomerScreen(
                      service: customerService,
                      serviceCatalog: serviceCatalogService,
                      financeService: financeService,
                      businessProfileService: businessProfileService,
                      invoiceService: invoiceService,
                      inventoryService: inventoryService,
                    ),
                  ),
                );
              },
            ),
            _ModuleCard(
              icon: Icons.calendar_month,
              label: 'Agenda',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AgendaScreen(
                      customerService: customerService,
                      serviceCatalogService: serviceCatalogService,
                      inventoryService: inventoryService,
                    ),
                  ),
                );
              },
            ),
            _ModuleCard(
              icon: Icons.attach_money,
              label: 'Finanzas',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FinanceScreen(service: financeService),
                  ),
                );
              },
            ),
            _ModuleCard(
              icon: Icons.handyman,
              label: 'Servicios',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ServicesScreen(service: serviceCatalogService),
                  ),
                );
              },
            ),
            _ModuleCard(
              icon: Icons.calculate,
              label: 'Cotizador',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CotizadorScreen(
                      tarifaService: tarifaService,
                      cotizacionService: cotizacionService,
                      serviceCatalogService: serviceCatalogService,
                      customerService: customerService,
                      financeService: financeService,
                      businessProfileService: businessProfileService,
                      invoiceService: invoiceService,
                      inventoryService: inventoryService,
                    ),
                  ),
                );
              },
            ),
            // Aquí se pueden agregar más módulos en el futuro, por ejemplo:
            // _ModuleCard(icon: Icons.task, label: 'Tareas', onTap: () {}),
          ],
        ),
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ModuleCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}