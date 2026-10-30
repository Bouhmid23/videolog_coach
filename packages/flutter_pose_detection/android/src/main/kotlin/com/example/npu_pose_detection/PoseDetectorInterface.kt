package com.example.npu_pose_detection

import android.graphics.Bitmap
import com.example.npu_pose_detection.models.AccelerationMode
import com.example.npu_pose_detection.models.PoseResult

/**
 * Common interface for pose detectors.
 *
 * Both MediaPipeNpuDetector and LiteRtPoseDetector implement this interface
 * to allow interchangeable use in VideoProcessor and other components.
 */
interface PoseDetectorInterface {
    /**
     * Whether the detector is initialized and ready for inference.
     */
    val isInitialized: Boolean

    /**
     * Current hardware acceleration mode.
     */
    val accelerationMode: AccelerationMode

    /**
     * Detect poses from image data.
     */
    fun detectPose(imageData: ByteArray): PoseResult

    fun detectPoseVideo(imageData: ByteArray, timestampMs: Long): PoseResult = detectPose(imageData)

    /**
     * Detect poses from an image file.
     */
    fun detectPoseFromFile(filePath: String): PoseResult

    /**
     * Detect poses from a bitmap.
     */
    fun detectPoseFromBitmap(bitmap: Bitmap): PoseResult

    fun detectPoseFromBitmap(bitmap: Bitmap, timestampMs: Long): PoseResult = detectPoseFromBitmap(bitmap)

    /**
     * Release resources.
     */
    fun dispose()
}
