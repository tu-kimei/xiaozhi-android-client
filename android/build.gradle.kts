allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// Old plugins (e.g. flutter_pcm_player 0.0.1) don't declare a namespace, which AGP 8 requires.
// Fall back to the package attribute from their AndroidManifest.xml.
subprojects {
    plugins.withId("com.android.library") {
        val android = extensions.getByType(com.android.build.gradle.LibraryExtension::class.java)
        if (android.namespace == null) {
            val manifest = file("src/main/AndroidManifest.xml")
            val pkg = Regex("package=\"([^\"]+)\"").find(manifest.readText())?.groupValues?.get(1)
            android.namespace = pkg ?: "com.plugin.${project.name.replace('-', '_')}"
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
