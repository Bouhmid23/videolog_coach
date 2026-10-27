package com.example.npu_pose_detection

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.util.Log
import com.example.npu_pose_detection.models.*
import org.tensorflow.lite.Interpreter
import java.io.File
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel
import kotlin.math.exp

/**
 * TensorFlow Lite based pose detector for benchmarking delegates.
 *
 * Uses MediaPipe pose_landmarks_detector.tflite model:
 * - Input: [1, 256, 256, 3] normalized to [0, 1]
 * - Output: [1, 195] = 33 landmarks x 5 (x, y, z, visibility, presence) + auxiliary
 */
class TFLitePoseDetector(private val context: Context) : PoseDetectorInterface {

    companion object {
        private const val TAG = "TFLitePoseDetector"
        private const val POSE_LANDMARKS_MODEL = "pose_landmarks_detector.tflite"
        private const val INPUT_SIZE = 256
        private const val NUM_LANDMARKS = 33
        private const val LANDMARK_DIMS = 5  // x, y, z, visibility, presence
        private const val SKEL_ASSETS_DIR = "qnn_skel"

        // Skel files for different Hexagon versions
        private val SKEL_FILES = listOf(
            "libQnnHtpV68Skel.so",
            "libQnnHtpV69Skel.so",
            "libQnnHtpV73Skel.so",
            "libQnnHtpV75Skel.so",
            "libQnnHtpV79Skel.so"
        )
    }

    private var interpreter: Interpreter? = null
    private var config: DetectorConfig = DetectorConfig()
    private var _accelerationMode: AccelerationMode = AccelerationMode.UNKNOWN
    private var qnnDelegate: Any? = null

    override val accelerationMode: AccelerationMode get() = _accelerationMode
    override val isInitialized: Boolean get() = interpreter != null

    data class BenchmarkResult(
        val delegateType: String,
        val success: Boolean,
        val avgInferenceTimeMs: Double,
        val minInferenceTimeMs: Double,
        val maxInferenceTimeMs: Double,
        val errorMessage: String? = null
    )

    fun initialize(config: DetectorConfig): AccelerationMode {
        this.config = config
        Log.i(TAG, "Initializing TFLite Pose Detector...")
        Log.i(TAG, "Device: ${Build.MANUFACTURER} ${Build.MODEL}")

        val model = loadModelFromAssets(POSE_LANDMARKS_MODEL)

        // Try QNN first, then CPU
        if (tryInitializeWithQNN(model)) {
            return _accelerationMode
        }

        return initializeWithCPU(model)
    }

    fun initializeWithDelegate(delegateType: String): Boolean {
        val model = loadModelFromAssets(POSE_LANDMARKS_MODEL)

        return when (delegateType.lowercase()) {
            "qnn", "npu" -> tryInitializeWithQNN(model)
            "gpu" -> tryInitializeWithGPU(model)
            "cpu" -> {
                initializeWithCPU(model)
                true
            }
            else -> false
        }
    }

    private fun loadModelFromAssets(modelName: String): MappedByteBuffer {
        Log.i(TAG, "Loading model: $modelName")
        val fileDescriptor = context.assets.openFd(modelName)
        val inputStream = FileInputStream(fileDescriptor.fileDescriptor)
        val fileChannel = inputStream.channel
        return fileChannel.map(
            FileChannel.MapMode.READ_ONLY,
            fileDescriptor.startOffset,
            fileDescriptor.declaredLength
        )
    }

    /**
     * Extract QNN skel libraries from assets to app's files directory.
     * Returns the directory path where skel files are extracted.
     */
    private fun extractSkelLibraries(): String {
        val skelDir = File(context.filesDir, "qnn_skel")
        if (!skelDir.exists()) {
            skelDir.mkdirs()
        }

        for (skelFile in SKEL_FILES) {
            val destFile = File(skelDir, skelFile)
            if (!destFile.exists()) {
                try {
                    context.assets.open("$SKEL_ASSETS_DIR/$skelFile").use { input ->
                        destFile.outputStream().use { output ->
                            input.copyTo(output)
                        }
                    }
                    // Make executable
                    destFile.setExecutable(true)
                    Log.i(TAG, "Extracted: $skelFile")
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to extract $skelFile: ${e.message}")
                }
            }
        }

        return skelDir.absolutePath
    }

    private fun tryInitializeWithQNN(model: MappedByteBuffer): Boolean {
        try {
            Log.i(TAG, "Trying QNN delegate (Snapdragon NPU)...")

            // Use the correct package: com.qualcomm.qti.QnnDelegate (from qtld-release.aar)
            val qnnDelegateClass = Class.forName("com.qualcomm.qti.QnnDelegate")
            val optionsClass = Class.forName("com.qualcomm.qti.QnnDelegate\$Options")
            val backendTypeClass = Class.forName("com.qualcomm.qti.QnnDelegate\$Options\$BackendType")

            // Create Options with HTP backend (NPU)
            val optionsConstructor = optionsClass.getConstructor()
            val options = optionsConstructor.newInstance()

            // Set backend to HTP (Hexagon Tensor Processor = NPU)
            val setBackendTypeMethod = optionsClass.getMethod("setBackendType", backendTypeClass)
            val htpBackend = backendTypeClass.getField("HTP_BACKEND").get(null)
            setBackendTypeMethod.invoke(options, htpBackend)

            // Set skel library directory (where libQnnHtpV*Skel.so is located)
            // If not provided, extract from assets to app's files directory
            val skelDir = config.skelLibraryDir ?: extractSkelLibraries()
            val setSkelLibraryDirMethod = optionsClass.getMethod("setSkelLibraryDir", String::class.java)
            setSkelLibraryDirMethod.invoke(options, skelDir)
            Log.i(TAG, "Set skel library dir: $skelDir")

            // Create QnnDelegate with options
            val delegateConstructor = qnnDelegateClass.getConstructor(optionsClass)
            qnnDelegate = delegateConstructor.newInstance(options)

            // Add delegate to interpreter
            val interpreterOptions = Interpreter.Options()
            interpreterOptions.addDelegate(qnnDelegate as org.tensorflow.lite.Delegate)

            interpreter = Interpreter(model, interpreterOptions)

            _accelerationMode = AccelerationMode.NPU
            Log.i(TAG, "✓ QNN delegate initialized (NPU/HTP)")
            return true

        } catch (e: ClassNotFoundException) {
            Log.w(TAG, "✗ QNN delegate class not found: ${e.message}")
        } catch (e: Exception) {
            Log.w(TAG, "✗ QNN initialization failed: ${e.message}")
            e.printStackTrace()
            disposeInterpreter()
        }
        return false
    }

    private fun tryInitializeWithGPU(model: MappedByteBuffer): Boolean {
        try {
            Log.i(TAG, "Trying GPU delegate...")

            // Try direct instantiation first (when TFLite GPU is properly linked)
            try {
                val gpuDelegate = org.tensorflow.lite.gpu.GpuDelegate()
                val interpreterOptions = Interpreter.Options()
                interpreterOptions.addDelegate(gpuDelegate)
                interpreter = Interpreter(model, interpreterOptions)
                _accelerationMode = AccelerationMode.GPU
                Log.i(TAG, "✓ GPU delegate initialized (direct)")
                return true
            } catch (e: NoClassDefFoundError) {
                Log.w(TAG, "GPU delegate not available via direct import: ${e.message}")
            } catch (e: UnsatisfiedLinkError) {
                Log.w(TAG, "GPU native library not loaded: ${e.message}")
            }

            // Fallback to reflection
            Log.i(TAG, "Trying reflection...")
            val gpuDelegateClass = Class.forName("org.tensorflow.lite.gpu.GpuDelegate")
            Log.i(TAG, "Found class: ${gpuDelegateClass.name}")

            val constructors = gpuDelegateClass.constructors
            Log.i(TAG, "Available constructors: ${constructors.size}")
            constructors.forEach { c ->
                Log.i(TAG, "  Constructor: ${c.parameterTypes.contentToString()}")
            }

            val delegateConstructor = gpuDelegateClass.getConstructor()
            val gpuDelegate = delegateConstructor.newInstance()
            Log.i(TAG, "Created delegate instance")

            val interpreterOptions = Interpreter.Options()
            interpreterOptions.addDelegate(gpuDelegate as org.tensorflow.lite.Delegate)

            interpreter = Interpreter(model, interpreterOptions)

            _accelerationMode = AccelerationMode.GPU
            Log.i(TAG, "✓ GPU delegate initialized (reflection)")
            return true

        } catch (e: ClassNotFoundException) {
            Log.w(TAG, "✗ GPU delegate class not found: ${e.message}")
        } catch (e: NoClassDefFoundError) {
            Log.w(TAG, "✗ GPU delegate not linked: ${e.message}")
        } catch (e: NoSuchMethodException) {
            Log.w(TAG, "✗ GPU delegate constructor not found: ${e.message}")
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "✗ GPU native library error: ${e.message}")
        } catch (e: Exception) {
            Log.w(TAG, "✗ GPU initialization failed: ${e.javaClass.simpleName}: ${e.message}")
            e.printStackTrace()
            disposeInterpreter()
        }
        return false
    }

    private fun initializeWithCPU(model: MappedByteBuffer): AccelerationMode {
        try {
            Log.i(TAG, "Initializing with CPU (XNNPACK)...")

            val options = Interpreter.Options()
            options.setNumThreads(4)

            interpreter = Interpreter(model, options)

            _accelerationMode = AccelerationMode.CPU
            Log.i(TAG, "✓ CPU initialized (4 threads)")

        } catch (e: Exception) {
            Log.e(TAG, "✗ CPU initialization failed: ${e.message}")
            throw e
        }
        return _accelerationMode
    }

    fun benchmark(delegateType: String, iterations: Int = 10): BenchmarkResult {
        Log.i(TAG, "=== Benchmarking $delegateType ($iterations iterations) ===")

        dispose()
        val initialized = initializeWithDelegate(delegateType)

        if (!initialized) {
            return BenchmarkResult(
                delegateType = delegateType,
                success = false,
                avgInferenceTimeMs = 0.0,
                minInferenceTimeMs = 0.0,
                maxInferenceTimeMs = 0.0,
                errorMessage = "Failed to initialize $delegateType delegate"
            )
        }

        val testBitmap = Bitmap.createBitmap(INPUT_SIZE, INPUT_SIZE, Bitmap.Config.ARGB_8888)

        try {
            val times = mutableListOf<Long>()

            Log.i(TAG, "Warmup (3 runs)...")
            repeat(3) { detectPoseFromBitmap(testBitmap) }

            Log.i(TAG, "Running benchmark...")
            repeat(iterations) { i ->
                val start = System.nanoTime()
                detectPoseFromBitmap(testBitmap)
                val end = System.nanoTime()
                val timeUs = (end - start) / 1000
                times.add(timeUs)
                Log.d(TAG, "  Run ${i + 1}: ${timeUs / 1000.0}ms")
            }

            val avgMs = times.average() / 1000.0
            val minMs = (times.minOrNull() ?: 0L) / 1000.0
            val maxMs = (times.maxOrNull() ?: 0L) / 1000.0

            Log.i(TAG, "=== $delegateType Results ===")
            Log.i(TAG, "  Avg: ${String.format("%.2f", avgMs)}ms")
            Log.i(TAG, "  Min: ${String.format("%.2f", minMs)}ms")
            Log.i(TAG, "  Max: ${String.format("%.2f", maxMs)}ms")

            return BenchmarkResult(delegateType, true, avgMs, minMs, maxMs)

        } catch (e: Exception) {
            Log.e(TAG, "Benchmark failed: ${e.message}")
            return BenchmarkResult(delegateType, false, 0.0, 0.0, 0.0, e.message)
        } finally {
            testBitmap.recycle()
        }
    }

    fun benchmarkAll(iterations: Int = 10): Map<String, BenchmarkResult> {
        val results = mutableMapOf<String, BenchmarkResult>()

        results["qnn"] = benchmark("qnn", iterations)
        // Note: TFLite GPU delegate conflicts with MediaPipe's bundled TFLite
        // MediaPipe handles GPU acceleration internally (~3ms via tasks-vision)
        // results["gpu"] = benchmark("gpu", iterations)
        results["cpu"] = benchmark("cpu", iterations)

        Log.i(TAG, "\n=== BENCHMARK SUMMARY ===")
        results.forEach { (delegate, result) ->
            if (result.success) {
                Log.i(TAG, "$delegate: ${String.format("%.2f", result.avgInferenceTimeMs)}ms (avg)")
            } else {
                Log.i(TAG, "$delegate: FAILED - ${result.errorMessage}")
            }
        }

        return results
    }

    override fun detectPoseFromBitmap(bitmap: Bitmap): PoseResult {
        val interp = interpreter ?: throw IllegalStateException("Interpreter not initialized")

        val startTime = System.nanoTime()

        // Resize to 256x256
        val resizedBitmap = Bitmap.createScaledBitmap(bitmap, INPUT_SIZE, INPUT_SIZE, true)

        // Prepare input: [1, 256, 256, 3] normalized to [0, 1]
        val inputBuffer = ByteBuffer.allocateDirect(1 * INPUT_SIZE * INPUT_SIZE * 3 * 4)
        inputBuffer.order(ByteOrder.nativeOrder())

        val pixels = IntArray(INPUT_SIZE * INPUT_SIZE)
        resizedBitmap.getPixels(pixels, 0, INPUT_SIZE, 0, 0, INPUT_SIZE, INPUT_SIZE)

        for (pixel in pixels) {
            inputBuffer.putFloat(((pixel shr 16) and 0xFF) / 255.0f)  // R
            inputBuffer.putFloat(((pixel shr 8) and 0xFF) / 255.0f)   // G
            inputBuffer.putFloat((pixel and 0xFF) / 255.0f)           // B
        }
        inputBuffer.rewind()

        // Output: [1, 195] or similar
        val outputBuffer = ByteBuffer.allocateDirect(1 * NUM_LANDMARKS * LANDMARK_DIMS * 4)
        outputBuffer.order(ByteOrder.nativeOrder())

        try {
            interp.run(inputBuffer, outputBuffer)
        } catch (e: Exception) {
            // Try with dynamic output shape
            val outputTensor = interp.getOutputTensor(0)
            val shape = outputTensor.shape()
            Log.d(TAG, "Output shape: ${shape.contentToString()}")

            val totalElements = shape.fold(1) { acc, dim -> acc * dim }
            val dynamicOutput = ByteBuffer.allocateDirect(totalElements * 4)
            dynamicOutput.order(ByteOrder.nativeOrder())

            interp.run(inputBuffer, dynamicOutput)
            dynamicOutput.rewind()

            // Parse landmarks from flat output
            val landmarks = parseLandmarksFromFlatOutput(dynamicOutput, totalElements)
            val processingTimeMs = ((System.nanoTime() - startTime) / 1_000_000.0).toInt()

            if (resizedBitmap != bitmap) resizedBitmap.recycle()

            return createPoseResult(landmarks, processingTimeMs, bitmap.width, bitmap.height)
        }

        outputBuffer.rewind()
        val landmarks = parseLandmarks(outputBuffer)
        val processingTimeMs = ((System.nanoTime() - startTime) / 1_000_000.0).toInt()

        if (resizedBitmap != bitmap) resizedBitmap.recycle()

        return createPoseResult(landmarks, processingTimeMs, bitmap.width, bitmap.height)
    }

    private fun parseLandmarks(buffer: ByteBuffer): List<PoseLandmark> {
        val landmarks = mutableListOf<PoseLandmark>()

        for (i in 0 until NUM_LANDMARKS) {
            val x = buffer.float / INPUT_SIZE  // Normalize to [0, 1]
            val y = buffer.float / INPUT_SIZE
            val z = buffer.float / INPUT_SIZE
            val visibility = sigmoid(buffer.float)
            val presence = sigmoid(buffer.float)

            if (visibility >= config.minConfidence && presence >= 0.5f) {
                landmarks.add(PoseLandmark(
                    typeIndex = i,
                    x = x.toDouble().coerceIn(0.0, 1.0),
                    y = y.toDouble().coerceIn(0.0, 1.0),
                    z = z.toDouble(),
                    visibility = visibility.toDouble()
                ))
            } else {
                landmarks.add(PoseLandmark.notDetected(i))
            }
        }

        return landmarks
    }

    private fun parseLandmarksFromFlatOutput(buffer: ByteBuffer, totalElements: Int): List<PoseLandmark> {
        val landmarks = mutableListOf<PoseLandmark>()
        val floats = FloatArray(totalElements)
        buffer.asFloatBuffer().get(floats)

        val stride = if (totalElements >= NUM_LANDMARKS * LANDMARK_DIMS) LANDMARK_DIMS else 4

        for (i in 0 until NUM_LANDMARKS) {
            val baseIdx = i * stride
            if (baseIdx + stride > totalElements) {
                landmarks.add(PoseLandmark.notDetected(i))
                continue
            }

            val x = floats[baseIdx] / INPUT_SIZE
            val y = floats[baseIdx + 1] / INPUT_SIZE
            val z = if (stride > 2) floats[baseIdx + 2] / INPUT_SIZE else 0f
            val visibility = if (stride > 3) sigmoid(floats[baseIdx + 3]) else 1f

            if (visibility >= config.minConfidence) {
                landmarks.add(PoseLandmark(
                    typeIndex = i,
                    x = x.toDouble().coerceIn(0.0, 1.0),
                    y = y.toDouble().coerceIn(0.0, 1.0),
                    z = z.toDouble(),
                    visibility = visibility.toDouble()
                ))
            } else {
                landmarks.add(PoseLandmark.notDetected(i))
            }
        }

        return landmarks
    }

    private fun sigmoid(x: Float): Float = 1.0f / (1.0f + exp(-x))

    private fun createPoseResult(
        landmarks: List<PoseLandmark>,
        processingTimeMs: Int,
        imageWidth: Int,
        imageHeight: Int
    ): PoseResult {
        val detectedLandmarks = landmarks.filter { it.visibility > config.minConfidence }
        val score = if (detectedLandmarks.isNotEmpty()) {
            detectedLandmarks.map { it.visibility }.average()
        } else 0.0

        val boundingBox = if (detectedLandmarks.isNotEmpty()) {
            val minX = detectedLandmarks.minOf { it.x }
            val maxX = detectedLandmarks.maxOf { it.x }
            val minY = detectedLandmarks.minOf { it.y }
            val maxY = detectedLandmarks.maxOf { it.y }
            BoundingBox(minX, minY, maxX - minX, maxY - minY)
        } else null

        val pose = Pose(landmarks, score, boundingBox)

        return PoseResult(
            poses = if (score > 0) listOf(pose) else emptyList(),
            processingTimeMs = processingTimeMs,
            accelerationMode = _accelerationMode,
            imageWidth = imageWidth,
            imageHeight = imageHeight
        )
    }

    override fun detectPose(imageData: ByteArray): PoseResult {
        val bitmap = BitmapFactory.decodeByteArray(imageData, 0, imageData.size)
            ?: throw IllegalArgumentException("Invalid image data")
        return detectPoseFromBitmap(bitmap).also { bitmap.recycle() }
    }

    override fun detectPoseFromFile(filePath: String): PoseResult {
        val file = File(filePath)
        if (!file.exists()) throw IllegalArgumentException("File not found: $filePath")
        val bitmap = BitmapFactory.decodeFile(filePath)
            ?: throw IllegalArgumentException("Could not decode image: $filePath")
        return detectPoseFromBitmap(bitmap).also { bitmap.recycle() }
    }

    private fun disposeInterpreter() {
        interpreter?.close()
        interpreter = null
    }

    override fun dispose() {
        disposeInterpreter()

        try {
            qnnDelegate?.let { delegate ->
                val closeMethod = delegate.javaClass.getMethod("close")
                closeMethod.invoke(delegate)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to close QNN delegate: ${e.message}")
        }
        qnnDelegate = null

        _accelerationMode = AccelerationMode.UNKNOWN
        Log.d(TAG, "TFLite Pose Detector disposed")
    }
}
