plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Clave con la que se firman los APK de Liznack.
//
// Android sólo deja instalar una actualización si el APK nuevo está firmado con
// la misma clave que el que ya está en el teléfono. La clave de depuración que
// genera el servidor de GitHub cambia en cada ejecución, así que con ella cada
// release sería un APK distinto: la app no podría actualizarse sola.
//
// Por eso la clave vive en el repo (`liznack.jks`) y la firman tanto el CI como
// la computadora. No es un secreto: este repositorio es público y la app se
// instala a mano, sin Play Store. Si algún día el repo deja de ser público, se
// borra el archivo y la clave pasa a venir del entorno (`LIZNACK_KEYSTORE`,
// `LIZNACK_KEYSTORE_PASSWORD`) o de un secreto del CI.
val archivoClave = System.getenv("LIZNACK_KEYSTORE") ?: "liznack.jks"
val passwordClave = System.getenv("LIZNACK_KEYSTORE_PASSWORD") ?: "liznack"
val hayClave = file(archivoClave).exists()

android {
    namespace = "com.caramelo.liznack"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.caramelo.liznack"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hayClave) {
            create("liznack") {
                storeFile = file(archivoClave)
                storePassword = passwordClave
                keyAlias = "liznack"
                keyPassword = passwordClave
            }
        }
    }

    buildTypes {
        release {
            // Con la clave del repo. Sin ella (clon sin el archivo) se usa la de
            // depuración, que sirve para probar pero no para publicar: cada
            // compilación saldría firmada distinto.
            signingConfig = if (hayClave) {
                signingConfigs.getByName("liznack")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    // FileProvider: para pasarle al instalador del sistema el APK que baja el
    // actualizador (MainActivity). Ya venía transitivo por los plugins.
    implementation("androidx.core:core:1.16.0")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
