import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

//
// Flutter has a color profile issue so colors will look different
// on Apple devices.
// https://github.com/flutter/flutter/issues/55092
// https://github.com/flutter/flutter/issues/39113
//

extension LKColors on Colors {
  // Accent principal (Cyan VideoLog) & secondaire
  static const primary = Color(0xFF18ABF8);
  static const primaryDark = Color(0xFF1289C7);
  static const secondary = Color(0xFF3A8FD6);

  // Logo Videolog (dégradé de bleus du « V »)
  static const logoLight = Color(0xFF66CCF5);
  static const logoBlue = Color(0xFF18ABF8);
  static const logoDeep = Color(0xFF009FE3);

  // Surfaces (charte VideoLog)
  static const background = Color(0xFF090B0E);
  static const surface = Color(0xFF0F1318);
  static const surfaceElevated = Color(0xFF151A21);
  static const surfaceHigher = Color(0xFF1C222B);
  static const border = Color(0xFF232B35);
  static const borderSubtle = Color(0xFF1B222B);

  // Text
  static const textPrimary = Color(0xFFEEF2F6);
  static const textSecondary = Color(0xFF98A3B0);
  // Contraste relevé (>= 4.5:1 sur #151A21) pour accessibilité WCAG AA
  static const textHint = Color(0xFF8592A3);

  // States
  static const success = Color(0xFF3DDC97);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFE5373A);

  // Backward compatibility in existing code
  static const lkBlue = primary;
  static const lkDarkBlue = surfaceElevated;
}

/// Tokens sémantiques propres à l'expérience sportive VideoLog.
@immutable
class VideologThemeTokens extends ThemeExtension<VideologThemeTokens> {
  const VideologThemeTokens({
    required this.success,
    required this.warning,
    required this.outdoorBackground,
    required this.outdoorBorder,
    required this.outdoorAccent,
  });

  final Color success;
  final Color warning;
  final Color outdoorBackground;
  final Color outdoorBorder;
  final Color outdoorAccent;

  static const dark = VideologThemeTokens(
    success: LKColors.success,
    warning: LKColors.warning,
    outdoorBackground: Colors.black,
    outdoorBorder: Colors.white,
    outdoorAccent: Color(0xFFFFD700),
  );

  @override
  VideologThemeTokens copyWith({
    Color? success,
    Color? warning,
    Color? outdoorBackground,
    Color? outdoorBorder,
    Color? outdoorAccent,
  }) {
    return VideologThemeTokens(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      outdoorBackground: outdoorBackground ?? this.outdoorBackground,
      outdoorBorder: outdoorBorder ?? this.outdoorBorder,
      outdoorAccent: outdoorAccent ?? this.outdoorAccent,
    );
  }

  @override
  VideologThemeTokens lerp(
    covariant ThemeExtension<VideologThemeTokens>? other,
    double t,
  ) {
    if (other is! VideologThemeTokens) return this;
    return VideologThemeTokens(
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      outdoorBackground:
          Color.lerp(outdoorBackground, other.outdoorBackground, t) ??
          outdoorBackground,
      outdoorBorder:
          Color.lerp(outdoorBorder, other.outdoorBorder, t) ?? outdoorBorder,
      outdoorAccent:
          Color.lerp(outdoorAccent, other.outdoorAccent, t) ?? outdoorAccent,
    );
  }
}

class LiveKitTheme {
  const LiveKitTheme();

  /// Police de titres / KPIs.
  static const String fontFamily = 'TradeGothic';

  /// Police de corps de texte (alignement web/mobile VideoLog).
  static const String bodyFontFamily = 'Montserrat';

  ThemeData buildThemeData(BuildContext ctx) {
    // google_fonts 9.x utilise `package:material_ui/material_ui.dart` pour
    // `TextTheme`, distinct du `TextTheme` de `package:flutter/material.dart`.
    // On applique donc `GoogleFonts.montserrat` style par style (`TextStyle`
    // reste partagé via `package:flutter/painting.dart`).
    final sourceTextTheme = Theme.of(ctx).textTheme;
    final montserratTheme = TextTheme(
      displayLarge: GoogleFonts.montserrat(textStyle: sourceTextTheme.displayLarge),
      displayMedium: GoogleFonts.montserrat(textStyle: sourceTextTheme.displayMedium),
      displaySmall: GoogleFonts.montserrat(textStyle: sourceTextTheme.displaySmall),
      headlineLarge: GoogleFonts.montserrat(textStyle: sourceTextTheme.headlineLarge),
      headlineMedium: GoogleFonts.montserrat(textStyle: sourceTextTheme.headlineMedium),
      headlineSmall: GoogleFonts.montserrat(textStyle: sourceTextTheme.headlineSmall),
      titleLarge: GoogleFonts.montserrat(textStyle: sourceTextTheme.titleLarge),
      titleMedium: GoogleFonts.montserrat(textStyle: sourceTextTheme.titleMedium),
      titleSmall: GoogleFonts.montserrat(textStyle: sourceTextTheme.titleSmall),
      bodyLarge: GoogleFonts.montserrat(textStyle: sourceTextTheme.bodyLarge),
      bodyMedium: GoogleFonts.montserrat(textStyle: sourceTextTheme.bodyMedium),
      bodySmall: GoogleFonts.montserrat(textStyle: sourceTextTheme.bodySmall),
      labelLarge: GoogleFonts.montserrat(textStyle: sourceTextTheme.labelLarge),
      labelMedium: GoogleFonts.montserrat(textStyle: sourceTextTheme.labelMedium),
      labelSmall: GoogleFonts.montserrat(textStyle: sourceTextTheme.labelSmall),
    ).apply(
      displayColor: LKColors.textPrimary,
      bodyColor: LKColors.textPrimary,
      decorationColor: LKColors.textPrimary,
    );

    // TradeGothic réservée aux grands titres et KPIs ; Montserrat conservée pour corps & labels.
    final baseTextTheme = montserratTheme.copyWith(
      displayLarge: montserratTheme.displayLarge?.copyWith(fontFamily: fontFamily),
      displayMedium: montserratTheme.displayMedium?.copyWith(fontFamily: fontFamily),
      displaySmall: montserratTheme.displaySmall?.copyWith(fontFamily: fontFamily),
      headlineLarge: montserratTheme.headlineLarge?.copyWith(fontFamily: fontFamily),
      headlineMedium: montserratTheme.headlineMedium?.copyWith(fontFamily: fontFamily),
      headlineSmall: montserratTheme.headlineSmall?.copyWith(fontFamily: fontFamily),
      titleLarge: montserratTheme.titleLarge?.copyWith(fontFamily: fontFamily),
      titleMedium: montserratTheme.titleMedium?.copyWith(fontFamily: fontFamily),
    );

    const buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    );
    const buttonPadding = EdgeInsets.symmetric(vertical: 14, horizontal: 20);

    return ThemeData(
      useMaterial3: true,
      fontFamily: montserratTheme.bodyMedium?.fontFamily ?? bodyFontFamily,
      scaffoldBackgroundColor: LKColors.background,
      canvasColor: LKColors.background,
      cardColor: LKColors.surfaceElevated,
      dividerColor: LKColors.border,
      hintColor: LKColors.textHint,
      iconTheme: const IconThemeData(color: LKColors.textPrimary),
      textTheme: baseTextTheme,
      extensions: const <ThemeExtension<dynamic>>[
        VideologThemeTokens.dark,
      ],

      colorScheme: const ColorScheme.dark(
        primary: LKColors.primary,
        onPrimary: Colors.white,
        primaryContainer: Color(0xFF0C3B59),
        onPrimaryContainer: Color(0xFFBFE9FF),
        secondary: LKColors.secondary,
        onSecondary: Colors.white,
        surface: LKColors.surface,
        onSurface: LKColors.textPrimary,
        surfaceContainerLowest: LKColors.background,
        surfaceContainerLow: LKColors.surface,
        surfaceContainer: LKColors.surfaceElevated,
        surfaceContainerHigh: LKColors.surfaceHigher,
        surfaceContainerHighest: LKColors.border,
        onSurfaceVariant: LKColors.textSecondary,
        outline: LKColors.border,
        outlineVariant: LKColors.borderSubtle,
        error: LKColors.danger,
        onError: Colors.white,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: LKColors.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: LKColors.textPrimary,
        elevation: 0,
        titleTextStyle: baseTextTheme.titleLarge?.copyWith(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w700,
          color: LKColors.textPrimary,
        ),
      ),

      cardTheme: CardThemeData(
        color: LKColors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: LKColors.border),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: buttonPadding,
          shape: buttonShape,
          foregroundColor: Colors.white,
          backgroundColor: LKColors.primary,
          disabledBackgroundColor: LKColors.primary.withValues(alpha: 0.45),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.75),
          textStyle: baseTextTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          elevation: 0,
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStateProperty.all(const Size(0, 48)),
          textStyle: WidgetStateProperty.all(
            baseTextTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          padding: WidgetStateProperty.all(buttonPadding),
          shape: WidgetStateProperty.all(buttonShape),
          elevation: WidgetStateProperty.all(0),
          foregroundColor: WidgetStateProperty.all(Colors.white),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return LKColors.primary.withValues(alpha: 0.45);
            }
            if (states.contains(WidgetState.pressed)) {
              return LKColors.primaryDark;
            }
            return LKColors.primary;
          }),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: buttonPadding,
          shape: buttonShape,
          foregroundColor: LKColors.textPrimary,
          side: const BorderSide(color: LKColors.border),
          textStyle: baseTextTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 44),
          shape: buttonShape,
          foregroundColor: LKColors.primary,
          textStyle: baseTextTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: LKColors.surfaceElevated,
        contentTextStyle: baseTextTheme.bodyMedium?.copyWith(
          color: LKColors.textPrimary,
        ),
        actionTextColor: LKColors.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: LKColors.border),
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: LKColors.surface,
        modalBackgroundColor: LKColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: LKColors.border,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: LKColors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        indicatorColor: LKColors.primary.withValues(alpha: 0.18),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: LKColors.primary);
          }
          return const IconThemeData(color: LKColors.textSecondary);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return baseTextTheme.labelSmall?.copyWith(
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? LKColors.primary : LKColors.textSecondary,
          );
        }),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: LKColors.surface,
        selectedColor: LKColors.primary.withValues(alpha: 0.18),
        surfaceTintColor: Colors.transparent,
        labelStyle: baseTextTheme.labelMedium?.copyWith(
          color: LKColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
        secondaryLabelStyle: baseTextTheme.labelMedium?.copyWith(
          color: LKColors.primary,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: const BorderSide(color: LKColors.border),
        deleteIconColor: LKColors.textSecondary,
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: LKColors.primary,
        inactiveTrackColor: LKColors.border,
        thumbColor: LKColors.primary,
        overlayColor: LKColors.primary.withValues(alpha: 0.18),
      ),

      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        checkColor: WidgetStateProperty.all(Colors.white),
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return LKColors.primary;
          return Colors.transparent;
        }),
        side: const BorderSide(color: LKColors.border),
      ),

      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return LKColors.primary;
          if (states.contains(WidgetState.disabled)) {
            return LKColors.border.withValues(alpha: 0.5);
          }
          return LKColors.border;
        }),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          if (states.contains(WidgetState.disabled)) return LKColors.textHint;
          return LKColors.textSecondary;
        }),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: LKColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: LKColors.border),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: LKColors.surface,
        labelStyle: const TextStyle(color: LKColors.textSecondary),
        hintStyle: const TextStyle(color: LKColors.textHint),
        prefixIconColor: LKColors.textSecondary,
        suffixIconColor: LKColors.textSecondary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: LKColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: LKColors.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: LKColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: LKColors.danger, width: 1.4),
        ),
      ),
    );
  }
}
