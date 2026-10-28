## R8 shrinks and obfuscates but doesn't optimize, as with the proguard-android.txt defaults Hearth used before AGP 9
## (which dropped them): optimizing is a separate change that needs its own TV testing.
-dontoptimize

## Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn io.flutter.embedding.**
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication

## Kids-profile provisioning: KidsBlockUninstallMain is only ever invoked by name on an app_process command line
## (see KidsAppAccess / SelfAdb), so R8 sees no references and would strip or rename it in release builds — silently
## breaking the block-uninstall step. Keep the class and its main() entry point.
-keep class com.thesiegs.hearth.KidsBlockUninstallMain { public static void main(java.lang.String[]); }

## Logs name the exception that ended something (Household.why): Hearth's own exceptions keep their names in release
## builds, so a log says "SyncException", not "c". Names only: they are still shrunk and optimized.
-keepnames class com.thesiegs.hearth.** extends java.lang.Throwable