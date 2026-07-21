# Flutter / Dart AOT: keep the generated library loader.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Don't warn about missing optional platform classes.
-dontwarn io.flutter.embedding.**

# Preserve the BLE MethodChannel contract used by RealBlePeripheral.
-keep class io.pulseapp.pulse.** { *; }
