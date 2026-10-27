import Foundation

/// Detection mode controlling speed/accuracy trade-off.
enum DetectionMode: String {
    case fast
    case balanced
    case accurate

    static func from(string: String) -> DetectionMode {
        return DetectionMode(rawValue: string.lowercased()) ?? .fast
    }
}

/// Hardware acceleration mode.
enum AccelerationMode: String {
    case npu
    case gpu
    case cpu
    case unknown

    static func from(string: String) -> AccelerationMode {
        return AccelerationMode(rawValue: string.lowercased()) ?? .unknown
    }
}

/// Configuration for pose detection.
struct DetectorConfig {
    let mode: DetectionMode
    let maxPoses: Int
    let minConfidence: Float
    let enableZEstimation: Bool
    let preferredAcceleration: AccelerationMode?

    init(
        mode: DetectionMode = .fast,
        maxPoses: Int = 1,
        minConfidence: Float = 0.5,
        enableZEstimation: Bool = true,
        preferredAcceleration: AccelerationMode? = nil
    ) {
        self.mode = mode
        self.maxPoses = max(1, min(10, maxPoses))
        self.minConfidence = max(0.0, min(1.0, minConfidence))
        self.enableZEstimation = enableZEstimation
        self.preferredAcceleration = preferredAcceleration
    }

    static func from(dictionary: [String: Any]) -> DetectorConfig {
        return DetectorConfig(
            mode: DetectionMode.from(string: dictionary["mode"] as? String ?? "fast"),
            maxPoses: dictionary["maxPoses"] as? Int ?? 1,
            minConfidence: (dictionary["minConfidence"] as? NSNumber)?.floatValue ?? 0.5,
            enableZEstimation: dictionary["enableZEstimation"] as? Bool ?? true,
            preferredAcceleration: (dictionary["preferredAcceleration"] as? String).flatMap {
                AccelerationMode.from(string: $0)
            }
        )
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "mode": mode.rawValue,
            "maxPoses": maxPoses,
            "minConfidence": minConfidence,
            "enableZEstimation": enableZEstimation
        ]
        if let pref = preferredAcceleration {
            dict["preferredAcceleration"] = pref.rawValue
        }
        return dict
    }
}
