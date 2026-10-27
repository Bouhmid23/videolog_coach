import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth_service.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _rememberMe = true;
  bool _obscurePassword = true;
  bool _busy = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: UIUtils.bodySmall(context)),
        backgroundColor: LKColors.danger,
        behavior: SnackBarBehavior.floating,
        margin: UIUtils.paddingLG,
        elevation: 4,
      ),
    );
  }

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      _showError('Veuillez remplir email et mot de passe.');
      return;
    }

    setState(() => _busy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('remember_me', _rememberMe);
      await AuthService.instance.signIn(email: email, password: password);
      if (mounted) context.go('/rooms');
    } catch (error) {
      // Ne jamais journaliser le mot de passe ni le token.
      _showError(AuthService.messageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LKColors.background,
      body: Container(
        decoration: BoxDecoration(
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
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  borderRadius: UIUtils.borderRadiusAllLG,
                                  color: LKColors.primary.withValues(
                                    alpha: 0.15,
                                  ),
                                ),
                                padding: UIUtils.paddingMD,
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
                            side: BorderSide(
                              color: LKColors.border,
                              width: 0.5,
                            ),
                          ),
                          child: Padding(
                            padding: UIUtils.paddingXXL,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Connexion',
                                  style: UIUtils.titleLarge(context).copyWith(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(height: UIUtils.xs),
                                Text(
                                  'Connectez-vous avec votre compte Firebase.',
                                  style: UIUtils.bodySmall(
                                    context,
                                  ).copyWith(color: LKColors.textHint),
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(height: UIUtils.xxl),

                                // Email Field
                                TextField(
                                  controller: _emailCtrl,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: UIUtils.inputDecoration(
                                    labelText: 'Email',
                                    hintText: 'athlete@videolog.app',
                                    prefixIcon: Icons.mail_outline_rounded,
                                  ),
                                  style: UIUtils.bodyLarge(context),
                                  cursorColor: LKColors.primary,
                                ),
                                SizedBox(height: UIUtils.md),

                                // Password Field
                                TextField(
                                  controller: _passwordCtrl,
                                  obscureText: _obscurePassword,
                                  decoration: UIUtils.inputDecoration(
                                    labelText: 'Mot de passe',
                                    hintText: 'Entrez votre mot de passe',
                                    prefixIcon: Icons.lock_outline_rounded,
                                    suffixIcon: _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    suffix: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                        color: LKColors.textSecondary,
                                        size: 20,
                                      ),
                                      onPressed: () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                                      padding: EdgeInsets.zero,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                  style: UIUtils.bodyLarge(context),
                                  cursorColor: LKColors.primary,
                                ),
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
                                    contentPadding: UIUtils.paddingHorizontalMD
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
                                    side: BorderSide(
                                      color: LKColors.border,
                                      width: 0.5,
                                    ),
                                    onChanged: (value) => setState(
                                      () => _rememberMe = value ?? true,
                                    ),
                                  ),
                                ),
                                SizedBox(height: UIUtils.xxl),

                                // Login Button
                                FilledButton.icon(
                                  onPressed: _busy ? null : _login,
                                  icon: _busy
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.login_rounded,
                                          size: 20,
                                        ),
                                  label: Text(
                                    _busy ? 'Connexion…' : 'Se connecter',
                                    style: UIUtils.labelLarge(
                                      context,
                                    ).copyWith(color: Colors.white),
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: LKColors.primary,
                                    foregroundColor: Colors.white,
                                    padding: UIUtils.paddingVerticalLG.add(
                                      UIUtils.paddingHorizontalXXL,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: UIUtils.borderRadiusAllMD,
                                    ),
                                    elevation: 0,
                                    shadowColor: Colors.transparent,
                                  ),
                                ),
                                SizedBox(height: UIUtils.md),

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
