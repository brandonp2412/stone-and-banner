import java.io.File
import java.util.Properties
import java.security.KeyStore
import java.security.MessageDigest

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val expectedSigner = "011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd"
val signingProperties = Properties()
val projectSigningFile = rootProject.file("key.properties")
val signingFile = if (projectSigningFile.isFile) projectSigningFile else
    File(System.getProperty("user.home"), ".config/android-signing/flexify-release.properties")
if (signingFile.isFile) signingFile.inputStream().use { signingProperties.load(it) }

android {
    namespace = "nz.stone_and_banner"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "nz.stone_and_banner"
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
        create("release") {
            keyAlias = signingProperties.getProperty("keyAlias")
            keyPassword = signingProperties.getProperty("keyPassword")
            storeFile = signingProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = signingProperties.getProperty("storePassword")
        }
    }
    buildTypes {
        configureEach {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// Never package this application ID with anything except the Flex certificate.
gradle.taskGraph.whenReady {
    if (allTasks.any { it.project == project && Regex("(?i)^(assemble|bundle|package|install).*").matches(it.name) }) {
        val config = android.signingConfigs.getByName("release")
        val keyFile = config.storeFile
        if (keyFile == null || !keyFile.isFile || config.storePassword.isNullOrEmpty() || config.keyAlias.isNullOrEmpty()) {
            throw GradleException("Flex signing key required for Stone & Banner")
        }
        val keyStore = KeyStore.getInstance(keyFile, config.storePassword!!.toCharArray())
        val certificate = keyStore.getCertificate(config.keyAlias)
            ?: throw GradleException("Missing Flex signing certificate")
        val actual = MessageDigest.getInstance("SHA-256").digest(certificate.encoded).joinToString("") { "%02x".format(it.toInt() and 255) }
        if (actual != expectedSigner) throw GradleException("Wrong signing certificate: $actual; expected $expectedSigner")
    }
}
