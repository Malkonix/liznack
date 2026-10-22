# AGENTS.md

App de ventas de golosinas: Flutter (solo Android) + servidor Node 24/SQLite
sin dependencias. La interfaz, los comentarios y los commits van en español;
"dulce/dulces" se refiere a la golosina, no es un error a corregir. En pruebas y
demos la contraseña es `dulce123`.

## Estructura

- `app/`: Flutter con SQLite local (`sqflite`); escribe primero en el teléfono y
  sincroniza después.
- `server/`: `node:http` + `node:sqlite`; API, portal SSR del administrador y
  generación de PDF.
- `docker-compose.yml`: servidor en Docker con el volumen `liznack-datos`.
- No hay workspace ni task runner: cada carpeta se instala/ejecuta por separado.

## Comandos

Flutter lo maneja `mise` en esta máquina. El proyecto pide **Dart `^3.13.5`**
(Flutter 3.47+): con una versión más vieja, `flutter pub get` falla.

```bash
mise use --global flutter@3.47.7
flutter --version
```

Servidor (Node 24+; `npm install` no hace falta, no hay dependencias):

```bash
cd server && npm test
node --test test/admin.test.js        # un solo archivo
```

App (el CI exige `flutter analyze` limpio):

```bash
cd app && flutter analyze && flutter test
flutter test test/ventas_test.dart    # un solo archivo
flutter test integration_test/venta_en_telefono_test.dart -d <dispositivo>
```

`test/sync_test.dart` **levanta el servidor real** en un puerto libre y con base
temporal: necesita `node` en el PATH, no un servidor ya corriendo (el README de
`app/` está desactualizado en eso). No hay linter ni formatter de JS configurado.

## Modelo de datos (no romper)

- El stock es derivado: `stock_base + movimientos − ventas no anuladas`. No se
  guarda como número absoluto ni viaja en la sincronización.
- El costo de compra vive solo en `almacen.costo_centavos`: no se copia a
  `productos` ni se manda al teléfono. El precio de venta sí viaja.
- Una venta es inmutable salvo `anulada`; el servidor recalcula el total desde
  los ítems y no duplica ventas por UUID.
- Cada cambio aceptado sube `rev` (por usuario); el teléfono pide `rev >
  ultima_rev` y pagina con `hay_mas`.
- Las migraciones son manuales en `migrar()` (`server/src/db.js`) con
  `PRAGMA table_info`: agregar la columna ahí, no hay framework.
- `traslados.tipo` es `envio` o `devolucion`. Una devolución valida contra el
  stock del vendedor, crea un movimiento negativo, suma al almacén y registra el
  traslado.

## Portal del administrador

- SSR sin framework: HTML en `admin_vistas.js`, rutas en `admin.js` (cadena de
  `if`). Los estilos y el JS del portal están en `server/src/public/`.
- Sesión con cookie HMAC `liznack_admin` (12 h) y CSRF con el token de sesión en
  el campo `csrf`. La API usa `Authorization: Bearer`; no mezclar los dos.
- Los cambios del portal usan `dispositivo_id = 'portal-admin'` y suben `rev`
  como cualquier dispositivo.
- Sin `LIZNACK_ADMIN`, `/admin` muestra "Portal desactivado"; la API sigue igual.
- Los PDF se generan con `server/src/pdf.js` (propio, A4). No agregar
  dependencias al servidor para eso.

## Build Android

- `shared_preferences_android` está fijado en **2.4.28** con
  `dependency_overrides`. La 2.5 usa JNI y R8 rompe el APK release: arranca y
  queda en el splash con `NoSuchMethodError`. No quitarlo sin volver a probar el
  APK release en un teléfono.
- `android/gradle.properties` usa `-Xmx4G`; con más memoria el daemon de Gradle
  muere en máquinas de 8 GB.
- El release se firma con la clave del repo: `app/android/app/liznack.jks`
  (alias y contraseña `liznack`). **No se puede cambiar**: Android sólo acepta
  una actualización firmada con la misma clave, así que cambiarla obliga a
  reinstalar la app a mano en cada teléfono. La clave vive en el repo a
  propósito (el repo es público y la app no va a Play); si alguna vez dejó de
  serlo, la clave puede venir del entorno (`LIZNACK_KEYSTORE`,
  `LIZNACK_KEYSTORE_PASSWORD`).
- El paquete es `com.caramelo.liznack` y el label "Liznack".
- No editar `app/build/`, `.dart_tool/` ni `server/data/` (base real).

## Actualizaciones de la app

- La app se actualiza sola: `app/lib/actualizacion/` (feed, descarga con
  verificación SHA-256, instalador) y `app/lib/ui/seccion_actualizaciones.dart`
  (el bloque de **Ajustes → Actualizaciones**).
- El feed son los releases del **mismo repositorio** en GitHub
  (`api.github.com/repos/Malkonix/liznack/releases/latest`). No usar otro repo
  ni un servidor propio: este repo es público y la app se lee sin sesión.
- El APK se verifica contra el `SHA256SUMS` del release antes de instalar: si
  no cuadra, se borra y no se instala.
- La firma la hace Android: la app baja el APK, lo verifica y abre el
  instalador del sistema (`MainActivity.kt`, canal
  `com.caramelo.liznack/instalador`). La app no instala nada sola.
- La versión que corre va compilada en el binario: `--dart-define=LIZNACK_VERSION`
  y `--dart-define=LIZNACK_BUILD` (el CI los pasa; `LIZNACK_BUILD` es el número
  de corrida del workflow). El APK de cada release se llama
  `liznack-<versión>-build.<n>.apk` y el feed lo busca por ese nombre.

## Release

- Cada push a `main` corre las pruebas y publica un release
  `v<versión>-build.<run>` con el APK, el tarball del servidor y el
  `SHA256SUMS` (versión desde `app/pubspec.yaml`). No pushear trabajo a medias.
- Las notas del release salen de `git log -n 6`: escribir commits concisos en
  español neutral, sin voseo ("instala", no "instalá").
- Después de cambiar el servidor, reconstruir Docker con
  `docker compose up -d --build`; los datos quedan en el volumen
  `liznack-datos`.

## Al probar en un teléfono

- La app apunta por defecto a `http://10.0.2.2:3000` (emulador). Se cambia con
  `--dart-define=LIZNACK_SERVIDOR=...` al compilar o en **Ajustes → Servidor**.
- Si la sincronización dice "No se pudo conectar", revisar la IP guardada en
  Ajustes: cambia por DHCP y suele quedar vieja. No es un bug de la app.
- El comprobante PDF de la app no incluye el costo; el del portal sí muestra la
  ganancia.
