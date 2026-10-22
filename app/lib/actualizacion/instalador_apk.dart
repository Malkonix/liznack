import 'package:flutter/services.dart';

/// El lado Android de la actualización.
///
/// Son cuatro cositas y se hacen con un canal propio de Kotlin en vez de con un
/// plugin: los paquetes que hacen esto llevan años sin mantenimiento y lo único
/// que hace falta es un `Intent` con un `FileProvider`.
///
/// A partir de ahí manda el sistema: muestra su diálogo y el usuario acepta o
/// no. La app **no** puede instalar nada a espaldas de quien tiene el teléfono,
/// y así debe ser.
class InstaladorApk {
  static const _canal = MethodChannel('com.caramelo.liznack/instalador');

  const InstaladorApk();

  /// Verdadero si el sistema permite a esta app instalar paquetes. Desde
  /// Android 8 es un permiso por app que el usuario concede en Ajustes.
  Future<bool> puedeInstalar() async {
    try {
      return await _canal.invokeMethod<bool>('puedeInstalar') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Abre los ajustes para conceder el permiso de instalar.
  Future<void> pedirPermiso() async {
    try {
      await _canal.invokeMethod<void>('pedirPermiso');
    } on PlatformException {
      // Si no se puede abrir la pantalla, el usuario tendrá que ir a mano.
    } on MissingPluginException {
      // Sin canal nativo no hay a dónde ir.
    }
  }

  /// Lanza el instalador del sistema con ese APK.
  Future<void> instalar(String ruta) async {
    try {
      await _canal.invokeMethod<void>('instalar', {'ruta': ruta});
    } on PlatformException catch (e) {
      throw Exception('No se pudo abrir el instalador: ${e.message}');
    } on MissingPluginException {
      throw Exception('Este equipo no puede instalar actualizaciones desde la app.');
    }
  }

  /// La carpeta donde se baja el APK: la caché de la app.
  Future<String> cacheDir() async {
    try {
      return await _canal.invokeMethod<String>('cacheDir') ?? '';
    } on PlatformException {
      return '';
    } on MissingPluginException {
      return '';
    }
  }

  /// Mantiene la CPU despierta mientras baja el APK.
  Future<void> mantenerDespierto() async {
    try {
      await _canal.invokeMethod<void>('mantener');
    } on PlatformException {
      // Si no se puede, la descarga sigue: solo se arriesga a cortarse con la
      // pantalla apagada, que es como estaba antes.
    } on MissingPluginException {
      // Igual: sin canal nativo no hay wake lock.
    }
  }

  Future<void> soltarDespierto() async {
    try {
      await _canal.invokeMethod<void>('soltar');
    } on PlatformException {
      // Nada que hacer; el tope de tiempo del lado nativo lo cubre.
    } on MissingPluginException {
      // Nada que hacer.
    }
  }
}
