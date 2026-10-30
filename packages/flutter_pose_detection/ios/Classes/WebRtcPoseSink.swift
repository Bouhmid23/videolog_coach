import Foundation
import UIKit
import CoreVideo
import Flutter
import WebRTC

/**
 * Zero-copy native WebRTC VideoSink for MediaPipe pose detection on iOS.
 *
 * Implements RTCVideoRenderer to receive frames directly from RTCVideoTrack.
 * Features:
 * - Direct CVPixelBuffer extraction from RTCVideoFrame with zero CPU copy.
 * - LIFO single-frame queue (drop-frame) to avoid blocking the WebRTC rendering pipeline.
 * - Dynamic Throttling: monitors thermal state (ProcessInfo.thermalState) and battery level (UIDevice)
 *   to automatically switch between nominal FPS (e.g. 30) and throttled FPS (e.g. 12-15).
 * - Accepts target FPS updates dynamically from Dart.
 */
class WebRtcPoseSink: NSObject, RTCVideoRenderer {

    private static let TAG = "WebRtcPoseSink"

    // MARK: - Track Resolution via FlutterWebRTCPlugin

    static func resolveVideoTrack(trackId: String) -> RTCVideoTrack? {
        guard let pluginClass = NSClassFromString("FlutterWebRTCPlugin") as? NSObject.Type,
              let shared = pluginClass.perform(NSSelectorFromString("sharedSingleton"))?.takeUnretainedValue() as? NSObject,
              let localTracks = shared.value(forKey: "localTracks") as? [String: AnyObject] else {
            print("[\(TAG)] Could not access localTracks dictionary in FlutterWebRTCPlugin")
            return nil
        }

        // 1. Direct lookup by key
        if let localTrack = localTracks[trackId] {
            if let track = (localTrack as AnyObject).perform(NSSelectorFromString("track"))?.takeUnretainedValue() as? RTCVideoTrack {
                print("[\(TAG)] Direct key match found for trackId: \(trackId)")
                return track
            }
        }

        // 2. Iterate map to find match on trackId or first RTCVideoTrack fallback
        var firstVideoTrack: RTCVideoTrack?
        for (_, localTrack) in localTracks {
            if let track = (localTrack as AnyObject).perform(NSSelectorFromString("track"))?.takeUnretainedValue() as? RTCVideoTrack {
                if firstVideoTrack == nil {
                    firstVideoTrack = track
                }
                if track.trackId == trackId {
                    print("[\(TAG)] Matched track.trackId in localTracks for: \(trackId)")
                    return track
                }
            }
        }

        if let fallback = firstVideoTrack {
            print("[\(TAG)] Matched fallback single RTCVideoTrack: \(fallback.trackId) (requested: \(trackId))")
            return fallback
        }

        print("[\(TAG)] No RTCVideoTrack found for trackId: \(trackId)")
        return nil
    }

    // MARK: - Properties

    private weak var detector: PoseDetectorProtocol?
    private var eventSink: FlutterEventSink?
    private weak var videoTrack: RTCVideoTrack?

    private var nominalFps: Int
    private var throttledFps: Int
    private var adaptiveThrottlingEnabled: BooleanLiteralType

    private var isRunning = false
    private var isProcessing = false
    private let queue = DispatchQueue(label: "com.example.flutter_pose_detection.webrtc_sink", qos: .userInitiated)
    private let frameLock = NSLock()
    private var pendingFrame: RTCVideoFrame?

    private var lastDispatchedTime: TimeInterval = 0
    private var frameCount: Int = 0
    private var fpsCalculator = FPSCalculator()

    // Dynamic Throttling state
    private var isThermalThrottled = false
    private var isLowBattery = false
    private var batteryLevel: Float = 1.0
    private var thermalObserver: NSObjectProtocol?
    private var batteryObserver: NSObjectProtocol?

    var currentEffectiveFps: Int {
        if adaptiveThrottlingEnabled && (isThermalThrottled || isLowBattery) {
            return throttledFps
        }
        return nominalFps
    }

    // MARK: - Init & Lifecycle

    init(
        detector: PoseDetectorProtocol,
        eventSink: FlutterEventSink?,
        nominalFps: Int = 30,
        throttledFps: Int = 15,
        adaptiveThrottlingEnabled: Bool = true
    ) {
        self.detector = detector
        self.eventSink = eventSink
        self.nominalFps = max(5, min(60, nominalFps))
        self.throttledFps = max(5, min(30, throttledFps))
        self.adaptiveThrottlingEnabled = adaptiveThrottlingEnabled
        super.init()
    }

    func start(track: RTCVideoTrack) {
        guard !isRunning else { return }
        isRunning = true
        videoTrack = track
        fpsCalculator.reset()
        frameCount = 0
        lastDispatchedTime = 0

        setupThermalListener()
        setupBatteryListener()

        track.add(self)
        print("[\(Self.TAG)] ✓ WebRtcPoseSink attached to RTCVideoTrack \(track.trackId), nominalFps=\(nominalFps), throttledFps=\(throttledFps)")
    }

    func updateTargetFps(_ fps: Int) {
        nominalFps = max(5, min(60, fps))
        print("[\(Self.TAG)] Nominal target FPS updated to \(nominalFps) (effective=\(currentEffectiveFps))")
    }

    func setAdaptiveThrottling(enabled: Bool, lowFps: Int = 15) {
        adaptiveThrottlingEnabled = enabled
        throttledFps = max(5, min(30, lowFps))
        print("[\(Self.TAG)] Adaptive throttling set to \(enabled) (throttledFps=\(throttledFps), effective=\(currentEffectiveFps))")
    }

    // MARK: - RTCVideoRenderer

    func setSize(_ size: CGSize) {
        // No-op for pose detection
    }

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard isRunning, let frame = frame else { return }

        let now = CACurrentMediaTime()
        let effectiveFps = currentEffectiveFps
        let minInterval = (effectiveFps > 0) ? (1.0 / Double(effectiveFps)) : 0.033

        // Dynamic Throttling check
        if now - lastDispatchedTime < minInterval {
            return // Drop frame before processing
        }

        // LIFO drop-frame queue (size = 1)
        frameLock.lock()
        pendingFrame = frame
        lastDispatchedTime = now
        let shouldSpawn = !isProcessing
        if shouldSpawn {
            isProcessing = true
        }
        frameLock.unlock()

        if shouldSpawn {
            queue.async { [weak self] in
                self?.processLoop()
            }
        }
    }

    private func processLoop() {
        while isRunning {
            frameLock.lock()
            guard let frame = pendingFrame else {
                isProcessing = false
                frameLock.unlock()
                break
            }
            pendingFrame = nil
            frameLock.unlock()

            processSingleFrame(frame)
        }
    }

    private func processSingleFrame(_ frame: RTCVideoFrame) {
        guard let detector = self.detector else { return }

        // Extract CVPixelBuffer directly from WebRTC frame
        guard let pixelBufferWrapper = frame.buffer as? RTCCVPixelBuffer else {
            return
        }

        let pixelBuffer = pixelBufferWrapper.pixelBuffer
        let timestampMs = Int(Date().timeIntervalSince1970 * 1000)

        do {
            let poseResult = try detector.detect(pixelBuffer: pixelBuffer, requestedTimestampMs: timestampMs)

            frameCount += 1
            let fps = fpsCalculator.update()

            let payload: [String: Any] = [
                "type": "frame",
                "frameNumber": frameCount,
                "timestampUs": timestampMs * 1000,
                "fps": fps,
                "isThermalThrottled": isThermalThrottled,
                "isLowBattery": isLowBattery,
                "batteryLevel": Double(batteryLevel),
                "targetFps": currentEffectiveFps,
                "result": poseResult.toDictionary()
            ]

            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.isRunning else { return }
                self.eventSink?(payload)
            }
        } catch {
            print("[\(Self.TAG)] Pose detection failed on frame: \(error)")
        }
    }

    // MARK: - Thermal & Battery Monitoring

    private func setupThermalListener() {
        let updateThermal = { [weak self] in
            guard let self = self else { return }
            let state = ProcessInfo.processInfo.thermalState
            let wasThrottled = self.isThermalThrottled
            self.isThermalThrottled = (state == .serious || state == .critical)
            if wasThrottled != self.isThermalThrottled {
                print("[\(Self.TAG)] 🌡️ iOS Thermal state changed: \(state.rawValue) -> throttled=\(self.isThermalThrottled) (targetFps=\(self.currentEffectiveFps))")
            }
        }

        updateThermal()

        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            updateThermal()
        }
    }

    private func setupBatteryListener() {
        UIDevice.current.isBatteryMonitoringEnabled = true

        let updateBattery = { [weak self] in
            guard let self = self else { return }
            let level = UIDevice.current.batteryLevel
            let state = UIDevice.current.batteryState
            if level >= 0 {
                self.batteryLevel = level
                let wasLow = self.isLowBattery
                self.isLowBattery = (level < 0.20 && state != .charging && state != .full)
                if wasLow != self.isLowBattery {
                    print("[\(Self.TAG)] 🔋 iOS Battery status: \(Int(level * 100))% (low=\(self.isLowBattery), targetFps=\(self.currentEffectiveFps))")
                }
            }
        }

        updateBattery()

        batteryObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            updateBattery()
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        videoTrack?.remove(self)
        videoTrack = nil

        frameLock.lock()
        pendingFrame = nil
        isProcessing = false
        frameLock.unlock()

        if let observer = thermalObserver {
            NotificationCenter.default.removeObserver(observer)
            thermalObserver = nil
        }

        if let observer = batteryObserver {
            NotificationCenter.default.removeObserver(observer)
            batteryObserver = nil
        }

        print("[\(Self.TAG)] WebRtcPoseSink stopped and disposed")
    }
}
