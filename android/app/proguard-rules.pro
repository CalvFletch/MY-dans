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

# Suppress Play Core missing class warnings (not using deferred components)
-dontwarn com.google.android.play.core.**

# WorkManager (R8 was stripping WorkDatabase_Impl constructor)
-keep class androidx.work.** { *; }
-dontwarn androidx.work.**
