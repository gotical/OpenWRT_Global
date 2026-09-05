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

// Единый compileSdk для всех плагинов (glance-appwidget:1.3.0-alpha02
// из home_widget требует 37+, иначе падает на AAR metadata).
gradle.projectsEvaluated {
    subprojects {
        try {
            val android = project.extensions.findByName("android")
            if (android != null) {
                // Новый DSL (BaseAppModuleExtension) — метод compileSdkVersion(int)
                val setter = try {
                    android.javaClass.getMethod("setCompileSdkVersion", Int::class.java)
                } catch (_: NoSuchMethodException) {
                    // Старый DSL (BaseExtension) — то же имя, но другой класс
                    null
                }
                if (setter != null) {
                    setter.invoke(android, 37)
                } else {
                    // Groovy DSL — прямое присваивание через property
                    try {
                        val prop = android.javaClass.getMethod("getCompileSdkVersion")
                        if (prop != null) {
                            // Groovy property assignment через reflection
                            val field = android.javaClass.superclass?.getDeclaredField("compileSdkVersion")
                            field?.setAccessible(true)
                            field?.set(android, 37)
                        }
                    } catch (_: Throwable) {}
                }
            }
        } catch (_: Throwable) {
            // ignore
        }
    }
}

// Переопределяем JVM target на 11 для всех Kotlin-плагинов. Без этого
// home_widget 0.8.x падает с "Cannot inline bytecode built with JVM
// target 11 into bytecode that is being built with JVM target 1.8".
allprojects {
    plugins.withId("org.jetbrains.kotlin.android") {
        extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension>("kotlin") {
            @Suppress("UnstableApiUsage")
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
