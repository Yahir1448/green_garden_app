import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';
import '../services/sync_queue_service.dart';

/// Franja delgada que aparece arriba de una pantalla cuando no hay
/// conexión, o mientras hay cambios pendientes de sincronizar. Se
/// actualiza sola (escucha [ConnectivityService] y [SyncQueueService]):
/// basta con colocarla en el `body` de cualquier pantalla, no hace
/// falta pasarle nada.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(
        [ConnectivityService.instance, SyncQueueService.instance],
      ),
      builder: (context, _) {
        final online = ConnectivityService.instance.isOnline;
        final pendientes = SyncQueueService.instance.cantidadPendiente;
        final sincronizando = SyncQueueService.instance.sincronizando;

        if (online && pendientes == 0) return const SizedBox.shrink();

        final String texto;
        final Color color;
        final IconData icono;

        if (!online) {
          color = Colors.orange;
          icono = Icons.cloud_off;
          texto = pendientes > 0
              ? 'Sin conexión — $pendientes cambio${pendientes == 1 ? '' : 's'} pendiente${pendientes == 1 ? '' : 's'} de sincronizar'
              : 'Sin conexión — los cambios se guardan y se suben después';
        } else if (sincronizando) {
          color = Colors.blueGrey;
          icono = Icons.cloud_sync;
          texto = 'Sincronizando $pendientes cambio${pendientes == 1 ? '' : 's'}...';
        } else {
          color = Colors.blueGrey;
          icono = Icons.cloud_upload_outlined;
          texto = '$pendientes cambio${pendientes == 1 ? '' : 's'} sin sincronizar todavía';
        }

        return Container(
          width: double.infinity,
          color: color.withValues(alpha: 0.15),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Icon(icono, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  texto,
                  style: TextStyle(fontSize: 12, color: color),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}