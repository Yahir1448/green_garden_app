import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth_screen.dart';
import 'screens/business_profile_screen.dart';
import 'screens/cotizador_screen.dart';
import 'screens/customer_screen.dart';
import 'screens/finance_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/services_screen.dart';
import 'services/brand_cache.dart';
import 'services/business_profile_service.dart';
import 'services/cotizacion_service.dart';
import 'services/customer_service.dart';
import 'services/finance_service.dart';
import 'services/inventory_service.dart';
import 'services/invoice_service.dart';
import 'services/notification_service.dart';
import 'services/service_catalog_service.dart';
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

class _AuthGateState extends State<AuthGate> {
  late final StreamSubscription<AuthState> _authSub;
  bool _autenticado = false;
  bool _cargandoInicial = false;

  @override
  void initState() {
    super.initState();

    final sesionActual = Supabase.instance.client.auth.currentSession;
    _autenticado = sesionActual != null;
    if (_autenticado) {
      _cargarTodo();
    }

    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final haySesion = data.session != null;
      if (haySesion && !_autenticado) {
        _cargarTodo();
      } else if (!haySesion && _autenticado) {
        _limpiarTodo();
      }
      if (mounted) setState(() => _autenticado = haySesion);
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
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
    // reciba avisos programados con datos de la cuenta anterior.
    NotificationService.instance.limpiarTodo();
  }

  @override
  Widget build(BuildContext context) {
    if (!_autenticado) {
      return const AuthScreen();
    }

    if (_cargandoInicial) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

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
                    builder: (_) => InventoryScreen(service: inventoryService),
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