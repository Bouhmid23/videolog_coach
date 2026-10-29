import 'dart:async';

import 'package:flutter/material.dart';

class PostureSmoothingDialog extends StatefulWidget {
  final double initialAlpha;
  final Future<void> Function(double alpha) onApply;

  const PostureSmoothingDialog({
    required this.initialAlpha,
    required this.onApply,
    super.key,
  });

  static Future<void> show(
    BuildContext context, {
    required double initialAlpha,
    required Future<void> Function(double alpha) onApply,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => PostureSmoothingDialog(
        initialAlpha: initialAlpha,
        onApply: onApply,
      ),
    );
  }

  @override
  State<PostureSmoothingDialog> createState() => _PostureSmoothingDialogState();
}

class _PostureSmoothingDialogState extends State<PostureSmoothingDialog> {
  late double _pendingAlpha;

  @override
  void initState() {
    super.initState();
    _pendingAlpha = widget.initialAlpha;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Lissage de la posture'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _pendingAlpha >= 1.0
                ? '1,00 · points bruts, sans lissage'
                : '${_pendingAlpha.toStringAsFixed(2)} · lissage appliqué',
          ),
          Slider(
            value: _pendingAlpha,
            min: 0,
            max: 1,
            divisions: 20,
            label: _pendingAlpha.toStringAsFixed(2),
            onChanged: (value) => setState(() => _pendingAlpha = value),
          ),
          const Text(
            'Le réglage est mémorisé sur cet appareil. '
            'À 1,00, image et worldLandmarks sont envoyés sans lissage.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            unawaited(widget.onApply(_pendingAlpha));
            Navigator.of(context).pop();
          },
          child: const Text('Appliquer'),
        ),
      ],
    );
  }
}
