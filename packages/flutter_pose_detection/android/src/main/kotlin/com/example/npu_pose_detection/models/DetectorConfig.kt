package com.example.npu_pose_detection.models

/**
 * Detection mode controlling speed/accuracy trade-off.
 */
enum class DetectionMode {
    FAST,
    BALANCED,
    ACCURATE;

    companion object {
        fun fromString(value: String): DetectionMode {
            return values().firstOrNull { it.name.equals(value, ignoreCase = true) } ?: FAST
        }
    }
}

/**
 * Hardware acceleration mode.
 */
enum class AccelerationMode {
    NPU,
    GPU,
    CPU,
    UNKNOWN;

    companion object {
        fun fromString(value: String): AccelerationMode {
            return values().firstOrNull { it.name.equals(value, ignoreCase = true) } ?: UNKNOWN
        }
    }
}

/**
 * Configuration for pose detection.
 */
data class DetectorConfig(
    val mode: DetectionMode = DetectionMode.FAST,
    val maxPoses: Int = 1,
    val minConfidence: Float = 0.5f,
    val minPoseDetectionConfidence: Float = minConfidence,
    val minPosePresenceConfidence: Float = minConfidence,
    val minTrackingConfidence: Float = minConfidence,
    val enableZEstimation: Boolean = true,
    val preferredAcceleration: AccelerationMode? = null,
    val skelLibraryDir: String? = null
) {
    companion object {
        fun fromMap(map: Map<*, *>): DetectorConfig {
            return DetectorConfig(
                mode = DetectionMode.fromString(map["mode"] as? String ?: "fast"),
                maxPoses = (map["maxPoses"] as? Number)?.toInt() ?: 1,
                minConfidence = (map["minConfidence"] as? Number)?.toFloat() ?: 0.5f,
                minPoseDetectionConfidence = (map["minPoseDetectionConfidence"] as? Number)?.toFloat()
                    ?: (map["minConfidence"] as? Number)?.toFloat() ?: 0.5f,
                minPosePresenceConfidence = (map["minPosePresenceConfidence"] as? Number)?.toFloat()
                    ?: (map["minConfidence"] as? Number)?.toFloat() ?: 0.5f,
                minTrackingConfidence = (map["minTrackingConfidence"] as? Number)?.toFloat()
                    ?: (map["minConfidence"] as? Number)?.toFloat() ?: 0.5f,
                enableZEstimation = map["enableZEstimation"] as? Boolean ?: true,
                preferredAcceleration = (map["preferredAcceleration"] as? String)?.let {
                    AccelerationMode.fromString(it)
                },
                skelLibraryDir = map["skelLibraryDir"] as? String
            )
        }
    }

    fun toMap(): Map<String, Any?> {
        return mapOf(
            "mode" to mode.name.lowercase(),
            "maxPoses" to maxPoses,
            "minConfidence" to minConfidence,
            "minPoseDetectionConfidence" to minPoseDetectionConfidence,
            "minPosePresenceConfidence" to minPosePresenceConfidence,
            "minTrackingConfidence" to minTrackingConfidence,
            "enableZEstimation" to enableZEstimation,
            "preferredAcceleration" to preferredAcceleration?.name?.lowercase(),
            "skelLibraryDir" to skelLibraryDir
        )
    }
}
