import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' show Participant;

import '../../../core/recording_controller.dart';
import '../../../data/remote_telemetry.dart';
import '../../../theme.dart';
import '../../utils/ui_utils.dart';
import '../participant.dart';
import '../participant_info.dart';

/// Galerie horizontale des participants secondaires (mode Portrait).
class RoomSecondaryHorizontalGallery extends StatelessWidget {
  const RoomSecondaryHorizontalGallery({
    super.key,
    required this.secondaryTracks,
    required this.recordingController,
    required this.outdoorSunMode,
    required this.onSelectTrack,
    required this.displayNameFor,
  });

  static const double _galleryHeight = 180;
  static const double _galleryHudSpacing = 4;
  static const double _galleryHudHeight = 36;

  final List<ParticipantTrack> secondaryTracks;
  final RecordingController? recordingController;
  final bool outdoorSunMode;
  final void Function(ParticipantTrack track) onSelectTrack;
  final String Function(Participant participant) displayNameFor;

  @override
  Widget build(BuildContext context) {
    if (secondaryTracks.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(bottom: UIUtils.sm),
      child: RepaintBoundary(
        child: SizedBox(
          height: _galleryHeight + _galleryHudHeight + _galleryHudSpacing,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: UIUtils.md),
            itemCount: secondaryTracks.length,
            separatorBuilder: (_, _) => SizedBox(width: UIUtils.sm),
            itemBuilder: (BuildContext context, int index) {
              final track = secondaryTracks[index];
              void selectTrack() => onSelectTrack(track);
              return SizedBox(
                key: ValueKey(
                  '${track.participant.identity}_${track.type.name}',
                ),
                width: _galleryHeight,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (track.telemetryListenable != null)
                      ValueListenableBuilder<RemoteTelemetry?>(
                        valueListenable: track.telemetryListenable!,
                        builder: (context, telemetry, _) {
                          if (telemetry?.hasData != true) {
                            return const SizedBox.shrink();
                          }
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: selectTrack,
                                child: DataHud(
                                  telemetry: telemetry,
                                  showValues: false,
                                  compact: true,
                                  showToggle: false,
                                  outdoorSunMode: outdoorSunMode,
                                ),
                              ),
                              const SizedBox(height: _galleryHudSpacing),
                            ],
                          );
                        },
                      )
                    else if (track.telemetry?.hasData == true) ...[
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: selectTrack,
                        child: DataHud(
                          telemetry: track.telemetry,
                          showValues: false,
                          compact: true,
                          showToggle: false,
                          outdoorSunMode: outdoorSunMode,
                        ),
                      ),
                      const SizedBox(height: _galleryHudSpacing),
                    ],
                    SizedBox(
                      width: _galleryHeight,
                      height: _galleryHeight,
                      child: ParticipantWidget.widgetFor(
                        track,
                        showDataHud: false,
                        recordingController: recordingController,
                        onTap: selectTrack,
                        outdoorSunMode: outdoorSunMode,
                        displayName: displayNameFor(track.participant),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Galerie verticale des participants secondaires pour le mode Paysage / Tablette.
class RoomSecondaryVerticalGallery extends StatelessWidget {
  const RoomSecondaryVerticalGallery({
    super.key,
    required this.secondaryTracks,
    required this.recordingController,
    required this.outdoorSunMode,
    required this.onSelectTrack,
    required this.displayNameFor,
  });

  final List<ParticipantTrack> secondaryTracks;
  final RecordingController? recordingController;
  final bool outdoorSunMode;
  final void Function(ParticipantTrack track) onSelectTrack;
  final String Function(Participant participant) displayNameFor;

  @override
  Widget build(BuildContext context) {
    if (secondaryTracks.isEmpty) {
      return Center(
        child: Padding(
          padding: UIUtils.paddingLG,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.people_outline_rounded,
                size: 36,
                color: LKColors.textHint,
              ),
              SizedBox(height: UIUtils.sm),
              Text(
                'Aucun autre participant',
                style: UIUtils.bodySmall(context)
                    .copyWith(color: LKColors.textHint),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.all(UIUtils.sm),
      itemCount: secondaryTracks.length,
      separatorBuilder: (_, _) => SizedBox(height: UIUtils.sm),
      itemBuilder: (context, index) {
        final track = secondaryTracks[index];
        void selectTrack() => onSelectTrack(track);

        return InkWell(
          onTap: selectTrack,
          borderRadius: UIUtils.borderRadiusAllMD,
          child: Container(
            decoration: BoxDecoration(
              color: LKColors.surfaceElevated,
              borderRadius: UIUtils.borderRadiusAllMD,
              border: Border.all(
                color: LKColors.border.withValues(alpha: 0.6),
                width: 0.8,
              ),
            ),
            padding: EdgeInsets.all(UIUtils.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: UIUtils.borderRadiusAllSM,
                  child: SizedBox(
                    height: 120,
                    child: RepaintBoundary(
                      child: ParticipantWidget.widgetFor(
                        track,
                        showDataHud: false,
                        recordingController: recordingController,
                        onTap: selectTrack,
                        outdoorSunMode: outdoorSunMode,
                        displayName: displayNameFor(track.participant),
                        showNameBadge: false,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: UIUtils.xs),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        displayNameFor(track.participant),
                        style: UIUtils.labelMedium(context).copyWith(
                          fontWeight: FontWeight.bold,
                          color: LKColors.textPrimary,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(
                      Icons.touch_app_rounded,
                      size: 13,
                      color: LKColors.textHint,
                    ),
                  ],
                ),
                if (track.telemetryListenable != null) ...[
                  SizedBox(height: UIUtils.xs),
                  ValueListenableBuilder<RemoteTelemetry?>(
                    valueListenable: track.telemetryListenable!,
                    builder: (context, telemetry, _) {
                      if (telemetry?.hasData != true) {
                        return const SizedBox.shrink();
                      }
                      return DataHud(
                        telemetry: telemetry,
                        showValues: true,
                        compact: true,
                        showToggle: false,
                        outdoorSunMode: outdoorSunMode,
                      );
                    },
                  ),
                ] else if (track.telemetry?.hasData == true) ...[
                  SizedBox(height: UIUtils.xs),
                  DataHud(
                    telemetry: track.telemetry,
                    showValues: true,
                    compact: true,
                    showToggle: false,
                    outdoorSunMode: outdoorSunMode,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// En-tête de la barre latérale en mode Paysage.
class RoomSidebarHeader extends StatelessWidget {
  const RoomSidebarHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: UIUtils.md,
        vertical: UIUtils.sm,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.analytics_rounded,
            color: LKColors.primary,
            size: 20,
          ),
          SizedBox(width: UIUtils.sm),
          Expanded(
            child: Text(
              'Participants & Télémétrie',
              style: UIUtils.titleSmall(context)
                  .copyWith(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Poignée chevron verticale permettant de replier/déplier la colonne latérale en mode Paysage.
class RoomSidebarToggleButton extends StatelessWidget {
  const RoomSidebarToggleButton({
    super.key,
    required this.isExpanded,
    required this.outdoorSunMode,
    required this.onToggle,
  });

  final bool isExpanded;
  final bool outdoorSunMode;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(28)),
        child: Container(
          width: 58,
          height: 104,
          decoration: BoxDecoration(
            color: outdoorSunMode
                ? Colors.black
                : LKColors.surfaceElevated.withValues(alpha: 0.95),
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(28),
            ),
            border: Border(
              top: BorderSide(
                color: outdoorSunMode ? Colors.white : LKColors.border,
                width: 1.5,
              ),
              left: BorderSide(
                color: outdoorSunMode ? Colors.white : LKColors.border,
                width: 1.5,
              ),
              bottom: BorderSide(
                color: outdoorSunMode ? Colors.white : LKColors.border,
                width: 1.5,
              ),
              right: BorderSide.none,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(-3, 0),
              ),
            ],
          ),
          child: Center(
            child: AnimatedRotation(
              turns: isExpanded ? 0.0 : 0.5,
              duration: UIUtils.animationDuration,
              curve: UIUtils.animationCurve,
              child: Icon(
                Icons.chevron_right_rounded,
                color: outdoorSunMode ? Colors.white : LKColors.primary,
                size: 54,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
