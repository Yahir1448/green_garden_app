import '../models/customer.dart';
import '../models/inventory_item.dart';
import '../services/inventory_service.dart';
import '../services/service_catalog_service.dart';

/// Descuenta del inventario los insumos que consumen los [servicios]
/// de un trabajo, según la "receta" configurada para cada uno en el
/// catálogo.
///
/// Solo se descuentan artículos de categoría [ItemCategoria.insumo].
/// Las herramientas no se gastan, así que se ignoran aunque aparezcan
/// en la receta de un servicio (por ejemplo, si un artículo fue insumo
/// y luego se cambió a herramienta).
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
      // Busca el artículo actual en el inventario para conocer su
      // categoría. Si ya no existe, se omite.
      InventoryItem? articulo;
      for (final item in inventoryService.items) {
        if (item.id == insumo.inventarioId) {
          articulo = item;
          break;
        }
      }
      if (articulo == null || articulo.categoria != ItemCategoria.insumo) {
        continue;
      }

      try {
        await inventoryService.ajustarCantidad(insumo.inventarioId, -insumo.cantidad);
      } catch (_) {
        // Si falla un insumo, no interrumpimos el descuento del resto.
      }
    }
  }
}