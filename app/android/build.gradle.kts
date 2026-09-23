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

// Certains plugins publient leur module Android avec un compileSdk trop ancien :
// flutter_quick_video_encoder 1.7.2 déclare `compileSdkVersion 33` alors que ses
// dépendances androidx (fragment 1.7.1, window 1.2.0, …) exigent 34 ou plus, ce qui
// fait échouer `checkReleaseAarMetadata` au build release :
//   > 15 issues were found when checking AAR metadata
//   > :flutter_quick_video_encoder is currently compiled against android-33
// On aligne donc tous les sous-projets sur un compileSdk récent.
//
// Important : ce bloc doit être enregistré AVANT le `evaluationDependsOn(":app")`
// ci-dessous. Sinon `:app` (et les plugins déjà évalués) reçoivent un
// `afterEvaluate` après leur évaluation → « Cannot run Project.afterEvaluate(Action)
// when the project is already evaluated ».
subprojects {
    afterEvaluate {
        val androidExtension = extensions.findByName("android") ?: return@afterEvaluate
        androidExtension.withGroovyBuilder {
            setProperty("compileSdkVersion", 36)
        }
    }
}

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
