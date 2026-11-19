import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/account_controller.dart';
import '../../core/auth_service.dart';
import '../../exts.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({
    this.email,
    this.onReloadAndRefresh,
    this.onSendEmailVerification,
    this.onVerifiedNavigation,
    this.initialCooldownSeconds = 0,
    super.key,
  });

  final String? email;
  final Future<bool> Function()? onReloadAndRefresh;
  final Future<void> Function()? onSendEmailVerification;
  final VoidCallback? onVerifiedNavigation;
  final int initialCooldownSeconds;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen>
    with WidgetsBindingObserver {
  static const int _defaultCooldownSeconds = 60;

  bool _checking = false;
  bool _resending = false;
  String? _statusMessage;
  bool _isError = false;
  late int _resendCooldownSeconds = widget.initialCooldownSeconds;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_resendCooldownSeconds > 0) {
      _startCooldownTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cooldownTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_checking) {
      unawaited(_checkVerified(silent: true));
    }
  }

  void _startCooldownTimer([int? seconds]) {
    _cooldownTimer?.cancel();
    setState(() {
      _resendCooldownSeconds = seconds ?? _defaultCooldownSeconds;
    });
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCooldownSeconds <= 1) {
        timer.cancel();
        setState(() => _resendCooldownSeconds = 0);
      } else {
        setState(() => _resendCooldownSeconds -= 1);
      }
    });
  }

  Future<void> _checkVerified({bool silent = false}) async {
    if (_checking) return;
    setState(() {
      _checking = true;
      if (!silent) {
        _statusMessage = null;
        _isError = false;
      }
    });
    try {
      final bool verified;
      if (widget.onReloadAndRefresh != null) {
        verified = await widget.onReloadAndRefresh!();
      } else {
        verified = await AuthService.instance.reloadAndRefreshToken();
        await AccountController.instance.refresh();
      }
      if (!mounted) return;
      if (verified) {
        if (widget.onVerifiedNavigation != null) {
          widget.onVerifiedNavigation!();
        } else if (AccountController.instance.needsOnboarding) {
          context.go('/onboarding');
        } else {
          context.go('/rooms');
        }
      } else if (!silent) {
        setState(() {
          _statusMessage =
              'Votre adresse e-mail n\'est pas encore vérifiée. Cliquez sur le lien reçu par e-mail puis réessayez.';
          _isError = true;
        });
      }
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _statusMessage = AuthService.messageFor(e);
        _isError = true;
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _resendEmail() async {
    if (_resending || _resendCooldownSeconds > 0) return;
    setState(() {
      _resending = true;
      _statusMessage = null;
      _isError = false;
    });
    try {
      if (widget.onSendEmailVerification != null) {
        await widget.onSendEmailVerification!();
      } else {
        await AuthService.instance.sendEmailVerification();
      }
      if (!mounted) return;
      final address = widget.email ?? AuthService.instance.email;
      setState(() {
        _statusMessage =
            'E-mail de vérification envoyé à ${address ?? 'votre adresse'}.';
        _isError = false;
      });
      _startCooldownTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = AuthService.messageFor(e);
        _isError = true;
      });
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.email ?? AuthService.instance.email ?? '';
    final canResend = !_resending && _resendCooldownSeconds <= 0;

    return Scaffold(
      backgroundColor: LKColors.background,
      appBar: AppBar(
        backgroundColor: LKColors.surface,
        title: const Text('Vérification e-mail'),
        actions: [
          IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: () async {
              final confirmed = await context.showSignOutDialog();
              if (confirmed == true) {
                await AuthService.instance.signOut();
              }
            },
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Se déconnecter',
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: UIUtils.paddingLG,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                color: LKColors.surfaceElevated,
                shape: RoundedRectangleBorder(
                  borderRadius: UIUtils.borderRadiusAllXL,
                  side: const BorderSide(color: LKColors.border),
                ),
                child: Padding(
                  padding: UIUtils.paddingXXL,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: LKColors.primary.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.mark_email_unread_rounded,
                          color: LKColors.primary,
                          size: 32,
                        ),
                      ),
                      SizedBox(height: UIUtils.lg),
                      Text(
                        'Vérifiez votre adresse e-mail',
                        style: UIUtils.titleLarge(context),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: UIUtils.sm),
                      Text(
                        'La validation de votre e-mail${email.isNotEmpty ? ' ($email)' : ''} est requise pour créer votre espace ou enregistrer votre profil sportif.',
                        style: UIUtils.bodyMedium(context),
                        textAlign: TextAlign.center,
                      ),
                      if (_statusMessage != null) ...[
                        SizedBox(height: UIUtils.lg),
                        Container(
                          padding: UIUtils.paddingMD,
                          decoration: BoxDecoration(
                            color: (_isError ? LKColors.danger : LKColors.success)
                                .withValues(alpha: 0.12),
                            borderRadius: UIUtils.borderRadiusAllMD,
                            border: Border.all(
                              color: (_isError
                                      ? LKColors.danger
                                      : LKColors.success)
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            _statusMessage!,
                            style: UIUtils.bodySmall(context).copyWith(
                              color: _isError
                                  ? LKColors.danger
                                  : LKColors.success,
                            ),
                          ),
                        ),
                      ],
                      SizedBox(height: UIUtils.xl),
                      FilledButton.icon(
                        onPressed: _checking ? null : () => _checkVerified(),
                        icon: _checking
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.verified_rounded, size: 18),
                        label: Text(
                          _checking
                              ? 'Vérification…'
                              : 'J\'ai vérifié mon e-mail',
                        ),
                      ),
                      SizedBox(height: UIUtils.md),
                      OutlinedButton.icon(
                        onPressed: canResend ? _resendEmail : null,
                        icon: const Icon(Icons.send_rounded, size: 18),
                        label: Text(
                          _resending
                              ? 'Envoi…'
                              : (_resendCooldownSeconds > 0
                                    ? 'Renvoyer l\'e-mail (${_resendCooldownSeconds}s)'
                                    : 'Renvoyer l\'e-mail de vérification'),
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
    );
  }
}
