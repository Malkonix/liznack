import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../actualizacion/feed_actualizaciones.dart';
import '../actualizacion/instalador_apk.dart';
import '../actualizacion/revisor.dart';
import '../actualizacion/servicio_actualizacion.dart';
import '../actualizacion/version_app.dart';
import 'tema.dart';

/// Bloque "Actualizaciones" de la pantalla de ajustes.
///
/// Mira el último release publicado en el repo de GitHub, lo descarga, **comprueba
/// su SHA-256** y se lo pasa al instalador de Android. El diálogo de
/// instalación lo enseña el sistema: la app no instala nada sola.
class SeccionActualizaciones extends StatefulWidget {
  const SeccionActualizaciones({super.key, this.servicio, this.revisor});

  /// Se puede pasar uno hecho a medida para poder probarlo.
  final ServicioActualizacion? servicio;
  final Revisor? revisor;

  @override
  State<SeccionActualizaciones> createState() => _SeccionActualizacionesState();
}

class _SeccionActualizacionesState extends State<SeccionActualizaciones> {
  final _instalador = const InstaladorApk();
  late final ServicioActualizacion _servicio =
      widget.servicio ?? ServicioActualizacion();
  Revisor? _revisor;

  ReleaseInfo? _disponible;
  bool _buscando = false;
  bool _descargando = false;
  double _progreso = 0;
  String? _error;
  bool _auto = true;

  @override
  void initState() {
    super.initState();
    _cargarPreferencias();
  }

  @override
  void dispose() {
    _servicio.cerrar();
    super.dispose();
  }

  Future<void> _cargarPreferencias() async {
    // Si el teléfono no tiene preferencias disponibles (por ejemplo en una
    // prueba de widgets), el bloque funciona igual: solo no recuerda la
    // elección de "revisar sola".
    try {
      final prefs = await SharedPreferences.getInstance();
      final revisor =
          widget.revisor ?? Revisor(servicio: _servicio, prefs: prefs);
      final auto = await revisor.automatico();
      if (!mounted) return;
      setState(() {
        _revisor = revisor;
        _auto = auto;
      });
    } catch (_) {
      // Sin preferencias se sigue sin la opción de revisar sola.
    }
  }

  Future<void> _buscar() async {
    setState(() {
      _buscando = true;
      _error = null;
    });
    try {
      final estado = await _servicio.buscar();
      if (!mounted) return;
      setState(() {
        _disponible = estado.disponible;
        _buscando = false;
      });
      if (!estado.hayNovedad && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Estás al día: no hay versión nueva.')),
        );
      }
    } on ErrorFeed catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.mensaje;
        _buscando = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _buscando = false;
      });
    }
  }

  Future<void> _instalar() async {
    final release = _disponible;
    if (release == null) return;

    // Sin el permiso de "instalar apps desconocidas" el sistema descarta el
    // Intent en silencio, así que conviene pedirlo antes de gastar la
    // descarga.
    if (!await _instalador.puedeInstalar()) {
      if (!mounted) return;
      final seguir = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Falta un permiso'),
          content: const Text(
            'Android necesita que le des permiso a Liznack para instalar '
            'actualizaciones. Te lleva a Ajustes; activa "Permitir de esta '
            'fuente" y vuelve acá.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Ahora no'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ir a Ajustes'),
            ),
          ],
        ),
      );
      if (seguir == true) await _instalador.pedirPermiso();
      return;
    }

    setState(() {
      _descargando = true;
      _progreso = 0;
      _error = null;
    });
    try {
      await _servicio.descargarEInstalar(release, onProgreso: (recibidos, total) {
        if (mounted && total > 0) setState(() => _progreso = recibidos / total);
      });
    } on ErrorActualizacion catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _descargando = false);
    }
  }

  Future<void> _alternarAuto(bool valor) async {
    setState(() => _auto = valor);
    await _revisor?.setAutomatico(valor);
  }

  @override
  Widget build(BuildContext context) {
    final release = _disponible;
    final hayNovedad =
        release != null && release.version.esMasNuevaQue(VersionApp.actual);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Versión actual: ${VersionApp.actual}',
          style: const TextStyle(fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        if (hayNovedad) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: carameloSuave,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hay una versión ${release.version}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
                if (release.notas.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    release.notas.trim(),
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, height: 1.35),
                  ),
                ],
                const SizedBox(height: 10),
                if (_descargando) ...[
                  LinearProgressIndicator(value: _progreso > 0 ? _progreso : null),
                  const SizedBox(height: 6),
                  Text(
                    'Descargando… ${(_progreso * 100).toStringAsFixed(0)} %',
                    style: const TextStyle(fontSize: 12),
                  ),
                ] else
                  FilledButton.icon(
                    onPressed: _instalar,
                    icon: const Icon(Icons.download),
                    label: const Text('Descargar e instalar'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (_error != null) ...[
          Text(_error!, style: const TextStyle(color: rojoError, fontSize: 12.5)),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          onPressed: _buscando || _descargando ? null : _buscar,
          icon: _buscando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.system_update),
          label: Text(_buscando ? 'Buscando…' : 'Buscar actualización'),
        ),
        const SizedBox(height: 4),
        // El bloque de ajustes pinta su propio fondo, y un ListTile dentro de
        // un DecoratedBox pierde el efecto del toque: por eso el Material.
        if (_revisor != null)
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _auto,
              onChanged: _alternarAuto,
              title: const Text('Revisar sola', style: TextStyle(fontSize: 13.5)),
              subtitle: Text(
                'Mira si hay versión nueva al abrir la app, como mucho una vez por día.',
                style: TextStyle(fontSize: 12, color: Colors.brown.shade400),
              ),
            ),
          ),
        Text(
          'La descarga se comprueba contra el SHA-256 publicado con la versión. Si no '
          'cuadra, se descarta y no se instala. Si se corta, se reanuda donde iba.',
          style: TextStyle(fontSize: 11.5, color: Colors.brown.shade400),
        ),
      ],
    );
  }
}
