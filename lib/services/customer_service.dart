import 'package:flutter/foundation.dart';

import '../models/customer.dart';

/// Servicio encargado de administrar los clientes/trabajos agendados.
/// Igual que [InventoryService], concentra toda la lógica de negocio
/// separada de las vistas, y notifica a quien lo escuche cuando los
/// datos cambian.
class CustomerService extends ChangeNotifier {
  final List<Customer> _customers = [
    Customer(
      id: '1',
      nombre: 'María Torres',
      lugar: 'Calle 5ta, Ciudad Jardín',
      fecha: DateTime.now().add(const Duration(days: 2)),
      precio: 45.0,
    ),
    Customer(
      id: '2',
      nombre: 'Carlos Pérez',
      lugar: 'Av. Las Palmas 120',
      fecha: DateTime.now().add(const Duration(days: 5)),
      precio: 80.0,
    ),
  ];

  /// Lista de solo lectura de todos los clientes, ordenada por fecha.
  List<Customer> get customers {
    final lista = List<Customer>.from(_customers);
    lista.sort((a, b) => a.fecha.compareTo(b.fecha));
    return List.unmodifiable(lista);
  }

  void agregarCliente(Customer cliente) {
    _customers.add(cliente);
    notifyListeners();
  }

  void actualizarCliente(String id, Customer actualizado) {
    final index = _customers.indexWhere((c) => c.id == id);
    if (index != -1) {
      _customers[index] = actualizado;
      notifyListeners();
    }
  }

  void eliminarCliente(String id) {
    _customers.removeWhere((c) => c.id == id);
    notifyListeners();
  }
}