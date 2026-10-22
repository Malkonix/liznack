import 'package:flutter/material.dart';

import '../nucleo/formato.dart';
import '../tienda.dart';
import 'tema.dart';
import 'tienda_scope.dart';

String textoEstado(EstadoSync estado, int pendientes) => switch (estado) {
      EstadoSync.sincronizado => 'Sincronizado',
      EstadoSync.pendiente => pendientes == 1 ? 'Pendiente · 1' : 'Pendiente · $pendientes',
      EstadoSync.sincronizando => 'Sincronizando',
      EstadoSync.error => 'Error',
      EstadoSync.soloLocal => 'Sin cuenta',
    };

Color colorEstado(EstadoSync estado) => switch (estado) {
      EstadoSync.sincronizado => verdeOk,
      EstadoSync.pendiente => ambarPendiente,
      EstadoSync.sincronizando => Colors.blueGrey,
      EstadoSync.error => rojoError,
      EstadoSync.soloLocal => Colors.grey.shade700,
    };

IconData iconoEstado(EstadoSync estado) => switch (estado) {
      EstadoSync.sincronizado => Icons.cloud_done_outlined,
      EstadoSync.pendiente => Icons.cloud_upload_outlined,
      EstadoSync.sincronizando => Icons.cloud_sync_outlined,
      EstadoSync.error => Icons.cloud_off_outlined,
      EstadoSync.soloLocal => Icons.phone_android_outlined,
    };

class ChipEstadoSync extends StatelessWidget {
  const ChipEstadoSync({super.key});

  @override
  Widget build(BuildContext context) {
    final tienda = TiendaScope.of(context);
    final estado = tienda.estadoSync;
    final color = colorEstado(estado);

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Material(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => mostrarDetalleSync(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (estado == EstadoSync.sincronizando)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: color),
                  )
                else
                  Icon(iconoEstado(estado), size: 16, color: color),
                const SizedBox(width: 6),
                Text(
                  textoEstado(estado, tienda.pendientes),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> mostrarDetalleSync(BuildContext context) {
  final tienda = TiendaScope.of(context);
  return showDialog<void>(
    context: context,
    builder: (contextDialogo) => ListenableBuilder(
      listenable: tienda,
      builder: (contextDialogo, _) {
        final estado = tienda.estadoSync;
        final color = colorEstado(estado);
        return AlertDialog(
          title: const Text('Sincronización'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(iconoEstado(estado), color: color, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        textoEstado(estado, tienda.pendientes),
                        style: TextStyle(color: color, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _linea('Cambios por enviar', '${tienda.pendientes}'),
                _linea(
                  'Última sincronización',
                  tienda.ultimaVez == null ? 'Todavía no' : fechaHoraLarga(tienda.ultimaVez!),
                ),
                if (tienda.error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    tienda.error!,
                    style: const TextStyle(color: rojoError, fontSize: 13),
                  ),
                ],
                if (tienda.avisos.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Avisos del servidor', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  for (final aviso in tienda.avisos)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $aviso', style: const TextStyle(fontSize: 13)),
                    ),
                ],
                const SizedBox(height: 16),
                Text(
                  tienda.sesion?.sincroniza == true
                      ? 'Tus ventas se guardan primero en el teléfono. Cuando hay internet, se suben solas.'
                      : 'Estás sin cuenta: todo queda guardado solo en este teléfono. Entrá con una cuenta para sincronizar.',
                  style: TextStyle(fontSize: 13, color: Colors.brown.shade400),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(contextDialogo).pop(), child: const Text('Cerrar')),
            if (tienda.sesion?.sincroniza == true)
              FilledButton(
                onPressed: tienda.sincronizando ? null : () => tienda.sincronizar(),
                child: const Text('Sincronizar ahora'),
              ),
          ],
        );
      },
    ),
  );
}

Widget _linea(String etiqueta, String valor) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(etiqueta, style: const TextStyle(fontSize: 13))),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              valor,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
