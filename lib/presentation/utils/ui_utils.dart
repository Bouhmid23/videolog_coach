import 'package:flutter/material.dart';

import '../../theme.dart';

enum AppSnackBarTone { info, success, warning, error }

/// Utilitaires d'espacement, de rayons, de typographie et de retours visuels
/// alignés sur [LiveKitTheme].
class UIUtils {
  UIUtils._();

  // ============================================================================
  // ESPACEMENTS (Spacing System - grille 4px)
  // ============================================================================

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double xxxl = 32.0;

  static const EdgeInsets paddingXS = EdgeInsets.all(xs);
  static const EdgeInsets paddingSM = EdgeInsets.all(sm);
  static const EdgeInsets paddingMD = EdgeInsets.all(md);
  static const EdgeInsets paddingLG = EdgeInsets.all(lg);
  static const EdgeInsets paddingXL = EdgeInsets.all(xl);
  static const EdgeInsets paddingXXL = EdgeInsets.all(xxl);

  static const EdgeInsets paddingHorizontalSM = EdgeInsets.symmetric(horizontal: sm);
  static const EdgeInsets paddingHorizontalMD = EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets paddingHorizontalLG = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets paddingHorizontalXL = EdgeInsets.symmetric(horizontal: xl);
  static const EdgeInsets paddingHorizontalXXL = EdgeInsets.symmetric(horizontal: xxl);
  static const EdgeInsets paddingVerticalXS = EdgeInsets.symmetric(vertical: xs);
  static const EdgeInsets paddingVerticalSM = EdgeInsets.symmetric(vertical: sm);
  static const EdgeInsets paddingVerticalMD = EdgeInsets.symmetric(vertical: md);
  static const EdgeInsets paddingVerticalLG = EdgeInsets.symmetric(vertical: lg);

  // ============================================================================
  // BORDURES (Border Radius)
  // ============================================================================

  static const double borderRadiusSM = 8.0;
  static const double borderRadiusMD = 12.0;
  static const double borderRadiusLG = 16.0;
  static const double borderRadiusXL = 20.0;
  static const double borderRadiusFull = 100.0;

  static const BorderRadius noBorderRadius = BorderRadius.only(
    topLeft: Radius.circular(borderRadiusXL),
    topRight: Radius.circular(borderRadiusXL),
  );
  static const BorderRadius borderRadiusAllSM = BorderRadius.all(Radius.circular(borderRadiusSM));
  static const BorderRadius borderRadiusAllMD = BorderRadius.all(Radius.circular(borderRadiusMD));
  static const BorderRadius borderRadiusAllLG = BorderRadius.all(Radius.circular(borderRadiusLG));
  static const BorderRadius borderRadiusAllXL = BorderRadius.all(Radius.circular(borderRadiusXL));
  static const BorderRadius borderRadiusAllFull = BorderRadius.all(Radius.circular(borderRadiusFull));

  static const BorderRadius cardBorderRadius = borderRadiusAllLG;
  static const BorderRadius buttonBorderRadius = borderRadiusAllMD;
  static const BorderRadius inputBorderRadius = borderRadiusAllMD;

  // ============================================================================
  // OMBRES (Elevation System)
  // ============================================================================

  static List<BoxShadow> shadowSM = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.2),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];

  static List<BoxShadow> shadowMD = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.3),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> shadowLG = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.3),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> shadowXL = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.3),
      blurRadius: 16,
      offset: const Offset(0, 4),
      spreadRadius: 2,
    ),
    BoxShadow(
      color: Colors.white.withValues(alpha: 0.05),
      blurRadius: 20,
      offset: Offset.zero,
    ),
  ];

  // ============================================================================
  // STYLES DE TEXTE
  // ============================================================================

  static TextStyle titleLarge(BuildContext context) =>
      Theme.of(context).textTheme.titleLarge!.copyWith(
        fontWeight: FontWeight.w700,
        color: LKColors.textPrimary,
      );

  static TextStyle titleMedium(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium!.copyWith(
        fontWeight: FontWeight.w600,
        color: LKColors.textPrimary,
      );

  static TextStyle titleSmall(BuildContext context) =>
      Theme.of(context).textTheme.titleSmall!.copyWith(
        fontWeight: FontWeight.w600,
        color: LKColors.textPrimary,
      );

  static TextStyle bodyLarge(BuildContext context) =>
      Theme.of(context).textTheme.bodyLarge!.copyWith(
        color: LKColors.textPrimary,
      );

  static TextStyle bodyMedium(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(
        color: LKColors.textSecondary,
      );

  static TextStyle bodySmall(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall!.copyWith(
        color: LKColors.textSecondary,
      );

  static TextStyle labelLarge(BuildContext context) =>
      Theme.of(context).textTheme.labelLarge!.copyWith(
        fontWeight: FontWeight.w600,
        color: LKColors.textPrimary,
      );

  static TextStyle labelMedium(BuildContext context) =>
      Theme.of(context).textTheme.labelMedium!.copyWith(
        color: LKColors.textSecondary,
      );

  // ============================================================================
  // CHAMPS DE TEXTE
  // ============================================================================

  static InputDecoration inputDecoration({
    String? labelText,
    String? hintText,
    IconData? prefixIcon,
    IconData? suffixIcon,
    VoidCallback? onSuffixIconTap,
    String? suffixTooltip,
    Widget? suffix,
  }) => InputDecoration(
    labelText: labelText,
    hintText: hintText,
    prefixIcon: prefixIcon != null
        ? Icon(prefixIcon, color: LKColors.textSecondary, size: 20)
        : null,
    suffixIcon: suffixIcon != null
        ? (onSuffixIconTap != null
              ? IconButton(
                  icon: Icon(
                    suffixIcon,
                    color: LKColors.textSecondary,
                    size: 20,
                  ),
                  tooltip: suffixTooltip,
                  onPressed: onSuffixIconTap,
                )
              : Icon(suffixIcon, color: LKColors.textSecondary, size: 20))
        : null,
    suffix: suffix,
    filled: true,
    fillColor: LKColors.surface,
    labelStyle: const TextStyle(color: LKColors.textSecondary, fontSize: 12),
    hintStyle: const TextStyle(color: LKColors.textHint, fontSize: 12),
    prefixIconColor: LKColors.textSecondary,
    suffixIconColor: LKColors.textSecondary,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    enabledBorder: const OutlineInputBorder(
      borderRadius: inputBorderRadius,
      borderSide: BorderSide(color: LKColors.border, width: 1),
    ),
    focusedBorder: const OutlineInputBorder(
      borderRadius: inputBorderRadius,
      borderSide: BorderSide(color: LKColors.primary, width: 1.4),
    ),
    errorBorder: const OutlineInputBorder(
      borderRadius: inputBorderRadius,
      borderSide: BorderSide(color: LKColors.danger, width: 1),
    ),
    focusedErrorBorder: const OutlineInputBorder(
      borderRadius: inputBorderRadius,
      borderSide: BorderSide(color: LKColors.danger, width: 1.4),
    ),
    border: const OutlineInputBorder(
      borderRadius: inputBorderRadius,
    ),
  );

  // ============================================================================
  // COULEURS D'ÉTAT & SNACKBARS
  // ============================================================================

  static const Color successColor = LKColors.success;
  static const Color warningColor = LKColors.warning;
  static const Color errorColor = LKColors.danger;
  static const Color infoColor = LKColors.primary;

  /// Affiche un [SnackBar] flottant cohérent avec la charte VideoLog.
  static void showSnackBar(
    BuildContext context,
    String message, {
    AppSnackBarTone tone = AppSnackBarTone.info,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final Color accentColor = switch (tone) {
      AppSnackBarTone.info => LKColors.primary,
      AppSnackBarTone.success => LKColors.success,
      AppSnackBarTone.warning => LKColors.warning,
      AppSnackBarTone.error => LKColors.danger,
    };

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: borderRadiusAllFull,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
            ],
          ),
          duration: duration,
          action: action,
        ),
      );
  }

  // ============================================================================
  // ANIMATIONS
  // ============================================================================

  static const Duration animationDuration = Duration(milliseconds: 300);
  static const Duration animationDurationSlow = Duration(milliseconds: 500);
  static const Duration animationDurationFast = Duration(milliseconds: 200);

  static const Curve animationCurve = Curves.easeOutCubic;
  static const Curve animationCurveFast = Curves.easeOut;
  static const Curve animationCurveBounce = Curves.easeOutBack;

  // ============================================================================
  // UTILITAIRES DE COULEUR
  // ============================================================================

  static Color withOpacity(Color color, double opacity) {
    return Color.lerp(color, Colors.transparent, 1 - opacity.clamp(0.0, 1.0))!;
  }

  static Color blendColors(Color color1, Color color2, double ratio) {
    return Color.lerp(color1, color2, ratio.clamp(0.0, 1.0))!;
  }

  static Color surfaceColor(int elevation) {
    if (elevation <= 0) return LKColors.surface;
    if (elevation <= 2) return LKColors.surfaceElevated;
    return blendColors(
      LKColors.surfaceElevated,
      LKColors.primary.withValues(alpha: 0.1),
      0.1 * elevation,
    );
  }

  // ============================================================================
  // ICÔNES AVEC COULEURS CONSISTANTES
  // ============================================================================

  static Icon primaryIcon(IconData icon, {double? size, double? opacity}) =>
      Icon(icon, color: LKColors.primary.withValues(alpha: opacity ?? 1.0), size: size);

  static Icon secondaryIcon(IconData icon, {double? size, double? opacity}) =>
      Icon(icon, color: LKColors.secondary.withValues(alpha: opacity ?? 1.0), size: size);

  static Icon successIcon(IconData icon, {double? size, double? opacity}) =>
      Icon(icon, color: LKColors.success.withValues(alpha: opacity ?? 1.0), size: size);

  static Icon warningIcon(IconData icon, {double? size, double? opacity}) =>
      Icon(icon, color: LKColors.warning.withValues(alpha: opacity ?? 1.0), size: size);

  static Icon errorIcon(IconData icon, {double? size, double? opacity}) =>
      Icon(icon, color: LKColors.danger.withValues(alpha: opacity ?? 1.0), size: size);

  static Icon textPrimaryIcon(IconData icon, {double? size, double? opacity}) =>
      Icon(icon, color: LKColors.textPrimary.withValues(alpha: opacity ?? 1.0), size: size);

  static Icon textSecondaryIcon(IconData icon, {double? size, double? opacity}) =>
      Icon(icon, color: LKColors.textSecondary.withValues(alpha: opacity ?? 1.0), size: size);
}
