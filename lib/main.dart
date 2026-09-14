import 'package:flutter/material.dart';

import 'screens/customer_screen.dart';
import 'screens/inventory_screen.dart';
import 'services/customer_service.dart';
import 'services/inventory_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'widgets/theme_toggle_button.dart';

void main() {
  runApp(const MyApp());
}

/// Punto de entrada y "orquestador" central de la app.
///
/// Aquí es donde se instancian los servicios (la capa que en esta
/// arquitectura funciona como microservicios internos: inventario,
/// clientes, y a futuro otros módulos). El tema claro/oscuro ya no vive
/// en este widget: se maneja de forma global en [ThemeController], para
/// que cualquier pantalla lo pueda leer o cambiar sin recibirlo como
/// parámetro.
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance.modeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'Green Garden',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeMode,
          home: HomePage(
            inventoryService: _inventoryService,
            customerService: _customerService,
          ),
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

  const HomePage({
    super.key,
    required this.inventoryService,
    required this.customerService,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Green Garden'),
        actions: const [ThemeToggleButton()],
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
                    builder: (_) => CustomerScreen(service: customerService),
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