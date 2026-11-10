import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../theme.dart';
import '../../utils/ui_utils.dart';
import '../../../viewmodels/controls_viewmodel.dart';

class AudioSheetContent extends StatefulWidget {
  final ControlsViewModel vm;
  final Room room;

  const AudioSheetContent({
    required this.vm,
    required this.room,
    super.key,
  });

  @override
  State<AudioSheetContent> createState() => _AudioSheetContentState();
}

class _AudioSheetContentState extends State<AudioSheetContent> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.vm.refreshAudioDevices());
  }

  @override
  Widget build(BuildContext context) {
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.82;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: Container(
          margin: UIUtils.paddingHorizontalLG.add(UIUtils.paddingVerticalLG),
          child: ClipRRect(
            borderRadius: UIUtils.borderRadiusAllLG,
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: AnimatedSize(
                duration: UIUtils.animationDuration,
                curve: UIUtils.animationCurve,
                alignment: Alignment.bottomCenter,
                child: Container(
                  padding: UIUtils.paddingLG,
                  decoration: BoxDecoration(
                    color: LKColors.surfaceElevated,
                    borderRadius: UIUtils.borderRadiusAllLG,
                    border: Border.all(color: LKColors.border, width: 0.5),
                    boxShadow: UIUtils.shadowXL,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Icon(
                            Icons.headset_mic_rounded,
                            color: LKColors.secondary,
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Périphériques Audio',
                              style: UIUtils.titleMedium(context),
                            ),
                          ),
                          IconButton(
                            onPressed: () async {
                              await widget.vm.refreshAudioDevices();
                              if (mounted) setState(() {});
                            },
                            icon: const Icon(Icons.refresh_rounded, size: 20),
                            color: LKColors.textSecondary,
                            tooltip: 'Actualiser les périphériques',
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sélectionnez la sortie et vérifiez le microphone actif.',
                        style: UIUtils.bodySmall(
                          context,
                        ).copyWith(color: LKColors.textHint),
                      ),
                      const SizedBox(height: 14),

                      // Content scrollable
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildOutputSection(),
                              const SizedBox(height: 16),
                              _buildInputSection(),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Close button
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context),
                          style: FilledButton.styleFrom(
                            backgroundColor: LKColors.primary,
                            foregroundColor: Colors.white,
                            padding: UIUtils.paddingVerticalSM,
                            shape: RoundedRectangleBorder(
                              borderRadius: UIUtils.borderRadiusAllSM,
                            ),
                          ),
                          child: const Text('Fermer'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOutputSection() {
    final outputs = widget.vm.audioOutputs ?? const [];
    final isSpeaker = widget.vm.speakerphoneOn;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.volume_up_rounded, size: 16, color: LKColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              'SORTIE AUDIO (ÉCOUTE)',
              style: UIUtils.bodySmall(context).copyWith(
                color: LKColors.textSecondary,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Tuile Écouteurs / Casque Bluetooth
        _buildAudioTile(
          icon: Icons.bluetooth_audio_rounded,
          iconColor: LKColors.secondary,
          title: _getBluetoothOutputTitle(outputs),
          subtitle: 'Idéal pour écouter sans écho',
          isSelected: !isSpeaker,
          onTap: () async {
            await widget.vm.setSpeakerphone(false);
            if (mounted) setState(() {});
          },
        ),
        const SizedBox(height: 6),

        // Tuile Haut-parleur du smartphone
        _buildAudioTile(
          icon: Icons.volume_up_rounded,
          iconColor: LKColors.warning,
          title: 'Haut-parleur du téléphone',
          subtitle: 'Volume fort pour coaching à plusieurs',
          isSelected: isSpeaker,
          onTap: () async {
            await widget.vm.setSpeakerphone(true);
            if (mounted) setState(() {});
          },
        ),

        // Si des périphériques matériels supplémentaires sont énumérés
        if (outputs.length > 2) ...[
          const SizedBox(height: 8),
          Text(
            'Autres périphériques détectés :',
            style: UIUtils.bodySmall(context).copyWith(color: LKColors.textHint),
          ),
          const SizedBox(height: 4),
          ...outputs.map((device) {
            final isSelected =
                device.deviceId == widget.room.selectedAudioOutputDeviceId;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _buildAudioTile(
                icon: Icons.speaker_rounded,
                iconColor: LKColors.textPrimary,
                title: device.label.isNotEmpty ? device.label : 'Sortie audio',
                subtitle: device.deviceId,
                isSelected: isSelected,
                onTap: () async {
                  await widget.vm.selectAudioOutput(device);
                  if (mounted) setState(() {});
                },
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildInputSection() {
    final inputs = widget.vm.audioInputs ?? const [];
    final isSpeaker = widget.vm.speakerphoneOn;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.mic_rounded, size: 16, color: LKColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              'ENTRÉE AUDIO (MICROPHONE)',
              style: UIUtils.bodySmall(context).copyWith(
                color: LKColors.textSecondary,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (inputs.isNotEmpty) ...[
          ...inputs.map((device) {
            final isSelected =
                device.deviceId == widget.room.selectedAudioInputDeviceId ||
                (widget.room.selectedAudioInputDeviceId == null &&
                    device == inputs.first);
            final isBt = _isBt(device.label);

            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _buildAudioTile(
                icon: isBt ? Icons.bluetooth_audio_rounded : Icons.mic_rounded,
                iconColor: isBt ? LKColors.secondary : LKColors.primary,
                title: device.label.isNotEmpty
                    ? device.label
                    : 'Microphone par défaut',
                subtitle: isBt
                    ? 'Microphone du kit Bluetooth'
                    : 'Microphone intégré avec annulation d\'écho',
                isSelected: isSelected,
                onTap: () async {
                  await widget.vm.selectAudioInput(device);
                  if (mounted) setState(() {});
                },
              ),
            );
          }),
        ] else ...[
          // Statut automatique du microphone couplé à la sortie
          _buildAudioTile(
            icon: !isSpeaker
                ? Icons.bluetooth_audio_rounded
                : Icons.mic_rounded,
            iconColor: !isSpeaker ? LKColors.secondary : LKColors.primary,
            title: !isSpeaker
                ? 'Microphone écouteurs (Bluetooth SCO)'
                : 'Microphone intégré du téléphone',
            subtitle:
                'Couplé automatiquement avec la sortie audio sélectionnée',
            isSelected: true,
            onTap: null,
          ),
        ],
      ],
    );
  }

  String _getBluetoothOutputTitle(List<MediaDevice> outputs) {
    for (final d in outputs) {
      if (_isBt(d.label)) {
        return d.label;
      }
    }
    return 'Écouteurs / Casque Bluetooth';
  }

  bool _isBt(String label) {
    final lower = label.toLowerCase();
    return lower.contains('bluetooth') ||
        lower.contains('headset') ||
        lower.contains('casque') ||
        lower.contains('airpod') ||
        lower.contains('buds') ||
        lower.contains('freebuds') ||
        lower.contains('wh-') ||
        lower.contains('wf-') ||
        lower.contains('bose') ||
        lower.contains('jabra') ||
        lower.contains('shokz');
  }

  Widget _buildAudioTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: isSelected
          ? LKColors.primary.withValues(alpha: 0.15)
          : LKColors.surface,
      borderRadius: UIUtils.borderRadiusAllMD,
      child: InkWell(
        onTap: onTap,
        borderRadius: UIUtils.borderRadiusAllMD,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: UIUtils.borderRadiusAllMD,
            border: Border.all(
              color: isSelected ? LKColors.primary : LKColors.border,
              width: isSelected ? 1.5 : 0.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: UIUtils.titleSmall(context).copyWith(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected
                            ? LKColors.textPrimary
                            : LKColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: UIUtils.bodySmall(context).copyWith(
                        color: LKColors.textHint,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isSelected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: LKColors.success,
                  size: 20,
                )
              else
                Icon(
                  Icons.radio_button_unchecked_rounded,
                  color: LKColors.textHint,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
