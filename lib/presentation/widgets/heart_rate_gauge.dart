import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../data/heart_rate_zones.dart';
import '../../theme.dart';

/// Athletic heart rate gauge displaying the active cardiovascular training zone (Z1-Z5),
/// a 5-step sports intensity bar, and tabular-formatted bpm readings.
class HeartRateHudGauge extends StatelessWidget {
  final int bpm;
  final bool compact;
  final bool transparent;
  final bool showZoneBar;
  final bool showValue;

  const HeartRateHudGauge({
    required this.bpm,
    this.compact = false,
    this.transparent = false,
    this.showZoneBar = true,
    this.showValue = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final zone = HeartRateZone.fromBpm(bpm);
    final borderRadius = BorderRadius.circular(999);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: LKColors.background.withValues(alpha: 0.75),
        borderRadius: borderRadius,
        border: Border.all(
          color: zone.color.withValues(alpha: 0.65),
          width: 0.9,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Colored heart icon matching zone
          Icon(
            Icons.favorite_rounded,
            color: zone.color,
            size: compact ? 12 : 14,
          ),
          const SizedBox(width: 3.5),

          // High-contrast zone badge (Z1..Z5)
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 3 : 5,
              vertical: 0.8,
            ),
            decoration: BoxDecoration(
              color: zone.color,
              borderRadius: BorderRadius.circular(3.5),
              boxShadow: [
                BoxShadow(
                  color: zone.color.withValues(alpha: 0.35),
                  blurRadius: 3,
                ),
              ],
            ),
            child: Text(
              zone.code,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: compact ? 7.5 : 8.5,
                letterSpacing: 0.3,
              ),
            ),
          ),

          // 5-segment athletic intensity bar (hidden in compact mode or when showZoneBar is false)
          if (showZoneBar && !compact && showValue) ...[
            const SizedBox(width: 5),
            _SportsIntensityBar(activeZoneIndex: zone.level.index),
          ],

          // Formatted bpm with tabular figures to avoid jitter
          if (showValue) ...[
            const SizedBox(width: 4.5),
            Text(
              '$bpm bpm',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: LKColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: transparent ? 10 : (compact ? 9 : 10),
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 5-step sports intensity gauge segments.
class _SportsIntensityBar extends StatelessWidget {
  final int activeZoneIndex;

  const _SportsIntensityBar({required this.activeZoneIndex});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final isFilled = index <= activeZoneIndex;
        final zoneColor = HeartRateZone.allZones[index].color;
        return Container(
          width: 3.5,
          height: 9,
          margin: const EdgeInsets.symmetric(horizontal: 0.8),
          decoration: BoxDecoration(
            color: isFilled ? zoneColor : Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(1.5),
            border: isFilled && index == activeZoneIndex
                ? Border.all(color: Colors.white, width: 0.5)
                : null,
          ),
        );
      }),
    );
  }
}
