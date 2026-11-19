import 'package:flutter/material.dart';

import '../../core/account_controller.dart';
import '../../core/api_service.dart';
import '../../core/auth_service.dart';
import '../../exts.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';
import 'athlete_profile_sheet.dart';
import 'organization_hub_sheet.dart';
import 'thresholds_sheet.dart';

/// Ouvre la feuille unifiée Compte & Réglages depuis le header global.
Future<void> showAccountSettingsSheet(
  BuildContext context, {
  ApiService? apiService,
  AccountController? accountController,
  AuthService? authService,
  int pendingInvitationsCount = 0,
  VoidCallback? onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => AccountSettingsSheet(
      apiService: apiService,
      accountController: accountController,
      authService: authService,
      pendingInvitationsCount: pendingInvitationsCount,
      onChanged: onChanged,
    ),
  );
}

class AccountSettingsSheet extends StatelessWidget {
  const AccountSettingsSheet({
    this.apiService,
    this.accountController,
    this.authService,
    this.pendingInvitationsCount = 0,
    this.onChanged,
    super.key,
  });

  final ApiService? apiService;
  final AccountController? accountController;
  final AuthService? authService;
  final int pendingInvitationsCount;
  final VoidCallback? onChanged;

  ApiService get _api => apiService ?? ApiService.instance;
  AccountController get _account =>
      accountController ?? AccountController.instance;
  AuthService get _auth => authService ?? AuthService.instance;

  String _initialsFor(String displayName, String? email) {
    final source = displayName.trim().isNotEmpty
        ? displayName.trim()
        : (email ?? '').trim();
    if (source.isEmpty) return 'VL';
    final parts = source
        .split(RegExp(r'[\s@._-]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return source.substring(0, source.length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final meUser = _account.me?.user;
    final displayName = meUser?.fullName.isNotEmpty == true
        ? meUser!.fullName
        : _auth.displayName;
    final email = _auth.email ?? meUser?.email ?? '';
    final activeMembership = _account.activeMembership;
    final orgId = _account.activeOrgId;
    final uid = _account.uid;
    final canOpenThresholds =
        orgId != null && orgId.isNotEmpty && uid.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Material(
          color: LKColors.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: UIUtils.borderRadiusAllXL,
            side: const BorderSide(color: LKColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            padding: UIUtils.paddingXL,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: LKColors.border,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: LKColors.primary.withValues(alpha: 0.16),
                      child: Text(
                        _initialsFor(displayName, email),
                        style: UIUtils.titleSmall(context).copyWith(
                          color: LKColors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    SizedBox(width: UIUtils.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName.isNotEmpty
                                ? displayName
                                : 'Mon compte',
                            style: UIUtils.titleMedium(context),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (email.isNotEmpty)
                            Text(
                              email,
                              style: UIUtils.bodySmall(context),
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (activeMembership != null) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: LKColors.primary.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${activeMembership.displayOrgName} · ${activeMembership.roleLabel}',
                                style: UIUtils.bodySmall(context).copyWith(
                                  color: LKColors.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: UIUtils.lg),
                const Divider(color: LKColors.border, height: 1),
                SizedBox(height: UIUtils.sm),
                _AccountActionTile(
                  icon: Icons.monitor_heart_outlined,
                  iconColor: LKColors.primary,
                  title: 'Profil sportif & RGPD',
                  subtitle: _account.hasHealthConsent
                      ? 'FC, poids, sports & consentement santé actif'
                      : 'Profil physique & consentement santé',
                  onTap: () async {
                    final navigator = Navigator.of(context);
                    final rootContext = navigator.context;
                    navigator.pop();
                    final updated = await showAthleteProfileSheet(rootContext);
                    if (updated != null) {
                      onChanged?.call();
                    }
                  },
                ),
                _AccountActionTile(
                  icon: Icons.speed_rounded,
                  iconColor: LKColors.secondary,
                  title: 'Seuils d\'entraînement (FTP / LTHR)',
                  subtitle: canOpenThresholds
                      ? 'Zones de puissance Coggan & cardiaques Friel'
                      : 'Sélectionnez un club actif pour éditer vos seuils',
                  enabled: canOpenThresholds,
                  onTap: canOpenThresholds
                      ? () async {
                          final navigator = Navigator.of(context);
                          final rootContext = navigator.context;
                          navigator.pop();
                          final updated = await showThresholdsSheet(
                            rootContext,
                            orgId: orgId,
                            uid: uid,
                            apiService: _api,
                          );
                          if (updated != null) {
                            onChanged?.call();
                          }
                        }
                      : null,
                ),
                _AccountActionTile(
                  icon: Icons.apartment_rounded,
                  iconColor: LKColors.warning,
                  title: 'Mes clubs, coachs & invitations',
                  subtitle: pendingInvitationsCount > 0
                      ? '$pendingInvitationsCount invitation(s) en attente'
                      : '${_account.memberships.length} organisation(s)',
                  trailingBadge: pendingInvitationsCount > 0
                      ? '$pendingInvitationsCount'
                      : null,
                  onTap: () async {
                    final navigator = Navigator.of(context);
                    final rootContext = navigator.context;
                    navigator.pop();
                    await showOrganizationHubSheet(
                      rootContext,
                      apiService: _api,
                      accountController: _account,
                      onChanged: onChanged,
                    );
                  },
                ),
                SizedBox(height: UIUtils.xs),
                const Divider(color: LKColors.border, height: 1),
                SizedBox(height: UIUtils.xs),
                _AccountActionTile(
                  icon: Icons.logout_rounded,
                  iconColor: LKColors.danger,
                  title: 'Se déconnecter',
                  titleColor: LKColors.danger,
                  onTap: () async {
                    final navigator = Navigator.of(context);
                    final rootContext = navigator.context;
                    final confirmed = await rootContext.showSignOutDialog();
                    if (confirmed == true) {
                      if (navigator.mounted && navigator.canPop()) {
                        navigator.pop();
                      }
                      await _auth.signOut();
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountActionTile extends StatelessWidget {
  const _AccountActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.titleColor,
    this.trailingBadge,
    this.enabled = true,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Color? titleColor;
  final String? trailingBadge;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
      minTileHeight: 56,
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: UIUtils.borderRadiusAllMD),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: enabled ? 0.14 : 0.06),
          borderRadius: UIUtils.borderRadiusAllMD,
        ),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? iconColor : LKColors.textHint,
        ),
      ),
      title: Text(
        title,
        style: UIUtils.bodyLarge(context).copyWith(
          color: enabled ? (titleColor ?? LKColors.textPrimary) : LKColors.textHint,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: UIUtils.bodySmall(context).copyWith(
                color: enabled ? LKColors.textSecondary : LKColors.textHint,
              ),
            )
          : null,
      trailing: trailingBadge != null
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: LKColors.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                trailingBadge!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          : (enabled
                ? const Icon(
                    Icons.chevron_right_rounded,
                    color: LKColors.textHint,
                  )
                : null),
      onTap: enabled ? onTap : null,
    );
  }
}
