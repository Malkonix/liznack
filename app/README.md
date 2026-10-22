# Liznack (app)

App Flutter de Liznack para vender dulces: inventario, ventas y sincronización
con el servidor.

## Correr la app

```bash
flutter pub get
flutter run
```

## Apuntar al servidor

Por defecto la app usa `http://10.0.2.2:3000` (el host desde el emulador de
Android). Para usar otro servidor:

```bash
flutter run --dart-define=LIZNACK_SERVIDOR=http://192.168.0.10:3000
```

## Pruebas

```bash
flutter test
```

Las pruebas de `test/sync_test.dart` necesitan el servidor de `server/`
levantado.
