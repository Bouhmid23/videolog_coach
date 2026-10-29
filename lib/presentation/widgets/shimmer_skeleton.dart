import 'package:flutter/material.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';

/// Reusable shimmer loading effect for skeletons.
///
/// Uses an animated [LinearGradient] to sweep a subtle highlight across
/// dark theme containers, providing fluid, world-class perceived performance.
class ShimmerEffect extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Color baseColor;
  final Color highlightColor;

  const ShimmerEffect({
    required this.child,
    this.duration = const Duration(milliseconds: 1500),
    this.baseColor = const Color(0xFF1E2638),
    this.highlightColor = const Color(0xFF2C374E),
    super.key,
  });

  @override
  State<ShimmerEffect> createState() => _ShimmerEffectState();
}

class _ShimmerEffectState extends State<ShimmerEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final t = _controller.value;
            // Sweep gradient from left to right (-1.0 to 2.0)
            final startX = (t * 3.0) - 1.0;
            return LinearGradient(
              begin: Alignment(startX - 0.5, -0.3),
              end: Alignment(startX + 0.5, 0.3),
              colors: [
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
              ],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Generic skeleton container box.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final BorderRadiusGeometry? borderRadius;
  final BoxShape shape;

  const SkeletonBox({
    this.width,
    this.height,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: LKColors.surfaceElevated,
        shape: shape,
        borderRadius: shape == BoxShape.circle
            ? null
            : (borderRadius ?? UIUtils.borderRadiusAllSM),
      ),
    );
  }
}

/// Skeleton representing the header of [RoomsScreen].
class RoomsHeaderSkeleton extends StatelessWidget {
  const RoomsHeaderSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: UIUtils.paddingXL,
      decoration: BoxDecoration(
        color: LKColors.surface,
        borderRadius: UIUtils.borderRadiusAllXL,
        border: Border.all(
          color: LKColors.border.withValues(alpha: 0.5),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(width: 80, height: 12),
          SizedBox(height: UIUtils.sm),
          const SkeletonBox(width: 180, height: 24),
          SizedBox(height: UIUtils.xs),
          const SkeletonBox(width: 220, height: 14),
          SizedBox(height: UIUtils.lg),
          Container(
            padding: UIUtils.paddingMD,
            decoration: BoxDecoration(
              color: LKColors.background.withValues(alpha: 0.35),
              borderRadius: UIUtils.borderRadiusAllMD,
              border: Border.all(
                color: LKColors.border.withValues(alpha: 0.6),
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SkeletonBox(width: 28, height: 20),
                      SizedBox(height: UIUtils.xs),
                      const SkeletonBox(width: 60, height: 12),
                    ],
                  ),
                ),
                Container(
                  width: 0.5,
                  height: 28,
                  margin: EdgeInsets.symmetric(horizontal: UIUtils.md),
                  color: LKColors.border,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SkeletonBox(width: 28, height: 20),
                      SizedBox(height: UIUtils.xs),
                      const SkeletonBox(width: 60, height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton representing a room card in [RoomsScreen].
class RoomCardSkeleton extends StatelessWidget {
  const RoomCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: LKColors.surface,
        borderRadius: UIUtils.borderRadiusAllXL,
        border: Border.all(
          color: LKColors.border.withValues(alpha: 0.4),
          width: 0.5,
        ),
      ),
      padding: UIUtils.paddingLG,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SkeletonBox(width: 44, height: 44, shape: BoxShape.circle),
              SizedBox(width: UIUtils.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SkeletonBox(width: 140, height: 18),
                    SizedBox(height: UIUtils.xs),
                    const SkeletonBox(width: 90, height: 12),
                  ],
                ),
              ),
              const SkeletonBox(
                width: 70,
                height: 24,
                borderRadius: BorderRadius.all(Radius.circular(999)),
              ),
            ],
          ),
          SizedBox(height: UIUtils.md),
          const SkeletonBox(width: double.infinity, height: 14),
          SizedBox(height: UIUtils.xs),
          const SkeletonBox(width: 180, height: 14),
          SizedBox(height: UIUtils.md),
          Row(
            children: [
              const SkeletonBox(width: 80, height: 20),
              const Spacer(),
              const SkeletonBox(width: 100, height: 32),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shimmer list showing placeholder skeletons during loading state.
class RoomsListSkeleton extends StatelessWidget {
  final int itemCount;

  const RoomsListSkeleton({this.itemCount = 3, super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          UIUtils.lg,
          UIUtils.md,
          UIUtils.lg,
          UIUtils.xxl,
        ),
        itemCount: itemCount + 1,
        separatorBuilder: (_, _) => SizedBox(height: UIUtils.md),
        itemBuilder: (context, index) {
          if (index == 0) return const RoomsHeaderSkeleton();
          return const RoomCardSkeleton();
        },
      ),
    );
  }
}
