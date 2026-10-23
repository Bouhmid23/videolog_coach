import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';
import '../utils/ui_utils.dart';

/// Champ de texte personnalisé suivant la charte graphique de l'application.
///
/// Fonctionnalités :
/// - Design moderne avec bordures arrondies
/// - Couleurs cohérentes avec le thème LKColors
/// - Feedback visuel au focus
/// - Validation intégrée
/// - Support des icônes prefix/suffix
/// - Animations subtiles
class LKTextField extends StatefulWidget {
  final String? label;
  final String? hintText;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final bool autocorrect;
  final bool autofocus;
  final bool enabled;
  final bool readOnly;
  final int? maxLines;
  final int? maxLength;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final IconData? prefixIconData;
  final IconData? suffixIconData;
  final VoidCallback? onSuffixPressed;
  final VoidCallback? onPrefixPressed;
  final bool showClearButton;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final String? helperText;
  final String? errorText;
  final bool filled;

  const LKTextField({
    this.label,
    this.hintText,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.autocorrect = true,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.maxLines = 1,
    this.maxLength,
    this.prefixIcon,
    this.suffixIcon,
    this.prefixIconData,
    this.suffixIconData,
    this.onSuffixPressed,
    this.onPrefixPressed,
    this.showClearButton = false,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.helperText,
    this.errorText,
    this.filled = true,
    super.key,
  });

  @override
  State<LKTextField> createState() => _LKTextFieldState();
}

class _LKTextFieldState extends State<LKTextField> {
  bool _hasFocus = false;
  bool _showPassword = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _hasFocus = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null;
    final hasSuffixAction = widget.onSuffixPressed != null || 
        (widget.showClearButton && widget.controller != null && widget.controller!.text.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Padding(
            padding: EdgeInsets.only(bottom: UIUtils.sm - 2),
            child: Text(
              widget.label!,
              style: UIUtils.labelMedium(context).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        
        // Container du champ de texte
        AnimatedContainer(
          duration: UIUtils.animationDuration,
          curve: UIUtils.animationCurve,
          decoration: BoxDecoration(
            color: widget.filled 
                ? (widget.enabled 
                    ? (_hasFocus 
                        ? LKColors.surfaceElevated 
                        : LKColors.surface) 
                    : LKColors.surface.withValues(alpha: 0.5)) 
                : Colors.transparent,
            borderRadius: UIUtils.inputBorderRadius,
            border: Border.all(
              color: hasError 
                  ? LKColors.danger 
                  : (_hasFocus 
                      ? LKColors.primary 
                      : LKColors.border),
              width: _hasFocus ? 1.4 : 1.0,
            ),
            boxShadow: _hasFocus && widget.enabled
                ? UIUtils.shadowSM
                : null,
          ),
          child: Row(
            children: [
              // Prefix Icon
              if (widget.prefixIcon != null || widget.prefixIconData != null) ...[
                Padding(
                  padding: EdgeInsets.only(left: UIUtils.md - 2),
                  child: widget.prefixIcon ?? 
                      IconButton(
                        icon: Icon(
                          widget.prefixIconData,
                          color: _hasFocus 
                              ? LKColors.primary 
                              : LKColors.textSecondary,
                        ),
                        onPressed: widget.onPrefixPressed ??
                            (widget.enabled ? () => _focusNode.requestFocus() : null),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 40),
                      ),
                ),
              ],
              
              // Champ de texte
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: (widget.prefixIcon != null || widget.prefixIconData != null) 
                        ? UIUtils.sm 
                        : UIUtils.md,
                    right: (hasSuffixAction || widget.suffixIcon != null || widget.suffixIconData != null) 
                        ? UIUtils.sm 
                        : UIUtils.md,
                    top: UIUtils.sm,
                    bottom: UIUtils.sm,
                  ),
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focusNode,
                    onChanged: (value) {
                      widget.onChanged?.call(value);
                      setState(() {}); // Pour mettre à jour l'icône de clear
                    },
                    onSubmitted: widget.onSubmitted,
                    keyboardType: widget.keyboardType,
                    textInputAction: widget.textInputAction,
                    obscureText: widget.obscureText && !_showPassword,
                    autocorrect: widget.autocorrect,
                    autofocus: widget.autofocus,
                    enabled: widget.enabled,
                    readOnly: widget.readOnly,
                    maxLines: widget.obscureText ? 1 : widget.maxLines,
                    maxLength: widget.maxLength,
                    textCapitalization: widget.textCapitalization,
                    inputFormatters: widget.inputFormatters,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: widget.enabled ? LKColors.textPrimary : LKColors.textHint,
                    ),
                    cursorColor: LKColors.primary,
                    decoration: InputDecoration.collapsed(
                      hintText: widget.hintText,
                      hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: LKColors.textHint,
                      ),
                    ),
                  ),
                ),
              ),
              
              // Suffix Icon / Actions
              if (hasSuffixAction || widget.suffixIcon != null || widget.suffixIconData != null) ...[
                Padding(
                  padding: EdgeInsets.only(right: UIUtils.md - 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Clear button
                      if (widget.showClearButton && 
                          widget.controller != null && 
                          widget.controller!.text.isNotEmpty &&
                          widget.enabled) ...[
                        IconButton(
                          icon: UIUtils.textSecondaryIcon(
                            Icons.close_rounded,
                            size: 18,
                          ),
                          onPressed: () {
                            widget.controller!.clear();
                            widget.onChanged?.call('');
                            _focusNode.requestFocus();
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36),
                          splashRadius: 20,
                          tooltip: 'Effacer',
                        ),
                      ],
                      
                      // Suffix Icon
                      if (widget.suffixIcon != null || widget.suffixIconData != null) ...[
                        widget.suffixIcon ?? 
                            IconButton(
                              icon: widget.obscureText 
                                  ? (_showPassword 
                                      ? UIUtils.textPrimaryIcon(Icons.visibility_rounded, size: 18)
                                      : UIUtils.textSecondaryIcon(Icons.visibility_off_rounded, size: 18))
                                  : Icon(
                                      widget.suffixIconData,
                                      color: _hasFocus 
                                          ? LKColors.primary 
                                          : LKColors.textSecondary,
                                      size: 18,
                                    ),
                              onPressed: widget.obscureText 
                                  ? () => setState(() => _showPassword = !_showPassword)
                                  : (widget.onSuffixPressed ?? () => _focusNode.requestFocus()),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 36),
                              splashRadius: 20,
                            ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        
        // Helper text ou Error text
        if (widget.helperText != null || widget.errorText != null) ...[
          AnimatedPadding(
            duration: UIUtils.animationDuration,
            padding: EdgeInsets.only(
              top: hasError ? UIUtils.xs : UIUtils.sm - 2,
              left: UIUtils.sm,
            ),
            child: AnimatedDefaultTextStyle(
              duration: UIUtils.animationDuration,
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                color: hasError ? LKColors.danger : LKColors.textHint,
              ),
              child: Text(
                widget.errorText ?? widget.helperText ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
