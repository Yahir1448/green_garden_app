import '../models/customer.dart';
import '../services/inventory_service.dart';
import '../services/service_catalog_service.dart';

/// Descuenta del inventario los insumos que consumen los [servicios]
/// de un trabajo, según la "receta" configurada para cada uno en el
/// catálogo (ver `RecetasScreen`).
///
/// Se llama justo después de marcar un trabajo como realizado, tanto
/// desde la pantalla de Clientes como desde la Agenda, para que el
/// descuento sea automático sin importar desde dónde se marque.
///
/// Un servicio "Personalizado" (sin `servicioId`, porque no vino del
/// catálogo) o un servicio del catálogo sin receta configurada
/// simplemente no descuenta nada — no es un error, solo no hay
/// insumos que restar.
Future<void> descontarInsumosDelTrabajo({
  required List<ServicioAgendado> servicios,
  required ServiceCatalogService serviceCatalog,
  required InventoryService inventoryService,
}) async {
  for (final servicio in servicios) {
    final delCatalogo = serviceCatalog.buscarPorId(servicio.servicioId);
    if (delCatalogo == null || delCatalogo.receta.isEmpty) continue;

    for (final insumo in delCatalogo.receta) {
      try {
        await inventoryService.ajustarCantidad(insumo.inventarioId, -insumo.cantidad);
      } catch (_) {
        // Si el insumo ya no existe en el inventario (se borró después
        // de configurar la receta), no interrumpimos el descuento del
        // resto de insumos/servicios por uno solo que falle.
      }
    }
  }
}