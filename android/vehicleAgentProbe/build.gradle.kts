plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
}

android {
    namespace = "mx.dori.vehicleagent.probe"
    compileSdk = 36
    defaultConfig {
        applicationId = "mx.dori.vehicleagent.probe"
        minSdk = 24
        targetSdk = 33
        versionCode = 5
        versionName = "0.5"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
}

kotlin {
    jvmToolchain(11)
}