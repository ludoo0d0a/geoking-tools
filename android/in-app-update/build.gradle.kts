plugins {
    id("com.android.library")
}

group = "fr.geoking.tools"
version = "1.0.0"

// When included as a subproject of an app with android.builtInKotlin=false (Vincent
// KMP+application), AGP does not compile Kotlin — apply the classic plugin.
// With builtInKotlin=true (Arthur/Gaston/default), AGP owns Kotlin; do not apply it.
val builtInKotlinEnabled =
    (findProperty("android.builtInKotlin") as String?)?.toBooleanStrictOrNull() ?: true
if (!builtInKotlinEnabled) {
    apply(plugin = "org.jetbrains.kotlin.android")
}

android {
    namespace = "fr.geoking.tools.inappupdate"
    compileSdk = 37

    defaultConfig {
        minSdk = 26
        consumerProguardFiles("consumer-rules.pro")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }
}

dependencies {
    api("com.google.android.play:app-update:2.1.0")
    api("com.google.android.play:app-update-ktx:2.1.0")
    api("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
    implementation("androidx.activity:activity:1.13.0")
    implementation("androidx.core:core-ktx:1.17.0")
}
