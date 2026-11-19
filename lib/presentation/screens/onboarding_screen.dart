import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/account_controller.dart';
import '../../core/api_service.dart';
import '../../core/auth_service.dart';
import '../../data/account_models.dart';
import '../../data/directory_models.dart';
import '../../exts.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';
import '../widgets/pending_invitations_card.dart';
import 'directory_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    this.apiService,
    this.accountController,
    this.emailVerifiedOverride,
    super.key,
  });

  final ApiService? apiService;
  final AccountController? accountController;
  final bool? emailVerifiedOverride;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _orgNameCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  int _stepIndex = 0; // 0: Structure & Identité, 1: Ville, Disciplines & Validation
  String _accountType = 'club'; // 'club' | 'solo_coach'
  final Set<String> _selectedSports = {'cyclisme'};
  bool _ageConfirmed = false;
  bool _submitting = false;
  String? _error;
  List<InAppInvitation> _pendingInvitations = const [];
  List<MyJoinRequest> _pendingJoinRequests = const [];
  List<SportMeta> _sportsCatalog = const [];

  ApiService get _api => widget.apiService ?? ApiService.instance;
  AccountController get _account =>
      widget.accountController ?? AccountController.instance;

  bool get _hasUnsavedChanges =>
      _orgNameCtrl.text.trim().isNotEmpty ||
      _cityCtrl.text.trim().isNotEmpty ||
      _phoneCtrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    final user = _account.me?.user;
    if (user != null) {
      _firstNameCtrl.text = user.firstName ?? '';
      _lastNameCtrl.text = user.lastName ?? '';
      _phoneCtrl.text = user.phone ?? '';
    }
    unawaited(_loadPendingInvitations());
    unawaited(_loadPendingJoinRequests());
    unawaited(_loadSportsCatalog());
  }

  Future<void> _loadPendingInvitations() async {
    try {
      final list = await _api.fetchMyInvitations();
      if (!mounted) return;
      setState(() => _pendingInvitations = list);
    } catch (_) {
      // Silencieux : l'utilisateur peut toujours explorer l'annuaire ou créer son espace.
    }
  }

  Future<void> _loadPendingJoinRequests() async {
    try {
      final list = await _api.fetchMyJoinRequests(status: 'pending');
      if (!mounted) return;
      setState(() => _pendingJoinRequests = list);
    } catch (_) {
      // Silencieux.
    }
  }

  Future<void> _loadSportsCatalog() async {
    try {
      final list = await _api.fetchSports();
      if (!mounted) return;
      setState(() => _sportsCatalog = list);
    } catch (_) {
      // Fallback sur kSupportedSports.
    }
  }

  Future<void> _openDirectory({int initialTabIndex = 0}) async {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      await context.push(
        initialTabIndex == 1 ? '/directory?tab=requests' : '/directory',
      );
    } else {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => DirectoryScreen(
            initialTabIndex: initialTabIndex,
            apiService: _api,
            accountController: _account,
            emailVerifiedOverride: widget.emailVerifiedOverride,
          ),
        ),
      );
    }
    if (mounted) {
      unawaited(_loadPendingJoinRequests());
    }
  }

  @override
  void dispose() {
    _orgNameCtrl.dispose();
    _cityCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _nextStep() {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;
    setState(() {
      _error = null;
      _stepIndex = 1;
    });
  }

  Future<void> _submit() async {
    final isVerified = widget.emailVerifiedOverride ?? _account.isEmailVerified;
    if (!isVerified) {
      context.push('/verify-email');
      return;
    }

    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    final orgName = _orgNameCtrl.text.trim();
    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();

    if (!_ageConfirmed) {
      setState(
        () => _error = 'Vous devez confirmer avoir au moins $kMinAgeYears ans.',
      );
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await _api.submitOnboarding(
        accountType: _accountType,
        organizationName: orgName,
        sports: _selectedSports.toList(),
        city: _cityCtrl.text.trim(),
        firstName: firstName,
        lastName: lastName,
        phone: _phoneCtrl.text.trim(),
        ageConfirmed: true,
      );
      await _account.refresh();
      if (!mounted) return;
      context.go('/rooms');
    } on ApiException catch (e) {
      if (e.isForbidden && !isVerified) {
        if (!mounted) return;
        context.push('/verify-email');
        return;
      }
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _submitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossible de finaliser la création de votre espace.';
        _submitting = false;
      });
    }
  }

  Future<void> _handleBackWithUnsavedCheck() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Abandonner la configuration ?'),
        content: const Text(
          'Les informations saisies pour votre espace seront perdues.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(false),
            child: const Text('Rester'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: LKColors.danger),
            onPressed: () => Navigator.of(dCtx).pop(true),
            child: const Text('Quitter'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      if (_stepIndex > 0) {
        setState(() => _stepIndex = 0);
      } else {
        Navigator.of(context).maybePop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final emailVerified =
        widget.emailVerifiedOverride ?? _account.isEmailVerified;

    return PopScope(
      canPop: (!_hasUnsavedChanges && _stepIndex == 0) || _submitting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_stepIndex > 0 && !_submitting) {
          setState(() => _stepIndex = 0);
          return;
        }
        unawaited(_handleBackWithUnsavedCheck());
      },
      child: Scaffold(
        backgroundColor: LKColors.background,
        appBar: AppBar(
          backgroundColor: LKColors.surface,
          title: const Text('Configurer votre espace'),
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
          child: SingleChildScrollView(
            padding: UIUtils.paddingLG,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!emailVerified) ...[
                      Container(
                        padding: UIUtils.paddingLG,
                        decoration: BoxDecoration(
                          color: LKColors.warning.withValues(alpha: 0.12),
                          borderRadius: UIUtils.borderRadiusAllLG,
                          border: Border.all(
                            color: LKColors.warning.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Vérification d\'e-mail requise',
                              style: UIUtils.titleSmall(context).copyWith(
                                color: LKColors.warning,
                              ),
                            ),
                            SizedBox(height: UIUtils.xs),
                            Text(
                              'Validez votre adresse e-mail avant de créer votre club/espace coach.',
                              style: UIUtils.bodySmall(context),
                            ),
                            SizedBox(height: UIUtils.md),
                            FilledButton.icon(
                              onPressed: () => context.push('/verify-email'),
                              icon: const Icon(
                                Icons.mark_email_read_rounded,
                                size: 18,
                              ),
                              label: const Text('Vérifier mon e-mail'),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: UIUtils.lg),
                    ],

                    if (_pendingInvitations.isNotEmpty) ...[
                      PendingInvitationsCard(
                        invitations: _pendingInvitations,
                        onInvitationHandled: ({
                          required bool accepted,
                          required InAppInvitation invitation,
                        }) async {
                          if (!mounted) return;
                          setState(() {
                            _pendingInvitations = _pendingInvitations
                                .where((i) => i.id != invitation.id)
                                .toList();
                          });
                        },
                      ),
                      SizedBox(height: UIUtils.lg),
                    ],

                    // Bannière annuaire & invitation (parcours athlète non bloquant)
                    Container(
                      padding: UIUtils.paddingMD,
                      decoration: BoxDecoration(
                        color: LKColors.surfaceElevated,
                        borderRadius: UIUtils.borderRadiusAllLG,
                        border: Border.all(
                          color: LKColors.primary.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.explore_rounded,
                                color: LKColors.primary,
                              ),
                              SizedBox(width: UIUtils.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Rejoindre un club ou un coach',
                                      style: UIUtils.titleSmall(context),
                                    ),
                                    Text(
                                      'Annuaire public ou code d\'invitation.',
                                      style: UIUtils.bodySmall(context),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(width: UIUtils.sm),
                              OutlinedButton(
                                onPressed: () => context.push('/invite/manual'),
                                child: const Text('Code'),
                              ),
                              SizedBox(width: UIUtils.xs),
                              FilledButton(
                                onPressed: () => _openDirectory(),
                                child: const Text('Explorer'),
                              ),
                            ],
                          ),
                          if (_pendingJoinRequests.isNotEmpty) ...[
                            SizedBox(height: UIUtils.xs),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () =>
                                    _openDirectory(initialTabIndex: 1),
                                icon: const Icon(
                                  Icons.hourglass_top_rounded,
                                  size: 16,
                                ),
                                label: Text(
                                  '${_pendingJoinRequests.length} demande${_pendingJoinRequests.length > 1 ? 's' : ''} en attente · Voir le suivi',
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(height: UIUtils.lg),

                    Card(
                      color: LKColors.surfaceElevated,
                      shape: RoundedRectangleBorder(
                        borderRadius: UIUtils.borderRadiusAllXL,
                        side: const BorderSide(color: LKColors.border),
                      ),
                      child: Padding(
                        padding: UIUtils.paddingXXL,
                        child: Form(
                          key: _formKey,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Créer votre espace',
                                      style: UIUtils.titleLarge(context),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: LKColors.primary.withValues(
                                        alpha: 0.14,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      'Étape ${_stepIndex + 1} / 2',
                                      style: UIUtils.bodySmall(context)
                                          .copyWith(
                                            color: LKColors.primary,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 11,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: UIUtils.sm),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: (_stepIndex + 1) / 2,
                                  minHeight: 4,
                                  backgroundColor: LKColors.border,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                        LKColors.primary,
                                      ),
                                ),
                              ),
                              SizedBox(height: UIUtils.md),
                              Text(
                                _stepIndex == 0
                                    ? 'Structure et identité du responsable.'
                                    : 'Localisation, disciplines et confirmation.',
                                style: UIUtils.bodySmall(context),
                              ),
                              SizedBox(height: UIUtils.lg),

                              if (_stepIndex == 0) ...[
                                SegmentedButton<String>(
                                  segments: const [
                                    ButtonSegment(
                                      value: 'club',
                                      label: Text('Club / Structure'),
                                      icon: Icon(Icons.groups_rounded),
                                    ),
                                    ButtonSegment(
                                      value: 'solo_coach',
                                      label: Text('Coach privé'),
                                      icon: Icon(Icons.person_rounded),
                                    ),
                                  ],
                                  selected: {_accountType},
                                  onSelectionChanged: (s) =>
                                      setState(() => _accountType = s.first),
                                ),
                                SizedBox(height: UIUtils.lg),

                                TextFormField(
                                  controller: _orgNameCtrl,
                                  textInputAction: TextInputAction.next,
                                  validator: (v) {
                                    if ((v ?? '').trim().length < 2) {
                                      return 'Au moins 2 caractères requis.';
                                    }
                                    return null;
                                  },
                                  decoration: UIUtils.inputDecoration(
                                    labelText: _accountType == 'club'
                                        ? 'Nom du club / organisation *'
                                        : 'Nom de votre activité coach *',
                                    prefixIcon: Icons.apartment_rounded,
                                  ),
                                ),
                                SizedBox(height: UIUtils.md),

                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _firstNameCtrl,
                                        textInputAction: TextInputAction.next,
                                        validator: (v) {
                                          if ((v ?? '').trim().isEmpty) {
                                            return 'Prénom requis.';
                                          }
                                          return null;
                                        },
                                        decoration: UIUtils.inputDecoration(
                                          labelText: 'Prénom *',
                                          prefixIcon:
                                              Icons.person_outline_rounded,
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: UIUtils.md),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _lastNameCtrl,
                                        textInputAction: TextInputAction.done,
                                        onFieldSubmitted: (_) => _nextStep(),
                                        validator: (v) {
                                          if ((v ?? '').trim().isEmpty) {
                                            return 'Nom requis.';
                                          }
                                          return null;
                                        },
                                        decoration: UIUtils.inputDecoration(
                                          labelText: 'Nom *',
                                          prefixIcon: Icons.badge_outlined,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: UIUtils.xl),

                                FilledButton.icon(
                                  onPressed: _nextStep,
                                  icon: const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Continuer'),
                                ),
                              ] else ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _cityCtrl,
                                        textInputAction: TextInputAction.next,
                                        decoration: UIUtils.inputDecoration(
                                          labelText: 'Ville',
                                          prefixIcon:
                                              Icons.location_city_rounded,
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: UIUtils.md),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _phoneCtrl,
                                        keyboardType: TextInputType.phone,
                                        textInputAction: TextInputAction.done,
                                        decoration: UIUtils.inputDecoration(
                                          labelText: 'Téléphone',
                                          prefixIcon: Icons.phone_outlined,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: UIUtils.lg),

                                Text(
                                  'Disciplines',
                                  style: UIUtils.labelLarge(context),
                                ),
                                SizedBox(height: UIUtils.sm),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: (_sportsCatalog.isNotEmpty
                                          ? _sportsCatalog
                                              .map((s) => (s.code, s.label))
                                              .toList()
                                          : kSupportedSports
                                              .map((s) => (s, s))
                                              .toList())
                                      .map((entry) {
                                    final (code, label) = entry;
                                    final selected =
                                        _selectedSports.contains(code);
                                    return FilterChip(
                                      label: Text(label),
                                      selected: selected,
                                      selectedColor: LKColors.primary
                                          .withValues(alpha: 0.22),
                                      checkmarkColor: LKColors.primary,
                                      onSelected: (on) {
                                        setState(() {
                                          if (on) {
                                            _selectedSports.add(code);
                                          } else if (_selectedSports.length >
                                              1) {
                                            _selectedSports.remove(code);
                                          }
                                        });
                                      },
                                    );
                                  }).toList(),
                                ),
                                SizedBox(height: UIUtils.md),

                                CheckboxListTile(
                                  value: _ageConfirmed,
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  title: Text(
                                    'Je confirme avoir au moins $kMinAgeYears ans',
                                    style: UIUtils.bodySmall(context),
                                  ),
                                  onChanged: (v) => setState(
                                    () => _ageConfirmed = v ?? false,
                                  ),
                                ),

                                if (_error != null) ...[
                                  SizedBox(height: UIUtils.sm),
                                  Text(
                                    _error!,
                                    style: UIUtils.bodySmall(
                                      context,
                                    ).copyWith(color: LKColors.danger),
                                  ),
                                ],
                                SizedBox(height: UIUtils.lg),

                                Row(
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: _submitting
                                          ? null
                                          : () =>
                                              setState(() => _stepIndex = 0),
                                      icon: const Icon(
                                        Icons.arrow_back_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Retour'),
                                    ),
                                    SizedBox(width: UIUtils.md),
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed:
                                            _submitting ? null : _submit,
                                        icon: _submitting
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : const Icon(
                                                Icons.rocket_launch_rounded,
                                                size: 18,
                                              ),
                                        label: Text(
                                          _submitting
                                              ? 'Création…'
                                              : 'Créer mon espace',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
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
    );
  }
}
