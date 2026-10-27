package com.example.npu_pose_detection.models

/**
 * Individual body landmark for MediaPipe 33-landmark format.
 *
 * typeIndex corresponds to MediaPipe landmark indices (0-32).
 */
data class PoseLandmark(
    val typeIndex: Int,
    val x: Double,
    val y: Double,
    val z: Double = 0.0,
    val visibility: Double
) {
    val isDetected: Boolean get() = visibility > 0

    companion object {
        fun notDetected(typeIndex: Int): PoseLandmark {
            return PoseLandmark(typeIndex, 0.0, 0.0, 0.0, 0.0)
        }
    }

    fun toMap(): Map<String, Any> {
        return mapOf(
            "type" to typeIndex,
            "x" to x,
            "y" to y,
            "z" to z,
            "visibility" to visibility
        )
    }
}

data class WorldLandmark(
    val typeIndex: Int,
    val x: Double,
    val y: Double,
    val z: Double,
    val visibility: Double
) {
    fun toMap(): Map<String, Any> = mapOf(
        "type" to typeIndex, "x" to x, "y" to y, "z" to z, "visibility" to visibility
    )
}

/**
 * Bounding box for detected pose.
 */
data class BoundingBox(
    val left: Double,
    val top: Double,
    val width: Double,
    val height: Double
) {
    fun toMap(): Map<String, Any> {
        return mapOf(
            "left" to left,
            "top" to top,
            "width" to width,
            "height" to height
        )
    }
}

/**
 * A single detected pose with 33 landmarks.
 */
data class Pose(
    val landmarks: List<PoseLandmark>,
    val score: Double,
    val boundingBox: BoundingBox? = null,
    val worldLandmarks: List<WorldLandmark> = emptyList()
) {
    fun toMap(): Map<String, Any?> {
        return mapOf(
            "landmarks" to landmarks.map { it.toMap() },
            "worldLandmarks" to worldLandmarks.map { it.toMap() },
            "score" to score,
            "boundingBox" to boundingBox?.toMap()
        )
    }
}

/**
 * Result from pose detection.
 */
data class PoseResult(
    val poses: List<Pose>,
    val processingTimeMs: Int,
    val accelerationMode: AccelerationMode,
    val timestamp: Long = System.currentTimeMillis(),
    val imageWidth: Int,
    val imageHeight: Int
) {
    companion object {
        fun empty(
            processingTimeMs: Int,
            accelerationMode: AccelerationMode,
            imageWidth: Int,
            imageHeight: Int
        ): PoseResult {
            return PoseResult(
                poses = emptyList(),
                processingTimeMs = processingTimeMs,
                accelerationMode = accelerationMode,
                imageWidth = imageWidth,
                imageHeight = imageHeight
            )
        }
    }

    fun toMap(): Map<String, Any> {
        return mapOf(
            "poses" to poses.map { it.toMap() },
            "processingTimeMs" to processingTimeMs,
            "accelerationMode" to accelerationMode.name.lowercase(),
            "timestamp" to timestamp,
            "imageWidth" to imageWidth,
            "imageHeight" to imageHeight
        )
    }
}
