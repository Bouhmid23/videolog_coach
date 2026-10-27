import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pose_detection/flutter_pose_detection.dart';

import '../widgets/pose_overlay_painter.dart';

/// Page for testing image-based pose detection.
class ImageDetectionPage extends StatefulWidget {
  final NpuPoseDetector detector;

  const ImageDetectionPage({super.key, required this.detector});

  @override
  State<ImageDetectionPage> createState() => _ImageDetectionPageState();
}

class _ImageDetectionPageState extends State<ImageDetectionPage> {
  Uint8List? _imageBytes;
  PoseResult? _result;
  bool _isProcessing = false;
  String? _error;

  final List<String> _sampleImages = [
    'assets/sample_pose.jpg',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Image Detection'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Expanded(
            child: _buildImagePreview(),
          ),
          _buildResultInfo(),
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    if (_imageBytes == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_outlined, size: 80, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No image selected',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
              'Load a sample image to test pose detection',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.memory(
          _imageBytes!,
          fit: BoxFit.contain,
        ),
        if (_result != null && _result!.hasPoses)
          Positioned.fill(
            child: CustomPaint(
              painter: PoseOverlayPainter(
                pose: _result!.firstPose!,
                imageWidth: _result!.imageWidth,
                imageHeight: _result!.imageHeight,
              ),
            ),
          ),
        if (_isProcessing)
          const Center(
            child: CircularProgressIndicator(),
          ),
      ],
    );
  }

  Widget _buildResultInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[100],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null)
            Text(
              'Error: $_error',
              style: const TextStyle(color: Colors.red),
            )
          else if (_result != null) ...[
            Text(
              'Processing time: ${_result!.processingTimeMs}ms',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text('Acceleration: ${_result!.accelerationMode.name}'),
            Text('Poses detected: ${_result!.poseCount}'),
            if (_result!.hasPoses)
              Text(
                'Pose score: ${(_result!.firstPose!.score * 100).toStringAsFixed(1)}%',
              ),
            Text(
              'Visible landmarks: ${_result?.firstPose?.getVisibleLandmarks().length ?? 0}/33',
            ),
          ] else
            const Text('Load an image to detect poses'),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _isProcessing ? null : _loadSampleImage,
              icon: const Icon(Icons.photo_library),
              label: const Text('Load Sample'),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _imageBytes != null && !_isProcessing
                  ? _detectPose
                  : null,
              icon: const Icon(Icons.search),
              label: const Text('Detect Pose'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadSampleImage() async {
    setState(() {
      _isProcessing = true;
      _error = null;
      _result = null;
    });

    try {
      // Try to load from assets
      final ByteData data = await rootBundle.load(_sampleImages.first);
      setState(() {
        _imageBytes = data.buffer.asUint8List();
        _isProcessing = false;
      });
    } catch (e) {
      // Create a simple colored placeholder image
      setState(() {
        _error = 'Sample image not found. Please add ${_sampleImages.first}';
        _isProcessing = false;
      });
    }
  }

  Future<void> _detectPose() async {
    if (_imageBytes == null) return;

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      final result = await widget.detector.detectPose(_imageBytes!);
      setState(() {
        _result = result;
        _isProcessing = false;
      });
    } on DetectionError catch (e) {
      setState(() {
        _error = '${e.code.name}: ${e.message}';
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isProcessing = false;
      });
    }
  }
}
