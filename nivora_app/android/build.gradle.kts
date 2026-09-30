allprojects {
    repositories {
        google()
        mavenCentral()
    }

    // THE RAZORPAY PIN. razorpay_flutter declares `com.razorpay:checkout:1.6.+` — a DYNAMIC
    // version range, which makes Gradle re-fetch maven-metadata.xml on every resolve to learn
    // what "+" means today. That breaks `--offline` outright (a range cannot be resolved from
    // cache), hands this machine's TLS-intercepting antivirus a fresh network fetch to kill —
    // the release pipeline has died on exactly that HEAD request — and lets a Razorpay release
    // nobody reviewed walk into the app on any clean build, which is the reason lockfiles exist.
    //
    // Forced to 1.6.41: the version already in this machine's Gradle cache and in every artifact
    // shipped so far. Raise it deliberately, never by leaving the range open.
    //
    // THAT PIN ALONE PINNED NOTHING THAT RUNS. checkout 1.6.41 is an empty wrapper: its
    // classes.jar is empty and its POM depends on com.razorpay:standard-core at version LATEST,
    // which pulls com.razorpay:core. So every online build took whatever Razorpay had published
    // that day, which is exactly what the paragraph above says this block prevents. v6 (the first
    // closed-test release) shipped standard-core 1.7.18 with core 1.0.18; Razorpay published
    // 1.7.19 / 1.0.19 on 2026-09-21, unreviewed here, and the next online build would have taken
    // them silently. The two lines below pin the code that actually executes to what v6 shipped
    // and is in this machine's cache. Raise all three together, on purpose, after reading the
    // release notes.
    configurations.all {
        resolutionStrategy {
            force("com.razorpay:checkout:1.6.41")
            force("com.razorpay:standard-core:1.7.18")
            force("com.razorpay:core:1.0.18")
        }
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
