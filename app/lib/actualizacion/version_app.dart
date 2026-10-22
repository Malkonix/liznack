import 'package:pub_semver/pub_semver.dart';

/// Versión de Liznack: la del `pubspec.yaml` y el número de build del release
/// que la compiló.
///
/// Son dos cosas porque el CI publica un release en cada push a `main` y la
/// versión de `pubspec.yaml` no cambia en cada push. El número de build (el
/// número de corrida del workflow) es lo que distingue dos releases de la
/// misma versión y lo que permite actualizarse sin tocar el `pubspec.yaml`.
class VersionApp implements Comparable<VersionApp> {
  const VersionApp(this.version, this.build);

  final Version version;
  final int build;

  static Version? _parse(String texto) {
    try {
      return Version.parse(texto.trim());
    } on FormatException {
      return null;
    }
  }

  /// La versión que corre ahora, compilada en el binario.
  ///
  /// El CI la pasa con `--dart-define=LIZNACK_VERSION=... --dart-define=LIZNACK_BUILD=...`.
  /// Sin esas variables (una compilación a mano) la app se toma como la más
  /// vieja: cualquier release publicado le sirve para actualizarse.
  static final VersionApp actual = VersionApp(
    _parse(const String.fromEnvironment('LIZNACK_VERSION', defaultValue: '0.0.0')) ??
        Version(0, 0, 0),
    const int.fromEnvironment('LIZNACK_BUILD', defaultValue: 0),
  );

  /// Etiqueta de un release: `v0.1.0-build.8`. Sin build: `v0.1.0`.
  static final _reEtiqueta = RegExp(r'^v?(\d+\.\d+\.\d+)(?:-build\.(\d+))?$');

  /// Lee la versión de la etiqueta de un release. `null` si no es una versión.
  static VersionApp? desdeEtiqueta(String etiqueta) {
    final m = _reEtiqueta.firstMatch(etiqueta.trim());
    if (m == null) return null;
    final version = _parse(m.group(1)!);
    if (version == null) return null;
    return VersionApp(version, int.parse(m.group(2) ?? '0'));
  }

  @override
  int compareTo(VersionApp otra) {
    final porVersion = version.compareTo(otra.version);
    if (porVersion != 0) return porVersion;
    return build.compareTo(otra.build);
  }

  /// Verdadero si esta versión es más nueva que [otra].
  bool esMasNuevaQue(VersionApp otra) => compareTo(otra) > 0;

  @override
  String toString() => build > 0 ? '$version (build $build)' : '$version';

  @override
  bool operator ==(Object other) =>
      other is VersionApp && other.version == version && other.build == build;

  @override
  int get hashCode => Object.hash(version, build);
}
