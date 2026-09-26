plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.patika.patika_app"
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
        applicationId = "com.patika.patika_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildFeatures {
        buildConfig = true
    }

    // Dağıtım türleri (Faz 4a). Google Play CALL_PHONE ve SEND_SMS izinlerini
    // kısıtlıyor: izin manifest'te YAZILI olması yeterli, kullanılmasa da Play
    // incelemesine takılır. Bu yüzden bir Dart bayrağı değil, derleme türü:
    // - play   (varsayılan, mağaza): bu izinler hiç yok; onaydan sonra arama/
    //          SMS ekranı açılır, kullanıcı tuşa basar.
    // - direct (kendi cihazlar / mağaza dışı): izinler src/direct/Android-
    //          Manifest.xml'de; onaydan sonra doğrudan arar / gönderir.
    // Dart tarafı hangi türde olduğunu BuildConfig.DIRECT_ACTIONS'tan öğrenir
    // (tek gerçek kaynak - bayrakla derleme türü birbirinden sapamaz).
    // İki tür aynı uygulama kimliğini kullanır: telefondaki uygulama, izinleri
    // ve verisi korunarak türler arasında güncellenebilir.
    flavorDimensions += "distribution"
    productFlavors {
        create("play") {
            dimension = "distribution"
            buildConfigField("boolean", "DIRECT_ACTIONS", "false")
        }
        create("direct") {
            dimension = "distribution"
            versionNameSuffix = "-direct"
            buildConfigField("boolean", "DIRECT_ACTIONS", "true")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
