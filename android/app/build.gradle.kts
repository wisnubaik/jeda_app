plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.wishnotregret.berijeda"
    compileSdk = 35 // NAIKKAN KE 35 SESUAI PERMINTAAN PLUGIN
    ndkVersion = "27.0.12077973"

    compileOptions {
        // PERBAIKAN 1: Wajib pakai awalan 'is' dan tanda '='
        isCoreLibraryDesugaringEnabled = false 
        
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.wishnotregret.berijeda"
        // GANTI INI: Pakai angka 21 langsung
        minSdk = 21 
        targetSdk = 35 
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {

   // coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:1.1.5")
}

flutter {
    source = "../.."
}