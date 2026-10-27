import Foundation
import AVFoundation

/// Video processor for frame-by-frame pose analysis.
class VideoProcessor {

    private var poseDetector: PoseDetectorProtocol?
    private var isCancelled = false
    private var progressHandler: ((VideoAnalysisProgress) -> Void)?
    private let processingQueue = DispatchQueue(label: "com.example.npu_pose_detection.video", qos: .userInitiated)

    init(detector: PoseDetectorProtocol) {
        self.poseDetector = detector
    }

    /// Analyze a video file for poses.
    ///
    /// - Parameters:
    ///   - videoPath: Path to the video file
    ///   - frameInterval: Process every Nth frame (1 = all frames)
    ///   - progress: Progress callback
    ///   - completion: Completion callback with result or error
    func analyzeVideo(
        at videoPath: String,
        frameInterval: Int = 1,
        progress: @escaping (VideoAnalysisProgress) -> Void,
        completion: @escaping (Result<VideoAnalysisResult, Error>) -> Void
    ) {
        self.progressHandler = progress
        self.isCancelled = false

        processingQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                let result = try self.processVideo(at: videoPath, frameInterval: frameInterval)
                DispatchQueue.main.async {
                    completion(.success(result))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Cancel ongoing analysis.
    func cancel() {
        isCancelled = true
    }

    private func processVideo(at path: String, frameInterval: Int) throws -> VideoAnalysisResult {
        let url = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: path) else {
            throw VideoProcessorError.fileNotFound
        }

        let asset = AVAsset(url: url)

        // Get video properties
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            throw VideoProcessorError.noVideoTrack
        }

        let duration = CMTimeGetSeconds(asset.duration)
        let frameRate = videoTrack.nominalFrameRate
        let totalFrames = Int(duration * Double(frameRate))
        let naturalSize = videoTrack.naturalSize

        // Create asset reader
        let reader = try AVAssetReader(asset: asset)

        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        let trackOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        trackOutput.alwaysCopiesSampleData = false
        reader.add(trackOutput)

        guard reader.startReading() else {
            throw VideoProcessorError.readerFailed(reader.error?.localizedDescription ?? "Unknown error")
        }

        var frameResults: [VideoFrameResult] = []
        var frameIndex = 0
        var analyzedCount = 0
        let startTime = CFAbsoluteTimeGetCurrent()

        while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
            if isCancelled {
                reader.cancelReading()
                break
            }

            // Only process at specified interval
            if frameIndex % frameInterval == 0 {
                let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))

                do {
                    // Extract CVPixelBuffer from sample buffer
                    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                        throw VideoProcessorError.readerFailed("Failed to get pixel buffer")
                    }

                    let poseResult = try poseDetector?.processFrame(pixelBuffer: pixelBuffer)

                    if let result = poseResult {
                        let frameResult = VideoFrameResult(
                            frameIndex: frameIndex,
                            timestampSeconds: timestamp,
                            result: result
                        )
                        frameResults.append(frameResult)
                    }
                } catch {
                    // Continue on error, just skip the frame
                }

                analyzedCount += 1

                // Report progress
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                let framesPerSecond = elapsed > 0 ? Double(analyzedCount) / elapsed : 0
                let remainingFrames = Double(totalFrames - frameIndex) / Double(frameInterval)
                let estimatedRemaining = framesPerSecond > 0 ? remainingFrames / framesPerSecond : nil

                let progress = VideoAnalysisProgress(
                    currentFrame: frameIndex,
                    totalFrames: totalFrames,
                    currentTimeSeconds: timestamp,
                    durationSeconds: duration,
                    estimatedRemainingSeconds: estimatedRemaining
                )

                DispatchQueue.main.async {
                    self.progressHandler?(progress)
                }
            }

            frameIndex += 1
        }

        let totalTime = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

        return VideoAnalysisResult(
            frames: frameResults,
            totalFrames: totalFrames,
            analyzedFrames: analyzedCount,
            durationSeconds: duration,
            frameRate: Double(frameRate),
            width: Int(naturalSize.width),
            height: Int(naturalSize.height),
            totalAnalysisTimeMs: totalTime
        )
    }
}

// MARK: - Error Types

enum VideoProcessorError: Error {
    case fileNotFound
    case noVideoTrack
    case readerFailed(String)
}

// MARK: - Data Models

struct VideoAnalysisProgress {
    let currentFrame: Int
    let totalFrames: Int
    let currentTimeSeconds: Double
    let durationSeconds: Double
    let estimatedRemainingSeconds: Double?

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "type": "progress",
            "currentFrame": currentFrame,
            "totalFrames": totalFrames,
            "currentTimeSeconds": currentTimeSeconds,
            "durationSeconds": durationSeconds
        ]
        if let remaining = estimatedRemainingSeconds {
            dict["estimatedRemainingSeconds"] = remaining
        }
        return dict
    }
}

struct VideoFrameResult {
    let frameIndex: Int
    let timestampSeconds: Double
    let result: PoseResult

    func toDictionary() -> [String: Any] {
        return [
            "frameIndex": frameIndex,
            "timestampSeconds": timestampSeconds,
            "result": result.toDictionary()
        ]
    }
}

struct VideoAnalysisResult {
    let frames: [VideoFrameResult]
    let totalFrames: Int
    let analyzedFrames: Int
    let durationSeconds: Double
    let frameRate: Double
    let width: Int
    let height: Int
    let totalAnalysisTimeMs: Int

    func toDictionary() -> [String: Any] {
        return [
            "frames": frames.map { $0.toDictionary() },
            "totalFrames": totalFrames,
            "analyzedFrames": analyzedFrames,
            "durationSeconds": durationSeconds,
            "frameRate": frameRate,
            "width": width,
            "height": height,
            "totalAnalysisTimeMs": totalAnalysisTimeMs
        ]
    }
}
