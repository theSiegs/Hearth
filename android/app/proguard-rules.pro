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