package com.example.npu_pose_detection

import com.example.npu_pose_detection.models.*

/**
 * Maps keypoints to PoseLandmark format.
 *
 * Supports both COCO 17-point and MediaPipe 33-point formats.
 */
class LandmarkMapper {

    companion object {
        const val NUM_KEYPOINTS_COCO = 17
        const val NUM_KEYPOINTS_MEDIAPIPE = 33
    }

    /**
     * Map keypoints to PoseLandmark format.
     *
     * @param keypoints Array of keypoints, each [y, x, confidence]
     * @param minConfidence Minimum confidence threshold
     * @return List of PoseLandmark
     */
    fun mapKeypoints(
        keypoints: Array<FloatArray>,
        minConfidence: Float
    ): List<PoseLandmark> {
        return keypoints.mapIndexed { index, point ->
            // Output format: [y, x, confidence]
            val y = point[0]
            val x = point[1]
            val confidence = point[2]

            if (confidence >= minConfidence) {
                PoseLandmark(
                    typeIndex = index,
                    x = x.toDouble(),
                    y = y.toDouble(),
                    z = 0.0,
                    visibility = confidence.toDouble()
                )
            } else {
                PoseLandmark.notDetected(index)
            }
        }
    }
}
