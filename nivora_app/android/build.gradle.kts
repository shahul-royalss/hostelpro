allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// WHERE THE BUILD OUTPUT GOES, and why it is overridable.
//
// This repository lives inside a OneDrive folder. A cloud-sync client keeps file handles open
// while it uploads, and Gradle deletes and recreates its output directories constantly — the
// two race, and the build dies with AccessDeniedException or "Unable to delete directory" on a
// DIFFERENT directory each run (mergeReleaseAssets, merged_native_libs, native_symbol_tables).
// It looks like a flaky toolchain and is not: it is two processes writing the same tree.
//
// Default stays `nivora_app/build` so a fresh clone behaves exactly as Flutter expects. Point
// it somewhere the sync client does not watch with either:
//     NIVORA_BUILD_DIR=/c/tmp/nivora-build flutter build apk --release
//     flutter build apk --release -PnivoraBuildDir=C:\tmp\nivora-build
// No machine-specific path is committed, so this is safe for CI and for other developers.
val buildDirOverride: String? =
    (findProperty("nivoraBuildDir") as String?)?.takeIf { it.isNotBlank() }
        ?: System.getenv("NIVORA_BUILD_DIR")?.takeIf { it.isNotBlank() }

val newBuildDir: Directory =
    if (buildDirOverride != null) {
        rootProject.layout.projectDirectory.dir(buildDirOverride)
    } else {
        rootProject.layout.buildDirectory.dir("../../build").get()
    }

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
