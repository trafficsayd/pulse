# Pulse release keep rules.
#
# Most Flutter plugins ship consumer ProGuard rules of their own; the entries
# below cover the JNI / reflection surfaces that have historically broken
# under R8 when only consumer rules were relied on.

# flutter_webrtc — native WebRTC classes are reached over JNI.
-keep class org.webrtc.** { *; }
-keep class com.cloudwebrtc.webrtc.** { *; }

# flutter_blue_plus — GATT callbacks are invoked reflectively by the OS.
-keep class com.lib.flutter_blue_plus.** { *; }

# Play Billing (in_app_purchase).
-keep class com.android.billingclient.** { *; }

# Keep annotations plugins use to discover entry points.
-keepattributes *Annotation*
