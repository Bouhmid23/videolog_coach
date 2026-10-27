import Foundation

/// Maps MoveNet/HRNet 17 keypoints to COCO 17 format directly.
///
/// COCO 17 keypoints (same as MoveNet/HRNet output):
/// 0: nose, 1: left_eye, 2: right_eye, 3: left_ear, 4: right_ear,
/// 5: left_shoulder, 6: right_shoulder, 7: left_elbow, 8: right_elbow,
/// 9: left_wrist, 10: right_wrist, 11: left_hip, 12: right_hip,
/// 13: left_knee, 14: right_knee, 15: left_ankle, 16: right_ankle
class LandmarkMapper {

    static let numKeypoints = 17

    /// Map keypoints to COCO 17 format (direct 1:1 mapping).
    ///
    /// - Parameters:
    ///   - keypoints: Array of 17 keypoints, each [y, x, confidence]
    ///   - minConfidence: Minimum confidence threshold
    /// - Returns: Array of 17 PoseLandmarks in COCO format
    func mapMoveNetToPose(
        _ keypoints: [[Float]],
        minConfidence: Float
    ) -> [PoseLandmark] {
        return keypoints.enumerated().map { index, point in
            // Output format: [y, x, confidence]
            let y = Double(point[0])
            let x = Double(point[1])
            let confidence = Double(point[2])

            if confidence >= Double(minConfidence) {
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
}
