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

// Единый compileSdk для всех плагинов (file_picker требует 36+, а по
// умолчанию собирается под 34 — падает на AAR metadata).
gradle.projectsEvaluated {
    subprojects {
        try {
            val android = project.extensions.findByName("android")
            android?.javaClass?.getMethod("compileSdkVersion", Int::class.java)?.invoke(android, 36)
        } catch (_: Throwable) {
            // Часть плагинов использует новый DSL — там compileSdk уже верный.
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
