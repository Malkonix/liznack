package com.caramelo.liznack

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Canal para que la app se actualice sola.
 *
 * Son cuatro cositas y evita depender de un plugin: los que hacen esto llevan
 * años sin mantenimiento y lo único que hace falta es un `Intent` con un
 * `FileProvider`.
 *
 * A partir de ahí manda Android: enseña su propio diálogo y el usuario acepta
 * o no. La app no puede instalar nada a espaldas de quien tiene el teléfono.
 */
class MainActivity : FlutterActivity() {

    private val canal = "com.caramelo.liznack/instalador"

    private var wakeLock: PowerManager.WakeLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, canal)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "puedeInstalar" -> result.success(puedeInstalar())
                    "pedirPermiso" -> {
                        pedirPermiso()
                        result.success(null)
                    }
                    "instalar" -> {
                        val ruta = call.argument<String>("ruta")
                        if (ruta.isNullOrEmpty()) {
                            result.error("SIN_RUTA", "No se indicó el APK", null)
                        } else {
                            try {
                                instalar(ruta)
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("FALLO", e.message, null)
                            }
                        }
                    }
                    // La carpeta donde se bajan los APK: la caché de la app, que
                    // el sistema puede borrar solo cuando hace falta espacio.
                    "cacheDir" -> result.success(cacheDir.absolutePath)
                    // Mantener la CPU despierta mientras baja el APK: con la
                    // pantalla apagada el sistema duerme el procesador y la
                    // descarga se corta a media.
                    "mantener" -> {
                        mantenerDespierto()
                        result.success(null)
                    }
                    "soltar" -> {
                        soltarDespierto()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * PARTIAL_WAKE_LOCK: mantiene la CPU, no la pantalla.
     *
     * Con tope de 15 minutos por seguridad. Si un fallo impidiera soltarlo, el
     * sistema lo libera solo en vez de dejar el teléfono sin batería; una
     * descarga de unos 55 MB no se acerca ni de lejos a ese límite.
     */
    private fun mantenerDespierto() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "liznack:descarga").apply {
            setReferenceCounted(false)
            acquire(15 * 60 * 1000L)
        }
    }

    private fun soltarDespierto() {
        runCatching { wakeLock?.takeIf { it.isHeld }?.release() }
        wakeLock = null
    }

    override fun onDestroy() {
        soltarDespierto()
        super.onDestroy()
    }

    /** Desde Android 8 instalar de fuentes desconocidas es un permiso por app. */
    private fun puedeInstalar(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }

    private fun pedirPermiso() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        startActivity(
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                .setData(Uri.parse("package:$packageName"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    private fun instalar(ruta: String) {
        val apk = File(ruta)
        require(apk.exists()) { "el APK no está en $ruta" }
        // Un file:// no vale desde Android 7: hay que pasar por un FileProvider y
        // dar permiso de lectura al instalador.
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", apk)
        startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }
}
