plugins { id("com.android.application"); id("org.jetbrains.kotlin.android"); id("org.jetbrains.kotlin.plugin.compose") }

android {
    namespace = "tech.tracepay.android"
    compileSdk = 35
    defaultConfig { applicationId = "tech.tracepay.android"; minSdk = 26; targetSdk = 35; versionCode = 23; versionName = "4.4.0" }
    buildTypes {
        // Debug talks to the development Mac over the LAN; cleartext HTTP is allowed only here.
        getByName("debug") {
            manifestPlaceholders["usesCleartextTraffic"] = "true"
            buildConfigField("String", "TRACEPAY_API_BASE_URL", "\"https://tracepay-api.livelystone-3bd01cb7.centralindia.azurecontainerapps.io/\"")
        }
        // Release must use the HTTPS production API. Replace the placeholder with your domain.
        getByName("release") {
            manifestPlaceholders["usesCleartextTraffic"] = "false"
            buildConfigField("String", "TRACEPAY_API_BASE_URL", "\"https://tracepay-api.livelystone-3bd01cb7.centralindia.azurecontainerapps.io/\"")
        }
    }
    buildFeatures { compose = true; buildConfig = true }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.12.01"))
    implementation("androidx.activity:activity-compose:1.10.0")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.biometric:biometric:1.2.0-alpha05")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.google.android.gms:play-services-code-scanner:16.1.0")
    implementation("androidx.fragment:fragment-ktx:1.8.5")  // BiometricPrompt needs FragmentActivity
    implementation("com.google.zxing:core:3.5.3")          // My QR code generation
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    debugImplementation("androidx.compose.ui:ui-tooling")
}
