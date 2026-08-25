allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// THE BUILD OUTPUT STAYS WHERE FLUTTER EXPECTS IT. Do not redirect it.
//
// This repo lives inside OneDrive, which holds file handles while it uploads while Gradle
// deletes and recreates its output directories — the two race, and a build dies with
// AccessDeniedException on a different directory each run (mergeReleaseAssets, then
// merged_native_libs, then native_symbol_tables). The obvious fix is to point the build
// somewhere OneDrive does not watch.
//
// That fix is WORSE THAN THE PROBLEM, and it cost real time here before being caught.
// `flutter build apk` locates its artifact at <project>/build/app/outputs/flutter-apk/ by
// convention. Move the Gradle output and the tool does not follow: it reports whatever file
// already sits at that path. Two consecutive builds both printed "Built ... (62.0MB)" while
// the real, larger artifact was written somewhere else entirely — the number was yesterday's
// stale APK being re-reported as today's success. A build system that lies about what it built
// is more dangerous than one that fails, because the failure is at least visible.
//
// So the output stays put. The OneDrive race is handled where it belongs, in
// scripts/release.sh, which clears the directories that lose the race and retries — a
// transient lock is a transient lock, and retrying is the honest response to one.
//
// The durable fix is not in this file at all: exclude nivora_app/build from OneDrive sync
// (right-click the folder → Always keep on this device → off, or move the repo out of
// OneDrive). Both remove the race rather than working around it.
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
