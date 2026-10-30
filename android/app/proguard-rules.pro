# MediaPipe (JNI + réflexion)
-keep class com.google.mediapipe.** { *; }
-keep interface com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# Flogger (utilisé par MediaPipe) : R8 ne doit pas inliner forEnclosingClass
-keep class com.google.common.flogger.** { *; }
-dontwarn com.google.common.flogger.**

# Protobuf utilisé par MediaPipe
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# Classes référencées depuis le code natif
-keepclasseswithmembernames class * {
    native <methods>;
}