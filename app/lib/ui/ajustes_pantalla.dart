import 'package:flutter/material.dart';

import '../nucleo/formato.dart';
import '../tienda.dart';
import 'estado_sync_widget.dart';
import 'tema.dart';
import 'tienda_scope.dart';

class AjustesPantalla extends StatefulWidget {
  const AjustesPantalla({super.key});

  @override
  State<AjustesPantalla> createState() => _AjustesPantallaState();
}

class _AjustesPantallaState extends State<AjustesPantalla> {
  final _servidor = TextEditingController();
  bool _servidorIniciado = false;
  bool _probando = false;
  bool _guardando = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_servidorIniciado) {
      _servidor.text = TiendaScope.of(context).servidorUrl;
      _servidorIniciado = true;
    }
  }

  @override
  void dispose() {
    _servidor.dispose();
    super.dispose();
  }

  Future<void> _sincronizar() async {
    final tienda = TiendaScope.of(context);
    await tienda.sincronizar();
    if (!mounted) return;
    final mensaje = switch (tienda.estadoSync) {
      EstadoSync.sincronizado => 'Todo sincronizado.',
      EstadoSync.error => tienda.error ?? 'No se pudo sincronizar.',
      EstadoSync.soloLocal => 'Estás sin cuenta: no hay nada que sincronizar.',
      _ => 'Sincronización en curso.',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _guardarServidor() async {
    setState(() => _guardando = true);
    try {
      await TiendaScope.of(context).cambiarServidor(_servidor.text);
      if (!mounted) return;
      _servidor.text = TiendaScope.of(context).servidorUrl;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dirección guardada.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _probar() async {
    setState(() => _probando = true);
    final responde = await TiendaScope.of(context).probarServidor();
    if (!mounted) return;
    setState(() => _probando = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          responde
              ? 'El servidor responde bien.'
              : 'No se pudo conectar. Revisá la dirección y el wifi.',
        ),
      ),
    );
  }

  Future<void> _salir() async {
    final tienda = TiendaScope.of(context);
    final esLocal = tienda.sesion?.soloLocal ?? false;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(esLocal ? 'Entrar con una cuenta' : 'Cerrar sesión'),
        content: Text(
          esLocal
              ? 'Vas a volver a la pantalla de ingreso. Tus productos y ventas quedan guardados '
                  'en este teléfono y se suben cuando entres con una cuenta.'
              : 'Los datos ya sincronizados quedan en el servidor. Lo que esté pendiente sigue '
                  'guardado en este teléfono hasta que vuelvas a entrar.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Continuar')),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    await tienda.cerrarSesion();
  }

  @override
  Widget build(BuildContext context) {
    final tienda = TiendaScope.of(context);
    final sesion = tienda.sesion;
    final estado = tienda.estadoSync;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        _Seccion(
          titulo: 'Cuenta',
          hijos: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: carameloSuave,
                child: Icon(sesion?.soloLocal == true ? Icons.phone_android : Icons.person_outline,
                    color: caramelo),
              ),
              title: Text(sesion?.email ?? 'Sin sesión'),
              subtitle: Text(
                sesion?.sincroniza == true
                    ? 'Sincroniza con el servidor'
                    : 'Solo este teléfono · sin sincronización',
              ),
            ),
            OutlinedButton.icon(
              onPressed: _salir,
              icon: Icon(sesion?.sincroniza == true ? Icons.logout : Icons.login),
              label: Text(sesion?.sincroniza == true ? 'Cerrar sesión' : 'Entrar con una cuenta'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Seccion(
          titulo: 'Sincronización',
          hijos: [
            Row(
              children: [
                Icon(iconoEstado(estado), size: 20, color: colorEstado(estado)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    textoEstado(estado, tienda.pendientes),
                    style: TextStyle(fontWeight: FontWeight.w700, color: colorEstado(estado)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _Dato(etiqueta: 'Cambios por enviar', valor: '${tienda.pendientes}'),
            _Dato(
              etiqueta: 'Última sincronización',
              valor: tienda.ultimaVez == null ? 'Todavía no' : fechaHoraLarga(tienda.ultimaVez!),
            ),
            if (tienda.error != null) ...[
              const SizedBox(height: 8),
              Text(tienda.error!, style: const TextStyle(color: rojoError, fontSize: 13)),
            ],
            for (final aviso in tienda.avisos)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• $aviso', style: const TextStyle(fontSize: 12.5)),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: tienda.sincronizando || sesion?.sincroniza != true ? null : _sincronizar,
              icon: tienda.sincronizando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.sync),
              label: Text(tienda.sincronizando ? 'Sincronizando…' : 'Sincronizar ahora'),
            ),
            if (sesion?.sincroniza != true) ...[
              const SizedBox(height: 8),
              Text(
                'Entrá con una cuenta para poder sincronizar entre el teléfono y el servidor.',
                style: TextStyle(fontSize: 12, color: Colors.brown.shade400),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        _Seccion(
          titulo: 'Servidor',
          hijos: [
            TextField(
              controller: _servidor,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Dirección',
                hintText: 'http://192.168.0.10:3000',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Emulador: http://10.0.2.2:3000\n'
              'Teléfono: la IP de la computadora en la misma red wifi '
              '(la muestra el servidor al arrancar).',
              style: TextStyle(fontSize: 12, color: Colors.brown.shade400),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _guardando ? null : _guardarServidor,
                    child: const Text('Guardar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _probando ? null : _probar,
                    child: _probando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Probar'),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Seccion(
          titulo: 'Cómo funciona',
          hijos: [
            Text(
              'Todo se guarda primero en el teléfono: podés vender sin internet, sin esperas.\n\n'
              'Cuando hay conexión, la app sube lo pendiente y baja los cambios del servidor. '
              'Si el mismo producto se cambió en dos lados, se queda con el cambio más reciente '
              'y te avisa acá.\n\n'
              'El stock se calcula con las ventas y las reposiciones, así dos teléfonos no se '
              'pisan el inventario.',
              style: TextStyle(fontSize: 13, height: 1.45, color: Colors.brown.shade500),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Liznack 0.1.0 · hecho para vender golosinas',
            style: TextStyle(fontSize: 11.5, color: Colors.brown.shade300),
          ),
        ),
      ],
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion({required this.titulo, required this.hijos});

  final String titulo;
  final List<Widget> hijos;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            titulo,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.4),
          ),
          const SizedBox(height: 10),
          ...hijos,
        ],
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.etiqueta, required this.valor});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(etiqueta, style: const TextStyle(fontSize: 12.5))),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              valor,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
