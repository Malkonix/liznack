import 'package:flutter/material.dart';

import '../sync/api_cliente.dart';
import 'tema.dart';
import 'tienda_scope.dart';

class LoginPantalla extends StatefulWidget {
  const LoginPantalla({super.key});

  @override
  State<LoginPantalla> createState() => _LoginPantallaState();
}

class _LoginPantallaState extends State<LoginPantalla> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _clave = TextEditingController();
  final _servidor = TextEditingController();
  final _servidorKey = GlobalKey<FormFieldState<String>>();

  bool _cargando = false;
  bool _verClave = false;
  bool _servidorAbierto = false;
  String? _error;
  bool _servidorIniciado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_servidorIniciado) {
      final tienda = TiendaScope.of(context);
      _servidor.text = tienda.servidorUrl;
      // Si la sesión se cayó sola (token vencido), se explica por qué hay que
      // volver a entrar en vez de dejar al vendedor adivinando.
      _error = tienda.avisoSesion;
      _servidorIniciado = true;
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _clave.dispose();
    _servidor.dispose();
    super.dispose();
  }

  Future<void> _entrar({required bool crear}) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final tienda = TiendaScope.of(context);
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      if (_servidor.text.trim() != tienda.servidorUrl) {
        await tienda.cambiarServidor(_servidor.text);
      }
      if (crear) {
        await tienda.crearCuenta(email: _email.text, clave: _clave.text);
      } else {
        await tienda.ingresar(email: _email.text, clave: _clave.text);
      }
    } on ErrorApi catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo completar. Revisá los datos e intentá de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _guardarServidor() async {
    try {
      await TiendaScope.of(context).cambiarServidor(_servidor.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dirección del servidor guardada.')),
        );
      }
    } on ErrorApi catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: const BoxDecoration(
                        color: carameloSuave,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Text('🍬', style: TextStyle(fontSize: 44)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Liznack',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Ventas e inventario para tu emprendimiento',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: Colors.brown.shade400),
                  ),
                  const SizedBox(height: 28),
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Correo',
                            hintText: 'vos@ejemplo.com',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                          validator: (valor) {
                            final texto = (valor ?? '').trim();
                            if (texto.isEmpty) return 'Escribí tu correo.';
                            if (!texto.contains('@') || !texto.contains('.')) {
                              return 'Ese correo no parece válido.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _clave,
                          obscureText: !_verClave,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _cargando ? null : _entrar(crear: false),
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _verClave ? 'Ocultar contraseña' : 'Mostrar contraseña',
                              icon: Icon(_verClave ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _verClave = !_verClave),
                            ),
                          ),
                          validator: (valor) {
                            if ((valor ?? '').length < 6) {
                              return 'Usá al menos 6 caracteres.';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: rojoError.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline, color: rojoError, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(color: rojoError, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _cargando ? null : () => _entrar(crear: false),
                    child: _cargando
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Text('Ingresar'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _cargando ? null : () => _entrar(crear: true),
                    child: const Text('Crear cuenta'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Creá la cuenta una vez, con internet. Después podés vender sin conexión.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.brown.shade300),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    elevation: 0,
                    color: Colors.white.withValues(alpha: 0.7),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: ExpansionTile(
                      initiallyExpanded: _servidorAbierto,
                      onExpansionChanged: (abierto) => setState(() => _servidorAbierto = abierto),
                      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      leading: const Icon(Icons.dns_outlined, size: 20),
                      title: const Text('Servidor', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        TiendaScope.of(context).servidorUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                      children: [
                        TextFormField(
                          key: _servidorKey,
                          controller: _servidor,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Dirección del servidor',
                            hintText: 'http://192.168.0.10:3000',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'En el emulador usá http://10.0.2.2:3000. En un teléfono, la IP de la '
                          'computadora en la misma red wifi.',
                          style: TextStyle(fontSize: 12, color: Colors.brown.shade300),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _cargando ? null : _guardarServidor,
                            child: const Text('Guardar dirección'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'La cuenta la crea el administrador desde el portal, '
                    'o podés crearla vos acá la primera vez.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.brown.shade300),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
