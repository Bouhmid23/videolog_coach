import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/api_service.dart';
import '../../core/auth_service.dart';
import '../../data/livekit_token.dart';
import '../../data/mobile_room.dart';
import '../../data/user_role.dart';
import '../../exts.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';

// Config POC
const String kDefaultRoom = 'poc-room';

/// Arguments passés à l'écran de session.
class RoomRouteArgs {
  const RoomRouteArgs({
    required this.room,
    required this.listener,
    required this.role,
    required this.roomName,
    required this.canControlRecording,
  });

  final Room room;
  final EventsListener<RoomEvent> listener;
  final UserRole role;
  final String roomName;
  final bool canControlRecording;
}

enum _ConnectStage { idle, preparing, connecting, media }

// -----------------------------------------------------------------------------
// ConnectPage
// -----------------------------------------------------------------------------

class ConnectPage extends StatefulWidget {
  const ConnectPage({
    super.key,
    this.roomName = kDefaultRoom,
    this.canControlRecording = false,
    this.room,
  });

  final String roomName;
  final bool canControlRecording;
  final MobileRoom? room;

  @override
  State<StatefulWidget> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  bool _busy = false;
  _ConnectStage _stage = _ConnectStage.idle;
  final UserRole _role = UserRole.trainee;

  String get _accountEmail =>
      AuthService.instance.email ?? AuthService.instance.displayName;

  String get _initials {
    final source = _accountEmail.trim();
    if (source.isEmpty) return '?';
    final parts = source
        .split(RegExp(r'[\s@._-]+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return source.substring(0, 1).toUpperCase();
  }

  String get _stageLabel {
    switch (_stage) {
      case _ConnectStage.preparing:
        return 'PRÉPARATION...';
      case _ConnectStage.connecting:
        return 'CONNEXION...';
      case _ConnectStage.media:
        return 'ACTIVATION MÉDIA...';
      case _ConnectStage.idle:
        return 'REJOINDRE MAINTENANT';
    }
  }

  @override
  void initState() {
    super.initState();
    if (lkPlatformIs(PlatformType.android)) {
      unawaited(_checkPermissions());
    }
  }

  Future<void> _checkPermissions() async {
    for (final perm in [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.camera,
      Permission.microphone,
    ]) {
      final status = await perm.request();
      if (status.isPermanentlyDenied) {
        debugPrint('Permission $perm refusée définitivement');
      }
    }
  }

  Future<LiveKitToken> _fetchToken() {
    return ApiService.getLiveKitToken(widget.roomName);
  }

  Future<void> _connect(BuildContext ctx) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _stage = _ConnectStage.preparing;
    });

    Room? room;
    EventsListener<RoomEvent>? listener;

    try {
      // L'identité LiveKit est dérivée du UID Firebase par le serveur.
      final tokenResult = await _fetchToken();

      if (mounted) setState(() => _stage = _ConnectStage.connecting);

      room = _createRoom();
      listener = room.createListener();

      try {
        await room.prepareConnection(tokenResult.url, tokenResult.token);
        await room.connect(tokenResult.url, tokenResult.token);
      } catch (_) {
        // Une tentative de connexion peut consommer ou expirer le JWT.
        // Redemander un token avant l'unique nouvelle tentative.
        await room.disconnect();
        final refreshed = await _fetchToken();
        await room.prepareConnection(refreshed.url, refreshed.token);
        await room.connect(refreshed.url, refreshed.token);
      }

      if (mounted) setState(() => _stage = _ConnectStage.media);

      // Paramètres par défaut : micro et caméra avant publiés immédiatement.
      await _publishDefaultDevices(room);

      if (!ctx.mounted) {
        await room.disconnect();
        await listener.dispose();
        return;
      }

      ctx.pushReplacement(
        '/room',
        extra: RoomRouteArgs(
          room: room,
          listener: listener,
          role: _role,
          roomName: widget.roomName,
          canControlRecording: widget.canControlRecording,
        ),
      );
    } catch (error) {
      debugPrint('Erreur connexion: $error');
      await room?.disconnect();
      await listener?.dispose();
      if (!ctx.mounted) return;
      await ctx.showErrorDialog(error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _stage = _ConnectStage.idle;
        });
      }
    }
  }

  Room _createRoom() {
    const cameraEncoding = VideoEncoding(
      maxBitrate: 2 * 1000 * 1000,
      maxFramerate: 30,
    );
    const screenEncoding = VideoEncoding(
      maxBitrate: 3 * 1000 * 1000,
      maxFramerate: 15,
    );

    return Room(
      roomOptions: const RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultCameraCaptureOptions: CameraCaptureOptions(
          maxFrameRate: 30,
          params: VideoParameters(dimensions: VideoDimensions(640, 480)),
        ),
        defaultAudioPublishOptions: AudioPublishOptions(
          name: 'custom_audio_track_name',
        ),
        defaultVideoPublishOptions: VideoPublishOptions(
          simulcast: false,
          videoCodec: 'H264',
          backupVideoCodec: BackupVideoCodec(enabled: true),
          videoEncoding: cameraEncoding,
          screenShareEncoding: screenEncoding,
        ),
      ),
    );
  }

  Future<void> _publishDefaultDevices(Room room) async {
    final local = room.localParticipant;
    if (local == null) return;

    try {
      await local.setMicrophoneEnabled(true);
    } catch (error) {
      debugPrint('Microphone indisponible: $error');
    }

    try {
      await local.setCameraEnabled(true);
    } catch (error) {
      debugPrint('Caméra indisponible: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LKColors.background,
      appBar: AppBar(
        backgroundColor: LKColors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: LKColors.textPrimary,
        elevation: 0,
        title: Text(
          'Rejoindre la session',
          style: UIUtils.titleMedium(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  UIUtils.lg,
                  UIUtils.sm,
                  UIUtils.lg,
                  UIUtils.xl,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeroCard(context),
                        SizedBox(height: UIUtils.lg),
                        _buildAccountCard(context),
                        SizedBox(height: UIUtils.md),
                        _buildConfigCard(context),
                        /*SizedBox(height: UIUtils.md),
                        _buildInfoBanner(context),*/
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _buildBottomBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard(BuildContext context) {
    final selectedRoom = widget.room;
    final isRecording = selectedRoom?.isRecording ?? false;
    final isLive = (selectedRoom?.participantCount ?? 0) > 0;
    final statusLabel = isRecording
        ? 'Enregistrement en cours'
        : isLive
        ? '${selectedRoom!.participantCount} participant${selectedRoom.participantCount > 1 ? 's' : ''} connecté${selectedRoom.participantCount > 1 ? 's' : ''}'
        : 'Session prête';
    final statusColor = isRecording
        ? LKColors.danger
        : isLive
        ? LKColors.success
        : LKColors.secondary;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                    SizedBox(height: 2),
                    Text(
                      widget.roomName,
                      style: UIUtils.titleLarge(
                        context,
                      ).copyWith(fontSize: 22, fontWeight: FontWeight.w700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          /*SizedBox(height: UIUtils.lg),
          Wrap(
            spacing: UIUtils.sm,
            runSpacing: UIUtils.sm,
            children: [
              _buildPill(
                context,
                icon: isRecording
                    ? Icons.fiber_manual_record_rounded
                    : isLive
                    ? Icons.sensors_rounded
                    : Icons.check_circle_rounded,
                label: statusLabel,
                color: statusColor,
              ),
              if (widget.canControlRecording)
                _buildPill(
                  context,
                  icon: Icons.settings_remote_rounded,
                  label: 'Contrôle Egress',
                  color: LKColors.success,
                ),
              _buildPill(
                context,
                icon: Icons.lock_rounded,
                label: 'Connexion sécurisée',
                color: LKColors.textSecondary,
              ),
            ],
          ),*/
        ],
      ),
    );
  }

  Widget _buildPill(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: UIUtils.sm, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: UIUtils.borderRadiusAllFull,
        border: Border.all(color: color.withValues(alpha: 0.22), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          SizedBox(width: 5),
          Text(
            label,
            style: UIUtils.bodySmall(
              context,
            ).copyWith(color: color, fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(BuildContext context) {
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
              _initials,
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
                  _accountEmail,
                  style: UIUtils.bodyMedium(
                    context,
                  ).copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 2),
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
                    SizedBox(width: 5),
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

  Widget _buildConfigCard(BuildContext context) {
    return Container(
      padding: UIUtils.paddingLG,
      decoration: BoxDecoration(
        color: LKColors.surface,
        borderRadius: UIUtils.borderRadiusAllLG,
        border: Border.all(color: LKColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Configuration automatique',
            style: UIUtils.labelLarge(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: UIUtils.md),
          _buildConfigRow(
            context,
            icon: Icons.videocam_rounded,
            title: 'Caméra avant',
            subtitle: '640 × 480 · 30 fps',
          ),
          _buildConfigDivider(),
          _buildConfigRow(
            context,
            icon: Icons.mic_rounded,
            title: 'Microphone',
            subtitle: 'Activé à l\'entrée',
          ),
          _buildConfigDivider(),
          _buildConfigRow(
            context,
            icon: Icons.tune_rounded,
            title: 'Réglages',
            subtitle: 'Modifiables pendant la session',
          ),
        ],
      ),
    );
  }

  Widget _buildConfigRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: LKColors.background.withValues(alpha: 0.55),
            borderRadius: UIUtils.borderRadiusAllSM,
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
                style: UIUtils.bodyMedium(
                  context,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                subtitle,
                style: UIUtils.bodySmall(
                  context,
                ).copyWith(color: LKColors.textHint, fontSize: 11),
              ),
            ],
          ),
        ),
        Icon(
          Icons.check_rounded,
          size: 17,
          color: LKColors.success.withValues(alpha: 0.8),
        ),
      ],
    );
  }

  Widget _buildConfigDivider() {
    return Container(
      height: 0.5,
      margin: EdgeInsets.symmetric(vertical: UIUtils.sm),
      color: LKColors.border.withValues(alpha: 0.7),
    );
  }

  /*Widget _buildInfoBanner(BuildContext context) {
    return Container(
      padding: UIUtils.paddingMD,
      decoration: BoxDecoration(
        color: LKColors.secondary.withValues(alpha: 0.07),
        borderRadius: UIUtils.borderRadiusAllMD,
        border: Border.all(
          color: LKColors.secondary.withValues(alpha: 0.16),
          width: 0.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: LKColors.secondary),
          SizedBox(width: UIUtils.sm),
          Expanded(
            child: Text(
              'Vous entrerez directement dans la session. Aucun écran de prévisualisation.',
              style: UIUtils.bodySmall(context).copyWith(
                color: LKColors.textSecondary,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }*/

  Widget _buildBottomBar(BuildContext context) {
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
                child: _busy
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
                  onPressed: _busy ? null : () => _connect(context),
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
                    child: _busy
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
                                _stageLabel,
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
                                _stageLabel,
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
                _busy
                    ? 'Merci de patienter pendant la connexion.'
                    : 'La caméra et le microphone seront activés automatiquement.',
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
