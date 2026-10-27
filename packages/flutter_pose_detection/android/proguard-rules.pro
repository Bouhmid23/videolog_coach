# LiteRT 2.1.0 (successor to TensorFlow Lite)
# https://ai.google.dev/edge/litert/android
-keep class com.google.ai.edge.litert.** { *; }
-keep class com.google.ai.edge.litert.gpu.** { *; }
-keep class com.google.ai.edge.litert.Accelerator { *; }
-keep class com.google.ai.edge.litert.CompiledModel { *; }
-keep class com.google.ai.edge.litert.CompiledModel$Options { *; }
-keep class com.google.ai.edge.litert.TensorBuffer { *; }
-dontwarn com.google.ai.edge.litert.**

# Keep TFLite classes
-keep class org.tensorflow.lite.** { *; }
-keep class org.tensorflow.lite.gpu.** { *; }
-keep class org.tensorflow.lite.gpu.GpuDelegate { *; }
-keep class org.tensorflow.lite.gpu.GpuDelegate$Options { *; }
-keep class org.tensorflow.lite.gpu.GpuDelegateFactory { *; }
-keep class org.tensorflow.lite.gpu.GpuDelegateFactory$Options { *; }
-dontwarn org.tensorflow.lite.**

# MediaPipe
-keep class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# AutoValue and annotation processing (used by MediaPipe)
-dontwarn javax.annotation.processing.**
-dontwarn javax.lang.model.**
-dontwarn com.google.auto.value.**
-dontwarn autovalue.shaded.**
