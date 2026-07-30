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

// ---------------------------------------------------------------------------
// file_picker + AGP 9 workaround
// ---------------------------------------------------------------------------
// file_picker 11's android/build.gradle contains:
//
//     def isAgp9OrAbove = ...ANDROID_GRADLE_PLUGIN_VERSION... >= 9
//     if (!isAgp9OrAbove) { apply plugin: 'org.jetbrains.kotlin.android' }
//
// so on AGP 9 it deliberately does not apply KGP, expecting Flutter's built-in
// Kotlin to compile its .kt sources. We cannot enable built-in Kotlin, because
// just_audio, audio_session, share_plus and ffmpeg_kit_flutter_new_audio all
// still apply KGP themselves and AGP 9 rejects that combination (see
// gradle.properties). The result is that nobody compiles file_picker's Kotlin
// and the build fails with:
//
//     GeneratedPluginRegistrant.java: cannot find symbol
//       com.mr.flutter.plugin.filepicker.FilePickerPlugin
//
// Applying KGP to just that subproject restores the pre-AGP-9 behaviour.
// file_picker also guards its `kotlinOptions` behind the same flag, so the
// jvmTarget has to be set here too — without it KGP defaults to a different
// target than the Java compilation and the build fails on a target mismatch.
//
// Remove this block once file_picker ships a release that works with AGP 9
// without requiring built-in Kotlin.
subprojects {
    if (project.name == "file_picker") {
        // KGP must be applied *after* the Android plugin, so hook the moment
        // file_picker's own script applies com.android.library rather than
        // applying eagerly here.
        project.plugins.withId("com.android.library") {
            project.plugins.apply("org.jetbrains.kotlin.android")
            project.tasks
                .withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java)
                .configureEach {
                    compilerOptions.jvmTarget.set(
                        org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17,
                    )
                }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
