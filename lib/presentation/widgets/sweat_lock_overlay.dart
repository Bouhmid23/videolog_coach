import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';

/// Overlay de verrouillage d'écran sportif (Pocket & Sweat Lock).
///
/// Protège le flux d'entraînement contre les appuis accidentels causés par :
/// - Les gouttes de sueur ou la pluie ruisselant sur la dalle capacitive.
/// - Le frottement du tissu lorsque le mobile est glissé dans un brassard ou une poche.
///
/// Déverrouillage sécurisé par appui long progressif (1.5s) avec retour haptique et anneau de progression.
class SweatLockOverlay extends StatefulWidget {
  final VoidCallback onUnlock;
  final bool outdoorSunMode;

  const SweatLockOverlay({
    required this.onUnlock,
    this.outdoorSunMode = false,
    super.key,
  });

  @override
  State<SweatLockOverlay> createState() => _SweatLockOverlayState();
}

class _SweatLockOverlayState extends State<SweatLockOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _holdController;
  Timer? _hapticTicker;
  bool _isHolding = false;

  static const Duration _unlockDuration = Duration(milliseconds: 1500);

  @override
  void initState() {
    super.initState();
    _holdController = AnimationController(
      vsync: this,
      duration: _unlockDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _completeUnlock();
        }
      });
  }

  @override
  void dispose() {
    _hapticTicker?.cancel();
    _holdController.dispose();
    super.dispose();
  }

  void _startHolding() {
    _unlocked = false;
    setState(() => _isHolding = true);
    unawaited(HapticFeedback.lightImpact());
    _holdController.forward(from: 0.0);

    _hapticTicker?.cancel();
    _hapticTicker = Timer.periodic(const Duration(milliseconds: 350), (_) {
      if (_isHolding) {
        unawaited(HapticFeedback.selectionClick());
      }
    });
  }

  bool _unlocked = false;

  void _cancelHolding() {
    if (!_isHolding || _unlocked) return;
    setState(() => _isHolding = false);
    _hapticTicker?.cancel();
    _holdController.reverse();
    unawaited(HapticFeedback.lightImpact());
  }

  void _completeUnlock() {
    if (_unlocked) return;
    _unlocked = true;
    _hapticTicker?.cancel();
    setState(() => _isHolding = false);
    widget.onUnlock();
  }

  @override
  Widget build(BuildContext context) {
    final sun = widget.outdoorSunMode;
    final accentColor = sun ? const Color(0xFFFFB800) : LKColors.primary;
    final backgroundColor = sun
        ? Colors.black.withValues(alpha: 0.65)
        : LKColors.background.withValues(alpha: 0.45);

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          // Un simple tap rappelle le geste nécessaire sans déverrouiller
          unawaited(HapticFeedback.selectionClick());
        },
        child: Container(
          color: backgroundColor,
          child: SafeArea(
            child: Stack(
              children: [
                // ── Badge supérieur Sweat Lock ──
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: sun ? Colors.black : LKColors.surface.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: sun ? Colors.white : LKColors.border,
                          width: sun ? 1.5 : 0.8,
                        ),
                        boxShadow: UIUtils.shadowMD,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_rounded,
                            color: accentColor,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.water_drop_rounded,
                            color: sun ? const Color(0xFF00E5FF) : LKColors.secondary,
                            size: 14,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'POCKET & SWEAT LOCK ACTIF',
                            style: TextStyle(
                              color: sun ? Colors.white : LKColors.textPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Bouton central / inférieur d'appui long pour déverrouiller ──
                Align(
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (_) => _startHolding(),
                        onPointerUp: (_) => _cancelHolding(),
                        onPointerCancel: (_) => _cancelHolding(),
                        child: AnimatedBuilder(
                          animation: _holdController,
                          builder: (context, _) {
                            final progress = _holdController.value;
                            return Container(
                              width: 86,
                              height: 86,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: sun
                                    ? Colors.black
                                    : LKColors.lkDarkBlue.withValues(alpha: 0.9),
                                border: Border.all(
                                  color: sun
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.3),
                                  width: 2.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: accentColor.withValues(alpha: _isHolding ? 0.45 : 0.15),
                                    blurRadius: _isHolding ? 20 : 10,
                                    spreadRadius: _isHolding ? 4 : 1,
                                  ),
                                ],
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Anneau de progression circulaire
                                  SizedBox(
                                    width: 74,
                                    height: 74,
                                    child: CircularProgressIndicator(
                                      value: progress,
                                      strokeWidth: 4.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                                    ),
                                  ),
                                  // Icône cadenas au centre
                                  Icon(
                                    _isHolding
                                        ? Icons.lock_open_rounded
                                        : Icons.lock_outline_rounded,
                                    size: 32,
                                    color: _isHolding ? accentColor : Colors.white,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: sun ? Colors.black : Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: sun ? Colors.white : Colors.white.withValues(alpha: 0.2),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          _isHolding
                              ? 'Maintenez...'
                              : 'Maintenir 1.5s pour déverrouiller',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: sun ? FontWeight.w900 : FontWeight.w700,
                            fontSize: 12,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
