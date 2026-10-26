# Liznack 🍬

App Android para vender golosinas (chocolates, gomitas, galletitas…) y llevar el
inventario, con un servidor mínimo para respaldar y compartir los datos entre
teléfonos. **Toda la interfaz está en español** y se puede vender sin internet.

Repositorio: <https://github.com/Malkonix/liznack>.

- Catálogo con precio y stock.
- Venta en dos toques, con cantidades y total automático.
- El stock baja solo con cada venta y se puede reponer.
- Resumen del día: cuánto se vendió y cuánta plata entró.
- Historial de ventas, con anulación (devuelve el stock).
- **Reporte de venta**: el detalle de cada venta en pantalla y en PDF, para
  compartir o imprimir, tanto en la app como en el portal del administrador.
- **Devoluciones**: lo que ya está en manos de un vendedor puede volver al
  almacén, y el portal muestra en todo momento **qué tiene cada vendedor**.
- Todo se guarda primero en el teléfono y se sincroniza cuando hay red, con
  estado visible: `Pendiente`, `Sincronizado`, `Sincronizando`, `Error`.

## Estructura

```
app/                App Flutter (solo Android), interfaz en español
server/             Servidor Node.js + SQLite, sin dependencias externas
docker-compose.yml  Servidor en Docker, con los datos en un volumen
```

## 1. Levantar el servidor

Requisito: **Node.js 24 o más nuevo** (usa el SQLite que ya viene adentro).

```bash
cd server
npm start
```

No hace falta `npm install`: el servidor no tiene dependencias.

Al arrancar muestra las direcciones para conectar el teléfono:

```
Liznack · servidor de inventario y ventas
  Escuchando en el puerto 3000
  Emulador Android: http://10.0.2.2:3000
  Teléfono en la misma red: http://192.168.0.10:3000
  Base de datos: data/liznack.db
```

La base queda en `server/data/liznack.db`. Para empezar de cero, parar el servidor
y borrar esa carpeta. Se puede cambiar con `PORT` y `DATABASE_FILE`:

```bash
PORT=4000 DATABASE_FILE=/tmp/liznack.db npm start
```

### Portal del administrador

El padre puede mirar y administrar todo desde el navegador:

- **Resumen**: ventas del día, plata, **ganancia** y stock bajo.
- **Almacén**: el depósito central. Cada producto se carga con **costo de compra
  y precio de venta**; la tabla muestra el margen por unidad y desde ahí se
  envían unidades al inventario de cada vendedor. También muestra **en qué
  vendedores está cada producto** y cuántas unidades tiene cada uno, con
  **Editar** (incluso el precio) y **Devolver** al almacén.
- **Inventario**: todos los productos de todas las cuentas, con filtros por
  vendedor, nombre, stock bajo y archivados.
- **Cuentas**: crear, borrar, cambiar contraseña y ver el detalle de cada hijo.
- **Ventas**: historial completo con **qué se vendió** en cada venta, cuánto
  entró y cuánta ganancia dejó, con la opción de anular. Cada venta tiene su
  página de detalle y el **PDF** del comprobante; el listado completo se
  descarga como PDF con los filtros aplicados.

Se activa con una contraseña en `LIZNACK_ADMIN`:

```bash
LIZNACK_ADMIN=tu-clave npm start
```

y queda en `http://<IP-del-servidor>:3000/admin`. Sin esa variable, `/admin`
muestra **Portal desactivado** y la API sigue funcionando igual.

Lo que el padre cambia ahí (precio, stock, anular una venta, enviar del almacén,
una devolución) se guarda con `dispositivo_id = 'portal-admin'` y sube la
revisión, así que el teléfono lo recibe en la próxima sincronización.

### Compras y ganancias

El **costo de compra vive solo en el almacén**: no se guarda en los productos del
vendedor ni viaja en la sincronización, así que el teléfono nunca lo muestra.
El precio de venta sí llega al teléfono y es el que se cobra. El costo se carga
al dar de alta el producto en **Almacén** o al editarlo desde **Almacén** o
**Inventario**; si todavía no estaba en el depósito, se crea ahí con stock 0.

La ganancia se calcula por venta como `precio de venta − costo de compra`, y se
resume en **Resumen** (hoy y últimos 7 días) y en **Ventas**. Si un producto
vendido no está en el almacén, no hay costo conocido: la venta se marca
**“sin costo”** y no se suma, en vez de mostrar un número inventado.

El almacén también resume **invertido** (costo × unidades), **valor de venta**
(precio × unidades) y la **ganancia** que dejaría si se vende todo.

### Reportes y PDF

Hay dos caminos para el mismo comprobante:

- **Portal**: **Ventas → Ver** abre el detalle de una venta (fecha, estado,
  ítems, total y ganancia) con **Descargar PDF**; en el listado, **PDF** baja el
  reporte completo con los filtros que estén puestos.
- **App del vendedor**: la pestaña **Ventas** tiene **PDF del día** y cada venta
  abre su detalle, con **Compartir PDF** e **Imprimir**.

El PDF lo arma cada lado por su cuenta, sin servicios externos: el servidor con
un generador propio (`server/src/pdf.js`, A4, sin comprimir para poder probarlo)
y la app con `pdf` + `printing`. **El costo de compra no entra en el PDF de la
app**; el del portal sí muestra la ganancia, porque es para el administrador.

### Almacén → vendedores

El almacén es de la casa, no de un teléfono. Al enviar stock a un vendedor:

1. Se descuenta del almacén.
2. Si el vendedor ya tiene ese producto (mismo nombre, sin importar mayúsculas
   ni espacios), se le suma una reposición; si estaba archivado, se reactiva.
3. Si no lo tiene, se le crea con el nombre y el precio del almacén.
4. Se registra el envío en el historial (`traslados`) y se sube la revisión, así
   que el teléfono recibe el stock nuevo en la próxima sincronización.

El almacén no se sincroniza con los teléfonos: solo ve lo que hay en el depósito.
El **stock en manos de cada vendedor** sí sale de los productos sincronizados, así
que se actualiza con cada venta, reposición o edición.

### Devoluciones

Un vendedor puede devolver al almacén lo que todavía tiene. Desde
**Almacén → En manos de los vendedores**, **Devolver** pide la cantidad:

1. Se valida contra el stock actual del vendedor (no se puede devolver de más).
2. Se crea un movimiento negativo con motivo `devolucion`, así que el teléfono lo
   recibe en la próxima sincronización y descuenta el stock.
3. Se suma al almacén y se registra el traslado con `tipo = 'devolucion'`.
4. Si el producto no existía en el almacén, se crea con costo 0 para no inventar
   un costo de compra.

El historial **Últimos movimientos** muestra envíos y devoluciones con su tipo.
También se puede **editar** un producto en manos del vendedor (nombre, precio de
venta y costo de compra) desde esa misma tabla o desde **Inventario**; el costo
se guarda en el almacén, sin viajar al teléfono, y el resto sube la revisión y
llega en la próxima sincronización.

### Releases automáticos

Cada push a `main` corre las pruebas del servidor y de la app y, si pasan,
publica un release con:

- `liznack-<versión>-build.<n>.apk`: la app lista para instalar.
- `liznack-servidor.tar.gz`: el servidor y el `docker-compose.yml`.
- `SHA256SUMS`: la firma de cada archivo, para comprobarlos.

La versión sale de `version:` en `app/pubspec.yaml` y el número de build del run
de GitHub, así que no hay que tocar nada a mano. El workflow está en
`.github/workflows/release.yml` y también se puede lanzar desde
**Actions → Release → Run workflow**.

```bash
git push origin main      # pruebas + release
```

### Actualizar la app desde la app

La app se actualiza sola, sin buscar el APK a mano: en **Ajustes →
Actualizaciones** hay un botón que busca la última versión publicada.

- El feed son los **releases de este mismo repositorio** en GitHub
  (`api.github.com/repos/Malkonix/liznack/releases/latest`). No hay que
  configurar nada en el teléfono ni usar otra cuenta: el repositorio es
  público.
- La app mira sola, una vez por día, al abrir. Si hay versión nueva aparece un
  aviso; se puede desactivar en el mismo lugar.
- El APK se descarga y **se comprueba contra el `SHA256SUMS`** del release. Si
  no cuadra, la descarga se borra y no se instala. Si se corta, se reanuda
  desde donde iba.
- Después el sistema muestra su propio diálogo de instalación: la app no
  instala nada sola. La primera vez Android pide permiso de "instalar apps
  desconocidas" para Liznack.
- Los APK se firman con la clave del repo (`app/android/app/liznack.jks`).
  Android sólo acepta una actualización firmada con la misma clave que la
  app instalada, así que **no se puede cambiar** sin reinstalar a mano en
  cada teléfono. La clave no es un secreto: el repositorio es público y la
  app se instala a mano, sin Play Store. Si algún día el repositorio deja de
  ser público, la clave puede pasar a venir del entorno
  (`LIZNACK_KEYSTORE`, `LIZNACK_KEYSTORE_PASSWORD`) o de un secreto del CI.

### Con Docker (opcional)

Si no querés instalar Node en la máquina que hace de servidor:

```bash
cp .env.example .env      # poné tu contraseña en LIZNACK_ADMIN
docker compose up -d --build
```

Queda en `http://<IP-de-la-máquina>:3000` para los teléfonos y el portal en
`http://<IP-de-la-máquina>:3000/admin`. El puerto publicado se cambia con
`LIZNACK_PUERTO` en el `.env`.

Los datos viven en el volumen `liznack-datos`, así que sobreviven a los
reinicios, a `docker compose down` y a reconstruir la imagen. Para borrar todo
(base incluida):

```bash
docker compose down -v
```

Para ver los logs o el estado:

```bash
docker compose logs -f
docker compose ps
```

Pruebas del servidor (25 casos de punta a punta por HTTP, incluidos el portal, el
almacén, las devoluciones y los PDF):

```bash
cd server
npm test
```

## 2. Correr la app

Requisitos: **Flutter 3.47 o más nuevo** (el `pubspec.yaml` pide Dart
`^3.13.5`) y el SDK de Android. En esta máquina Flutter lo maneja `mise`:

```bash
mise use --global flutter@3.47.7    # una vez
flutter --version
```

```bash
cd app
flutter pub get
flutter run            # con un emulador o un teléfono conectado por USB
```

Para generar el APK de prueba:

```bash
cd app
flutter build apk --debug
# queda en app/build/app/outputs/flutter-apk/app-debug.apk
```

Para instalarlo en un teléfono conectado:

```bash
adb install -r app/build/app/outputs/flutter-apk/app-debug.apk
```

### Notas del build de Android

- `shared_preferences_android` está fijado en **2.4.28** con
  `dependency_overrides`. La 2.5 llama al plugin por JNI y el R8 del build
  release borra clases de Kotlin: el APK arranca y queda en el splash con
  `NoSuchMethodError` / `ClassNotFoundException`. La 2.4.28 usa MethodChannel.
  Si se actualiza, **probar el APK release en un teléfono** antes de publicarlo.
- El APK release se firma con la clave del repo (`app/android/app/liznack.jks`,
  alias `liznack`, contraseña `liznack`). Sirve para instalar y para
  actualizarse desde la app; no para publicar en Play.
- `android/gradle.properties` usa `-Xmx4G -XX:MaxMetaspaceSize=1G`: con `-Xmx8G`
  el daemon de Gradle se queda sin memoria y muere en máquinas de 8 GB.
- El build tarda uno o dos minutos y pesa unos 55 MB.

### Primera vez

1. La cuenta la crea el administrador desde el portal, o se crea desde la app
   con **Crear cuenta** (correo y contraseña de 6+ caracteres). Después se
   ingresa. La dirección del servidor se configura en **Servidor** dentro del
   ingreso: en el emulador es `http://10.0.2.2:3000`; en un teléfono, la IP de
   la computadora (`http://192.168.x.x:3000`).
2. Recibir los productos del almacén (los envía el administrador) o cargarlos en
   **Inventario** (nombre, precio y stock inicial).
3. Vender desde **Vender**.

Después del primer ingreso, la sesión queda guardada y **la app abre y vende sin
internet**. No hay forma de entrar sin cuenta: los teléfonos que ya venían de la
versión anterior con datos locales siguen viéndolos y pueden pasar a una cuenta
desde **Ajustes**, donde esos datos se suben a la cuenta nueva.

## 3. Esquema

### En el servidor (`server/src/db.js`)

| Tabla | Campos principales |
| --- | --- |
| `usuarios` | `id`, `email` (único), `hash`, `salt`, `creado_en` |
| `sesiones` | `token_hash`, `usuario_id`, `expira_en` (90 días) |
| `contadores` | `usuario_id`, `siguiente_rev` — revisión incremental por dueño |
| `productos` | `usuario_id`, `id`, `nombre`, `precio_centavos`, `stock_base`, `activo`, `actualizado_en`, `dispositivo_id`, `rev` |
| `ventas` | `usuario_id`, `id`, `creado_en`, `total_centavos`, `anulada`, `actualizado_en`, `dispositivo_id`, `rev` |
| `venta_items` | `usuario_id`, `id`, `venta_id`, `producto_id`, `nombre`, `precio_centavos`, `cantidad` |
| `movimientos` | `usuario_id`, `id`, `producto_id`, `cantidad` (+/−), `motivo`, `creado_en`, `dispositivo_id`, `rev` |
| `almacen` | `id`, `nombre`, `nombre_clave` (único), `costo_centavos`, `precio_centavos`, `stock`, `creado_en` |
| `traslados` | `id`, `almacen_id`, `usuario_id`, `producto_id`, `cantidad`, `tipo` (`envio`/`devolucion`), `creado_en` |

`almacen` y `traslados` son solo del portal: no viajan a los teléfonos. El costo
de compra (`costo_centavos`) tampoco se copia a `productos`, así que la app del
vendedor nunca lo recibe. Lo que sí viaja es el efecto del traslado (el producto
nuevo o la reposición) en la cuenta del vendedor.

La app repite `productos`, `ventas`, `venta_items` y `movimientos`, más:

- `pendiente` en cada fila que todavía no confirmó el servidor.
- `meta` con `dispositivo_id`, `ultima_rev`, última sincronización, error y avisos.

**El stock no se guarda como número absoluto.** Se calcula igual en los dos lados:

```
stock = stock_base
      + suma de movimientos (reposiciones y mermas)
      - suma de cantidades de ventas no anuladas
```

Así, si dos teléfonos venden el mismo chocolate sin conexión, las dos ventas se
suman y el stock no se pisa. Reponer stock agrega un movimiento inmutable, no
sobrescribe el número.

### API

| Método y ruta | Para qué |
| --- | --- |
| `GET /api/salud` | Ver si el servidor está vivo |
| `POST /api/registro` | `{email, contrasena}` → `{token, usuario}` |
| `POST /api/login` | Igual, para volver a entrar |
| `GET /api/sesion` | Validar el token |
| `POST /api/sync` | Subir pendientes y bajar cambios (ver abajo) |
| `GET /api/inventario` | Productos con stock calculado (para revisar a mano) |
| `GET /api/ventas?desde=ms` | Ventas y total recaudado |

Todas menos salud/registro/login piden `Authorization: Bearer <token>`.

## 4. Cómo funciona sin internet y cómo se resuelven los choques

1. **Escribir es local.** Una venta, un producto o una reposición se guardan en
   SQLite del teléfono dentro de una transacción, marcados `pendiente = 1`. La
   venta se cobra aunque no haya red, y el stock local se recalcula al instante.
2. **Sincronizar es aparte.** A los ~1 segundo de cada cambio (y al abrir la app,
   al volver a primer plano y cada 90 segundos) se intenta `POST /api/sync` con
   los pendientes y `ultima_rev`.
3. **El servidor asigna revisiones.** Cada fila que acepta recibe un `rev` mayor.
   La respuesta trae todo lo que tenga `rev > ultima_rev` (paginado con
   `hay_mas`), y la app avanza su marca. Si no hay red, los pendientes quedan y
   la app muestra `Error` con el motivo; al volver la conexión se reintenta solo.
4. **Las ventas no se duplican.** La app genera el UUID de la venta; el servidor
   inserta una sola vez y **nunca** reescribe ítems ni totales de una venta
   existente. Reintentar el mismo envío es inofensivo. El total se recalcula en
   el servidor a partir de los ítems: la plata no se confía al cliente.
5. **Los productos usan “gana el último cambio”.** Se comparan
   `actualizado_en` y, si empatan, el `dispositivo_id` mayor. Si el servidor
   descarta el cambio del teléfono, devuelve su versión y un aviso que la app
   muestra en **Ajustes → Sincronización** y en el detalle del chip. El cambio
   perdedor no se pierde en silencio: se informa. (En este MVP no se fusionan
   campo por campo: gana la fila completa.)
6. **Anular también sincroniza.** `anulada` es lo único editable de una venta y
   sigue la misma regla de último cambio. Al anular, el stock vuelve porque la
   fórmula excluye las ventas anuladas.
7. **Cambio de cuenta.** Si en el mismo teléfono se entra con otra cuenta, los
   datos locales se borran antes de bajar los de la cuenta nueva. Si el teléfono
   venía de la versión con “sin cuenta”, esos datos locales se suben a la cuenta
   al ingresar.
8. **El almacén reparte con reposiciones.** Enviar stock a un vendedor descuenta
   del almacén, crea el producto si no lo tenía (o lo reactiva si estaba
   archivado), le agrega un movimiento de reposición y sube la revisión. Para el
   teléfono es un cambio más, y llega en la próxima sincronización.

El chip de la barra superior (y **Ajustes**) siempre muestra el estado real:
`Sincronizado`, `Pendiente · N`, `Sincronizando`, `Error` o `Sin cuenta`.

## 5. Endpoint de sincronización

```jsonc
// POST /api/sync
{
  "dispositivo_id": "uuid-del-telefono",
  "ultima_rev": 12,
  "cambios": {
    "productos":   [ { "id": "...", "nombre": "Chocolate", "precio_centavos": 500,
                       "stock_base": 10, "activo": true,
                       "actualizado_en": 1761000000000, "dispositivo_id": "..." } ],
    "ventas":      [ { "id": "...", "creado_en": 1761000000000,
                       "total_centavos": 1000, "anulada": false,
                       "actualizado_en": 1761000000000, "dispositivo_id": "...",
                       "items": [ { "id": "...", "producto_id": "...", "nombre": "Chocolate",
                                    "precio_centavos": 500, "cantidad": 2 } ] } ],
    "movimientos": [ { "id": "...", "producto_id": "...", "cantidad": 24,
                       "motivo": "reposicion", "creado_en": 1761000000000,
                       "dispositivo_id": "..." } ]
  }
}
```

```jsonc
// 200 OK
{
  "servidor_en": 1761000005000,
  "ultima_rev": 15,
  "hay_mas": false,
  "cambios": { "productos": [], "ventas": [], "movimientos": [] },
  "aplicados": { "productos": 0, "ventas": 1, "movimientos": 0 },
  "conflictos": [ { "tipo": "producto", "id": "...", "resolucion": "servidor",
                    "mensaje": "Había un cambio más reciente en el servidor; se conservó ese." } ],
  "rechazados": []
}
```

## 6. Pruebas

```bash
cd server && npm test     # 25 pruebas: auth, sync, idempotencia, conflictos, stock, permisos, portal, almacén, devoluciones y PDF
cd app && flutter test    # 33 pruebas: formato, ventas/stock, PDF, widgets, sync real y actualizaciones
```

La prueba `app/test/sync_test.dart` **levanta el servidor Node real**, hace una
venta “sin conexión” en una SQLite real, la sincroniza, verifica el stock y la
plata en el servidor, y después baja todo en un segundo teléfono. También cubre
un corte de red, un conflicto entre dos dispositivos y el cambio de cuenta. Requiere `node` en el
PATH; si no está, se saltea sola.

## 7. Límites conocidos (MVP)

- Pensado para un negocio familiar: cada hijo tiene su cuenta y el padre entra
  al portal con una única contraseña de administrador (no hay usuarios con rol
  ni permisos distintos entre cuentas).
- El almacén reconoce el producto del vendedor por el nombre, sin distinguir
  mayúsculas ni espacios. Si el vendedor lo escribió con otro nombre, para el
  almacén es otro producto.
- Los relojes de los teléfonos se usan para ordenar cambios. Un reloj muy
  adelantado gana conflictos de producto (las ventas no se ven afectadas).
- La ganancia de las ventas viejas se calcula con el costo **actual** del
  almacén: si se cambia el costo, los reportes anteriores se recalculan.
- HTTP sin cifrar para la red local (`usesCleartextTraffic`). En producción
  conviene HTTPS y un proxy delante del servidor.
- El servidor es de un solo proceso y SQLite: alcanza para un puesto de venta.
- El token de sesión se guarda en las preferencias del teléfono, sin cifrado propio
  (el teléfono ya está bloqueado con PIN; para más seguridad habría que usar el
  almacén cifrado del sistema).
- No emite comprobantes fiscales ni cobra con tarjeta: el PDF es un resumen de
  la venta y el cobro se registra en efectivo.
