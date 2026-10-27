import Foundation
import UIKit
import CoreMedia
import TensorFlowLite

/**
 * MediaPipe pose detector using TFLite with CoreML delegate for ANE acceleration.
 *
 * Uses the same 2-stage pipeline as MediaPipe:
 * 1. pose_detector.tflite - Detects person bounding box (224x224 input)
 * 2. pose_landmarks_detector.tflite - Detects 33 landmarks (256x256 input)
 *
 * Hardware acceleration:
 * - ANE: CoreML delegate (Neural Engine on A12+)
 * - GPU: Metal delegate (fallback)
 * - CPU: XNNPACK (final fallback)
 */
class MediaPipePoseDetector: PoseDetectorProtocol {

    // MARK: - Constants

    private static let TAG = "MediaPipePoseDetector"

    private static let MODEL_DETECTOR = "pose_detector"
    private static let MODEL_LANDMARKS = "pose_landmarks_detector"

    private static let DETECTOR_INPUT_SIZE = 224
    private static let LANDMARKS_INPUT_SIZE = 256
    private static let NUM_LANDMARKS = 33
    private static let LANDMARK_DIMS = 5  // x, y, z, visibility, presence

    // MARK: - Properties

    private var detectorInterpreter: Interpreter?
    private var landmarksInterpreter: Interpreter?
    private var config: DetectorConfig
    private var _accelerationMode: AccelerationMode = .unknown
    private var isReady = false

    var accelerationMode: AccelerationMode { _accelerationMode }
    var isInitialized: Bool { isReady && detectorInterpreter != nil && landmarksInterpreter != nil }

    // MARK: - Initialization

    init(config: DetectorConfig) {
        self.config = config
    }

    /**
     * Initialize MediaPipe models with hardware acceleration.
     *
     * Tries CoreML delegate (ANE) first, then Metal (GPU), then CPU.
     */
    func initialize() throws -> AccelerationMode {
        print("[\(Self.TAG)] Initializing MediaPipe pose detector...")

        guard let detectorPath = getModelPath(Self.MODEL_DETECTOR),
              let landmarksPath = getModelPath(Self.MODEL_LANDMARKS) else {
            throw DetectorError.inferenceFailed("MediaPipe models not found")
        }

        // Try CoreML delegate first (Neural Engine)
        if config.preferredAcceleration != .cpu {
            if tryInitializeWithCoreML(detectorPath: detectorPath, landmarksPath: landmarksPath) {
                return _accelerationMode
            }

            // Try Metal delegate (GPU)
            if tryInitializeWithMetal(detectorPath: detectorPath, landmarksPath: landmarksPath) {
                return _accelerationMode
            }
        }

        // Fallback to CPU
        return try initializeWithCPU(detectorPath: detectorPath, landmarksPath: landmarksPath)
    }

    private func tryInitializeWithCoreML(detectorPath: String, landmarksPath: String) -> Bool {
        do {
            print("[\(Self.TAG)] Trying MediaPipe with CoreML delegate (ANE)...")

            var detectorOptions = Interpreter.Options()
            detectorOptions.threadCount = 4

            var landmarksOptions = Interpreter.Options()
            landmarksOptions.threadCount = 4

            guard let coreMLDelegate = CoreMLDelegate() else {
                print("[\(Self.TAG)] CoreML delegate creation failed")
                return false
            }

            detectorInterpreter = try Interpreter(
                modelPath: detectorPath,
                options: detectorOptions,
                delegates: [coreMLDelegate]
            )
            try detectorInterpreter?.allocateTensors()

            // Create a new CoreML delegate for landmarks model
            guard let landmarksCoreMLDelegate = CoreMLDelegate() else {
                cleanup()
                return false
            }

            landmarksInterpreter = try Interpreter(
                modelPath: landmarksPath,
                options: landmarksOptions,
                delegates: [landmarksCoreMLDelegate]
            )
            try landmarksInterpreter?.allocateTensors()

            _accelerationMode = .npu
            isReady = true
            print("[\(Self.TAG)] ✓ Initialized MediaPipe with CoreML (ANE)")
            return true
        } catch {
            print("[\(Self.TAG)] ✗ CoreML initialization failed: \(error)")
            cleanup()
            return false
        }
    }

    private func tryInitializeWithMetal(detectorPath: String, landmarksPath: String) -> Bool {
        do {
            print("[\(Self.TAG)] Trying MediaPipe with Metal delegate (GPU)...")

            var detectorOptions = Interpreter.Options()
            detectorOptions.threadCount = 4

            var landmarksOptions = Interpreter.Options()
            landmarksOptions.threadCount = 4

            let metalDelegate = MetalDelegate()

            detectorInterpreter = try Interpreter(
                modelPath: detectorPath,
                options: detectorOptions,
                delegates: [metalDelegate]
            )
            try detectorInterpreter?.allocateTensors()

            let landmarksMetalDelegate = MetalDelegate()
            landmarksInterpreter = try Interpreter(
                modelPath: landmarksPath,
                options: landmarksOptions,
                delegates: [landmarksMetalDelegate]
            )
            try landmarksInterpreter?.allocateTensors()

            _accelerationMode = .gpu
            isReady = true
            print("[\(Self.TAG)] ✓ Initialized MediaPipe with Metal (GPU)")
            return true
        } catch {
            print("[\(Self.TAG)] ✗ Metal initialization failed: \(error)")
            cleanup()
            return false
        }
    }

    private func initializeWithCPU(detectorPath: String, landmarksPath: String) throws -> AccelerationMode {
        print("[\(Self.TAG)] Fallback to MediaPipe CPU...")

        var options = Interpreter.Options()
        options.threadCount = 4

        detectorInterpreter = try Interpreter(modelPath: detectorPath, options: options)
        try detectorInterpreter?.allocateTensors()

        landmarksInterpreter = try Interpreter(modelPath: landmarksPath, options: options)
        try landmarksInterpreter?.allocateTensors()

        _accelerationMode = .cpu
        isReady = true
        print("[\(Self.TAG)] ✓ Initialized MediaPipe with CPU")
        return _accelerationMode
    }

    private func cleanup() {
        detectorInterpreter = nil
        landmarksInterpreter = nil
        isReady = false
    }

    // MARK: - Model Path

    private func getModelPath(_ modelName: String) -> String? {
        let podBundle = Bundle(for: type(of: self))

        // Try resource bundle first
        if let resourceBundlePath = podBundle.path(forResource: "flutter_pose_detection", ofType: "bundle"),
           let resourceBundle = Bundle(path: resourceBundlePath),
           let modelPath = resourceBundle.path(forResource: modelName, ofType: "tflite") {
            print("[\(Self.TAG)] Found \(modelName) in resource bundle")
            return modelPath
        }

        // Try plugin bundle directly
        if let bundlePath = podBundle.path(forResource: modelName, ofType: "tflite") {
            print("[\(Self.TAG)] Found \(modelName) in pod bundle")
            return bundlePath
        }

        // Try main bundle
        if let mainPath = Bundle.main.path(forResource: modelName, ofType: "tflite") {
            print("[\(Self.TAG)] Found \(modelName) in main bundle")
            return mainPath
        }

        print("[\(Self.TAG)] Model not found: \(modelName).tflite")
        return nil
    }

    // MARK: - Detection

    func detectPose(imageData: Data) throws -> PoseResult {
        guard isReady else {
            throw DetectorError.notInitialized
        }

        guard let uiImage = UIImage(data: imageData),
              let cgImage = uiImage.cgImage else {
            throw DetectorError.invalidImageFormat
        }

        return try detectPose(cgImage: cgImage)
    }

    func detectPose(filePath: String) throws -> PoseResult {
        guard isReady else {
            throw DetectorError.notInitialized
        }

        guard FileManager.default.fileExists(atPath: filePath) else {
            throw DetectorError.fileNotFound
        }

        guard let uiImage = UIImage(contentsOfFile: filePath),
              let cgImage = uiImage.cgImage else {
            throw DetectorError.invalidImageFormat
        }

        return try detectPose(cgImage: cgImage)
    }

    func detectPose(cgImage: CGImage) throws -> PoseResult {
        guard isReady else {
            throw DetectorError.notInitialized
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Stage 1: Detect person bounding box (simplified - use full image)
        // For single-person detection, we can skip person detection and use full image
        let detection = Detection(xMin: 0, yMin: 0, width: 1, height: 1, score: 1)

        // Stage 2: Run landmarks detector
        let landmarks = try runLandmarksDetector(cgImage: cgImage, detection: detection)

        let processingTime = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

        // Calculate overall score
        let detectedLandmarks = landmarks.filter { $0.isDetected }
        let score = detectedLandmarks.isEmpty ? 0.0 :
            detectedLandmarks.map { $0.visibility }.reduce(0, +) / Double(detectedLandmarks.count)

        let pose: Pose?
        if score >= Double(config.minConfidence) {
            pose = Pose(
                landmarks: landmarks,
                score: score,
                boundingBox: calculateBoundingBox(landmarks)
            )
        } else {
            pose = nil
        }

        return PoseResult(
            poses: pose.map { [$0] } ?? [],
            processingTimeMs: processingTime,
            accelerationMode: _accelerationMode,
            timestamp: Date(),
            imageWidth: cgImage.width,
            imageHeight: cgImage.height
        )
    }

    func processFrame(pixelBuffer: CVPixelBuffer) throws -> PoseResult {
        guard isReady else {
            throw DetectorError.notInitialized
        }

        // Convert pixel buffer to CGImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw DetectorError.invalidImageFormat
        }

        return try detectPose(cgImage: cgImage)
    }

    // MARK: - Inference

    /**
     * Run landmarks detector on cropped region.
     *
     * Input: [1, 256, 256, 3] normalized to [0, 1]
     * Output: [1, 195] = 33 landmarks x 5 (x, y, z, visibility, presence) + auxiliary
     */
    private func runLandmarksDetector(cgImage: CGImage, detection: Detection) throws -> [PoseLandmark] {
        guard let interpreter = landmarksInterpreter else {
            throw DetectorError.notInitialized
        }

        // Prepare input: resize and normalize to [0, 1]
        guard let inputData = prepareInputData(cgImage: cgImage, size: Self.LANDMARKS_INPUT_SIZE) else {
            throw DetectorError.invalidImageFormat
        }

        // Copy input
        try interpreter.copy(inputData, toInputAt: 0)

        // Run inference
        try interpreter.invoke()

        // Get output
        let outputTensor = try interpreter.output(at: 0)
        let outputData = outputTensor.data

        // Parse landmarks
        return parseLandmarks(outputData, detection: detection)
    }

    private func prepareInputData(cgImage: CGImage, size: Int) -> Data? {
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * size

        var pixelData = [UInt8](repeating: 0, count: size * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: &pixelData,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        // Convert to float normalized [0, 1]
        var floatData = [Float](repeating: 0, count: size * size * 3)
        for y in 0..<size {
            for x in 0..<size {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let floatOffset = (y * size + x) * 3

                floatData[floatOffset] = Float(pixelData[offset]) / 255.0      // R
                floatData[floatOffset + 1] = Float(pixelData[offset + 1]) / 255.0  // G
                floatData[floatOffset + 2] = Float(pixelData[offset + 2]) / 255.0  // B
            }
        }

        return Data(bytes: floatData, count: floatData.count * MemoryLayout<Float>.size)
    }

    private func parseLandmarks(_ outputData: Data, detection: Detection) -> [PoseLandmark] {
        let floats = outputData.withUnsafeBytes { pointer in
            Array(pointer.bindMemory(to: Float.self))
        }

        var landmarks = [PoseLandmark]()
        let inputSize = Float(Self.LANDMARKS_INPUT_SIZE)

        for i in 0..<Self.NUM_LANDMARKS {
            let baseIdx = i * Self.LANDMARK_DIMS
            guard baseIdx + 4 < floats.count else {
                landmarks.append(PoseLandmark.notDetected(typeIndex: i))
                continue
            }

            // Normalize pixel coordinates (0-256) to (0-1)
            let x = floats[baseIdx] / inputSize
            let y = floats[baseIdx + 1] / inputSize
            let z = floats[baseIdx + 2] / inputSize
            let visibility = sigmoid(floats[baseIdx + 3])
            let presence = sigmoid(floats[baseIdx + 4])

            // Transform coordinates back to original image space
            let origX = detection.xMin + x * detection.width
            let origY = detection.yMin + y * detection.height

            if visibility >= config.minConfidence && presence >= 0.5 {
                landmarks.append(PoseLandmark(
                    typeIndex: i,
                    x: Double(max(0, min(1, origX))),
                    y: Double(max(0, min(1, origY))),
                    z: Double(z),
                    visibility: Double(visibility)
                ))
            } else {
                landmarks.append(PoseLandmark.notDetected(typeIndex: i))
            }
        }

        return landmarks
    }

    private func sigmoid(_ x: Float) -> Float {
        return 1.0 / (1.0 + exp(-x))
    }

    // MARK: - Utilities

    private func calculateBoundingBox(_ landmarks: [PoseLandmark]) -> BoundingBox? {
        let detected = landmarks.filter { $0.isDetected }
        guard !detected.isEmpty else { return nil }

        let minX = detected.map { $0.x }.min()!
        let maxX = detected.map { $0.x }.max()!
        let minY = detected.map { $0.y }.min()!
        let maxY = detected.map { $0.y }.max()!

        let padding = 0.1
        let width = maxX - minX
        let height = maxY - minY

        return BoundingBox(
            left: max(0.0, min(1.0, minX - width * padding)),
            top: max(0.0, min(1.0, minY - height * padding)),
            width: max(0.0, min(1.0, width * (1 + 2 * padding))),
            height: max(0.0, min(1.0, height * (1 + 2 * padding)))
        )
    }

    func updateConfig(_ config: DetectorConfig) {
        self.config = config
    }

    func dispose() {
        cleanup()
        _accelerationMode = .unknown
        print("[\(Self.TAG)] MediaPipe detector disposed")
    }

    // MARK: - Detection Result

    private struct Detection {
        let xMin: Float
        let yMin: Float
        let width: Float
        let height: Float
        let score: Float
    }
}
