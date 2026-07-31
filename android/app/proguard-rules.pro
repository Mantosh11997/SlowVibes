# ---------------------------------------------------------------------------
# R8 keep rules
# ---------------------------------------------------------------------------
# Flutter enables R8 for release builds automatically. R8 removes anything it
# cannot see referenced in code — which breaks any library that resolves a
# class by name at runtime, because there is no reference for R8 to follow.
#
# That is exactly what crashed this app on startup:
#
#   Unable to get provider androidx.startup.InitializationProvider
#     -> Failed to create an instance of androidx.work.impl.WorkDatabase
#
# google_mobile_ads depends on WorkManager, WorkManager is a Room database, and
# Room instantiates "<DatabaseName>_Impl" via Class.forName(). R8 had stripped
# androidx.work.impl.WorkDatabase_Impl (confirmed in build/app/outputs/mapping/
# release/usage.txt), so the lookup failed before any Dart code ran.
# ---------------------------------------------------------------------------

# --- Room -------------------------------------------------------------------
# Keep every generated Room implementation and the no-arg constructors Room
# reflects on. This covers WorkManager's database and any added later.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class **_Impl { <init>(...); *; }
-keep class androidx.room.** { *; }
-dontwarn androidx.room.paging.**

# --- WorkManager ------------------------------------------------------------
# Workers are also constructed reflectively, by class name, from the database.
-keep class androidx.work.** { *; }
-keep class * extends androidx.work.Worker { <init>(...); }
-keep class * extends androidx.work.ListenableWorker { <init>(...); }
-keep class * extends androidx.work.InputMerger { <init>(...); }

# --- App Startup ------------------------------------------------------------
# Initializers are named in the manifest and loaded by name, so R8 cannot see
# the reference either.
-keep class * extends androidx.startup.Initializer { <init>(); }
-keep class androidx.startup.** { *; }

# --- flutter_local_notifications + Gson --------------------------------------
# The plugin persists every scheduled notification as JSON (via Gson) so the
# boot receiver can restore the alarms after a restart. Gson maps JSON keys to
# *field names*, so if R8 renames those fields the saved schedule no longer
# deserialises and the daily reminders silently stop after a reboot. The plugin
# ships no consumer rules of its own, so they belong here.
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }

# Gson relies on generic signatures at runtime; without Signature retained,
# TypeToken<List<...>> erases to TypeToken<Object> and parsing fails.
-keepattributes Signature, *Annotation*, EnclosingMethod, InnerClasses
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep public class * implements java.lang.reflect.Type
-dontwarn com.google.gson.**

# --- Google Mobile Ads ------------------------------------------------------
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.ads.** { *; }
-dontwarn com.google.android.gms.ads.**

# --- FFmpegKit --------------------------------------------------------------
# Resolves its native symbols through JNI; renaming these breaks every session.
-keep class com.antonkarpenko.ffmpegkit.** { *; }
-keep class com.arthenica.** { *; }
-dontwarn com.antonkarpenko.ffmpegkit.**
-dontwarn com.arthenica.**

# --- just_audio / Media3 ----------------------------------------------------
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**

# --- Flutter ----------------------------------------------------------------
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Flutter's embedding references Play Core split-install APIs so that deferred
# components work. Those classes are only on the classpath if the app actually
# depends on Play Core, which this one does not — it ships as a normal APK with
# no dynamic feature modules. R8 treats the dangling references as errors, so
# they are suppressed here. Exact list taken from R8's own generated
# build/app/outputs/mapping/release/missing_rules.txt.
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task

# Keep annotations and signatures so runtime reflection keeps working.
-keepattributes *Annotation*, InnerClasses, Signature, EnclosingMethod
