pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")

gradle.beforeProject {
    // 修复旧版插件（flutter_app_badger）缺失 namespace
    // 在项目配置前检查并注入
    if (name == ":flutter_app_badger") {
        val gf = File(projectDir, "build.gradle")
        if (gf.exists() && !gf.readText().contains("namespace")) {
            gf.writeText(
                gf.readText().replaceFirst(
                    "android {",
                    "android {\n    namespace \"fr.g123k.flutterappbadge\""
                )
            )
        }
    }
}
