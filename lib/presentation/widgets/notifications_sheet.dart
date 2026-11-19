import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/account_controller.dart';
import '../../core/api_service.dart';
import '../../data/account_models.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';

Future<void> showNotificationsSheet(
  BuildContext context, {
  ApiService? apiService,
  AccountController? accountController,
  ValueChanged<int>? onUnreadCountChanged,
  VoidCallback? onOpenCalendarTab,
  ValueChanged<AppNotification>? onNotificationTap,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => NotificationsSheet(
      apiService: apiService,
      accountController: accountController,
      onUnreadCountChanged: onUnreadCountChanged,
      onOpenCalendarTab: onOpenCalendarTab,
      onNotificationTap: onNotificationTap,
    ),
  );
}

class NotificationsSheet extends StatefulWidget {
  const NotificationsSheet({
    this.apiService,
    this.accountController,
    this.onUnreadCountChanged,
    this.onOpenCalendarTab,
    this.onNotificationTap,
    super.key,
  });

  final ApiService? apiService;
  final AccountController? accountController;
  final ValueChanged<int>? onUnreadCountChanged;
  final VoidCallback? onOpenCalendarTab;
  final ValueChanged<AppNotification>? onNotificationTap;

  @override
  State<NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<NotificationsSheet> {
  bool _loading = true;
  bool _markingAll = false;
  String? _error;
  List<AppNotification> _items = const [];
  int _unreadCount = 0;

  ApiService get _api => widget.apiService ?? ApiService.instance;
  AccountController get _account =>
      widget.accountController ?? AccountController.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await _api.fetchNotifications();
      if (!mounted) return;
      setState(() {
        _items = resp.items;
        _unreadCount = resp.unreadCount;
        _loading = false;
      });
      widget.onUnreadCountChanged?.call(resp.unreadCount);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossible de charger les notifications.';
        _loading = false;
      });
    }
  }

  Future<void> _markAllRead() async {
    if (_markingAll || _unreadCount == 0) return;
    setState(() => _markingAll = true);
    try {
      await _api.markAllNotificationsRead();
      if (!mounted) return;
      setState(() {
        _items = _items.map((n) => n.copyWith(read: true)).toList();
        _unreadCount = 0;
        _markingAll = false;
      });
      widget.onUnreadCountChanged?.call(0);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _markingAll = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: LKColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _markingAll = false);
    }
  }

  Future<void> _handleTap(AppNotification notif) async {
    if (!notif.read) {
      final nextUnread = (_unreadCount - 1).clamp(0, 9999);
      setState(() {
        _items = _items
            .map((n) => n.id == notif.id ? n.copyWith(read: true) : n)
            .toList();
        _unreadCount = nextUnread;
      });
      widget.onUnreadCountChanged?.call(nextUnread);
      try {
        await _api.markNotificationRead(notif.id);
      } catch (_) {
        // Silencieux : l'état local reste fluide même si le réseau échoue.
      }
    }

    if (!mounted) return;

    if (widget.onNotificationTap != null) {
      widget.onNotificationTap!(notif);
      return;
    }

    final targetOrgId = (notif.orgId != null && notif.orgId!.trim().isNotEmpty)
        ? notif.orgId!.trim()
        : _account.activeOrgId;

    if (notif.type == 'join_request_approved') {
      await _account.refresh(syncAthleteProfile: false);
      if (targetOrgId != null && targetOrgId.isNotEmpty) {
        await _account.selectOrganization(targetOrgId);
      }
      if (!mounted) return;
      final router = GoRouter.maybeOf(context);
      Navigator.of(context).pop();
      if (router != null) {
        router.go('/rooms');
      }
      UIUtils.showSnackBar(
        context,
        notif.body.trim().isNotEmpty
            ? notif.body.trim()
            : 'Votre demande d\'adhésion a été acceptée !',
        tone: AppSnackBarTone.success,
      );
      return;
    }

    if (notif.type == 'join_request_rejected') {
      final router = GoRouter.maybeOf(context);
      Navigator.of(context).pop();
      if (router != null) {
        router.push('/directory?tab=requests');
      }
      return;
    }

    if (targetOrgId != null &&
        targetOrgId.isNotEmpty &&
        targetOrgId != _account.activeOrgId) {
      await _account.selectOrganization(targetOrgId);
    }

    if (!mounted) return;

    final link = notif.link ?? '';
    if (notif.type == 'activity_comment' ||
        link.startsWith('/app/activities/')) {
      final segments = Uri.tryParse(link)?.pathSegments ?? const <String>[];
      final activityId = segments.isNotEmpty ? segments.last : '';
      if (targetOrgId != null &&
          targetOrgId.isNotEmpty &&
          activityId.isNotEmpty) {
        Navigator.of(context).pop();
        context.push(
          '/activities/${Uri.encodeComponent(targetOrgId)}/${Uri.encodeComponent(activityId)}',
        );
        return;
      }
    }

    if (notif.type == 'workout_comment' || link == '/app/calendar') {
      Navigator.of(context).pop();
      widget.onOpenCalendarTab?.call();
      return;
    }
  }

  static IconData _iconForType(String type) {
    switch (type) {
      case 'activity_comment':
        return Icons.directions_bike_rounded;
      case 'workout_comment':
        return Icons.fitness_center_rounded;
      case 'invitation':
      case 'org_invitation':
        return Icons.mail_outline_rounded;
      case 'join_request_approved':
        return Icons.check_circle_outline_rounded;
      case 'join_request_rejected':
        return Icons.cancel_outlined;
      default:
        return Icons.notifications_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM HH:mm');
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      ),
      decoration: const BoxDecoration(
        color: LKColors.surfaceElevated,
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
              const Icon(
                Icons.notifications_outlined,
                color: LKColors.primary,
                size: 22,
              ),
              SizedBox(width: UIUtils.sm),
              Text('Notifications', style: UIUtils.titleLarge(context)),
              if (_unreadCount > 0) ...[
                SizedBox(width: UIUtils.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: LKColors.primary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$_unreadCount',
                    style: const TextStyle(
                      color: LKColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (_unreadCount > 0)
                TextButton(
                  onPressed: _markingAll ? null : _markAllRead,
                  child: Text(_markingAll ? '...' : 'Tout lire'),
                ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          SizedBox(height: UIUtils.sm),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: UIUtils.bodyMedium(context),
                  ),
                  SizedBox(height: UIUtils.md),
                  FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Réessayer'),
                  ),
                ],
              ),
            )
          else if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.notifications_none_rounded,
                    size: 40,
                    color: LKColors.textHint,
                  ),
                  SizedBox(height: UIUtils.sm),
                  Text(
                    'Aucune notification pour le moment.',
                    textAlign: TextAlign.center,
                    style: UIUtils.bodySmall(context),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _items.length,
                separatorBuilder: (_, _) => SizedBox(height: UIUtils.xs),
                itemBuilder: (context, index) {
                  final n = _items[index];
                  return InkWell(
                    borderRadius: UIUtils.borderRadiusAllMD,
                    onTap: () => _handleTap(n),
                    child: Container(
                      padding: UIUtils.paddingMD,
                      decoration: BoxDecoration(
                        color: n.read
                            ? LKColors.surface
                            : LKColors.primary.withValues(alpha: 0.08),
                        borderRadius: UIUtils.borderRadiusAllMD,
                        border: Border.all(
                          color: n.read
                              ? LKColors.border
                              : LKColors.primary.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: (n.read
                                      ? LKColors.textHint
                                      : LKColors.primary)
                                  .withValues(alpha: 0.14),
                              borderRadius: UIUtils.borderRadiusAllSM,
                            ),
                            child: Icon(
                              _iconForType(n.type),
                              size: 18,
                              color:
                                  n.read ? LKColors.textHint : LKColors.primary,
                            ),
                          ),
                          SizedBox(width: UIUtils.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    if (!n.read) ...[
                                      Container(
                                        width: 7,
                                        height: 7,
                                        margin: const EdgeInsets.only(right: 6),
                                        decoration: const BoxDecoration(
                                          color: LKColors.primary,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ],
                                    Expanded(
                                      child: Text(
                                        n.title,
                                        style: UIUtils.bodyMedium(context)
                                            .copyWith(
                                          fontWeight: n.read
                                              ? FontWeight.w500
                                              : FontWeight.w700,
                                          color: LKColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                    if (n.createdAt != null)
                                      Text(
                                        fmt.format(n.createdAt!.toLocal()),
                                        style: UIUtils.bodySmall(context)
                                            .copyWith(fontSize: 10),
                                      ),
                                  ],
                                ),
                                if (n.body.trim().isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    n.body.trim(),
                                    style: UIUtils.bodySmall(context),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
