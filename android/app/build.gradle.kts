import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "pt.nxtperformancestudio.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "pt.nxtperformancestudio.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // A chave de assinatura vive FORA do repositório, em
        // `android/key.properties`, e esse ficheiro está no
        // `.gitignore`. Quem tiver a chave consegue publicar
        // atualizações da app em nome do estúdio — não é um segredo
        // como outro qualquer, é O segredo, e a Google não a substitui
        // se for perdida ou exposta.
        //
        // Sem o ficheiro, a build de release continua a funcionar com a
        // chave de debug (que é o que permite `flutter run --release`
        // numa máquina qualquer). O que NÃO funciona é publicar: a Play
        // Console recusa um pacote assinado em debug. É por isso que a
        // verificação de `storeFile` existe aqui em baixo em vez de
        // rebentar o build.
        create("release") {
            val propsFile = rootProject.file("key.properties")
            if (propsFile.exists()) {
                val props = Properties()
                propsFile.inputStream().use { entrada -> props.load(entrada) }
                keyAlias = props.getProperty("keyAlias")
                keyPassword = props.getProperty("keyPassword")
                val caminho = props.getProperty("storeFile")
                if (caminho != null) storeFile = file(caminho)
                storePassword = props.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Se a chave de publicação não estiver presente, cai na de
            // debug em vez de falhar — ver o comentário acima.
            signingConfig = if (rootProject.file("key.properties").exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
