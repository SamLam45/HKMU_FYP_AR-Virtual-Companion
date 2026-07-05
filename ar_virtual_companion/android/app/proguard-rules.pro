# Flutter Proguard Rules
-keep class io.flutter.** { *; }
-keep class com.google.** { *; }
-keep enum com.google.** { *; }
-keep interface com.google.** { *; }

# Keep plugin-specific classes
-keep class androidx.lifecycle.** { *; }
-keep interface androidx.lifecycle.** { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep application classes
-keep public class * extends android.app.Activity
-keep public class * extends android.app.Service
-keep public class * extends android.content.BroadcastReceiver
-keep public class * extends android.content.ContentProvider

# Keep custom application classes
-keep class com.example.ar_ai_girl_friend.** { *; }

# Keep model classes
-keepclassmembers class * {
    *** get*();
    void set*(***);
}

# Suppress warnings
-dontwarn androidx.**
-dontwarn com.google.**
-dontwarn io.flutter.**

# Optimization settings
-optimizationpasses 5
-dontusemixedcaseclassnames
