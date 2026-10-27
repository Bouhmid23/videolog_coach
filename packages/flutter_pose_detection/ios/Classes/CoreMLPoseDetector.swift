import Foundation
import CoreML
import UIKit
import CoreMedia
import Accelerate

/**
 * Native Core ML pose detector for optimal Apple Neural Engine (ANE) performance.
 *
 * Uses Core ML directly (not Vision) since the model has MultiArray input, not image input.
 * This provides direct ANE acceleration without Vision framework overhead.
 *
 * Note: Requires HRNetPose.mlpackage model converted from ONNX/PyTorch
 */
class CoreMLPoseDetector {

    // MARK: - Constants

    private static let TAG = "CoreMLPoseDetector"
    private static let NUM_KEYPOINTS = 17
    private static let INPUT_WIDTH = 192
    private static let INPUT_HEIGHT = 256
    private static let HEATMAP_WIDTH = 48
    private static let HEATMAP_HEIGHT = 64

    // MARK: - Properties

    private var mlModel: MLModel?
    private var config: DetectorConfig
    private var _accelerationMode: AccelerationMode = .unknown
    private var isReady = false

    var accelerationMode: AccelerationMode { _accelerationMode }
    var isInitialized: Bool { isReady && mlModel != nil }

    // MARK: - Initialization

    init(config: DetectorConfig) {
        self.config = config
    }

    /**
     * Initialize with native Core ML model.
     *
     * Core ML automatically selects optimal compute unit:
     * 1. ANE (Neural Engine) - best power efficiency
     * 2. Metal (GPU) - fallback if ANE busy
     * 3. CPU (BNNS) - last resort
     */
    func initialize() throws -> AccelerationMode {
        print("[\(Self.TAG)] Initializing native Core ML detector...")

        // Try to load HRNetPose Core ML model
        guard let modelURL = getModelURL("HRNetPose") else {
            print("[\(Self.TAG)] Core ML model not found, falling back to TFLite")
            throw DetectorError.inferenceFailed("HRNetPose.mlpackage not found")
        }

        do {
            // Load Core ML model with configuration
            let mlConfig = MLModelConfiguration()

            // Prefer Neural Engine for best performance
            mlConfig.computeUnits = .all  // Let system choose optimal (ANE preferred)

            mlModel = try MLModel(contentsOf: modelURL, configuration: mlConfig)

            // Log model input/output info
            if let model = mlModel {
                print("[\(Self.TAG)] Model inputs: \(model.modelDescription.inputDescriptionsByName.keys)")
                print("[\(Self.TAG)] Model outputs: \(model.modelDescription.outputDescriptionsByName.keys)")
            }

            _accelerationMode = .npu  // Assume ANE is primary when available
            isReady = true

            print("[\(Self.TAG)] ✓ Initialized HRNetPose with Core ML (ANE optimized)")
            return _accelerationMode
        } catch {
            print("[\(Self.TAG)] ✗ Core ML initialization failed: \(error)")
            throw error
        }
    }

    // MARK: - Model Path

    private func getModelURL(_ modelName: String) -> URL? {
        let bundle = Bundle(for: type(of: self))

        // Try compiled .mlmodelc first
        if let url = bundle.url(forResource: modelName, withExtension: "mlmodelc") {
            print("[\(Self.TAG)] Found compiled model: \(url)")
            return url
        }

        // Try .mlpackage (uncompiled, Xcode compiles at build time)
        if let url = bundle.url(forResource: modelName, withExtension: "mlpackage") {
            print("[\(Self.TAG)] Found mlpackage: \(url)")
            return url
        }

        // Try resource bundle (CocoaPods)
        if let resourceBundlePath = bundle.path(forResource: "flutter_pose_detection", ofType: "bundle"),
           let resourceBundle = Bundle(path: resourceBundlePath) {

            if let url = resourceBundle.url(forResource: modelName, withExtension: "mlmodelc") {
                print("[\(Self.TAG)] Found model in resource bundle: \(url)")
                return url
            }

            if let url = resourceBundle.url(forResource: modelName, withExtension: "mlpackage") {
                print("[\(Self.TAG)] Found mlpackage in resource bundle: \(url)")
                return url
            }
        }

        // Try main bundle
        if let url = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") {
            print("[\(Self.TAG)] Found model in main bundle: \(url)")
            return url
        }

        if let url = Bundle.main.url(forResource: modelName, withExtension: "mlpackage") {
            print("[\(Self.TAG)] Found mlpackage in main bundle: \(url)")
            return url
        }

        print("[\(Self.TAG)] Model not found: \(modelName)")
        return nil
    }

    // MARK: - Detection

    /**
     * Process CGImage using Core ML directly.
     */
    func detectPose(cgImage: CGImage) throws -> PoseResult {
        guard isReady, let model = mlModel else {
            throw DetectorError.notInitialized
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Preprocess image to model input format
        guard let inputArray = preprocessImage(cgImage) else {
            throw DetectorError.invalidImageFormat
        }

        // Run inference
        let keypoints = try runInference(model: model, input: inputArray)

        let processingTime = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

        // Map to landmarks
        let landmarks = mapKeypoints(keypoints)
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

    /**
     * Process CVPixelBuffer directly from camera.
     */
    func processFrame(pixelBuffer: CVPixelBuffer) throws -> PoseResult {
        guard isReady, let model = mlModel else {
            throw DetectorError.notInitialized
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // Preprocess pixel buffer to model input format
        guard let inputArray = preprocessPixelBuffer(pixelBuffer) else {
            throw DetectorError.invalidImageFormat
        }

        // Run inference
        let keypoints = try runInference(model: model, input: inputArray)

        let processingTime = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

        let landmarks = mapKeypoints(keypoints)
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
            imageWidth: width,
            imageHeight: height
        )
    }

    // MARK: - Inference

    private func runInference(model: MLModel, input: MLMultiArray) throws -> [[Float]] {
        // Get input feature name from model description
        guard let inputName = model.modelDescription.inputDescriptionsByName.keys.first else {
            throw DetectorError.inferenceFailed("No input feature found")
        }

        // Create feature provider
        let inputFeature = try MLDictionaryFeatureProvider(dictionary: [inputName: input])

        // Run prediction
        let output = try model.prediction(from: inputFeature)

        // Get output feature name
        guard let outputName = model.modelDescription.outputDescriptionsByName.keys.first,
              let outputFeature = output.featureValue(for: outputName),
              let outputArray = outputFeature.multiArrayValue else {
            throw DetectorError.inferenceFailed("Failed to get output")
        }

        return parseHeatmaps(outputArray)
    }

    // MARK: - Preprocessing

    /**
     * Preprocess CGImage to MLMultiArray in NCHW format.
     * Input shape: [1, 3, 256, 192]
     */
    private func preprocessImage(_ image: CGImage) -> MLMultiArray? {
        let width = Self.INPUT_WIDTH
        let height = Self.INPUT_HEIGHT

        // Create resized RGB pixel data
        guard let pixelData = resizeAndExtractRGB(image, width: width, height: height) else {
            return nil
        }

        return createInputArray(from: pixelData, width: width, height: height)
    }

    /**
     * Preprocess CVPixelBuffer to MLMultiArray in NCHW format.
     */
    private func preprocessPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> MLMultiArray? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        // Create CGImage from pixel buffer
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        return preprocessImage(cgImage)
    }

    private func resizeAndExtractRGB(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelData
    }

    /**
     * Create MLMultiArray in NCHW format with normalized values.
     * HRNet expects values normalized to [0, 1] or [-1, 1] range.
     */
    private func createInputArray(from pixelData: [UInt8], width: Int, height: Int) -> MLMultiArray? {
        // Shape: [1, 3, 256, 192] - NCHW format
        guard let array = try? MLMultiArray(shape: [1, 3, NSNumber(value: height), NSNumber(value: width)], dataType: .float32) else {
            return nil
        }

        let bytesPerPixel = 4

        // ImageNet normalization for HRNet
        let mean: [Float] = [0.485, 0.456, 0.406]
        let std: [Float] = [0.229, 0.224, 0.225]

        for y in 0..<height {
            for x in 0..<width {
                let pixelOffset = y * width * bytesPerPixel + x * bytesPerPixel
                let r = Float(pixelData[pixelOffset]) / 255.0
                let g = Float(pixelData[pixelOffset + 1]) / 255.0
                let b = Float(pixelData[pixelOffset + 2]) / 255.0

                // Normalize with ImageNet mean/std
                let normalizedR = (r - mean[0]) / std[0]
                let normalizedG = (g - mean[1]) / std[1]
                let normalizedB = (b - mean[2]) / std[2]

                // NCHW layout: [batch, channel, height, width]
                let rIdx = 0 * height * width + y * width + x
                let gIdx = 1 * height * width + y * width + x
                let bIdx = 2 * height * width + y * width + x

                array[rIdx] = NSNumber(value: normalizedR)
                array[gIdx] = NSNumber(value: normalizedG)
                array[bIdx] = NSNumber(value: normalizedB)
            }
        }

        return array
    }

    // MARK: - Heatmap Parsing

    private func parseHeatmaps(_ multiArray: MLMultiArray) -> [[Float]] {
        let heatmapSize = Self.HEATMAP_WIDTH * Self.HEATMAP_HEIGHT
        var keypoints: [[Float]] = []

        for k in 0..<Self.NUM_KEYPOINTS {
            var maxVal: Float = -.greatestFiniteMagnitude
            var maxIdx = 0

            for i in 0..<heatmapSize {
                let idx = k * heatmapSize + i
                let value = multiArray[idx].floatValue
                if value > maxVal {
                    maxVal = value
                    maxIdx = i
                }
            }

            let heatmapX = maxIdx % Self.HEATMAP_WIDTH
            let heatmapY = maxIdx / Self.HEATMAP_WIDTH
            let normalizedX = Float(heatmapX) / Float(Self.HEATMAP_WIDTH)
            let normalizedY = Float(heatmapY) / Float(Self.HEATMAP_HEIGHT)
            let confidence = 1.0 / (1.0 + exp(-maxVal))  // sigmoid

            keypoints.append([normalizedY, normalizedX, confidence])
        }

        return keypoints
    }

    // MARK: - Keypoint Mapping (same as TFLite version)

    /// Map keypoints to COCO 17 format (direct 1:1 mapping).
    private func mapKeypoints(_ keypoints: [[Float]]) -> [PoseLandmark] {
        return keypoints.enumerated().map { index, point in
            let y = Double(point[0])
            let x = Double(point[1])
            let confidence = Double(point[2])

            if confidence >= Double(config.minConfidence) {
                return PoseLandmark(
                    type: LandmarkType(rawValue: index)!,
                    x: x,
                    y: y,
                    z: 0.0,
                    visibility: confidence
                )
            } else {
                return PoseLandmark.notDetected(type: LandmarkType(rawValue: index)!)
            }
        }
    }

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

    // MARK: - Cleanup

    func dispose() {
        mlModel = nil
        isReady = false
        _accelerationMode = .unknown
        print("[\(Self.TAG)] Detector disposed")
    }
}
