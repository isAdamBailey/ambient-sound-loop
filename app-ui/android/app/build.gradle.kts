import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing reads the upload key from android/key.properties, which git
// ignores. A release build without that file fails rather than falling back to
// the debug key, so a debug-signed bundle can never reach Play. Debug and
// profile builds keep the debug key.
val signingPropsFile = rootProject.file("key.properties")
val signingProps = Properties().apply {
    if (signingPropsFile.exists()) signingPropsFile.inputStream().use { load(it) }
}
val hasReleaseSigning = signingPropsFile.exists()

android {
    namespace = "dev.humspan.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // The Play Console app is registered to this id; it can never change once uploaded.
        applicationId = "io.adambailey.humspan"
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
        if (hasReleaseSigning) {
            create("release") {
                fun prop(key: String): String = signingProps.getProperty(key)
                    ?: throw GradleException("${signingPropsFile.path} is missing \"$key\".")
                storeFile = rootProject.file(prop("storeFile"))
                storePassword = prop("storePassword")
                keyAlias = prop("keyAlias")
                keyPassword = prop("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) signingConfig = signingConfigs.getByName("release")
        }
    }
}

gradle.taskGraph.whenReady {
    val buildsRelease = allTasks.any { it.project == project && it.name.contains("Release") }
    if (buildsRelease && !hasReleaseSigning) {
        throw GradleException(
            "Release builds sign with the upload key, but ${signingPropsFile.path} " +
                "does not exist. Create it with storeFile, storePassword, keyAlias and " +
                "keyPassword (see README). It is never committed.",
        )
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
