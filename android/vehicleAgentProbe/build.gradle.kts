plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
}

android {
    namespace = "mx.dori.vehicleagent.probe"
    compileSdk = 36
    buildFeatures { buildConfig = true }
    defaultConfig {
        applicationId = "mx.dori.vehicleagent.probe"
        minSdk = 24
        targetSdk = 33
        versionCode = 8
        versionName = "0.8"
        buildConfigField("String", "INGEST_URL", "\"https://yyxzuiantrmoyozetswv.supabase.co/functions/v1/dori-vehicle-telemetry-ingest\"")
        buildConfigField("String", "AGENT_TOKEN", "\"${providers.gradleProperty("agentToken").orElse("")}\"")
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
}

kotlin {
    jvmToolchain(11)
}
