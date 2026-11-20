import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

import '../../../theme.dart';
import '../../utils/ui_utils.dart';

/// En-tête de présentation de la session sélectionnée sur l'écran de pré-connexion.
class ConnectHeroCard extends StatelessWidget {
  const ConnectHeroCard({
    super.key,
    required this.title,
    this.orgName,
  });

  final String title;
  final String? orgName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: UIUtils.paddingXL,
      decoration: BoxDecoration(
        borderRadius: UIUtils.borderRadiusAllXL,
        border: Border.all(
          color: LKColors.primary.withValues(alpha: 0.28),
          width: 0.5,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            LKColors.primary.withValues(alpha: 0.2),
            LKColors.secondary.withValues(alpha: 0.07),
            LKColors.surface,
          ],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: LKColors.primary.withValues(alpha: 0.16),
              borderRadius: UIUtils.borderRadiusAllLG,
            ),
            child: const Icon(
              Icons.videocam_rounded,
              color: LKColors.primary,
              size: 25,
            ),
          ),
          SizedBox(width: UIUtils.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SESSION SÉLECTIONNÉE',
                  style: UIUtils.bodySmall(context).copyWith(
                    color: LKColors.textHint,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: UIUtils.titleLarge(
                    context,
                  ).copyWith(fontSize: 22, fontWeight: FontWeight.w700),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (orgName != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    orgName!,
                    style: UIUtils.bodySmall(context).copyWith(
                      color: LKColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bannière d'avertissement lorsque des permissions système sont refusées définitivement.
class ConnectPermissionSettingsBanner extends StatelessWidget {
  const ConnectPermissionSettingsBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: UIUtils.paddingMD,
      decoration: BoxDecoration(
        color: LKColors.warning.withValues(alpha: 0.12),
        borderRadius: UIUtils.borderRadiusAllLG,
        border: Border.all(color: LKColors.warning.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: LKColors.warning),
          SizedBox(width: UIUtils.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Autorisations bloquées',
                  style: UIUtils.titleSmall(context).copyWith(
                    color: LKColors.warning,
                  ),
                ),
                Text(
                  'Certaines permissions caméra, micro ou capteurs sont refusées dans les réglages.',
                  style: UIUtils.bodySmall(context),
                ),
              ],
            ),
          ),
          SizedBox(width: UIUtils.sm),
          TextButton(
            onPressed: openAppSettings,
            child: const Text('Réglages'),
          ),
        ],
      ),
    );
  }
}

/// Carte récapitulative du compte authentifié sur l'écran de pré-connexion.
class ConnectAccountCard extends StatelessWidget {
  const ConnectAccountCard({
    super.key,
    required this.initials,
    required this.displayLabel,
  });

  final String initials;
  final String displayLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: UIUtils.paddingLG,
      decoration: BoxDecoration(
        color: LKColors.surface,
        borderRadius: UIUtils.borderRadiusAllLG,
        border: Border.all(color: LKColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: LKColors.primary.withValues(alpha: 0.14),
              borderRadius: UIUtils.borderRadiusAllFull,
            ),
            child: Text(
              initials,
              style: UIUtils.labelLarge(
                context,
              ).copyWith(color: LKColors.primary, fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(width: UIUtils.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayLabel,
                  style: UIUtils.bodyMedium(
                    context,
                  ).copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: LKColors.success,
                        borderRadius: UIUtils.borderRadiusAllFull,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Compte authentifié',
                      style: UIUtils.bodySmall(
                        context,
                      ).copyWith(color: LKColors.textHint, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Icon(
            Icons.verified_user_rounded,
            size: 20,
            color: LKColors.success.withValues(alpha: 0.8),
          ),
        ],
      ),
    );
  }
}

/// Barre d'action inférieure (« Rejoindre maintenant ») de l'écran de pré-connexion.
class ConnectBottomBar extends StatelessWidget {
  const ConnectBottomBar({
    super.key,
    required this.busy,
    required this.stageLabel,
    required this.onConnect,
  });

  final bool busy;
  final String stageLabel;
  final VoidCallback? onConnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        UIUtils.lg,
        UIUtils.md,
        UIUtils.lg,
        UIUtils.lg,
      ),
      decoration: BoxDecoration(
        color: LKColors.surfaceElevated,
        border: Border(
          top: BorderSide(
            color: LKColors.border.withValues(alpha: 0.7),
            width: 0.5,
          ),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedSwitcher(
                duration: UIUtils.animationDuration,
                child: busy
                    ? ClipRRect(
                        key: const ValueKey('progress'),
                        borderRadius: UIUtils.borderRadiusAllFull,
                        child: const LinearProgressIndicator(
                          minHeight: 3,
                          backgroundColor: LKColors.border,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            LKColors.primary,
                          ),
                        ),
                      )
                    : const SizedBox(
                        key: ValueKey('progress-placeholder'),
                        height: 3,
                      ),
              ),
              SizedBox(height: UIUtils.md),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: onConnect,
                  style: FilledButton.styleFrom(
                    backgroundColor: LKColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: LKColors.primary.withValues(
                      alpha: 0.4,
                    ),
                    disabledForegroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: UIUtils.borderRadiusAllMD,
                    ),
                    elevation: 0,
                  ),
                  child: AnimatedSwitcher(
                    duration: UIUtils.animationDuration,
                    child: busy
                        ? Row(
                            key: const ValueKey('connecting'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: UIUtils.md),
                              Text(
                                stageLabel,
                                style: UIUtils.labelLarge(context).copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          )
                        : Row(
                            key: const ValueKey('idle'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.login_rounded,
                                size: 20,
                                color: Colors.white,
                              ),
                              SizedBox(width: UIUtils.sm),
                              Text(
                                stageLabel,
                                style: UIUtils.labelLarge(context).copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              SizedBox(height: UIUtils.sm),
              Text(
                busy
                    ? 'Merci de patienter pendant la connexion.'
                    : 'Cadrage et réglages audio/caméra appliqués dès l\'entrée en session.',
                textAlign: TextAlign.center,
                style: UIUtils.bodySmall(
                  context,
                ).copyWith(color: LKColors.textHint, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Affiche la feuille modale expliquant les permissions nécessaires avant le direct.
Future<bool?> showConnectPrePermissionRationaleSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: UIUtils.paddingXL,
        decoration: BoxDecoration(
          color: LKColors.surfaceElevated,
          borderRadius: UIUtils.borderRadiusAllXL,
          border: Border.all(color: LKColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: LKColors.primary.withValues(alpha: 0.14),
                    borderRadius: UIUtils.borderRadiusAllMD,
                  ),
                  child: const Icon(
                    Icons.verified_user_outlined,
                    color: LKColors.primary,
                  ),
                ),
                SizedBox(width: UIUtils.md),
                Expanded(
                  child: Text(
                    'Accès nécessaires avant le direct',
                    style: UIUtils.titleMedium(ctx),
                  ),
                ),
              ],
            ),
            SizedBox(height: UIUtils.md),
            Text(
              'Pour filmer votre séance, diffuser l\'audio au coach et lire vos capteurs sportifs :',
              style: UIUtils.bodySmall(ctx),
            ),
            SizedBox(height: UIUtils.md),
            const _RationaleItem(
              icon: Icons.videocam_outlined,
              title: 'Caméra & Microphone',
              subtitle: 'Vidéo en direct et échanges audio avec le coach.',
            ),
            const SizedBox(height: 10),
            const _RationaleItem(
              icon: Icons.bluetooth_connected_rounded,
              title: 'Bluetooth (BLE)',
              subtitle: 'Lunettes Engo, ceinture cardio HRM et cadence.',
            ),
            const SizedBox(height: 10),
            const _RationaleItem(
              icon: Icons.gps_fixed_rounded,
              title: 'Localisation (en cours d\'utilisation)',
              subtitle: 'Vitesse GPS extérieure et scan BLE Android.',
            ),
            SizedBox(height: UIUtils.xl),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Plus tard'),
                  ),
                ),
                SizedBox(width: UIUtils.md),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Autoriser l\'accès'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _RationaleItem extends StatelessWidget {
  const _RationaleItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: LKColors.surface,
            borderRadius: UIUtils.borderRadiusAllSM,
            border: Border.all(color: LKColors.border),
          ),
          child: Icon(icon, size: 18, color: LKColors.primary),
        ),
        SizedBox(width: UIUtils.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: UIUtils.bodyMedium(context).copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(subtitle, style: UIUtils.bodySmall(context)),
            ],
          ),
        ),
      ],
    );
  }
}
