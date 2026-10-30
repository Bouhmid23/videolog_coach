package com.example.npu_pose_detection

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.*
import org.webrtc.VideoFrame
import org.webrtc.VideoSink
import org.webrtc.VideoTrack
import org.webrtc.YuvHelper
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * Zero-copy native WebRTC VideoSink for MediaPipe pose detection.
 *
 * Direct pipeline from WebRTC VideoTrack -> Native VideoSink -> MediaPipe Worker -> EventChannel (Dart).
 * Features:
 * - LIFO single-frame queue (drop-frame) to never block the WebRTC video stream thread.
 * - Dynamic Throttling: monitors thermal state (API 29+) and battery level to automatically
 *   switch between nominal FPS (e.g. 30) and throttled FPS (e.g. 12-15).
 * - Accepts target FPS updates from Dart (e.g. motion-based adaptive throttling).
 */
class WebRtcPoseSink(
    private val context: Context,
    private val detector: PoseDetectorInterface,
    private val eventSink: EventChannel.EventSink?,
    private var nominalFps: Int = 30,
    private var throttledFps: Int = 15,
    private var adaptiveThrottlingEnabled: Boolean = true
) : VideoSink {

    companion object {
        private const val TAG = "WebRtcPoseSink"

        /**
         * Resolves the WebRTC VideoTrack from flutter_webrtc via reflection.
         */
        /**
         * Safely extracts a VideoTrack from an unknown object (LocalTrack, LocalVideoTrack, or VideoTrack)
         * by inspecting all declared fields and superclasses.
         */
        private fun extractVideoTrack(obj: Any?): VideoTrack? {
            if (obj == null) return null
            if (obj is VideoTrack) return obj
            var cls: Class<*>? = obj.javaClass
            while (cls != null && cls != Any::class.java) {
                for (field in cls.declaredFields) {
                    try {
                        field.isAccessible = true
                        val value = field.get(obj)
                        if (value is VideoTrack) return value
                    } catch (_: Exception) {}
                }
                for (method in cls.declaredMethods) {
                    try {
                        if (method.parameterCount == 0 && VideoTrack::class.java.isAssignableFrom(method.returnType)) {
                            method.isAccessible = true
                            val value = method.invoke(obj)
                            if (value is VideoTrack) return value
                        }
                    } catch (_: Exception) {}
                }
                cls = cls.superclass
            }
            return null
        }

        fun resolveVideoTrack(trackId: String): VideoTrack? {
            return try {
                val pluginClass = Class.forName("com.cloudwebrtc.webrtc.FlutterWebRTCPlugin")
                val sharedField = pluginClass.getField("sharedSingleton")
                val pluginInstance = sharedField.get(null) ?: run {
                    Log.w(TAG, "FlutterWebRTCPlugin.sharedSingleton is null")
                    return null
                }

                // 1. Direct getLocalTrack lookup
                try {
                    val method = pluginClass.getMethod("getLocalTrack", String::class.java)
                    val localTrack = method.invoke(pluginInstance, trackId)
                    val vt = extractVideoTrack(localTrack)
                    if (vt != null) {
                        Log.i(TAG, "Resolved VideoTrack directly via getLocalTrack($trackId)")
                        return vt
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Direct getLocalTrack lookup failed: ${e.message}")
                }

                // Inspect MethodCallHandlerImpl
                val mField = pluginClass.getDeclaredField("methodCallHandler").apply { isAccessible = true }
                val handler = mField.get(pluginInstance) ?: return null

                var fallbackTrack: VideoTrack? = null

                // 2. Scan methodCallHandler.localTracks map
                try {
                    val ltField = handler.javaClass.getDeclaredField("localTracks").apply { isAccessible = true }
                    val map = ltField.get(handler) as? Map<*, *>
                    if (map != null) {
                        for ((key, localTrack) in map) {
                            val track = extractVideoTrack(localTrack)
                            if (track != null) {
                                if (fallbackTrack == null) fallbackTrack = track
                                if (track.id() == trackId || key == trackId) {
                                    Log.i(TAG, "Resolved VideoTrack from localTracks by match: $trackId")
                                    return track
                                }
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "localTracks map scan failed: ${e.message}")
                }

                // 3. Scan localStreams map
                try {
                    val lsField = handler.javaClass.getDeclaredField("localStreams").apply { isAccessible = true }
                    val streams = lsField.get(handler) as? Map<*, *>
                    if (streams != null) {
                        for ((_, streamObj) in streams) {
                            if (streamObj != null) {
                                val vtList = extractVideoTrackList(streamObj)
                                for (track in vtList) {
                                    if (fallbackTrack == null) fallbackTrack = track
                                    if (track.id() == trackId) {
                                        Log.i(TAG, "Resolved VideoTrack from localStreams by ID: $trackId")
                                        return track
                                    }
                                }
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "localStreams map scan failed: ${e.message}")
                }

                // 4. Scan renders (FlutterRTCVideoRenderer)
                try {
                    val rField = handler.javaClass.getDeclaredField("renders").apply { isAccessible = true }
                    val renders = rField.get(handler) as? android.util.LongSparseArray<*>
                    if (renders != null) {
                        for (i in 0 until renders.size()) {
                            val renderer = renders.valueAt(i)
                            if (renderer != null) {
                                val track = extractVideoTrack(renderer)
                                if (track != null) {
                                    if (fallbackTrack == null) fallbackTrack = track
                                    if (track.id() == trackId) {
                                        Log.i(TAG, "Resolved VideoTrack from active renderer: $trackId")
                                        return track
                                    }
                                }
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "renders scan failed: ${e.message}")
                }

                if (fallbackTrack != null) {
                    Log.i(TAG, "Resolved fallback active VideoTrack: ${fallbackTrack.id()} (requested: $trackId)")
                    return fallbackTrack
                }

                Log.w(TAG, "Could not resolve VideoTrack for trackId: $trackId")
                null
            } catch (e: Exception) {
                Log.e(TAG, "Failed to resolve VideoTrack via reflection: ${e.message}", e)
                null
            }
        }

        private fun extractVideoTrackList(streamObj: Any): List<VideoTrack> {
            val list = mutableListOf<VideoTrack>()
            try {
                val field = streamObj.javaClass.getField("videoTracks")
                @Suppress("UNCHECKED_CAST")
                val tracks = field.get(streamObj) as? List<VideoTrack>
                if (tracks != null) list.addAll(tracks)
            } catch (_: Exception) {}
            return list
        }
    }

    private var videoTrack: VideoTrack? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    private val isRunning = AtomicBoolean(false)
    private val isProcessing = AtomicBoolean(false)
    private val pendingFrame = AtomicReference<VideoFrame?>(null)

    private var lastDispatchedTimeMs: Long = 0
    private var frameCount: Int = 0
    private val fpsCalculator = FPSCalculator()

    // Adaptive Throttling state
    private var isThermalThrottled: Boolean = false
    private var isLowBattery: Boolean = false
    private var batteryLevel: Float = 1.0f
    private var thermalListener: Any? = null
    private var batteryReceiver: BroadcastReceiver? = null

    val currentEffectiveFps: Int
        get() {
            return if (adaptiveThrottlingEnabled && (isThermalThrottled || isLowBattery)) {
                throttledFps
            } else {
                nominalFps
            }
        }

    fun start(track: VideoTrack) {
        if (isRunning.getAndSet(true)) return

        videoTrack = track
        fpsCalculator.reset()
        frameCount = 0
        lastDispatchedTimeMs = 0

        setupThermalListener()
        setupBatteryListener()

        track.addSink(this)
        Log.i(TAG, "✓ WebRtcPoseSink attached to track ${track.id()}, nominalFps=$nominalFps, throttledFps=$throttledFps")
    }

    fun updateTargetFps(fps: Int) {
        nominalFps = fps.coerceIn(5, 60)
        Log.i(TAG, "Nominal target FPS updated to $nominalFps (effective=$currentEffectiveFps)")
    }

    fun setAdaptiveThrottling(enabled: Boolean, lowFps: Int = 15) {
        adaptiveThrottlingEnabled = enabled
        throttledFps = lowFps.coerceIn(5, 30)
        Log.i(TAG, "Adaptive throttling set to $enabled (throttledFps=$throttledFps, effective=$currentEffectiveFps)")
    }

    override fun onFrame(frame: VideoFrame) {
        if (!isRunning.get()) return

        val nowMs = SystemClock.elapsedRealtime()
        val effectiveFps = currentEffectiveFps
        val minIntervalMs = if (effectiveFps > 0) (1000.0 / effectiveFps).toLong() else 33

        // Dynamic Throttling check
        if (nowMs - lastDispatchedTimeMs < minIntervalMs) {
            return // Drop frame before retaining
        }

        // LIFO drop-frame queue (size = 1)
        frame.retain()
        val oldFrame = pendingFrame.getAndSet(frame)
        oldFrame?.release()
        lastDispatchedTimeMs = nowMs

        if (isProcessing.compareAndSet(false, true)) {
            scope.launch {
                processLoop()
            }
        }
    }

    private suspend fun processLoop() {
        try {
            while (isRunning.get()) {
                val frame = pendingFrame.getAndSet(null) ?: break

                try {
                    val timestampMs = SystemClock.elapsedRealtime()
                    val bitmap = convertVideoFrameToBitmap(frame)

                    if (bitmap != null && isRunning.get()) {
                        val poseResult = detector.detectPoseFromBitmap(bitmap, timestampMs)
                        bitmap.recycle()

                        val fps = fpsCalculator.update()
                        frameCount++

                        mainHandler.post {
                            if (isRunning.get()) {
                                eventSink?.success(
                                    mapOf(
                                        "type" to "frame",
                                        "frameNumber" to frameCount,
                                        "timestampUs" to timestampMs * 1000,
                                        "fps" to fps,
                                        "isThermalThrottled" to isThermalThrottled,
                                        "isLowBattery" to isLowBattery,
                                        "batteryLevel" to batteryLevel,
                                        "targetFps" to currentEffectiveFps,
                                        "result" to poseResult.toMap()
                                    )
                                )
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Error during native frame inference: ${e.message}")
                } finally {
                    frame.release()
                }
            }
        } finally {
            isProcessing.set(false)
            // If another frame arrived right when exiting loop, trigger again
            if (pendingFrame.get() != null && isRunning.get() && isProcessing.compareAndSet(false, true)) {
                scope.launch { processLoop() }
            }
        }
    }

    /**
     * Converts a WebRTC VideoFrame (I420 or Texture) to an Android Bitmap in native memory.
     */
    private fun convertVideoFrameToBitmap(videoFrame: VideoFrame): Bitmap? {
        val buffer = videoFrame.buffer
        val i420Buffer = try {
            buffer.toI420()
        } catch (e: Exception) {
            Log.w(TAG, "buffer.toI420() failed: ${e.message}")
            null
        } ?: return null

        return try {
            val width = i420Buffer.width
            val height = i420Buffer.height

            val y = i420Buffer.dataY
            val u = i420Buffer.dataU
            val v = i420Buffer.dataV

            val strideY = i420Buffer.strideY
            val strideU = i420Buffer.strideU
            val strideV = i420Buffer.strideV

            val chromaWidth = (width + 1) / 2
            val chromaHeight = (height + 1) / 2
            val minSize = width * height + chromaWidth * chromaHeight * 2

            val yuvBuffer = ByteBuffer.allocateDirect(minSize)

            // WebRTC YuvHelper converts I420 to NV21/NV12
            YuvHelper.I420ToNV12(y, strideY, v, strideV, u, strideU, yuvBuffer, width, height)

            val cleanedArray = ByteArray(minSize)
            yuvBuffer.rewind()
            yuvBuffer.get(cleanedArray)

            val yuvImage = YuvImage(cleanedArray, ImageFormat.NV21, width, height, null)
            val out = ByteArrayOutputStream()
            yuvImage.compressToJpeg(Rect(0, 0, width, height), 90, out)
            val jpegBytes = out.toByteArray()

            val rawBitmap = BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.size)

            val rotation = videoFrame.rotation
            if (rotation != 0 && rawBitmap != null) {
                val matrix = Matrix().apply { postRotate(rotation.toFloat()) }
                val rotated = Bitmap.createBitmap(rawBitmap, 0, 0, rawBitmap.width, rawBitmap.height, matrix, true)
                rawBitmap.recycle()
                rotated
            } else {
                rawBitmap
            }
        } catch (e: Exception) {
            Log.e(TAG, "VideoFrame to Bitmap conversion failed: ${e.message}")
            null
        } finally {
            i420Buffer.release()
        }
    }

    // -------------------------------------------------------------------------
    // Thermal & Battery Listeners (Dynamic Throttling)
    // -------------------------------------------------------------------------

    private fun setupThermalListener() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
                val listener = PowerManager.OnThermalStatusChangedListener { status ->
                    val wasThrottled = isThermalThrottled
                    isThermalThrottled = status >= PowerManager.THERMAL_STATUS_MODERATE
                    if (wasThrottled != isThermalThrottled) {
                        Log.i(TAG, "🌡️ Thermal status changed: $status -> throttled=$isThermalThrottled (targetFps=$currentEffectiveFps)")
                    }
                }
                powerManager?.addThermalStatusListener(listener)
                thermalListener = listener
            } catch (e: Exception) {
                Log.w(TAG, "Could not register ThermalStatusListener: ${e.message}")
            }
        }
    }

    private fun setupBatteryListener() {
        try {
            batteryReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent?.action == Intent.ACTION_BATTERY_CHANGED) {
                        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
                        val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
                        val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                                status == BatteryManager.BATTERY_STATUS_FULL

                        if (level >= 0 && scale > 0) {
                            batteryLevel = level.toFloat() / scale.toFloat()
                            val wasLow = isLowBattery
                            isLowBattery = (batteryLevel < 0.20f) && !isCharging
                            if (wasLow != isLowBattery) {
                                Log.i(TAG, "🔋 Battery status: ${(batteryLevel * 100).toInt()}% (low=$isLowBattery, targetFps=$currentEffectiveFps)")
                            }
                        }
                    }
                }
            }
            context.registerReceiver(batteryReceiver, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        } catch (e: Exception) {
            Log.w(TAG, "Could not register BatteryReceiver: ${e.message}")
        }
    }

    fun stop() {
        if (!isRunning.getAndSet(false)) return

        try {
            videoTrack?.removeSink(this)
        } catch (e: Exception) {
            Log.w(TAG, "Error removing VideoSink: ${e.message}")
        }
        videoTrack = null

        val pending = pendingFrame.getAndSet(null)
        pending?.release()

        // Unregister listeners
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && thermalListener != null) {
            try {
                val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
                @Suppress("UNCHECKED_CAST")
                powerManager?.removeThermalStatusListener(thermalListener as PowerManager.OnThermalStatusChangedListener)
            } catch (e: Exception) {
                Log.w(TAG, "Error unregistering thermal listener: ${e.message}")
            }
            thermalListener = null
        }

        batteryReceiver?.let {
            try {
                context.unregisterReceiver(it)
            } catch (e: Exception) {
                Log.w(TAG, "Error unregistering battery receiver: ${e.message}")
            }
            batteryReceiver = null
        }

        scope.cancel()
        Log.i(TAG, "WebRtcPoseSink stopped and disposed")
    }
}
