import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../app_config.dart';
import '../../core/account_controller.dart';
import '../../core/auth_service.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';

const String _googleLogoSvg = '''
<svg viewBox="0 0 24 24" width="20" height="20" xmlns="http://www.w3.org/2000/svg">
  <path fill="#4285F4" d="M23.745 12.27c0-.7-.06-1.4-.19-2.07H12v4.51h6.6c-.29 1.52-1.14 2.82-2.4 3.68v3.05h3.88c2.27-2.09 3.665-5.17 3.665-9.17Z"/>
  <path fill="#34A853" d="M12 24c3.24 0 5.95-1.08 7.93-2.91l-3.88-3.05c-1.08.72-2.45 1.16-4.05 1.16-3.12 0-5.77-2.11-6.72-4.96H1.29v3.14C3.26 21.3 7.31 24 12 24Z"/>
  <path fill="#FBBC05" d="M5.28 14.24c-.24-.72-.38-1.49-.38-2.24s.14-1.52.38-2.24V6.62H1.29C.47 8.24 0 10.06 0 12s.47 3.76 1.29 5.38l3.99-3.14Z"/>
  <path fill="#EA4335" d="M12 4.75c1.77 0 3.35.61 4.6 1.8l3.42-3.42C17.95 1.19 15.24 0 12 0 7.31 0 3.26 2.7 1.29 6.62l3.99 3.14c.95-2.85 3.6-4.96 6.72-4.96Z"/>
</svg>
''';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    this.authService,
    this.accountController,
    this.onSendPasswordReset,
    this.onSignIn,
    this.onSignUp,
    this.onSignInWithGoogle,
    this.onSignInWithApple,
    this.showAppleSignIn,
    super.key,
  });

  final AuthService? authService;
  final AccountController? accountController;
  final Future<void> Function(String email)? onSendPasswordReset;
  final Future<void> Function(String email, String password)? onSignIn;
  final Future<void> Function(String email, String password)? onSignUp;
  final Future<void> Function()? onSignInWithGoogle;
  final Future<void> Function()? onSignInWithApple;
  final bool? showAppleSignIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static final RegExp _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _rememberMe = true;
  bool _obscurePassword = true;
  bool _createAccountMode = false;
  bool _busy = false;
  String _passwordDraft = '';

  AuthService get _auth => widget.authService ?? AuthService.instance;
  AccountController get _account =>
      widget.accountController ?? AccountController.instance;

  bool get _appleSupported =>
      widget.showAppleSignIn ??
      (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS));

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    UIUtils.showSnackBar(context, message, tone: AppSnackBarTone.error);
  }

  void _showInfo(String message) {
    if (!mounted) return;
    UIUtils.showSnackBar(context, message, tone: AppSnackBarTone.success);
  }

  String? _validateEmail(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) {
      return 'Adresse e-mail requise.';
    }
    if (!_emailRegex.hasMatch(trimmed)) {
      return 'Veuillez saisir une adresse e-mail valide.';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final raw = value ?? '';
    if (raw.isEmpty) {
      return 'Mot de passe requis.';
    }
    if (_createAccountMode && raw.length < 6) {
      return 'Au moins 6 caractères requis.';
    }
    return null;
  }

  ({String label, double progress, Color color}) _passwordStrength(String pwd) {
    if (pwd.isEmpty) {
      return (label: '', progress: 0.0, color: LKColors.border);
    }
    var score = 0;
    if (pwd.length >= 6) score++;
    if (pwd.length >= 10) score++;
    if (RegExp(r'[A-Z]').hasMatch(pwd) && RegExp(r'[0-9]').hasMatch(pwd)) {
      score++;
    }
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(pwd)) score++;

    if (score <= 1) {
      return (label: 'Faible', progress: 0.33, color: LKColors.danger);
    }
    if (score == 2) {
      return (label: 'Correct', progress: 0.66, color: LKColors.warning);
    }
    return (label: 'Robuste', progress: 1.0, color: LKColors.success);
  }

  Future<void> _submit() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    setState(() => _busy = true);
    try {
      await _auth.setRememberMe(_rememberMe);
      if (_createAccountMode) {
        if (widget.onSignUp != null) {
          await widget.onSignUp!(email, password);
        } else {
          await _auth.signUp(email: email, password: password);
        }
        _showInfo(
          'Compte créé. Un e-mail de vérification vient d\'être envoyé.',
        );
      } else {
        if (widget.onSignIn != null) {
          await widget.onSignIn!(email, password);
        } else {
          await _auth.signIn(email: email, password: password);
        }
      }
      await _account.refresh();
      if (!mounted) return;
      _navigateAfterAuth();
    } catch (error) {
      // Ne jamais journaliser le mot de passe ni le token.
      _showError(AuthService.messageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openForgotPasswordDialog() async {
    final sentTo = await showDialog<String>(
      context: context,
      builder: (_) => _ForgotPasswordDialog(
        initialEmail: _emailCtrl.text.trim(),
        validator: _validateEmail,
        onSendReset: (targetEmail) async {
          if (widget.onSendPasswordReset != null) {
            await widget.onSendPasswordReset!(targetEmail);
          } else {
            await _auth.sendPasswordResetEmail(targetEmail);
          }
        },
        onError: _showError,
      ),
    );
    if (sentTo != null && sentTo.isNotEmpty) {
      _showInfo('E-mail de réinitialisation envoyé à $sentTo.');
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _busy = true);
    try {
      await _auth.setRememberMe(_rememberMe);
      if (widget.onSignInWithGoogle != null) {
        await widget.onSignInWithGoogle!();
      } else {
        await _auth.signInWithGoogle();
      }
      await _account.refresh();
      if (!mounted) return;
      _navigateAfterAuth();
    } catch (error) {
      if (AuthService.isCancellation(error)) return;
      _showError(AuthService.messageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithApple() async {
    setState(() => _busy = true);
    try {
      await _auth.setRememberMe(_rememberMe);
      if (widget.onSignInWithApple != null) {
        await widget.onSignInWithApple!();
      } else {
        await _auth.signInWithApple();
      }
      await _account.refresh();
      if (!mounted) return;
      _navigateAfterAuth();
    } catch (error) {
      if (AuthService.isCancellation(error)) return;
      _showError(AuthService.messageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _navigateAfterAuth() {
    final pendingInvite = _account.pendingInviteToken;
    if (pendingInvite != null && pendingInvite.isNotEmpty) {
      context.go('/invite/${Uri.encodeComponent(pendingInvite)}');
      return;
    }
    if (_account.needsOnboarding) {
      context.go('/onboarding');
    } else {
      context.go('/rooms');
    }
  }

  @override
  Widget build(BuildContext context) {
    final strength = _passwordStrength(_passwordDraft);

    return Scaffold(
      backgroundColor: LKColors.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              LKColors.background,
              LKColors.surfaceElevated,
              LKColors.surfaceElevated,
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: UIUtils.paddingLG,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Logo Section
                        AnimatedContainer(
                          duration: UIUtils.animationDuration,
                          padding: UIUtils.paddingXXL,
                          decoration: BoxDecoration(
                            borderRadius: UIUtils.borderRadiusAllXL,
                            border: Border.all(
                              color: LKColors.border,
                              width: 0.5,
                            ),
                            color: Colors.white.withValues(alpha: 0.03),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 76,
                                height: 64,
                                decoration: BoxDecoration(
                                  borderRadius: UIUtils.borderRadiusAllLG,
                                  color: LKColors.primary.withValues(
                                    alpha: 0.10,
                                  ),
                                ),
                                padding: const EdgeInsets.all(8),
                                child: Image.asset(
                                  'images/v.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                              SizedBox(width: UIUtils.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Videolog Sport',
                                      style: UIUtils.titleLarge(context)
                                          .copyWith(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    SizedBox(height: UIUtils.xs),
                                    Text(
                                      'Performance · Coaching · Live',
                                      style: UIUtils.bodySmall(
                                        context,
                                      ).copyWith(color: LKColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: UIUtils.xxl),

                        // Login Card
                        Card(
                          color: LKColors.surfaceElevated,
                          surfaceTintColor: Colors.transparent,
                          elevation: 0,
                          margin: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: UIUtils.borderRadiusAllXL,
                            side: const BorderSide(
                              color: LKColors.border,
                              width: 0.5,
                            ),
                          ),
                          child: Padding(
                            padding: UIUtils.paddingXXL,
                            child: Form(
                              key: _formKey,
                              autovalidateMode:
                                  AutovalidateMode.onUserInteraction,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _createAccountMode
                                        ? 'Créer un compte'
                                        : 'Connexion',
                                    style: UIUtils.titleLarge(context).copyWith(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: UIUtils.xxl),

                                  // Email & Password Fields (with Autofill)
                                  AutofillGroup(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        TextFormField(
                                          controller: _emailCtrl,
                                          keyboardType:
                                              TextInputType.emailAddress,
                                          textInputAction: TextInputAction.next,
                                          autofillHints: const [
                                            AutofillHints.email,
                                            AutofillHints.username,
                                          ],
                                          validator: _validateEmail,
                                          decoration: UIUtils.inputDecoration(
                                            labelText: 'Email',
                                            hintText: 'athlete@videolog.app',
                                            prefixIcon:
                                                Icons.mail_outline_rounded,
                                          ),
                                          style: UIUtils.bodyLarge(context),
                                          cursorColor: LKColors.primary,
                                        ),
                                        SizedBox(height: UIUtils.md),

                                        TextFormField(
                                          controller: _passwordCtrl,
                                          obscureText: _obscurePassword,
                                          textInputAction: TextInputAction.done,
                                          autofillHints: [
                                            _createAccountMode
                                                ? AutofillHints.newPassword
                                                : AutofillHints.password,
                                          ],
                                          validator: _validatePassword,
                                          onChanged: (value) => setState(
                                            () => _passwordDraft = value,
                                          ),
                                          onFieldSubmitted: (_) {
                                            if (!_busy) _submit();
                                          },
                                          decoration: UIUtils.inputDecoration(
                                            labelText: 'Mot de passe',
                                            hintText:
                                                'Entrez votre mot de passe',
                                            prefixIcon:
                                                Icons.lock_outline_rounded,
                                            suffixIcon: _obscurePassword
                                                ? Icons.visibility_outlined
                                                : Icons.visibility_off_outlined,
                                            suffixTooltip: _obscurePassword
                                                ? 'Afficher le mot de passe'
                                                : 'Masquer le mot de passe',
                                            onSuffixIconTap: () => setState(
                                              () => _obscurePassword =
                                                  !_obscurePassword,
                                            ),
                                          ),
                                          style: UIUtils.bodyLarge(context),
                                          cursorColor: LKColors.primary,
                                        ),
                                      ],
                                    ),
                                  ),

                                  if (_createAccountMode &&
                                      _passwordDraft.isNotEmpty) ...[
                                    SizedBox(height: UIUtils.sm),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(999),
                                            child: LinearProgressIndicator(
                                              value: strength.progress,
                                              minHeight: 5,
                                              backgroundColor: LKColors.border,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    strength.color,
                                                  ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: UIUtils.sm),
                                        Text(
                                          strength.label,
                                          style: UIUtils.bodySmall(context)
                                              .copyWith(
                                                color: strength.color,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 11,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ],

                                  if (!_createAccountMode) ...[
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed: _busy
                                            ? null
                                            : _openForgotPasswordDialog,
                                        child: const Text(
                                          'Mot de passe oublié ?',
                                        ),
                                      ),
                                    ),
                                  ] else
                                    SizedBox(height: UIUtils.sm),

                                  // Remember Me Checkbox
                                  AnimatedContainer(
                                    duration: UIUtils.animationDuration,
                                    decoration: BoxDecoration(
                                      borderRadius: UIUtils.borderRadiusAllSM,
                                      border: Border.all(
                                        color: LKColors.border,
                                        width: 0.3,
                                      ),
                                    ),
                                    child: CheckboxListTile(
                                      value: _rememberMe,
                                      contentPadding: UIUtils
                                          .paddingHorizontalMD
                                          .add(UIUtils.paddingVerticalSM),
                                      title: Text(
                                        'Se souvenir de moi',
                                        style: UIUtils.bodySmall(context),
                                      ),
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                      activeColor: LKColors.primary,
                                      checkboxShape: RoundedRectangleBorder(
                                        borderRadius: UIUtils.borderRadiusAllSM,
                                      ),
                                      side: const BorderSide(
                                        color: LKColors.border,
                                        width: 0.5,
                                      ),
                                      onChanged: (value) => setState(
                                        () => _rememberMe = value ?? true,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: UIUtils.xxl),

                                  // Login / SignUp Button
                                  FilledButton.icon(
                                    onPressed: _busy ? null : _submit,
                                    icon: _busy
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Icon(
                                            _createAccountMode
                                                ? Icons.person_add_rounded
                                                : Icons.login_rounded,
                                            size: 20,
                                          ),
                                    label: Text(
                                      _busy
                                          ? 'Connexion…'
                                          : (_createAccountMode
                                                ? 'Créer mon compte'
                                                : 'Se connecter'),
                                      style: UIUtils.labelLarge(
                                        context,
                                      ).copyWith(color: Colors.white),
                                    ),
                                  ),
                                  SizedBox(height: UIUtils.md),

                                  Row(
                                    children: [
                                      const Expanded(
                                        child: Divider(
                                          color: LKColors.border,
                                          thickness: 0.8,
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        child: Text(
                                          'OU',
                                          style: UIUtils.bodySmall(context)
                                              .copyWith(
                                                color: LKColors.textSecondary,
                                              ),
                                        ),
                                      ),
                                      const Expanded(
                                        child: Divider(
                                          color: LKColors.border,
                                          thickness: 0.8,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: UIUtils.md),

                                  OutlinedButton.icon(
                                    onPressed:
                                        _busy ? null : _signInWithGoogle,
                                    icon: SvgPicture.string(
                                      _googleLogoSvg,
                                      width: 20,
                                      height: 20,
                                    ),
                                    label: Text(
                                      'Continuer avec Google',
                                      style: UIUtils.labelLarge(context),
                                    ),
                                  ),

                                  if (_appleSupported) ...[
                                    SizedBox(height: UIUtils.sm),
                                    OutlinedButton.icon(
                                      onPressed:
                                          _busy ? null : _signInWithApple,
                                      icon: const Icon(
                                        Icons.apple_rounded,
                                        size: 22,
                                        color: LKColors.textPrimary,
                                      ),
                                      label: Text(
                                        'Continuer avec Apple',
                                        style: UIUtils.labelLarge(context),
                                      ),
                                    ),
                                  ],

                                  SizedBox(height: UIUtils.md),

                                  Wrap(
                                    alignment: WrapAlignment.spaceBetween,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      TextButton(
                                        onPressed: _busy
                                            ? null
                                            : () => setState(() {
                                                _createAccountMode =
                                                    !_createAccountMode;
                                              }),
                                        child: Text(
                                          _createAccountMode
                                              ? 'Déjà un compte ?'
                                              : 'Créer un compte',
                                        ),
                                      ),
                                      TextButton.icon(
                                        onPressed: _busy
                                            ? null
                                            : () => context.push(
                                                '/invite/manual',
                                              ),
                                        icon: const Icon(
                                          Icons.mail_outline_rounded,
                                          size: 16,
                                        ),
                                        label: const Text(
                                          'J\'ai une invitation',
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: UIUtils.sm),

                                  if (AppConfig.isLocal) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: LKColors.warning.withValues(
                                          alpha: 0.14,
                                        ),
                                        borderRadius: UIUtils.borderRadiusAllMD,
                                        border: Border.all(
                                          color: LKColors.warning.withValues(
                                            alpha: 0.4,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        'LOCAL · ${AppConfig.apiBaseUrl}',
                                        style: UIUtils.bodySmall(context)
                                            .copyWith(
                                              color: LKColors.warning,
                                              fontWeight: FontWeight.w600,
                                            ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    SizedBox(height: UIUtils.sm),
                                  ],

                                  // Footer Text
                                  Text(
                                    'Videolog © 2026 · Tous droits réservés',
                                    style: UIUtils.bodySmall(
                                      context,
                                    ).copyWith(color: LKColors.textHint),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog({
    required this.initialEmail,
    required this.validator,
    required this.onSendReset,
    required this.onError,
  });

  final String initialEmail;
  final String? Function(String?) validator;
  final Future<void> Function(String email) onSendReset;
  final void Function(String message) onError;

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailCtrl;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _sending = true);
    final targetEmail = _emailCtrl.text.trim();
    try {
      await widget.onSendReset(targetEmail);
      if (!mounted) return;
      Navigator.of(context).pop(targetEmail);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      widget.onError(AuthService.messageFor(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Réinitialiser le mot de passe'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Saisissez votre adresse e-mail pour recevoir un lien de réinitialisation.',
              style: UIUtils.bodySmall(context),
            ),
            SizedBox(height: UIUtils.md),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              validator: widget.validator,
              decoration: UIUtils.inputDecoration(
                labelText: 'Email',
                hintText: 'athlete@videolog.app',
                prefixIcon: Icons.mail_outline_rounded,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _sending ? null : _submit,
          child: Text(_sending ? 'Envoi…' : 'Envoyer le lien'),
        ),
      ],
    );
  }
}
