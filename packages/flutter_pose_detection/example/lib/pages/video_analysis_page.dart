import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_pose_detection/flutter_pose_detection.dart';

/// Video analysis page for processing video files.
class VideoAnalysisPage extends StatefulWidget {
  const VideoAnalysisPage({super.key});

  @override
  State<VideoAnalysisPage> createState() => _VideoAnalysisPageState();
}

class _VideoAnalysisPageState extends State<VideoAnalysisPage> {
  NpuPoseDetector? _detector;
  bool _isInitialized = false;
  bool _isAnalyzing = false;
  double _progress = 0.0;
  String _status = 'Initializing...';
  VideoAnalysisResult? _result;
  StreamSubscription<VideoAnalysisProgress>? _progressSubscription;
  int _currentFrameIndex = 0;

  @override
  void initState() {
    super.initState();
    _initializeDetector();
  }

  Future<void> _initializeDetector() async {
    try {
      _detector = NpuPoseDetector();
      await _detector!.initialize();
      setState(() {
        _isInitialized = true;
        _status = 'Ready - Select a video to analyze';
      });
    } catch (e) {
      setState(() {
        _status = 'Initialization failed: $e';
      });
    }
  }

  Future<void> _pickAndAnalyzeVideo() async {
    if (!_isInitialized || _detector == null) return;

    final picker = ImagePicker();
    final video = await picker.pickVideo(source: ImageSource.gallery);

    if (video == null) return;

    setState(() {
      _isAnalyzing = true;
      _progress = 0.0;
      _result = null;
      _status = 'Analyzing video...';
    });

    // Subscribe to progress updates
    _progressSubscription = _detector!.videoAnalysisProgress.listen(
      (progress) {
        setState(() {
          _progress = progress.progress;
          _status =
              '${(progress.progress * 100).toStringAsFixed(1)}% - Frame ${progress.currentFrame}/${progress.totalFrames}';
        });
      },
      onError: (error) {
        setState(() {
          _status = 'Error: $error';
          _isAnalyzing = false;
        });
      },
    );

    try {
      final result = await _detector!.analyzeVideo(
        video.path,
        frameInterval: 3, // Analyze every 3rd frame for faster processing
      );

      setState(() {
        _result = result;
        _isAnalyzing = false;
        _status =
            'Complete! Analyzed ${result.analyzedFrames} frames in ${(result.totalAnalysisTimeMs / 1000).toStringAsFixed(1)}s';
      });
    } catch (e) {
      setState(() {
        _status = 'Analysis failed: $e';
        _isAnalyzing = false;
      });
    } finally {
      _progressSubscription?.cancel();
    }
  }

  Future<void> _cancelAnalysis() async {
    await _detector?.cancelVideoAnalysis();
    _progressSubscription?.cancel();
    setState(() {
      _isAnalyzing = false;
      _status = 'Cancelled';
    });
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    _detector?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Analysis'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _status,
                      style: const TextStyle(fontSize: 16),
                    ),
                    if (_isAnalyzing) ...[
                      const SizedBox(height: 16),
                      LinearProgressIndicator(value: _progress),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _cancelAnalysis,
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Action button
            if (!_isAnalyzing)
              ElevatedButton.icon(
                onPressed: _isInitialized ? _pickAndAnalyzeVideo : null,
                icon: const Icon(Icons.video_library),
                label: const Text('Select Video'),
              ),

            const SizedBox(height: 24),

            // Results
            if (_result != null) ...[
              const Text(
                'Analysis Results',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _buildResultsCard(),
              const SizedBox(height: 16),
              _buildFrameBrowser(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultsCard() {
    final result = _result!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatRow(
                'Video Duration', '${result.durationSeconds.toStringAsFixed(1)}s'),
            _buildStatRow('Video Size', '${result.width} x ${result.height}'),
            _buildStatRow('Frame Rate', '${result.frameRate.toStringAsFixed(1)} FPS'),
            _buildStatRow('Total Frames', '${result.totalFrames}'),
            _buildStatRow('Analyzed Frames', '${result.analyzedFrames}'),
            _buildStatRow(
              'Detection Rate',
              '${(result.detectionRate * 100).toStringAsFixed(1)}%',
            ),
            _buildStatRow(
              'Analysis Speed',
              '${result.analysisSpeed.toStringAsFixed(1)} FPS',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildFrameBrowser() {
    final result = _result!;
    if (result.frames.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No frames with pose detected'),
        ),
      );
    }

    final framesWithPose = result.frames.where((f) => f.result.hasPoses).toList();
    if (framesWithPose.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No poses detected in video'),
        ),
      );
    }

    final currentFrame = _currentFrameIndex < framesWithPose.length
        ? framesWithPose[_currentFrameIndex]
        : framesWithPose.first;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Frame ${_currentFrameIndex + 1} / ${framesWithPose.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${currentFrame.timestampSeconds.toStringAsFixed(2)}s',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Pose score: ${(currentFrame.result.firstPose!.score * 100).toStringAsFixed(0)}%',
            ),
            Text(
              'Visible landmarks: ${currentFrame.result.firstPose!.landmarks.where((l) => l.visibility > 0.5).length} / 33',
            ),
            const SizedBox(height: 16),
            Slider(
              value: _currentFrameIndex.toDouble(),
              min: 0,
              max: (framesWithPose.length - 1).toDouble(),
              divisions: framesWithPose.length - 1,
              onChanged: (value) {
                setState(() {
                  _currentFrameIndex = value.toInt();
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}
