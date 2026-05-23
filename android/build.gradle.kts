allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// 修复旧版插件缺少 namespace 的 AGP 8+ 兼容问题（flutter_app_badger 等）
subprojects {
    afterEvaluate {
        val android = try {
            extensions.getByName("android")
        } catch (_: Exception) {
            null
        }
        (android as? com.android.build.gradle.BaseExtension)?.let {
            if (it.namespace == null) {
                it.namespace = project.group?.toString() ?: "com.example.${project.name}"
            }
        }
    }
}
