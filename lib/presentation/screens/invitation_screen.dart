import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/account_controller.dart';
import '../../core/api_service.dart';
import '../../core/auth_service.dart';
import '../../data/account_models.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';

class InvitationScreen extends StatefulWidget {
  const InvitationScreen({required this.initialToken, super.key});

  final String initialToken;

  @override
  State<InvitationScreen> createState() => _InvitationScreenState();
}

class _InvitationScreenState extends State<InvitationScreen> {
  final _tokenCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();

  String _activeToken = '';
  InvitationPreview? _preview;
  bool _loadingPreview = false;
  bool _accepting = false;
  bool _ageConfirmed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = AccountController.instance.me?.user;
    if (user != null) {
      _firstNameCtrl.text = user.firstName ?? '';
      _lastNameCtrl.text = user.lastName ?? '';
    }
    final extracted = widget.initialToken == 'manual'
        ? ''
        : (AccountController.extractInviteToken(widget.initialToken) ??
              widget.initialToken);
    _activeToken = extracted;
    _tokenCtrl.text = extracted;
    if (extracted.isNotEmpty) {
      _loadPreview(extracted);
    }
  }

  @override
  void didUpdateWidget(covariant InvitationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialToken != widget.initialToken) {
      final extracted = widget.initialToken == 'manual'
          ? ''
          : (AccountController.extractInviteToken(widget.initialToken) ??
                widget.initialToken);
      if (extracted.isNotEmpty && extracted != _activeToken) {
        _activeToken = extracted;
        _tokenCtrl.text = extracted;
        _loadPreview(extracted);
      }
    }
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPreview(String raw) async {
    final token = AccountController.extractInviteToken(raw) ?? raw.trim();
    if (token.isEmpty) {
      setState(() => _error = 'Veuillez coller un lien ou un code d\'invitation valide.');
      return;
    }
    setState(() {
      _activeToken = token;
      _loadingPreview = true;
      _error = null;
      _preview = null;
    });
    try {
      final preview = await ApiService.instance.previewInvitation(token);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _loadingPreview = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loadingPreview = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossible de charger cette invitation.';
        _loadingPreview = false;
      });
    }
  }

  Future<void> _accept() async {
    if (_activeToken.isEmpty) return;
    if (!_ageConfirmed) {
      setState(
        () => _error = 'Vous devez confirmer avoir au moins $kMinAgeYears ans.',
      );
      return;
    }
    setState(() {
      _accepting = true;
      _error = null;
    });
    try {
      await ApiService.instance.acceptInvitation(
        _activeToken,
        firstName: _firstNameCtrl.text.trim(),
        lastName: _lastNameCtrl.text.trim(),
        ageConfirmed: true,
      );
      try {
        await AuthService.instance.reloadAndRefreshToken();
      } catch (_) {}
      AccountController.instance.setPendingInviteToken(null);
      await AccountController.instance.refresh();
      if (!mounted) return;
      context.go('/rooms');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _accepting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossible d\'accepter l\'invitation.';
        _accepting = false;
      });
    }
  }

  void _goToLogin() {
    AccountController.instance.setPendingInviteToken(_activeToken);
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = AuthService.instance.isSignedIn;
    return Scaffold(
      backgroundColor: LKColors.background,
      appBar: AppBar(
        backgroundColor: LKColors.surface,
        title: const Text('Invitation'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            AccountController.instance.setPendingInviteToken(null);
            if (signedIn) {
              context.go(
                AccountController.instance.needsOnboarding
                    ? '/onboarding'
                    : '/rooms',
              );
            } else {
              context.go('/login');
            }
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: UIUtils.paddingLG,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
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
                      Text(
                        'Rejoindre une organisation',
                        style: UIUtils.titleLarge(context),
                      ),
                      SizedBox(height: UIUtils.xs),
                      Text(
                        'Collez votre lien ou code d\'invitation reçu par e-mail.',
                        style: UIUtils.bodySmall(context),
                      ),
                      SizedBox(height: UIUtils.lg),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _tokenCtrl,
                              decoration: UIUtils.inputDecoration(
                                labelText: 'Lien ou code d\'invitation',
                                hintText: 'https://app.videolog.app/invite/...',
                                prefixIcon: Icons.link_rounded,
                                suffixIcon: Icons.content_paste_rounded,
                                suffixTooltip:
                                    'Coller depuis le presse-papiers',
                                onSuffixIconTap: () async {
                                  final data = await Clipboard.getData(
                                    Clipboard.kTextPlain,
                                  );
                                  final pasted = data?.text?.trim() ?? '';
                                  if (pasted.isEmpty) {
                                    if (!mounted) return;
                                    setState(() {
                                      _error =
                                          'Le presse-papiers ne contient aucun code.';
                                    });
                                    return;
                                  }
                                  _tokenCtrl.text = pasted;
                                  await _loadPreview(pasted);
                                },
                              ),
                              onSubmitted: _loadPreview,
                            ),
                          ),
                          SizedBox(width: UIUtils.sm),
                          FilledButton(
                            onPressed: _loadingPreview
                                ? null
                                : () => _loadPreview(_tokenCtrl.text),
                            child: const Text('Vérifier'),
                          ),
                        ],
                      ),
                      if (_loadingPreview) ...[
                        SizedBox(height: UIUtils.xl),
                        const Center(child: CircularProgressIndicator()),
                      ],
                      if (_error != null) ...[
                        SizedBox(height: UIUtils.md),
                        Container(
                          padding: UIUtils.paddingMD,
                          decoration: BoxDecoration(
                            color: LKColors.danger.withValues(alpha: 0.12),
                            borderRadius: UIUtils.borderRadiusAllMD,
                            border: Border.all(
                              color: LKColors.danger.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            _error!,
                            style: UIUtils.bodySmall(
                              context,
                            ).copyWith(color: LKColors.danger),
                          ),
                        ),
                      ],
                      if (_preview != null) ...[
                        SizedBox(height: UIUtils.xl),
                        Container(
                          padding: UIUtils.paddingLG,
                          decoration: BoxDecoration(
                            color: LKColors.surface,
                            borderRadius: UIUtils.borderRadiusAllLG,
                            border: Border.all(
                              color: LKColors.primary.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _preview!.orgName,
                                style: UIUtils.titleMedium(context),
                              ),
                              SizedBox(height: UIUtils.xs),
                              Text(
                                'Rôle proposé : ${_preview!.roleLabel}',
                                style: UIUtils.bodyMedium(context).copyWith(
                                  color: LKColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (_preview!.maskedEmail.isNotEmpty) ...[
                                SizedBox(height: UIUtils.xs),
                                Text(
                                  'Destinataire : ${_preview!.maskedEmail}',
                                  style: UIUtils.bodySmall(context),
                                ),
                              ],
                            ],
                          ),
                        ),
                        SizedBox(height: UIUtils.lg),
                        if (!signedIn) ...[
                          Text(
                            'Connectez-vous ou créez votre compte avec l\'adresse e-mail invitée pour accepter.',
                            style: UIUtils.bodySmall(context),
                          ),
                          SizedBox(height: UIUtils.md),
                          FilledButton.icon(
                            onPressed: _goToLogin,
                            icon: const Icon(Icons.login_rounded, size: 18),
                            label: const Text('Se connecter pour accepter'),
                          ),
                        ] else ...[
                          TextField(
                            controller: _firstNameCtrl,
                            decoration: UIUtils.inputDecoration(
                              labelText: 'Prénom (optionnel)',
                              prefixIcon: Icons.person_outline_rounded,
                            ),
                          ),
                          SizedBox(height: UIUtils.md),
                          TextField(
                            controller: _lastNameCtrl,
                            decoration: UIUtils.inputDecoration(
                              labelText: 'Nom (optionnel)',
                              prefixIcon: Icons.badge_outlined,
                            ),
                          ),
                          SizedBox(height: UIUtils.md),
                          CheckboxListTile(
                            value: _ageConfirmed,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(
                              'Je confirme avoir au moins $kMinAgeYears ans',
                              style: UIUtils.bodySmall(context),
                            ),
                            onChanged: (v) =>
                                setState(() => _ageConfirmed = v ?? false),
                          ),
                          SizedBox(height: UIUtils.md),
                          FilledButton.icon(
                            onPressed: _accepting ? null : _accept,
                            icon: _accepting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check_circle_outline),
                            label: Text(
                              _accepting
                                  ? 'Validation…'
                                  : 'Accepter l\'invitation',
                            ),
                          ),
                        ],
                      ],
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
