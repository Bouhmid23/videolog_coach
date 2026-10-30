import Flutter
import UIKit
import AVFoundation
import AVKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var micStreamHandler: MicMeterStreamHandler?
  private var pipManager: PipManager?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      // 1. Canal micro réactif (EventChannel videolog/mic_meter_stream)
      let micChannel = FlutterEventChannel(
        name: "videolog/mic_meter_stream",
        binaryMessenger: controller.binaryMessenger
      )
      let micHandler = MicMeterStreamHandler()
      micStreamHandler = micHandler
      micChannel.setStreamHandler(micHandler)

      // 2. Gestionnaire Picture-in-Picture (MethodChannel videolog/pip)
      pipManager = PipManager(
        binaryMessenger: controller.binaryMessenger,
        rootViewController: controller
      )
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

// MARK: - PipManager (iOS 15+ AVPictureInPictureVideoCallViewController)

class PipManager: NSObject, AVPictureInPictureControllerDelegate {
  private let channel: FlutterMethodChannel
  private var pipController: AVPictureInPictureController?
  private var pipVideoCallViewController: Any?
  private var isPipActive = false
  private var autoEnterEnabled = false
  private weak var rootViewController: UIViewController?

  init(binaryMessenger: FlutterBinaryMessenger, rootViewController: UIViewController?) {
    self.channel = FlutterMethodChannel(name: "videolog/pip", binaryMessenger: binaryMessenger)
    self.rootViewController = rootViewController
    super.init()
    setupMethodChannel()
    setupPipController()
  }

  private func isSupported() -> Bool {
    if #available(iOS 15.0, *) {
      return AVPictureInPictureController.isPictureInPictureSupported()
    }
    return false
  }

  private func setupPipController() {
    guard #available(iOS 15.0, *), isSupported(), let rootView = rootViewController?.view else { return }

    let callVC = AVPictureInPictureVideoCallViewController()
    callVC.preferredContentSize = CGSize(width: 9, height: 16)
    callVC.view.backgroundColor = UIColor(red: 11/255.0, green: 17/255.0, blue: 32/255.0, alpha: 1.0)

    let contentSource = AVPictureInPictureController.ContentSource(
      activeVideoCallSourceView: rootView,
      contentViewController: callVC
    )

    let controller = AVPictureInPictureController(contentSource: contentSource)
    controller.delegate = self
    controller.canStartPictureInPictureAutomaticallyFromInline = autoEnterEnabled
    self.pipController = controller
    self.pipVideoCallViewController = callVC
  }

  private func setupMethodChannel() {
    channel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else {
        result(false)
        return
      }
      switch call.method {
      case "isSupported":
        result(self.isSupported())
      case "enableAutoEnter":
        let args = call.arguments as? [String: Any]
        let width = args?["width"] as? Int ?? 9
        let height = args?["height"] as? Int ?? 16
        self.enableAutoEnter(width: width, height: height)
        result(true)
      case "disableAutoEnter":
        self.disableAutoEnter()
        result(true)
      case "enter":
        result(self.enterPip())
      case "isInPip":
        result(self.isPipActive)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func enableAutoEnter(width: Int, height: Int) {
    autoEnterEnabled = true
    if #available(iOS 15.0, *) {
      if pipController == nil {
        setupPipController()
      }
      if let callVC = pipVideoCallViewController as? AVPictureInPictureVideoCallViewController {
        callVC.preferredContentSize = CGSize(width: width, height: height)
      }
      pipController?.canStartPictureInPictureAutomaticallyFromInline = true
    }
  }

  private func disableAutoEnter() {
    autoEnterEnabled = false
    if #available(iOS 15.0, *) {
      pipController?.canStartPictureInPictureAutomaticallyFromInline = false
    }
  }

  private func enterPip() -> Bool {
    if #available(iOS 15.0, *) {
      guard let controller = pipController, controller.isPictureInPicturePossible else {
        return false
      }
      controller.startPictureInPicture()
      return true
    }
    return false
  }

  // MARK: - AVPictureInPictureControllerDelegate

  func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    if #available(iOS 15.0, *),
       let callVC = pipVideoCallViewController as? AVPictureInPictureVideoCallViewController,
       let rootView = rootViewController?.view,
       let snapshot = rootView.snapshotView(afterScreenUpdates: false) {
      snapshot.tag = 999
      callVC.view.subviews.forEach { if $0.tag == 999 { $0.removeFromSuperview() } }
      snapshot.frame = callVC.view.bounds
      snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      callVC.view.addSubview(snapshot)
    }
  }

  func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    isPipActive = true
    channel.invokeMethod("pipModeChanged", true)
  }

  func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    isPipActive = false
    if #available(iOS 15.0, *),
       let callVC = pipVideoCallViewController as? AVPictureInPictureVideoCallViewController {
      callVC.view.subviews.forEach { if $0.tag == 999 { $0.removeFromSuperview() } }
    }
    channel.invokeMethod("pipModeChanged", false)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    isPipActive = false
    channel.invokeMethod("pipModeChanged", false)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
  ) {
    completionHandler(true)
  }
}

// MARK: - MicMeterStreamHandler

class MicMeterStreamHandler: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var audioEngine: AVAudioEngine?
  private var currentLevel: Double = 0.0

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    return startRecording()
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    stopRecording()
    return nil
  }

  private func startRecording() -> FlutterError? {
    let session = AVAudioSession.sharedInstance()
    if session.recordPermission == .undetermined {
      session.requestRecordPermission { [weak self] granted in
        if granted {
          DispatchQueue.main.async {
            _ = self?.startRecording()
          }
        }
      }
      return nil
    } else if session.recordPermission != .granted {
      return FlutterError(
        code: "PERMISSION_NOT_GRANTED",
        message: "Microphone permission is not granted",
        details: nil
      )
    }

    do {
      try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
      try session.setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      return FlutterError(
        code: "AUDIO_SESSION_ERROR",
        message: "Failed to configure audio session: \(error.localizedDescription)",
        details: nil
      )
    }

    let engine = AVAudioEngine()
    let inputNode = engine.inputNode
    let recordingFormat = inputNode.outputFormat(forBus: 0)

    guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
      return FlutterError(
        code: "INVALID_FORMAT",
        message: "Invalid audio input format",
        details: nil
      )
    }

    currentLevel = 0.0
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] (buffer, _) in
      guard let self = self, let channelData = buffer.floatChannelData?[0] else { return }
      let frameLength = Int(buffer.frameLength)
      guard frameLength > 0 else { return }

      var sumSq: Float = 0.0
      for i in 0..<frameLength {
        let sample = channelData[i]
        sumSq += sample * sample
      }
      let rms = sqrt(sumSq / Float(frameLength))
      let normalized = Double(min(max(rms * 5.5, 0.0), 1.0))

      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        self.currentLevel = self.currentLevel * 0.35 + normalized * 0.65
        self.eventSink?(self.currentLevel)
      }
    }

    do {
      try engine.start()
      self.audioEngine = engine
      return nil
    } catch {
      inputNode.removeTap(onBus: 0)
      return FlutterError(
        code: "ENGINE_START_FAILED",
        message: "Failed to start audio engine: \(error.localizedDescription)",
        details: nil
      )
    }
  }

  private func stopRecording() {
    if let engine = audioEngine {
      if engine.isRunning {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
      }
      audioEngine = nil
    }
    currentLevel = 0.0
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(0.0)
    }
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}
