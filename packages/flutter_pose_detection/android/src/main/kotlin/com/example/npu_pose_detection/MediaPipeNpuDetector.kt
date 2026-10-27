package com.example.npu_pose_detection

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.util.Log
import android.os.SystemClock
import com.example.npu_pose_detection.models.*
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult
import java.io.File
import java.nio.ByteBuffer

/**
 * MediaPipe pose detector using official PoseLandmarker API.
 *
 * Uses MediaPipe Tasks Vision library for pose detection with 33 landmarks.
 * Hardware acceleration: GPU delegate (MediaPipe doesn't support QNN directly)
 */
class MediaPipeNpuDetector(private val context: Context) : PoseDetectorInterface {

    companion object {
        private const val TAG = "MediaPipeNpuDetector"
        private const val MODEL_ASSET = "pose_landmarker_lite.task"
        private const val NUM_LANDMARKS = 33
    }

    private var poseLandmarker: PoseLandmarker? = null
    private var config: DetectorConfig = DetectorConfig()
    private var _accelerationMode: AccelerationMode = AccelerationMode.UNKNOWN
    private var lastVideoTimestampMs: Long = 0

    override val accelerationMode: AccelerationMode get() = _accelerationMode
    override val isInitialized: Boolean get() = poseLandmarker != null

    /**
     * Initialize MediaPipe PoseLandmarker.
     */
    fun initialize(config: DetectorConfig): AccelerationMode {
        this.config = config

        Log.i(TAG, "Initializing MediaPipe PoseLandmarker...")

        // Load model from assets as ByteBuffer
        val modelBuffer = loadModelFromAssets()

        // Try GPU first, fallback to CPU
        if (config.preferredAcceleration != AccelerationMode.CPU) {
            if (tryInitializeWithGPU(modelBuffer)) {
                return _accelerationMode
            }
        }

        // Fallback to CPU
        return initializeWithCPU(modelBuffer)
    }

    private fun loadModelFromAssets(): ByteBuffer {
        Log.i(TAG, "Loading model from assets...")

        context.assets.open(MODEL_ASSET).use { input ->
            val bytes = input.readBytes()
            Log.i(TAG, "Read ${bytes.size} bytes from assets")

            // Log first 10 bytes for debugging
            val header = bytes.take(10).map { String.format("%02X", it) }.joinToString(" ")
            Log.i(TAG, "File header: $header")

            // Create direct ByteBuffer (required by MediaPipe)
            val buffer = ByteBuffer.allocateDirect(bytes.size)
            buffer.put(bytes)
            buffer.rewind()

            return buffer
        }
    }

    private fun tryInitializeWithGPU(modelBuffer: ByteBuffer): Boolean {
        try {
            Log.i(TAG, "Trying MediaPipe with GPU delegate...")

            val baseOptions = BaseOptions.builder()
                .setModelAssetBuffer(modelBuffer)
                .setDelegate(Delegate.GPU)
                .build()

            val options = PoseLandmarker.PoseLandmarkerOptions.builder()
                .setBaseOptions(baseOptions)
                .setRunningMode(RunningMode.VIDEO)
                .setMinPoseDetectionConfidence(config.minPoseDetectionConfidence)
                .setMinPosePresenceConfidence(config.minPosePresenceConfidence)
                .setMinTrackingConfidence(config.minTrackingConfidence)
                .setNumPoses(config.maxPoses.coerceIn(1, 10))
                .build()

            poseLandmarker = PoseLandmarker.createFromOptions(context, options)
            _accelerationMode = AccelerationMode.GPU
            Log.i(TAG, "✓ Initialized MediaPipe with GPU delegate")
            return true
        } catch (e: Exception) {
            Log.w(TAG, "✗ GPU initialization failed: ${e.message}")
            poseLandmarker?.close()
            poseLandmarker = null
            modelBuffer.rewind()  // Reset buffer position for retry
            return false
        }
    }

    private fun initializeWithCPU(modelBuffer: ByteBuffer): AccelerationMode {
        try {
            Log.i(TAG, "Initializing MediaPipe with CPU...")

            val baseOptions = BaseOptions.builder()
                .setModelAssetBuffer(modelBuffer)
                .setDelegate(Delegate.CPU)
                .build()

            val options = PoseLandmarker.PoseLandmarkerOptions.builder()
                .setBaseOptions(baseOptions)
                .setRunningMode(RunningMode.VIDEO)
                .setMinPoseDetectionConfidence(config.minPoseDetectionConfidence)
                .setMinPosePresenceConfidence(config.minPosePresenceConfidence)
                .setMinTrackingConfidence(config.minTrackingConfidence)
                .setNumPoses(config.maxPoses.coerceIn(1, 10))
                .build()

            poseLandmarker = PoseLandmarker.createFromOptions(context, options)
            _accelerationMode = AccelerationMode.CPU
            Log.i(TAG, "✓ Initialized MediaPipe with CPU")
            return _accelerationMode
        } catch (e: Exception) {
            Log.e(TAG, "✗ CPU initialization failed: ${e.message}")
            throw e
        }
    }

    /**
     * Detect poses from bitmap.
     */
    override fun detectPoseFromBitmap(bitmap: Bitmap): PoseResult =
        detectPoseFromBitmap(bitmap, SystemClock.elapsedRealtime())

    private fun detectPoseFromBitmap(bitmap: Bitmap, requestedTimestampMs: Long): PoseResult {
        val landmarker = poseLandmarker
            ?: throw IllegalStateException("PoseLandmarker not initialized")

        val startTime = System.currentTimeMillis()

        // Convert to MediaPipe image
        val mpImage = BitmapImageBuilder(bitmap).build()

        // Run detection
        val timestampMs = synchronized(this) {
            maxOf(requestedTimestampMs, lastVideoTimestampMs + 1).also {
                lastVideoTimestampMs = it
            }
        }
        val result = landmarker.detectForVideo(mpImage, timestampMs)

        val processingTime = (System.currentTimeMillis() - startTime).toInt()

        // Convert result to our format
        val poses = convertResult(result, bitmap.width, bitmap.height)

        Log.d(TAG, "Detection: ${poses.size} pose, ${processingTime}ms, ${_accelerationMode}")

        return PoseResult(
            poses = poses,
            processingTimeMs = processingTime,
            accelerationMode = _accelerationMode,
            imageWidth = bitmap.width,
            imageHeight = bitmap.height
        )
    }

    private fun convertResult(result: PoseLandmarkerResult, imageWidth: Int, imageHeight: Int): List<Pose> {
        if (result.landmarks().isEmpty()) {
            return emptyList()
        }

        return result.landmarks().mapIndexed { poseIndex, poseLandmarks ->
            val landmarks = poseLandmarks.mapIndexed { index, landmark ->
                PoseLandmark(
                    typeIndex = index,
                    x = landmark.x().toDouble(),
                    y = landmark.y().toDouble(),
                    z = landmark.z().toDouble(),
                    visibility = (landmark.visibility().orElse(0f)).toDouble()
                )
            }

            // Calculate bounding box from landmarks
            val detectedLandmarks = landmarks.filter { it.visibility > config.minConfidence }
            val boundingBox = if (detectedLandmarks.isNotEmpty()) {
                val minX = detectedLandmarks.minOf { it.x }
                val maxX = detectedLandmarks.maxOf { it.x }
                val minY = detectedLandmarks.minOf { it.y }
                val maxY = detectedLandmarks.maxOf { it.y }
                val padding = 0.1
                val width = maxX - minX
                val height = maxY - minY
                BoundingBox(
                    left = (minX - width * padding).coerceIn(0.0, 1.0),
                    top = (minY - height * padding).coerceIn(0.0, 1.0),
                    width = (width * (1 + 2 * padding)).coerceIn(0.0, 1.0),
                    height = (height * (1 + 2 * padding)).coerceIn(0.0, 1.0)
                )
            } else null

            // Calculate score as average visibility
            val score = if (detectedLandmarks.isNotEmpty()) {
                detectedLandmarks.map { it.visibility }.average()
            } else 0.0

            val worldLandmarks = result.worldLandmarks().getOrNull(poseIndex)
                ?.mapIndexed { index, landmark ->
                    WorldLandmark(
                        typeIndex = index,
                        x = landmark.x().toDouble(),
                        y = landmark.y().toDouble(),
                        z = landmark.z().toDouble(),
                        visibility = landmark.visibility().orElse(0f).toDouble()
                    )
                }.orEmpty()

            Pose(
                landmarks = landmarks,
                score = score,
                boundingBox = boundingBox,
                worldLandmarks = worldLandmarks
            )
        }
    }

    /**
     * Detect poses from image data.
     */
    override fun detectPose(imageData: ByteArray): PoseResult {
        val bitmap = BitmapFactory.decodeByteArray(imageData, 0, imageData.size)
            ?: throw IllegalArgumentException("Invalid image data")
        return detectPoseFromBitmap(bitmap)
    }

    override fun detectPoseVideo(imageData: ByteArray, timestampMs: Long): PoseResult {
        val bitmap = BitmapFactory.decodeByteArray(imageData, 0, imageData.size)
            ?: throw IllegalArgumentException("Invalid image data")
        return try {
            detectPoseFromBitmap(bitmap, timestampMs)
        } finally {
            bitmap.recycle()
        }
    }

    /**
     * Detect poses from file.
     */
    override fun detectPoseFromFile(filePath: String): PoseResult {
        val file = File(filePath)
        if (!file.exists()) {
            throw IllegalArgumentException("File not found: $filePath")
        }
        val bitmap = BitmapFactory.decodeFile(filePath)
            ?: throw IllegalArgumentException("Could not decode image: $filePath")
        return detectPoseFromBitmap(bitmap)
    }

    /**
     * Process camera frame.
     */
    fun processFrame(
        planes: List<Map<String, Any>>,
        width: Int,
        height: Int,
        format: String,
        rotation: Int
    ): PoseResult {
        val bitmap = when (format) {
            "yuv420", "nv21" -> convertYuvToBitmap(planes, width, height)
            "bgra8888" -> convertBgraToBitmap(planes, width, height)
            else -> throw IllegalArgumentException("Unsupported format: $format")
        }

        val rotatedBitmap = if (rotation != 0) {
            rotateBitmap(bitmap, rotation)
        } else {
            bitmap
        }

        return detectPoseFromBitmap(rotatedBitmap).also {
            if (rotatedBitmap != bitmap) rotatedBitmap.recycle()
            bitmap.recycle()
        }
    }

    fun updateConfig(config: DetectorConfig) {
        this.config = config
    }

    override fun dispose() {
        poseLandmarker?.close()
        poseLandmarker = null
        _accelerationMode = AccelerationMode.UNKNOWN
        Log.d(TAG, "MediaPipe PoseLandmarker disposed")
    }

    // Frame conversion utilities
    private fun convertYuvToBitmap(planes: List<Map<String, Any>>, width: Int, height: Int): Bitmap {
        val yPlane = planes[0]["bytes"] as ByteArray
        val uPlane = if (planes.size > 1) planes[1]["bytes"] as? ByteArray else null
        val vPlane = if (planes.size > 2) planes[2]["bytes"] as? ByteArray else null

        val nv21: ByteArray
        if (uPlane != null && vPlane != null) {
            nv21 = ByteArray(width * height * 3 / 2)
            System.arraycopy(yPlane, 0, nv21, 0, yPlane.size)
            val uvSize = width * height / 4
            for (i in 0 until uvSize) {
                nv21[yPlane.size + i * 2] = vPlane[i]
                nv21[yPlane.size + i * 2 + 1] = uPlane[i]
            }
        } else {
            nv21 = yPlane
        }

        val yuvImage = android.graphics.YuvImage(nv21, android.graphics.ImageFormat.NV21, width, height, null)
        val out = java.io.ByteArrayOutputStream()
        yuvImage.compressToJpeg(android.graphics.Rect(0, 0, width, height), 90, out)
        return BitmapFactory.decodeByteArray(out.toByteArray(), 0, out.size())
    }

    private fun convertBgraToBitmap(planes: List<Map<String, Any>>, width: Int, height: Int): Bitmap {
        val bytes = planes[0]["bytes"] as ByteArray
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        bitmap.copyPixelsFromBuffer(java.nio.ByteBuffer.wrap(bytes))
        return bitmap
    }

    private fun rotateBitmap(bitmap: Bitmap, rotation: Int): Bitmap {
        val matrix = Matrix()
        matrix.postRotate(rotation.toFloat())
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    }
}
