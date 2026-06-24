# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# sqflite
-keep class com.tekartik.sqflite.** { *; }

# shared_preferences
-keep class androidx.preference.** { *; }

# mobile_scanner
-keep class com.google.mlkit.** { *; }

# url_launcher
-keep class androidx.browser.** { *; }

# cached_network_image
-keep class com.baseflow.** { *; }
-dontwarn com.squareup.okhttp.**

# General
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
