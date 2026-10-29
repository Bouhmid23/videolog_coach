import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/remote_telemetry.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';
import 'heart_rate_gauge.dart';

export 'heart_rate_gauge.dart';
export '../../data/heart_rate_zones.dart';

class DataHud extends StatefulWidget {
  final RemoteTelemetry? telemetry;
  final ValueListenable<RemoteTelemetry?>? telemetryListenable;
  final bool showValues;
  final bool transparent;
  final bool compact;
  final bool showToggle;

  const DataHud({
    this.telemetry,
    this.telemetryListenable,
    this.showValues = true,
    this.transparent = false,
    this.compact = false,
    this.showToggle = true,
    super.key,
  });

  @override
  State<DataHud> createState() => _DataHudState();
}

class _DataHudState extends State<DataHud> {
  bool _expanded = true;
  static const double _compactWidth = 320;

  List<(IconData, Color, String, String)> _buildItems(
    RemoteTelemetry? telemetry,
  ) {
    final items = <(IconData, Color, String, String)>[];
    if (telemetry == null) return items;

    if (telemetry.speed != null) {
      items.add((
        Icons.speed_rounded,
        LKColors.warning,
        '${telemetry.speed!.toStringAsFixed(1)} km/h',
        '',
      ));
    }
    if (telemetry.cadence != null) {
      items.add((
        Icons.pedal_bike_rounded,
        LKColors.success,
        '${telemetry.cadence!.toStringAsFixed(0)} rpm',
        '',
      ));
    }
    if (telemetry.altitude != null) {
      items.add((
        Icons.height_rounded,
        LKColors.secondary,
        '${telemetry.altitude!.toStringAsFixed(0)} m',
        '',
      ));
    }
    if (telemetry.bearing != null) {
      items.add((
        Icons.explore_rounded,
        LKColors.warning,
        '${telemetry.bearing!.toStringAsFixed(0)} deg',
        '',
      ));
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final listenable = widget.telemetryListenable;
    if (listenable != null) {
      return ValueListenableBuilder<RemoteTelemetry?>(
        valueListenable: listenable,
        builder: (context, telemetry, _) =>
            _buildForTelemetry(context, telemetry ?? widget.telemetry),
      );
    }
    return _buildForTelemetry(context, widget.telemetry);
  }

  Widget _buildForTelemetry(BuildContext context, RemoteTelemetry? telemetry) {
    final hasHrm = telemetry?.hasHrm == true;
    final items = _buildItems(telemetry);
    if (items.isEmpty && !hasHrm) {
      if (!widget.transparent) return const SizedBox.shrink();
      return AnimatedContainer(
        duration: UIUtils.animationDuration,
        curve: UIUtils.animationCurve,
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: LKColors.lkDarkBlue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: LKColors.lkDarkBlue.withValues(alpha: 0.3),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.sensors_off_rounded,
              size: 13,
              color: LKColors.textHint,
            ),
            const SizedBox(width: 5),
            Text(
              'Aucune donnée capteur',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: LKColors.textHint,
                fontSize: 9,
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = widget.compact || constraints.maxWidth < _compactWidth;
        final content = Wrap(
          spacing: compact ? UIUtils.xs : UIUtils.sm,
          runSpacing: compact ? 0 : UIUtils.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (hasHrm)
              HeartRateHudGauge(
                bpm: telemetry!.heartRate!,
                compact: compact,
                transparent: widget.transparent,
                showValue: widget.showValues,
                showZoneBar: !compact,
              ),
            for (final item in items)
              _HudChip(
                icon: item.$1,
                color: item.$2,
                text: widget.showValues ? item.$3 : item.$4,
                compact: compact,
                transparent: widget.transparent,
              ),
            if (widget.showToggle && !compact && !widget.transparent)
              _HudChip(
                icon: _expanded
                    ? Icons.unfold_less_rounded
                    : Icons.unfold_more_rounded,
                color: LKColors.textSecondary,
                text: _expanded ? 'Reduire' : 'Details',
                showText: _expanded,
                onTap: () => setState(() => _expanded = !_expanded),
              ),
          ],
        );

        if (widget.transparent) {
          return Align(alignment: Alignment.centerLeft, child: content);
        }

        return Align(
          alignment: Alignment.topLeft,
          child: ClipRRect(
            borderRadius: UIUtils.borderRadiusAllMD,
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: UIUtils.sm,
                  vertical: UIUtils.xs,
                ),
                decoration: BoxDecoration(
                  color: LKColors.surface.withValues(alpha: 0.85),
                  borderRadius: UIUtils.borderRadiusAllMD,
                  border: Border.all(color: LKColors.border, width: 0.5),
                  boxShadow: UIUtils.shadowSM,
                ),
                child: content,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HudChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final bool showText;
  final bool compact;
  final bool transparent;
  final VoidCallback? onTap;

  const _HudChip({
    required this.icon,
    required this.color,
    required this.text,
    this.showText = true,
    this.compact = false,
    this.transparent = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasText = showText && text.isNotEmpty;
    final borderRadius = BorderRadius.circular(999);
    final chip = AnimatedContainer(
      duration: UIUtils.animationDuration,
      curve: UIUtils.animationCurve,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: LKColors.background.withValues(alpha: 0.65),
        borderRadius: borderRadius,
        border: Border.all(
          color: LKColors.border.withValues(alpha: 0.6),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: compact ? 13 : 14),
          AnimatedSize(
            duration: UIUtils.animationDuration,
            curve: UIUtils.animationCurve,
            child: !hasText
                ? const SizedBox(width: 0)
                : Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      text,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: LKColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: transparent
                            ? 10
                            : compact
                            ? 9
                            : 10,
                        fontFeatures: const [ui.FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );

    if (onTap == null) return chip;
    return InkWell(
      onTap: onTap,
      borderRadius: borderRadius,
      child: chip,
    );
  }
}
