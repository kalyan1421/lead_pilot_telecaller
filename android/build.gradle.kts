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
// Some plugins (e.g. file_picker → flutter_plugin_android_lifecycle) require
// compileSdk 36, but plugin modules don't inherit the app's compileSdk in this
// Flutter version and reset it to their own value inside their `android {}`
// block. Override it in afterEvaluate (which runs AFTER that block). This block
// MUST come before the evaluationDependsOn block below, otherwise the projects
// are already evaluated and afterEvaluate throws. Reflection avoids needing the
// Android Gradle Plugin classes on this script's classpath.
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android") ?: return@afterEvaluate
        try {
            androidExt.javaClass
                .getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                .invoke(androidExt, 36)
        } catch (e: Exception) {
            // Not an Android module (or signature differs) — ignore.
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
