import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/account_controller.dart';
import '../../core/api_service.dart';
import '../../core/auth_service.dart';
import '../../data/account_models.dart';
import '../../data/directory_models.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';

/// Résultat renvoyé à la fermeture de [JoinRequestSheet].
class JoinRequestSheetResult {
  const JoinRequestSheetResult({
    this.createdRequest,
    this.shouldRefreshOrg = false,
  });

  final MyJoinRequest? createdRequest;
  final bool shouldRefreshOrg;
}

/// Ouvre le BottomSheet permettant de soumettre une demande d'adhésion
/// (`POST /v1/orgs/{org_id}/join-requests`).
Future<JoinRequestSheetResult?> showJoinRequestSheet(
  BuildContext context, {
  required DirectoryOrganization organization,
  ApiService? apiService,
  AccountController? accountController,
  AuthService? authService,
  bool? emailVerifiedOverride,
}) {
  return showModalBottomSheet<JoinRequestSheetResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => JoinRequestSheet(
      organization: organization,
      apiService: apiService,
      accountController: accountController,
      authService: authService,
      emailVerifiedOverride: emailVerifiedOverride,
    ),
  );
}

class JoinRequestSheet extends StatefulWidget {
  const JoinRequestSheet({
    required this.organization,
    this.apiService,
    this.accountController,
    this.authService,
    this.emailVerifiedOverride,
    super.key,
  });

  final DirectoryOrganization organization;
  final ApiService? apiService;
  final AccountController? accountController;
  final AuthService? authService;
  final bool? emailVerifiedOverride;

  @override
  State<JoinRequestSheet> createState() => _JoinRequestSheetState();
}

class _JoinRequestSheetState extends State<JoinRequestSheet> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();

  late final Set<String> _selectedSports;
  String? _selectedGroupId;
  String? _selectedCoachUid;
  bool _ageConfirmed = false;
  bool _needsIdentityFields = false;
  bool _hasServerBirthDate = false;
  bool _submitting = false;
  bool _resendingEmail = false;
  bool _showEmailVerificationBanner = false;
  String? _error;

  ApiService get _api => widget.apiService ?? ApiService.instance;
  AccountController get _account =>
      widget.accountController ?? AccountController.instance;
  AuthService get _auth => widget.authService ?? AuthService.instance;

  bool get _isEmailVerified =>
      widget.emailVerifiedOverride ?? _account.isEmailVerified;

  List<({String code, String label, bool isIndoor})> get _availableSports {
    if (widget.organization.sportsDetails.isNotEmpty) {
      return widget.organization.sportsDetails
          .map((s) => (code: s.code, label: s.label, isIndoor: s.isIndoor))
          .toList();
    }
    return widget.organization.sports
        .map((code) => (code: code, label: code, isIndoor: false))
        .toList();
  }

  List<DirectoryGroup> get _filteredGroups {
    final groups = widget.organization.groups;
    if (_selectedSports.isEmpty) return groups;
    final matching =
        groups.where((g) => _selectedSports.contains(g.sport)).toList();
    return matching.isNotEmpty ? matching : groups;
  }

  @override
  void initState() {
    super.initState();
    final user = _account.me?.user;
    final first = user?.firstName?.trim() ?? '';
    final last = user?.lastName?.trim() ?? '';
    _firstNameCtrl.text = first;
    _lastNameCtrl.text = last;
    _needsIdentityFields = first.isEmpty || last.isEmpty;

    _hasServerBirthDate = user?.athleteProfile?.birthDate != null;
    _ageConfirmed = _hasServerBirthDate;

    _showEmailVerificationBanner = !_isEmailVerified;

    final sports = _availableSports;
    final preselected = <String>{};
    if (sports.length == 1) {
      preselected.add(sports.first.code);
    } else {
      final profileSport = user?.athleteProfile?.sport.trim().toLowerCase();
      if (profileSport != null && profileSport.isNotEmpty) {
        for (final s in sports) {
          if (s.code.toLowerCase() == profileSport ||
              s.label.toLowerCase() == profileSport) {
            preselected.add(s.code);
          }
        }
      }
    }
    _selectedSports = preselected;
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  void _toggleSport(String code, bool selected) {
    setState(() {
      if (selected) {
        _selectedSports.add(code);
      } else {
        _selectedSports.remove(code);
      }
      if (_selectedGroupId != null &&
          !_filteredGroups.any((g) => g.id == _selectedGroupId)) {
        _selectedGroupId = null;
      }
    });
  }

  Future<void> _resendVerificationEmail() async {
    if (_resendingEmail) return;
    setState(() => _resendingEmail = true);
    try {
      await _auth.sendEmailVerification();
      if (!mounted) return;
      UIUtils.showSnackBar(
        context,
        'E-mail de vérification renvoyé. Consultez votre boîte de réception.',
        tone: AppSnackBarTone.success,
      );
    } catch (_) {
      if (!mounted) return;
      UIUtils.showSnackBar(
        context,
        'Impossible d\'envoyer l\'e-mail de vérification pour le moment.',
        tone: AppSnackBarTone.error,
      );
    } finally {
      if (mounted) {
        setState(() => _resendingEmail = false);
      }
    }
  }

  bool _looksLikeUnverifiedEmailError(ApiException e) {
    final text = '${e.detail ?? ''} ${e.message}'.toLowerCase();
    return text.contains('mail') ||
        text.contains('vérifier') ||
        text.contains('verifier') ||
        text.contains('email_verified');
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    if (!_ageConfirmed) {
      setState(() {
        _error =
            'Vous devez confirmer avoir au moins $kMinAgeYears ans pour envoyer une demande.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final created = await _api.submitJoinRequest(
        orgId: widget.organization.id,
        requestedSports: _selectedSports.toList(),
        requestedGroupId:
            widget.organization.isSoloCoach ? null : _selectedGroupId,
        targetCoachUid:
            widget.organization.isSoloCoach ? null : _selectedCoachUid,
        message: _messageCtrl.text.trim().isEmpty
            ? null
            : _messageCtrl.text.trim(),
        firstName: _needsIdentityFields ? _firstNameCtrl.text.trim() : null,
        lastName: _needsIdentityFields ? _lastNameCtrl.text.trim() : null,
        ageConfirmed: _ageConfirmed,
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        JoinRequestSheetResult(createdRequest: created),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isForbidden && _looksLikeUnverifiedEmailError(e)) {
        setState(() {
          _submitting = false;
          _showEmailVerificationBanner = true;
          _error = e.message;
        });
        return;
      }
      if (e.isForbidden || e.isConflict) {
        UIUtils.showSnackBar(
          context,
          e.message,
          tone: AppSnackBarTone.warning,
        );
        Navigator.of(context).pop(
          const JoinRequestSheetResult(shouldRefreshOrg: true),
        );
        return;
      }
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Impossible d\'envoyer la demande d\'adhésion.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final org = widget.organization;
    final sports = _availableSports;
    final groups = _filteredGroups;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Material(
      color: LKColors.surfaceElevated,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.90,
        ),
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: LKColors.border)),
        ),
        padding: EdgeInsets.fromLTRB(
          UIUtils.lg,
          UIUtils.md,
          UIUtils.lg,
          UIUtils.lg + bottomInset,
        ),
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: LKColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          SizedBox(height: UIUtils.md),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Demander l\'adhésion',
                      style: UIUtils.titleLarge(context),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${org.name} · ${org.typeLabel}',
                      style: UIUtils.bodySmall(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Fermer',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          SizedBox(height: UIUtils.sm),
          Flexible(
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_showEmailVerificationBanner) ...[
                      Container(
                        padding: UIUtils.paddingMD,
                        decoration: BoxDecoration(
                          color: LKColors.warning.withValues(alpha: 0.12),
                          borderRadius: UIUtils.borderRadiusAllMD,
                          border: Border.all(
                            color: LKColors.warning.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.mark_email_unread_outlined,
                                  color: LKColors.warning,
                                  size: 18,
                                ),
                                SizedBox(width: UIUtils.sm),
                                Expanded(
                                  child: Text(
                                    'Vérification d\'e-mail requise',
                                    style: UIUtils.labelLarge(context).copyWith(
                                      color: LKColors.warning,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: UIUtils.xs),
                            Text(
                              'Validez votre adresse e-mail avant de soumettre une demande d\'adhésion.',
                              style: UIUtils.bodySmall(context),
                            ),
                            SizedBox(height: UIUtils.sm),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _resendingEmail
                                      ? null
                                      : _resendVerificationEmail,
                                  icon: _resendingEmail
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.send_rounded,
                                          size: 15,
                                        ),
                                  label: const Text(
                                    'Renvoyer l\'e-mail de vérification',
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    context.push('/verify-email');
                                  },
                                  child: const Text('Vérifier mon e-mail'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: UIUtils.md),
                    ],

                    if (sports.isNotEmpty) ...[
                      Text(
                        'Disciplines souhaitées',
                        style: UIUtils.labelLarge(context),
                      ),
                      SizedBox(height: UIUtils.xs),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: sports.map((s) {
                          final selected = _selectedSports.contains(s.code);
                          return FilterChip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (s.isIndoor) ...[
                                  const Icon(
                                    Icons.home_outlined,
                                    size: 14,
                                    color: LKColors.primary,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Flexible(
                                  child: Text(
                                    s.label,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            selected: selected,
                            selectedColor:
                                LKColors.primary.withValues(alpha: 0.22),
                            checkmarkColor: LKColors.primary,
                            onSelected: (on) => _toggleSport(s.code, on),
                          );
                        }).toList(),
                      ),
                      SizedBox(height: UIUtils.md),
                    ],

                    if (!org.isSoloCoach && groups.isNotEmpty) ...[
                      DropdownButtonFormField<String?>(
                        initialValue: _selectedGroupId,
                        isExpanded: true,
                        dropdownColor: LKColors.surfaceHigher,
                        decoration: UIUtils.inputDecoration(
                          labelText: 'Groupe souhaité (optionnel)',
                          prefixIcon: Icons.groups_outlined,
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Aucune préférence'),
                          ),
                          for (final g in groups)
                            DropdownMenuItem<String?>(
                              value: g.id,
                              child: Text(
                                g.sportLabel != null &&
                                        g.sportLabel!.isNotEmpty
                                    ? '${g.name} (${g.sportLabel})'
                                    : g.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) => setState(() => _selectedGroupId = v),
                      ),
                      SizedBox(height: UIUtils.md),
                    ],

                    if (!org.isSoloCoach && org.coaches.length > 1) ...[
                      DropdownButtonFormField<String?>(
                        initialValue: _selectedCoachUid,
                        isExpanded: true,
                        dropdownColor: LKColors.surfaceHigher,
                        decoration: UIUtils.inputDecoration(
                          labelText: 'Coach souhaité (optionnel)',
                          prefixIcon: Icons.sports_rounded,
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Aucune préférence'),
                          ),
                          for (final c in org.coaches)
                            DropdownMenuItem<String?>(
                              value: c.uid,
                              child: Text(
                                '${c.name} (${c.roleLabel})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) => setState(() => _selectedCoachUid = v),
                      ),
                      SizedBox(height: UIUtils.md),
                    ],

                    if (_needsIdentityFields) ...[
                      Text(
                        'Votre identité',
                        style: UIUtils.labelLarge(context),
                      ),
                      SizedBox(height: UIUtils.xs),
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
                                prefixIcon: Icons.person_outline_rounded,
                              ),
                            ),
                          ),
                          SizedBox(width: UIUtils.sm),
                          Expanded(
                            child: TextFormField(
                              controller: _lastNameCtrl,
                              textInputAction: TextInputAction.next,
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
                      SizedBox(height: UIUtils.md),
                    ],

                    TextFormField(
                      controller: _messageCtrl,
                      maxLines: 4,
                      minLines: 2,
                      maxLength: 1000,
                      textInputAction: TextInputAction.newline,
                      decoration: UIUtils.inputDecoration(
                        labelText: 'Message de présentation (optionnel)',
                        hintText:
                            'Ex : objectifs de saison, niveau actuel, disponibilités…',
                        prefixIcon: Icons.chat_bubble_outline_rounded,
                      ),
                    ),
                    SizedBox(height: UIUtils.xs),

                    CheckboxListTile(
                      value: _ageConfirmed,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        'Je confirme avoir au moins $kMinAgeYears ans',
                        style: UIUtils.bodySmall(context).copyWith(
                          color: LKColors.textPrimary,
                        ),
                      ),
                      onChanged: _submitting
                          ? null
                          : (v) => setState(() {
                                _ageConfirmed = v ?? false;
                                if (_ageConfirmed) _error = null;
                              }),
                    ),

                    if (_error != null) ...[
                      SizedBox(height: UIUtils.xs),
                      Container(
                        padding: UIUtils.paddingSM,
                        decoration: BoxDecoration(
                          color: LKColors.danger.withValues(alpha: 0.12),
                          borderRadius: UIUtils.borderRadiusAllSM,
                          border: Border.all(
                            color: LKColors.danger.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          _error!,
                          style: UIUtils.bodySmall(context).copyWith(
                            color: LKColors.danger,
                          ),
                        ),
                      ),
                    ],

                    SizedBox(height: UIUtils.md),
                    SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send_rounded, size: 18),
                        label: Text(
                          _submitting
                              ? 'Envoi en cours…'
                              : 'Envoyer la demande d\'adhésion',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}
