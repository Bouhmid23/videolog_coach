/// A MediaPipe world landmark in meters, centered around the body's hip origin.
class WorldLandmark {
  const WorldLandmark({
    required this.typeIndex,
    required this.x,
    required this.y,
    required this.z,
    required this.visibility,
  });

  final int typeIndex;
  final double x;
  final double y;
  final double z;
  final double visibility;

  factory WorldLandmark.fromJson(Map<String, dynamic> json) => WorldLandmark(
        typeIndex: json['type'] as int,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        z: (json['z'] as num).toDouble(),
        visibility: (json['visibility'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'type': typeIndex,
        'x': x,
        'y': y,
        'z': z,
        'visibility': visibility,
      };
}
