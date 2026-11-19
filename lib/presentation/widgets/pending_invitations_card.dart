import 'package:flutter/material.dart';

import '../../core/account_controller.dart';
import '../../core/api_service.dart';
import '../../data/account_models.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';

/// Affiche les invitations in-app reçues (`/v1/me/invitations`) avec
/// actions « Accepter » et « Refuser » en un clic.
class PendingInvitationsCard extends StatefulWidget {
  const PendingInvitationsCard({
    required this.invitations,
    this.apiService,
    this.accountController,
    this.onInvitationHandled,
    super.key,
  });

  final List<InAppInvitation> invitations;
  final ApiService? apiService;
  final AccountController? accountController;
  final Future<void> Function({
    required bool accepted,
    required InAppInvitation invitation,
  })? onInvitationHandled;

  @override
  State<PendingInvitationsCard> createState() => _PendingInvitationsCardState();
}

class _PendingInvitationsCardState extends State<PendingInvitationsCard> {
  String? _busyInvitationId;

  ApiService get _api => widget.apiService ?? ApiService.instance;
  AccountController get _account =>
      widget.accountController ?? AccountController.instance;

  Future<void> _handleDecision(
    InAppInvitation inv, {
    required bool accept,
  }) async {
    if (_busyInvitationId != null) return;
    setState(() => _busyInvitationId = inv.id);

    try {
      if (accept) {
        await _api.acceptMyInvitation(inv.id);
        await _account.refresh(syncAthleteProfile: false);
        if (inv.orgId.isNotEmpty) {
          await _account.selectOrganization(inv.orgId);
        }
      } else {
        await _api.declineMyInvitation(inv.id);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? 'Vous avez rejoint ${inv.orgName}.'
                : 'Invitation de ${inv.orgName} refusée.',
          ),
          backgroundColor: accept ? LKColors.success : LKColors.surfaceElevated,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await widget.onInvitationHandled?.call(
        accepted: accept,
        invitation: inv,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: LKColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible de traiter cette invitation.'),
          backgroundColor: LKColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busyInvitationId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.invitations.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: UIUtils.paddingMD,
      decoration: BoxDecoration(
        color: LKColors.primary.withValues(alpha: 0.08),
        borderRadius: UIUtils.borderRadiusAllLG,
        border: Border.all(color: LKColors.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.mark_email_unread_rounded,
                color: LKColors.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.invitations.length > 1
                      ? '${widget.invitations.length} invitations reçues'
                      : 'Invitation reçue',
                  style: UIUtils.titleSmall(context).copyWith(
                    color: LKColors.primary,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: UIUtils.sm),
          for (var i = 0; i < widget.invitations.length; i++) ...[
            if (i > 0) SizedBox(height: UIUtils.sm),
            _buildItem(context, widget.invitations[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, InAppInvitation inv) {
    final busy = _busyInvitationId == inv.id;
    final disabled = _busyInvitationId != null;

    return Container(
      padding: UIUtils.paddingMD,
      decoration: BoxDecoration(
        color: LKColors.surfaceElevated,
        borderRadius: UIUtils.borderRadiusAllMD,
        border: Border.all(color: LKColors.border, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                inv.orgName,
                style: UIUtils.bodyMedium(context).copyWith(
                  color: LKColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: LKColors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${inv.orgTypeLabel} · ${inv.roleLabel}',
                  style: const TextStyle(
                    color: LKColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (inv.inviterName != null && inv.inviterName!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Invité par ${inv.inviterName}',
              style: UIUtils.bodySmall(context),
            ),
          ],
          SizedBox(height: UIUtils.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: disabled
                      ? null
                      : () => _handleDecision(inv, accept: false),
                  child: const Text('Refuser'),
                ),
              ),
              SizedBox(width: UIUtils.sm),
              Expanded(
                child: FilledButton(
                  onPressed: disabled
                      ? null
                      : () => _handleDecision(inv, accept: true),
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Accepter'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
