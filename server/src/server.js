import { createServer } from 'node:http';
import { networkInterfaces } from 'node:os';
import { abrirBase } from './db.js';
import { crearManejador } from './app.js';

const puerto = Number.parseInt(process.env.PORT ?? '3000', 10);
const puertoPublico = Number.parseInt(process.env.LIZNACK_PUERTO_PUBLICO ?? String(puerto), 10);
const adminClave = process.env.LIZNACK_ADMIN ?? '';
// En Docker las IPs de las interfaces son las del contenedor y no sirven para
// conectar el teléfono: ahí lo que importa es la IP de la máquina anfitriona.
const enContenedor = process.env.LIZNACK_DOCKER === '1';
const db = abrirBase();
const servidor = createServer(crearManejador(db, { adminClave }));

/** Muestra las IPs de la red local: el teléfono necesita una de estas. */
function direccionesLocales() {
  const salida = [];
  for (const lista of Object.values(networkInterfaces())) {
    for (const iface of lista ?? []) {
      if (iface.family === 'IPv4' && !iface.internal) salida.push(iface.address);
    }
  }
  return salida;
}

servidor.listen(puerto, '0.0.0.0', () => {
  console.log('Liznack · servidor de inventario y ventas');
  console.log(`  Escuchando en el puerto ${puerto}`);

  if (enContenedor) {
    console.log(`  Corriendo en Docker (puerto publicado: ${puertoPublico})`);
    console.log(`  Teléfono en la misma red: http://IP-DE-LA-MAQUINA:${puertoPublico}`);
    if (adminClave) {
      console.log(`  Portal del administrador: http://IP-DE-LA-MAQUINA:${puertoPublico}/admin`);
    } else {
      console.log('  Portal del administrador: desactivado');
      console.log('    activalo con LIZNACK_ADMIN en el archivo .env');
    }
  } else {
    console.log(`  Emulador Android: http://10.0.2.2:${puerto}`);
    for (const ip of direccionesLocales()) {
      console.log(`  Teléfono en la misma red: http://${ip}:${puerto}`);
    }
    if (adminClave) {
      console.log(`  Portal del administrador: http://localhost:${puerto}/admin`);
      for (const ip of direccionesLocales()) {
        console.log(`    desde otro dispositivo: http://${ip}:${puerto}/admin`);
      }
    } else {
      console.log('  Portal del administrador: desactivado');
      console.log('    activalo con: LIZNACK_ADMIN=tu-clave npm start');
    }
  }

  console.log('  Base de datos:', process.env.DATABASE_FILE ?? 'data/liznack.db');
  console.log('  Ctrl+C para detener.');
});

function cerrar() {
  servidor.close(() => {
    try {
      db.close();
    } catch {
      // ya estaba cerrada
    }
    process.exit(0);
  });
  setTimeout(() => process.exit(0), 3_000).unref();
}

process.on('SIGINT', cerrar);
process.on('SIGTERM', cerrar);
