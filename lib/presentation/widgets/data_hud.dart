import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/remote_telemetry.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';
import 'animated_count.dart';
import 'heart_rate_gauge.dart';

export 'animated_count.dart';
export 'heart_rate_gauge.dart';
export '../../data/heart_rate_zones.dart';

class DataHud extends StatefulWidget {
  final RemoteTelemetry? telemetry;
  final ValueListenable<RemoteTelemetry?>? telemetryListenable;
  final bool showValues;
  final bool transparent;
  final bool compact;
  final bool showToggle;
  final bool outdoorSunMode;

  const DataHud({
    this.telemetry,
    this.telemetryListenable,
    this.showValues = true,
    this.transparent = false,
    this.compact = false,
    this.showToggle = true,
    this.outdoorSunMode = false,
    super.key,
  });

  @override
  State<DataHud> createState() => _DataHudState();
}

class _HudItemData {
  final IconData icon;
  final Color standardColor;
  final Color neonColor;
  final double value;
  final int fractionDigits;
  final String unit;

  const _HudItemData({
    required this.icon,
    required this.standardColor,
    required this.neonColor,
    required this.value,
    required this.fractionDigits,
    required this.unit,
  });

  Color color({required bool outdoorSunMode}) =>
      outdoorSunMode ? neonColor : standardColor;
}

class _DataHudState extends State<DataHud> {
  bool _expanded = true;
  static const double _compactWidth = 320;

  List<_HudItemData> _buildItems(RemoteTelemetry? telemetry) {
    final items = <_HudItemData>[];
    if (telemetry == null) return items;

    if (telemetry.speed != null) {
      items.add(_HudItemData(
        icon: Icons.speed_rounded,
        standardColor: LKColors.warning,
        neonColor: const Color(0xFFFFD700), // Ambre / Or fluo
        value: telemetry.speed!,
        fractionDigits: 1,
        unit: 'km/h',
      ));
    }
    if (telemetry.cadence != null) {
      items.add(_HudItemData(
        icon: Icons.pedal_bike_rounded,
        standardColor: LKColors.success,
        neonColor: const Color(0xFF00FF66), // Vert néon saturé
        value: telemetry.cadence!,
        fractionDigits: 0,
        unit: 'rpm',
      ));
    }
    if (telemetry.altitude != null) {
      items.add(_HudItemData(
        icon: Icons.height_rounded,
        standardColor: LKColors.secondary,
        neonColor: const Color(0xFF00E5FF), // Cyan néon
        value: telemetry.altitude!,
        fractionDigits: 0,
        unit: 'm',
      ));
    }
    if (telemetry.bearing != null) {
      items.add(_HudItemData(
        icon: Icons.explore_rounded,
        standardColor: LKColors.warning,
        neonColor: const Color(0xFFFF6600), // Orange néon
        value: telemetry.bearing!,
        fractionDigits: 0,
        unit: 'deg',
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
                outdoorSunMode: widget.outdoorSunMode,
              ),
            for (final item in items)
              _HudChip(
                icon: item.icon,
                color: item.color(outdoorSunMode: widget.outdoorSunMode),
                text: widget.showValues
                    ? '${item.value.toStringAsFixed(item.fractionDigits)} ${item.unit}'
                    : '',
                value: widget.showValues ? item.value : null,
                fractionDigits: item.fractionDigits,
                unit: item.unit,
                showText: widget.showValues,
                compact: compact,
                transparent: widget.transparent,
                outdoorSunMode: widget.outdoorSunMode,
              ),
            if (widget.showToggle && !compact && !widget.transparent)
              _HudChip(
                icon: _expanded
                    ? Icons.unfold_less_rounded
                    : Icons.unfold_more_rounded,
                color: widget.outdoorSunMode ? Colors.white : LKColors.textSecondary,
                text: _expanded ? 'Reduire' : 'Details',
                showText: _expanded,
                compact: compact,
                transparent: widget.transparent,
                outdoorSunMode: widget.outdoorSunMode,
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
                  color: widget.outdoorSunMode
                      ? Colors.black
                      : LKColors.surface.withValues(alpha: 0.85),
                  borderRadius: UIUtils.borderRadiusAllMD,
                  border: Border.all(
                    color: widget.outdoorSunMode ? Colors.white : LKColors.border,
                    width: widget.outdoorSunMode ? 1.5 : 0.5,
                  ),
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
  final double? value;
  final int fractionDigits;
  final String unit;
  final bool showText;
  final bool compact;
  final bool transparent;
  final bool outdoorSunMode;
  final VoidCallback? onTap;

  const _HudChip({
    required this.icon,
    required this.color,
    required this.text,
    this.value,
    this.fractionDigits = 0,
    this.unit = '',
    this.showText = true,
    this.compact = false,
    this.transparent = false,
    this.outdoorSunMode = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasText = showText && (text.isNotEmpty || value != null);
    final borderRadius = BorderRadius.circular(999);

    final backgroundColor = outdoorSunMode
        ? Colors.black
        : (transparent
            ? LKColors.background.withValues(alpha: 0.5)
            : LKColors.background.withValues(alpha: 0.65));

    final borderColor = outdoorSunMode
        ? color
        : LKColors.border.withValues(alpha: 0.6);

    return AnimatedContainer(
      duration: UIUtils.animationDuration,
      curve: UIUtils.animationCurve,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: borderRadius,
        border: Border.all(
          color: borderColor,
          width: outdoorSunMode ? 1.2 : 0.8,
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
                    child: value != null
                        ? AnimatedSportsCount(
                            value: value!,
                            fractionDigits: fractionDigits,
                            suffix: ' $unit',
                            outdoorSunMode: outdoorSunMode,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: outdoorSunMode ? Colors.white : LKColors.textPrimary,
                              fontWeight: outdoorSunMode ? FontWeight.w900 : FontWeight.w700,
                              fontSize: transparent
                                  ? 10
                                  : compact
                                      ? 9
                                      : 10,
                              fontFeatures: const [ui.FontFeature.tabularFigures()],
                            ),
                          )
                        : Text(
                            text,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: outdoorSunMode ? Colors.white : LKColors.textPrimary,
                              fontWeight: outdoorSunMode ? FontWeight.w900 : FontWeight.w700,
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

  }
}
