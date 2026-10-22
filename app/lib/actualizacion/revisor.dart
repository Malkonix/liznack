import 'package:shared_preferences/shared_preferences.dart';

import 'feed_actualizaciones.dart';
import 'servicio_actualizacion.dart';

/// Revisa el feed por su cuenta, sin molestar, y avisa si hay versión nueva.
///
/// Como mucho una vez por día: la API de GitHub sin sesión tiene un límite de
/// peticiones por hora y por IP, y el teléfono puede estar sin internet medio
/// tiempo. El resultado se guarda aunque no haya red: si el chequeo falló, se
/// reintenta al día siguiente.
class Revisor {
  Revisor({required this.servicio, required this.prefs});

  final ServicioActualizacion servicio;
  final SharedPreferences prefs;

  static const claveAutomatico = 'liznack.actualizacion.automatico';
  static const claveUltimaRevision = 'liznack.actualizacion.ultima_revision';

  /// Cada cuánto se mira solo.
  static const Duration intervalo = Duration(hours: 24);

  /// Si mira solo al abrir la app.
  Future<bool> automatico() async => prefs.getBool(claveAutomatico) ?? true;

  Future<void> setAutomatico(bool valor) =>
      prefs.setBool(claveAutomatico, valor);

  /// Cuándo miró por última vez.
  DateTime? ultimaRevision() {
    final ms = prefs.getInt(claveUltimaRevision) ?? 0;
    if (ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Mira el feed si toca y devuelve el release nuevo, si lo hay.
  ///
  /// Devuelve `null` cuando no toca revisar, cuando no hay nada nuevo o
  /// cuando el feed no se pudo leer: en ningún caso molesta al usuario.
  Future<ReleaseInfo?> revisarSiToca() async {
    if (!await automatico()) return null;
    final ultima = ultimaRevision();
    final ahora = DateTime.now();
    if (ultima != null && ahora.difference(ultima) < intervalo) return null;
    await prefs.setInt(claveUltimaRevision, ahora.millisecondsSinceEpoch);
    try {
      final estado = await servicio.buscar();
      if (estado.hayNovedad) return estado.disponible;
    } catch (_) {
      // Sin red, sin releases o GitHub ocupado: no es para tanto. Se reintenta
      // en la próxima revisión.
    }
    return null;
  }
}
