plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
}

android {
    namespace = "mx.dori.vehicleagent.probe"
    compileSdk = 36
    buildFeatures { buildConfig = true }
    defaultConfig {
        val agentToken = providers.gradleProperty("agentToken").orElse("").get()
        check(agentToken.isNotEmpty()) { "AGENT_TOKEN_RESOLVED_FAILED" }
        val escapedAgentToken = agentToken
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
        applicationId = "mx.dori.vehicleagent.probe"
        minSdk = 24
        targetSdk = 33
        versionCode = 8
        versionName = "0.8"
        buildConfigField("String", "INGEST_URL", "\"https://yyxzuiantrmoyozetswv.supabase.co/functions/v1/dori-vehicle-telemetry-ingest\"")
        buildConfigField("String", "AGENT_TOKEN", "\"$escapedAgentToken\"")
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
}

kotlin {
    jvmToolchain(11)
}
