import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_service.dart';
import '../../core/auth_service.dart';
import '../../data/mobile_room.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';

class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key});

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  static final DateFormat _dateFormat = DateFormat('dd/MM HH:mm');

  List<MobileRoom> _rooms = const [];
  bool _loading = true;
  String? _error;

  int get _liveCount => _rooms.where((r) => r.participantCount > 0).length;
  int get _recordingCount => _rooms.where((r) => r.isRecording).length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final rooms = await ApiService.getRooms();
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _error = null;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await AuthService.instance.signOut();
        return;
      }
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossible de charger les sessions.';
        _loading = false;
      });
    }
  }

  Future<void> _openRoom(MobileRoom room) async {
    await context.push(
      '/connect/${Uri.encodeComponent(room.name)}',
      extra: room,
    );
  }

  String _relativeTime(DateTime date) {
    final local = date.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inMinutes < 1) return "à l'instant";
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
    return 'le ${_dateFormat.format(local)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LKColors.background,
      appBar: AppBar(
        backgroundColor: LKColors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        foregroundColor: LKColors.textPrimary,
        toolbarHeight: 68,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sessions sportives', style: UIUtils.titleMedium(context)),
            Text(
              'Coaching en direct',
              style: UIUtils.bodySmall(
                context,
              ).copyWith(color: LKColors.textHint, fontSize: 11),
            ),
          ],
        ),
        elevation: 0,
        shadowColor: Colors.transparent,
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _load(showSpinner: false),
            icon: UIUtils.textPrimaryIcon(Icons.refresh_rounded, size: 24),
            tooltip: 'Actualiser',
          ),
          IconButton(
            onPressed: () => AuthService.instance.signOut(),
            icon: UIUtils.textPrimaryIcon(Icons.logout_rounded, size: 24),
            tooltip: 'Se déconnecter',
          ),
          SizedBox(width: UIUtils.xs),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: LKColors.primary,
          onRefresh: () => _load(showSpinner: false),
          child: _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(LKColors.primary),
        ),
      );
    }

    if (_error != null) {
      return _buildMessageState(
        context,
        icon: Icons.cloud_off_rounded,
        title: 'Sessions indisponibles',
        message: _error!,
        actionLabel: 'Réessayer',
        onAction: _load,
      );
    }

    if (_rooms.isEmpty) {
      return _buildMessageState(
        context,
        icon: Icons.videocam_off_rounded,
        title: 'Aucune session pour le moment',
        message:
            'Votre compte n\'est inscrit à aucune session en cours. '
            'Actualisez ou vérifiez vos accès avec votre coach.',
        actionLabel: 'Actualiser',
        onAction: _load,
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        UIUtils.lg,
        UIUtils.md,
        UIUtils.lg,
        UIUtils.xxl,
      ),
      itemCount: _rooms.length + 1,
      separatorBuilder: (_, _) => SizedBox(height: UIUtils.md),
      itemBuilder: (context, index) {
        if (index == 0) return _buildHeader(context);
        return _buildRoomCard(context, _rooms[index - 1]);
      },
    );
  }

  Widget _buildMessageState(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String message,
    required String actionLabel,
    required Future<void> Function() onAction,
  }) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: UIUtils.paddingLG,
      children: [
        SizedBox(height: 48),
        Container(
          padding: UIUtils.paddingXXL,
          decoration: BoxDecoration(
            color: LKColors.surface,
            borderRadius: UIUtils.borderRadiusAllXL,
            border: Border.all(color: LKColors.border, width: 0.5),
          ),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: LKColors.primary.withValues(alpha: 0.1),
                  borderRadius: UIUtils.borderRadiusAllFull,
                ),
                child: Icon(icon, size: 30, color: LKColors.primary),
              ),
              SizedBox(height: UIUtils.lg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: UIUtils.titleMedium(context),
              ),
              SizedBox(height: UIUtils.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: UIUtils.bodySmall(
                  context,
                ).copyWith(color: LKColors.textHint, height: 1.5),
              ),
              SizedBox(height: UIUtils.xl),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(actionLabel, style: UIUtils.labelLarge(context)),
                style: FilledButton.styleFrom(
                  backgroundColor: LKColors.primary,
                  foregroundColor: Colors.white,
                  padding: UIUtils.paddingHorizontalXL.add(
                    UIUtils.paddingVerticalMD,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: UIUtils.borderRadiusAllMD,
                  ),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: UIUtils.paddingXL,
      decoration: BoxDecoration(
        borderRadius: UIUtils.borderRadiusAllXL,
        border: Border.all(
          color: LKColors.primary.withValues(alpha: 0.25),
          width: 0.5,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            LKColors.primary.withValues(alpha: 0.16),
            LKColors.secondary.withValues(alpha: 0.06),
            LKColors.surface,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BON RETOUR',
                      style: UIUtils.bodySmall(context).copyWith(
                        color: LKColors.secondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: UIUtils.xs),
                    Text(
                      'Bonjour ${AuthService.instance.displayName}',
                      style: UIUtils.titleLarge(
                        context,
                      ).copyWith(fontSize: 22, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: UIUtils.xs),
                    Text(
                      'Choisissez la session à rejoindre.',
                      style: UIUtils.bodySmall(
                        context,
                      ).copyWith(color: LKColors.textHint),
                    ),
                  ],
                ),
              ),
              SizedBox(width: UIUtils.md),
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: LKColors.primary.withValues(alpha: 0.16),
                  borderRadius: UIUtils.borderRadiusAllLG,
                ),
                child: Icon(
                  Icons.sports_score_rounded,
                  color: LKColors.primary,
                  size: 24,
                ),
              ),
            ],
          ),
          SizedBox(height: UIUtils.lg),
          Container(
            padding: UIUtils.paddingMD,
            decoration: BoxDecoration(
              color: LKColors.background.withValues(alpha: 0.35),
              borderRadius: UIUtils.borderRadiusAllMD,
              border: Border.all(
                color: LKColors.border.withValues(alpha: 0.6),
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                _buildStat(
                  context,
                  value: '${_rooms.length}',
                  label: 'session${_rooms.length > 1 ? 's' : ''}',
                  color: LKColors.textPrimary,
                ),
                _buildStatDivider(),
                _buildStat(
                  context,
                  value: '$_liveCount',
                  label: 'en direct',
                  color: LKColors.success,
                ),
                if (_recordingCount > 0) ...[
                  _buildStatDivider(),
                  _buildStat(
                    context,
                    value: '$_recordingCount',
                    label: 'enregistrement',
                    color: LKColors.danger,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(
    BuildContext context, {
    required String value,
    required String label,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: UIUtils.titleSmall(
              context,
            ).copyWith(color: color, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          Text(
            label,
            style: UIUtils.bodySmall(
              context,
            ).copyWith(color: LKColors.textHint, fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(
      width: 0.5,
      height: 28,
      margin: EdgeInsets.symmetric(horizontal: UIUtils.md),
      color: LKColors.border,
    );
  }

  Widget _buildRoomCard(BuildContext context, MobileRoom room) {
    final isLive = room.participantCount > 0;
    final isRecording = room.isRecording;
    final accent = isRecording
        ? LKColors.danger
        : isLive
        ? LKColors.success
        : LKColors.primary;
    final stateLabel = isRecording
        ? 'Enregistrement'
        : room.isBusy
        ? room.recordingLabel
        : isLive
        ? 'En direct'
        : 'Disponible';
    final stateIcon = isRecording
        ? Icons.fiber_manual_record_rounded
        : isLive
        ? Icons.sensors_rounded
        : Icons.videocam_rounded;
    final updated = room.updatedAt == null
        ? null
        : 'Activité ${_relativeTime(room.updatedAt!)}';

    return Container(
      decoration: BoxDecoration(
        color: LKColors.surface,
        borderRadius: UIUtils.borderRadiusAllXL,
        border: Border.all(
          color: accent.withValues(alpha: isLive || isRecording ? 0.34 : 0.16),
          width: 0.5,
        ),
        boxShadow: isLive || isRecording
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: UIUtils.borderRadiusAllXL,
          onTap: () => _openRoom(room),
          child: Padding(
            padding: UIUtils.paddingLG,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: UIUtils.borderRadiusAllLG,
                      ),
                      child: Icon(
                        isRecording
                            ? Icons.fiber_manual_record_rounded
                            : Icons.videocam_rounded,
                        color: accent,
                        size: 25,
                      ),
                    ),
                    SizedBox(width: UIUtils.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            room.name,
                            style: UIUtils.titleMedium(context).copyWith(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: UIUtils.sm),
                          Wrap(
                            spacing: UIUtils.sm,
                            runSpacing: UIUtils.xs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _buildStatusPill(
                                context,
                                label: stateLabel,
                                icon: stateIcon,
                                color: accent,
                                emphasize: isLive || isRecording,
                              ),
                              _buildInfoPill(
                                context,
                                icon: Icons.people_alt_rounded,
                                label: room.participantCount == 0
                                    ? 'Aucun participant'
                                    : '${room.participantCount} participant${room.participantCount > 1 ? 's' : ''}',
                              ),
                              if (room.canControlRecording)
                                _buildInfoPill(
                                  context,
                                  icon: Icons.settings_remote_rounded,
                                  label: 'Contrôle Egress',
                                  color: LKColors.success,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (updated != null) ...[
                  SizedBox(height: UIUtils.md),
                  Row(
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 13,
                        color: LKColors.textHint,
                      ),
                      SizedBox(width: UIUtils.xs),
                      Expanded(
                        child: Text(
                          updated,
                          style: UIUtils.bodySmall(
                            context,
                          ).copyWith(color: LKColors.textHint, fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                ],
                SizedBox(height: UIUtils.md),
                SizedBox(
                  height: 46,
                  child: FilledButton.icon(
                    onPressed: () => _openRoom(room),
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: Text(
                      'Rejoindre la session',
                      style: UIUtils.labelMedium(context).copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: UIUtils.borderRadiusAllMD,
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusPill(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color color,
    bool emphasize = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: emphasize ? 9 : 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: emphasize ? 0.14 : 0.1),
        borderRadius: UIUtils.borderRadiusAllFull,
        border: Border.all(
          color: color.withValues(alpha: emphasize ? 0.3 : 0.18),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          SizedBox(width: 5),
          Text(
            label,
            style: UIUtils.bodySmall(
              context,
            ).copyWith(color: color, fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPill(
    BuildContext context, {
    required IconData icon,
    required String label,
    Color? color,
  }) {
    final tone = color ?? LKColors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: tone),
        SizedBox(width: 4),
        Text(
          label,
          style: UIUtils.bodySmall(context).copyWith(color: tone, fontSize: 11),
        ),
      ],
    );
  }
}
