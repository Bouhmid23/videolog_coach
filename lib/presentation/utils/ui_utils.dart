import 'package:flutter/material.dart';

import '../../theme.dart';

/// Utilitaires pour appliquer la charte graphique de manière cohérente
/// dans toute l'application.
///
/// Couleurs principales :
/// - Primary: #5A8BFF (bleu clair)
/// - Primary Dark: #3D6EE0 (bleu foncé)
/// - Secondary: #22D3EE (cyan clair)
/// - Background: #0B1120 (noir bleuâtre très foncé)
/// - Surface: #111827 (noir bleuâtre foncé)
/// - Surface Elevated: #172034 (noir bleuâtre moyen)
/// - Border: #273449 (gris bleuâtre)
/// - Text Primary: #F8FAFC (blanc presque pur)
/// - Text Secondary: #B8C4D9 (gris clair)
/// - Text Hint: #93A2BE (gris moyen)

class UIUtils {
  UIUtils._();

  // ============================================================================
  // ESPACEMENTS (Spacing System)
  // ============================================================================
  
  /// Espacements standard basés sur un système de 4px
  static const double xs = 4.0;   // Extra Small
  static const double sm = 8.0;   // Small
  static const double md = 12.0;  // Medium
  static const double lg = 16.0;  // Large
  static const double xl = 20.0;  // Extra Large
  static const double xxl = 24.0; // Extra Extra Large
  static const double xxxl = 32.0; // Extra Extra Extra Large

  /// Paddings standard
  static const EdgeInsets paddingXS = EdgeInsets.all(xs);
  static const EdgeInsets paddingSM = EdgeInsets.all(sm);
  static const EdgeInsets paddingMD = EdgeInsets.all(md);
  static const EdgeInsets paddingLG = EdgeInsets.all(lg);
  static const EdgeInsets paddingXL = EdgeInsets.all(xl);
  static const EdgeInsets paddingXXL = EdgeInsets.all(xxl);

  /// Paddings horizontaux/verticaux
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
  
  /// Rayons de bordure standard
  static const double borderRadiusSM = 8.0;
  static const double borderRadiusMD = 12.0;
  static const double borderRadiusLG = 16.0;
  static const double borderRadiusXL = 20.0;
  static const double borderRadiusFull = 100.0; // Pour les cercles

  /// BorderRadius standard
  static const BorderRadius noBorderRadius = BorderRadius.only(topLeft: Radius.circular(borderRadiusXL),topRight: Radius.circular(borderRadiusXL));
  static const BorderRadius borderRadiusAllSM = BorderRadius.all(Radius.circular(borderRadiusSM));
  static const BorderRadius borderRadiusAllMD = BorderRadius.all(Radius.circular(borderRadiusMD));
  static const BorderRadius borderRadiusAllLG = BorderRadius.all(Radius.circular(borderRadiusLG));
  static const BorderRadius borderRadiusAllXL = BorderRadius.all(Radius.circular(borderRadiusXL));
  static const BorderRadius borderRadiusAllFull = BorderRadius.all(Radius.circular(borderRadiusFull));

  /// BorderRadius pour les cartes
  static const BorderRadius cardBorderRadius = BorderRadius.all(Radius.circular(borderRadiusLG));

  /// BorderRadius pour les boutons
  static const BorderRadius buttonBorderRadius = BorderRadius.all(Radius.circular(borderRadiusMD));

  /// BorderRadius pour les champs de texte
  static const BorderRadius inputBorderRadius = BorderRadius.all(Radius.circular(borderRadiusMD));

  // ============================================================================
  // OMBRES (Elevation System)
  // ============================================================================
  
  /// Niveaux d'élévation standard
  static List<BoxShadow> shadowSM = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.2),
      blurRadius: 4,
      offset: Offset(0, 1),
      spreadRadius: 0,
    ),
  ];

  static  List<BoxShadow> shadowMD = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.3),
      blurRadius: 8,
      offset: Offset(0, 2),
      spreadRadius: 0,
    ),
  ];

  static  List<BoxShadow> shadowLG = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.3),
      blurRadius: 12,
      offset: Offset(0, 4),
      spreadRadius: 0,
    ),
  ];

  static  List<BoxShadow> shadowXL = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.3),
      blurRadius: 16,
      offset: Offset(0, 4),
      spreadRadius: 2,
    ),
    BoxShadow(
      color: Colors.white.withValues(alpha: 0.05),
      blurRadius: 20,
      offset: Offset(0, 0),
      spreadRadius: 0,
    ),
  ];

  // ============================================================================
  // STYLES DE TEXTE
  // ============================================================================
  
  /// Style de titre principal
  static TextStyle titleLarge(BuildContext context) =>
      Theme.of(context).textTheme.titleLarge!.copyWith(
        fontWeight: FontWeight.w700,
        color: LKColors.textPrimary,
      );

  /// Style de titre secondaire
  static TextStyle titleMedium(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium!.copyWith(
        fontWeight: FontWeight.w600,
        color: LKColors.textPrimary,
      );

  /// Style de titre petit
  static TextStyle titleSmall(BuildContext context) =>
      Theme.of(context).textTheme.titleSmall!.copyWith(
        fontWeight: FontWeight.w600,
        color: LKColors.textPrimary,
      );

  /// Style de corps de texte
  static TextStyle bodyLarge(BuildContext context) =>
      Theme.of(context).textTheme.bodyLarge!.copyWith(
        color: LKColors.textPrimary,
      );

  /// Style de corps de texte secondaire
  static TextStyle bodyMedium(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(
        color: LKColors.textSecondary,
      );

  /// Style de corps de texte petit
  static TextStyle bodySmall(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall!.copyWith(
        color: LKColors.textSecondary,
      );

  /// Style de label
  static TextStyle labelLarge(BuildContext context) =>
      Theme.of(context).textTheme.labelLarge!.copyWith(
        fontWeight: FontWeight.w600,
        color: LKColors.textPrimary,
      );

  /// Style de label secondaire
  static TextStyle labelMedium(BuildContext context) =>
      Theme.of(context).textTheme.labelMedium!.copyWith(
        color: LKColors.textSecondary,
      );

  // ============================================================================
  // STYLES DE BOUTON
  // ============================================================================
  
  /// Style de bouton primaire
  static ButtonStyle primaryButtonStyle = ElevatedButton.styleFrom(
    foregroundColor: Colors.white,
    backgroundColor: LKColors.primary,
    padding:  EdgeInsets.symmetric(vertical: 14, horizontal: 20),
    shape: RoundedRectangleBorder(borderRadius: borderRadiusAllMD),
    textStyle:  TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 14,
    ),
    elevation: 0,
    shadowColor: Colors.transparent,
  );

  /// Style de bouton secondaire
  static ButtonStyle secondaryButtonStyle = OutlinedButton.styleFrom(
    foregroundColor: LKColors.primary,
    padding:  EdgeInsets.symmetric(vertical: 14, horizontal: 20),
    shape: RoundedRectangleBorder(borderRadius: borderRadiusAllMD),
    side:  BorderSide(color: LKColors.border, width: 1),
    textStyle:  TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 14,
    ),
  );

  /// Style de bouton iconique
  static ButtonStyle iconButtonStyle = IconButton.styleFrom(
    foregroundColor: LKColors.textPrimary,
    backgroundColor: LKColors.surface,
    padding:  EdgeInsets.all(10),
    shape: RoundedRectangleBorder(borderRadius: borderRadiusAllSM),
  );

  /// Style de bouton petit (pour les actions secondaires)
  static ButtonStyle smallButtonStyle = ElevatedButton.styleFrom(
    foregroundColor: LKColors.textPrimary,
    backgroundColor: LKColors.surfaceElevated,
    padding:  EdgeInsets.symmetric(vertical: 8, horizontal: 12),
    shape: RoundedRectangleBorder(borderRadius: borderRadiusAllSM),
    textStyle:  TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 12,
    ),
    elevation: 0,
    shadowColor: Colors.transparent,
  );

  // ============================================================================
  // STYLES DE CARTE
  // ============================================================================
  
  /// Style de carte standard
  static CardTheme cardTheme = CardTheme(
    color: LKColors.surfaceElevated,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shadowColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: cardBorderRadius,
      side:  BorderSide(color: LKColors.border, width: 1),
    ),
    margin: EdgeInsets.zero,
  );

  /// Style de carte surélevée (pour les dialogues, modals)
  static CardTheme elevatedCardTheme = CardTheme(
    color: LKColors.surfaceElevated,
    surfaceTintColor: Colors.transparent,
    elevation: 4,
    shadowColor: Colors.black.withValues(alpha: 0.3),
    shape: RoundedRectangleBorder(
      borderRadius: cardBorderRadius,
      side:  BorderSide(color: LKColors.border, width: 1),
    ),
  );

  // ============================================================================
  // STYLES DE CHAMP DE TEXTE
  // ============================================================================
  
  /// Style de champ de texte standard
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
    prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: LKColors.textSecondary, size: 20) : null,
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
  // COULEURS D'ÉTAT
  // ============================================================================
  
  /// Couleur pour les états de succès
  static const Color successColor = LKColors.success;
  
  /// Couleur pour les avertissements
  static const Color warningColor = LKColors.warning;
  
  /// Couleur pour les erreurs
  static const Color errorColor = LKColors.danger;
  
  /// Couleur pour les informations
  static const Color infoColor = LKColors.primary;

  // ============================================================================
  // ANIMATIONS
  // ============================================================================
  
  /// Durée standard pour les animations
  static const Duration animationDuration = Duration(milliseconds: 300);
  static const Duration animationDurationSlow = Duration(milliseconds: 500);
  static const Duration animationDurationFast = Duration(milliseconds: 200);

  /// Courbe d'animation standard
  static const Curve animationCurve = Curves.easeOutCubic;
  static const Curve animationCurveFast = Curves.easeOut;
  static const Curve animationCurveBounce = Curves.easeOutBack;

  // ============================================================================
  // UTILITAIRES DE COULEUR
  // ============================================================================
  
  /// Applique une opacité à une couleur tout en gardant le type Color
  static Color withOpacity(Color color, double opacity) {
    return Color.lerp(color, Colors.transparent, 1 - opacity.clamp(0.0, 1.0))!;
  }

  /// Mélange deux couleurs
  static Color blendColors(Color color1, Color color2, double ratio) {
    return Color.lerp(color1, color2, ratio.clamp(0.0, 1.0))!;
  }

  /// Couleur de surface avec élévation
  static Color surfaceColor(int elevation) {
    if (elevation <= 0) return LKColors.surface;
    if (elevation <= 2) return LKColors.surfaceElevated;
    return blendColors(LKColors.surfaceElevated, LKColors.primary.withValues(alpha: 0.1), 0.1 * elevation);
  }

  // ============================================================================
  // STYLES DE DIALOGUE
  // ============================================================================
  
  /// Style de dialogue moderne
  static DialogTheme dialogTheme = DialogTheme(
    backgroundColor: LKColors.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 4,
    shadowColor: Colors.black.withValues(alpha: 0.4),
    shape: RoundedRectangleBorder(borderRadius: cardBorderRadius),
    iconColor: LKColors.primary,
    titleTextStyle:  TextStyle(
      color: LKColors.textPrimary,
      fontWeight: FontWeight.w700,
      fontSize: 18,
    ),
    contentTextStyle:  TextStyle(
      color: LKColors.textSecondary,
      fontSize: 14,
    ),
  );

  // ============================================================================
  // STYLES DE BADGE/CHIP
  // ============================================================================
  
  /// Style pour les chips/puces
  static ChipThemeData chipTheme = ChipThemeData(
    backgroundColor: LKColors.surface,
    surfaceTintColor: Colors.transparent,
    labelStyle:  TextStyle(
      color: LKColors.textPrimary,
      fontSize: 11,
      fontWeight: FontWeight.w500,
    ),
    padding:  EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    shape: RoundedRectangleBorder(borderRadius: borderRadiusAllSM),
    side:  BorderSide(color: LKColors.border, width: 0.5),
    secondaryLabelStyle:  TextStyle(
      color: LKColors.textPrimary,
      fontSize: 11,
      fontWeight: FontWeight.w500,
    ),
    deleteIconColor: LKColors.textSecondary,
  );

  // ============================================================================
  // STYLES DE BOTTOM SHEET
  // ============================================================================
  
  /// Style de bottom sheet
  static BottomSheetThemeData bottomSheetTheme = BottomSheetThemeData(
    backgroundColor: LKColors.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 4,
    shadowColor: Colors.black.withValues(alpha: 0.4),
    shape:  RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(borderRadiusLG)),
    ),
    clipBehavior: Clip.antiAlias,
    modalElevation: 8,
    modalBackgroundColor: LKColors.surface,
  );

  // ============================================================================
  // STYLES DE SWITCH
  // ============================================================================
  
  /// Style de switch personnalisé
  static SwitchThemeData switchTheme = SwitchThemeData(
    trackColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return LKColors.primary;
      if (states.contains(WidgetState.disabled)) return LKColors.border.withValues(alpha: 0.5);
      return LKColors.border;
    }),
    thumbColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return Colors.white;
      if (states.contains(WidgetState.disabled)) return LKColors.textHint;
      return LKColors.textSecondary;
    }),
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.hovered)) {
        return LKColors.primary.withValues(alpha: 0.1);
      }
      return Colors.transparent;
    }),
  );

  // ============================================================================
  // ICÔNES AVEC COULEURS CONSISTANTES
  // ============================================================================
  
  /// Icône avec la couleur primaire
  static Icon primaryIcon(IconData icon, {double? size, double? opacity}) =>
      Icon(icon, color: LKColors.primary.withValues(alpha: opacity ?? 1.0), size: size);

  /// Icône avec la couleur secondaire
  static Icon secondaryIcon(IconData icon, {double? size, double? opacity}) =>
      Icon(icon, color: LKColors.secondary.withValues(alpha: opacity ?? 1.0), size: size);

  /// Icône avec la couleur de succès
  static Icon successIcon(IconData icon, {double? size, double? opacity}) =>
      Icon(icon, color: LKColors.success.withValues(alpha: opacity ?? 1.0), size: size);

  /// Icône avec la couleur d'avertissement
  static Icon warningIcon(IconData icon, {double? size, double? opacity}) =>
      Icon(icon, color: LKColors.warning.withValues(alpha: opacity ?? 1.0), size: size);

  /// Icône avec la couleur d'erreur
  static Icon errorIcon(IconData icon, {double? size, double? opacity}) =>
      Icon(icon, color: LKColors.danger.withValues(alpha: opacity ?? 1.0), size: size);

  /// Icône avec la couleur de texte principale
  static Icon textPrimaryIcon(IconData icon, {double? size, double? opacity}) =>
      Icon(icon, color: LKColors.textPrimary.withValues(alpha: opacity ?? 1.0), size: size);

  /// Icône avec la couleur de texte secondaire
  static Icon textSecondaryIcon(IconData icon, {double? size, double? opacity}) =>
      Icon(icon, color: LKColors.textSecondary.withValues(alpha: opacity ?? 1.0), size: size);
}
