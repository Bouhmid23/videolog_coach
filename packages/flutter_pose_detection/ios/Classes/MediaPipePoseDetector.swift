import Foundation
import UIKit
import CoreMedia
import MediaPipeTasksVision

/**
 * Détecteur de pose iOS basé sur MediaPipe Tasks `PoseLandmarker`.
 *
 * Même moteur et même modèle (`pose_landmarker_lite.task`) que sur Android :
 * détection de la personne puis suivi entre les images (mode vidéo), avec
 * - les landmarks image normalisés (x, y, z, visibilité) ;
 * - les worldLandmarks en mètres, centrés sur le bassin (utilisés par le web).
 *
 * Accélération : GPU en priorité, CPU en repli (comme Android).
 */
class MediaPipePoseDetector: PoseDetectorProtocol {

    // MARK: - Constants

    private static let TAG = "MediaPipePoseDetector"
    private static let MODEL_NAME = "pose_landmarker_lite"
    private static let MODEL_EXT = "task"
    private static let NUM_LANDMARKS = 33

    // MARK: - Properties

    private var poseLandmarker: PoseLandmarker?
    private var config: DetectorConfig
    private var _accelerationMode: AccelerationMode = .unknown

    /// Les horodatages du mode vidéo doivent être strictement croissants.
    private var lastTimestampMs: Int = 0
    private let lock = NSLock()

    var accelerationMode: AccelerationMode { _accelerationMode }
    var isInitialized: Bool { poseLandmarker != nil }

    // MARK: - Initialization

    init(config: DetectorConfig) {
        self.config = config
    }

    /// Crée le PoseLandmarker : GPU d'abord, puis CPU.
    func initialize() throws -> AccelerationMode {
        print("[\(Self.TAG)] Initializing MediaPipe PoseLandmarker...")

        guard let modelPath = getModelPath() else {
            throw DetectorError.modelLoadFailed("\(Self.MODEL_NAME).\(Self.MODEL_EXT) not found")
        }

        if config.preferredAcceleration != .cpu {
            if let mode = try? createLandmarker(modelPath: modelPath, delegate: .GPU) {
                print("[\(Self.TAG)] ✓ Initialized PoseLandmarker with GPU")
                return mode
            }
            print("[\(Self.TAG)] ✗ GPU initialization failed, falling back to CPU")
        }

        let mode = try createLandmarker(modelPath: modelPath, delegate: .CPU)
        print("[\(Self.TAG)] ✓ Initialized PoseLandmarker with CPU")
        return mode
    }

    private func createLandmarker(modelPath: String, delegate: Delegate) throws -> AccelerationMode {
        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.baseOptions.delegate = delegate
        options.runningMode = .video
        options.numPoses = max(1, min(10, config.maxPoses))
        options.minPoseDetectionConfidence = config.minConfidence
        options.minPosePresenceConfidence = config.minConfidence
        options.minTrackingConfidence = config.minConfidence

        poseLandmarker = try PoseLandmarker(options: options)
        _accelerationMode = (delegate == .GPU) ? .gpu : .cpu
        return _accelerationMode
    }

    // MARK: - Model Path

    private func getModelPath() -> String? {
        let name = Self.MODEL_NAME
        let ext = Self.MODEL_EXT
        let podBundle = Bundle(for: type(of: self))

        if let resourceBundlePath = podBundle.path(forResource: "flutter_pose_detection", ofType: "bundle"),
           let resourceBundle = Bundle(path: resourceBundlePath),
           let path = resourceBundle.path(forResource: name, ofType: ext) {
            return path
        }
        if let path = podBundle.path(forResource: name, ofType: ext) {
            return path
        }
        if let path = Bundle.main.path(forResource: name, ofType: ext) {
            return path
        }
        print("[\(Self.TAG)] Model not found: \(name).\(ext)")
        return nil
    }

    // MARK: - Detection

    func detectPose(imageData: Data) throws -> PoseResult {
        guard let uiImage = UIImage(data: imageData) else {
            throw DetectorError.invalidImageFormat
        }
        return try detect(uiImage: uiImage, requestedTimestampMs: nil)
    }

    /// Détection avec l'horodatage de la capture (suivi entre images).
    func detectPoseVideo(imageData: Data, timestampMs: Int) throws -> PoseResult {
        guard let uiImage = UIImage(data: imageData) else {
            throw DetectorError.invalidImageFormat
        }
        return try detect(uiImage: uiImage, requestedTimestampMs: timestampMs)
    }

    func detectPose(filePath: String) throws -> PoseResult {
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw DetectorError.fileNotFound
        }
        guard let uiImage = UIImage(contentsOfFile: filePath) else {
            throw DetectorError.invalidImageFormat
        }
        return try detect(uiImage: uiImage, requestedTimestampMs: nil)
    }

    func processFrame(pixelBuffer: CVPixelBuffer) throws -> PoseResult {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw DetectorError.invalidImageFormat
        }
        return try detect(uiImage: UIImage(cgImage: cgImage), requestedTimestampMs: nil)
    }

    private func nextTimestamp(_ requested: Int?) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let base = requested ?? Int(Date().timeIntervalSince1970 * 1000)
        let ts = max(base, lastTimestampMs + 1)
        lastTimestampMs = ts
        return ts
    }

    private func detect(uiImage: UIImage, requestedTimestampMs: Int?) throws -> PoseResult {
        guard let landmarker = poseLandmarker else {
            throw DetectorError.notInitialized
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let image = try MPImage(uiImage: uiImage)
        let timestamp = nextTimestamp(requestedTimestampMs)
        let result = try landmarker.detect(videoFrame: image, timestampInMilliseconds: timestamp)
        let processingTime = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

        let width = Int(uiImage.size.width * uiImage.scale)
        let height = Int(uiImage.size.height * uiImage.scale)

        return PoseResult(
            poses: convert(result),
            processingTimeMs: processingTime,
            accelerationMode: _accelerationMode,
            timestamp: Date(),
            imageWidth: width,
            imageHeight: height
        )
    }

    // MARK: - Conversion

    private func convert(_ result: PoseLandmarkerResult) -> [Pose] {
        var poses = [Pose]()

        for (poseIndex, normalized) in result.landmarks.enumerated() {
            let landmarks: [PoseLandmark] = normalized.enumerated().map { index, lm in
                PoseLandmark(
                    typeIndex: index,
                    x: Double(lm.x),
                    y: Double(lm.y),
                    z: Double(lm.z),
                    visibility: lm.visibility?.doubleValue ?? 0
                )
            }

            let worldLandmarks: [WorldLandmark]
            if poseIndex < result.worldLandmarks.count {
                worldLandmarks = result.worldLandmarks[poseIndex].enumerated().map { index, lm in
                    WorldLandmark(
                        typeIndex: index,
                        x: Double(lm.x),
                        y: Double(lm.y),
                        z: Double(lm.z),
                        visibility: lm.visibility?.doubleValue ?? 0
                    )
                }
            } else {
                worldLandmarks = []
            }

            let detected = landmarks.filter { $0.visibility > Double(config.minConfidence) }
            let score = detected.isEmpty
                ? 0.0
                : detected.map { $0.visibility }.reduce(0, +) / Double(detected.count)

            poses.append(Pose(
                landmarks: landmarks,
                score: score,
                boundingBox: calculateBoundingBox(detected),
                worldLandmarks: worldLandmarks
            ))
        }

        return poses
    }

    private func calculateBoundingBox(_ landmarks: [PoseLandmark]) -> BoundingBox? {
        guard !landmarks.isEmpty else { return nil }

        let minX = landmarks.map { $0.x }.min()!
        let maxX = landmarks.map { $0.x }.max()!
        let minY = landmarks.map { $0.y }.min()!
        let maxY = landmarks.map { $0.y }.max()!

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

    // MARK: - Lifecycle

    func updateConfig(_ config: DetectorConfig) {
        self.config = config
    }

    func dispose() {
        poseLandmarker = nil
        _accelerationMode = .unknown
        print("[\(Self.TAG)] PoseLandmarker disposed")
    }
}
