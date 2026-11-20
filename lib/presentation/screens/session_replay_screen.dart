import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../core/account_controller.dart';
import '../../core/api_service.dart';
import '../../data/mobile_room.dart';
import '../../data/session_models.dart';
import '../../theme.dart';
import '../utils/ui_utils.dart';

class SessionReplayScreen extends StatefulWidget {
  const SessionReplayScreen({
    required this.orgId,
    required this.roomName,
    super.key,
  });

  final String orgId;
  final String roomName;

  @override
  State<SessionReplayScreen> createState() => _SessionReplayScreenState();
}

class _SessionReplayScreenState extends State<SessionReplayScreen> {
  SessionDetail? _detail;
  List<SessionTelemetrySample> _telemetry = const [];
  List<SessionAlert> _alerts = const [];
  List<SessionMarker> _markers = const [];

  bool _loading = true;
  String? _error;

  VideoPlayerController? _videoCtrl;
  int _selectedRecordingIdx = 0;
  bool _videoInitializing = false;
  String? _videoError;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  String? _selectedParticipantUid;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _disposeVideoController();
    super.dispose();
  }

  void _disposeVideoController() {
    final ctrl = _videoCtrl;
    _videoCtrl = null;
    if (ctrl != null) {
      ctrl.removeListener(_onVideoTick);
      unawaited(ctrl.dispose());
    }
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiService.instance.fetchSessionDetail(widget.orgId, widget.roomName),
        ApiService.instance.fetchSessionTelemetry(widget.orgId, widget.roomName),
        ApiService.instance.fetchSessionAlerts(widget.orgId, widget.roomName),
        ApiService.instance.fetchSessionMarkers(widget.orgId, widget.roomName),
      ]);
      if (!mounted) return;
      final detail = results[0] as SessionDetail;
      setState(() {
        _detail = detail;
        _telemetry = results[1] as List<SessionTelemetrySample>;
        _alerts = results[2] as List<SessionAlert>;
        _markers = results[3] as List<SessionMarker>;
        _loading = false;
      });
      await _initRecordingAt(_selectedRecordingIdx);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossible de charger les données de cette séance.';
        _loading = false;
      });
    }
  }

  Future<void> _initRecordingAt(int index, {Duration? restorePosition}) async {
    final detail = _detail;
    if (detail == null || detail.recordings.isEmpty) {
      _disposeVideoController();
      if (mounted) setState(() {});
      return;
    }

    // Rafraîchit les URLs présignées MinIO (valables 1 heure) si besoin.
    if (detail.areSignedUrlsNearExpiry) {
      try {
        final refreshed = await ApiService.instance.fetchSessionDetail(
          widget.orgId,
          widget.roomName,
        );
        if (mounted) {
          setState(() => _detail = refreshed);
        }
      } catch (_) {}
    }

    final recordings = _detail?.recordings ?? const [];
    if (index < 0 || index >= recordings.length) return;
    final rec = recordings[index];
    if (!rec.hasPlayableUrl) {
      setState(() => _videoError = 'Aucune vidéo MP4 disponible pour cette capture.');
      return;
    }

    _disposeVideoController();
    setState(() {
      _selectedRecordingIdx = index;
      _videoInitializing = true;
      _videoError = null;
    });

    final controller = VideoPlayerController.networkUrl(Uri.parse(rec.mp4Url));
    controller.addListener(_onVideoTick);
    _videoCtrl = controller;

    try {
      await controller.initialize();
      if (restorePosition != null && restorePosition > Duration.zero) {
        await controller.seekTo(restorePosition);
      }
      if (!mounted) return;
      setState(() {
        _videoInitializing = false;
        _totalDuration = controller.value.duration;
        _currentPosition = controller.value.position;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _videoInitializing = false;
        _videoError =
            'Lecture impossible (le lien présigné a peut-être expiré). Appuyez sur Actualiser.';
      });
    }
  }

  void _onVideoTick() {
    final ctrl = _videoCtrl;
    if (ctrl == null || !mounted) return;
    final val = ctrl.value;
    if (val.hasError && _videoError == null) {
      setState(() {
        _videoError =
            'Erreur de lecture vidéo (lien expiré ou format non supporté).';
      });
      return;
    }
    if ((val.position - _currentPosition).abs() >=
            const Duration(milliseconds: 200) ||
        val.duration != _totalDuration) {
      setState(() {
        _currentPosition = val.position;
        _totalDuration = val.duration;
      });
    }
  }

  Future<void> _seekToMs(double ptsMs) async {
    final ctrl = _videoCtrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final target = Duration(milliseconds: ptsMs.round().clamp(0, 86400000));
    await ctrl.seekTo(target);
  }

  Future<void> _refreshPresignedUrlsAndResume() async {
    final resumePos = _currentPosition;
    try {
      final refreshed = await ApiService.instance.fetchSessionDetail(
        widget.orgId,
        widget.roomName,
      );
      if (!mounted) return;
      setState(() => _detail = refreshed);
      await _initRecordingAt(
        _selectedRecordingIdx,
        restorePosition: resumePos,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: LKColors.danger),
      );
    }
  }

  SessionRecording? get _currentRecording {
    final recordings = _detail?.recordings ?? const [];
    if (_selectedRecordingIdx >= 0 && _selectedRecordingIdx < recordings.length) {
      return recordings[_selectedRecordingIdx];
    }
    return null;
  }

  SessionTelemetrySample? _sampleAtCurrentPosition() {
    final filtered = _selectedParticipantUid == null
        ? _telemetry
        : _telemetry
              .where((s) => s.participant == _selectedParticipantUid)
              .toList();
    if (filtered.isEmpty) return null;

    final currentPosMs = _currentPosition.inMilliseconds.toDouble();
    final rec = _currentRecording;

    // 1. Recalage temporel par horodatage absolu avec la capture vidéo
    final videoStartedAt = rec?.videoStartedAt;
    if (videoStartedAt != null) {
      final videoStartEpochMs =
          videoStartedAt.millisecondsSinceEpoch.toDouble();
      final targetEpochMs = videoStartEpochMs + currentPosMs;
      final videoDurationMs = (_totalDuration > Duration.zero
              ? _totalDuration
              : Duration(seconds: (rec?.durationS ?? 0).round()))
          .inMilliseconds
          .toDouble();

      // Filtrer les échantillons reçus pendant la fenêtre de cet enregistrement (+/- 2s de marge)
      final inRecordingWindow = filtered.where((s) {
        if (s.serverTs <= 0) return false;
        return s.serverTs >= (videoStartEpochMs - 2000) &&
            s.serverTs <= (videoStartEpochMs + videoDurationMs + 2000);
      }).toList();

      if (inRecordingWindow.isNotEmpty) {
        SessionTelemetrySample? best;
        for (final s in inRecordingWindow) {
          if (s.serverTs <= targetEpochMs) {
            best = s;
          } else {
            break;
          }
        }
        return best ?? inRecordingWindow.first;
      }
    }

    // 2. Fallback classique (si ptsMs est déjà aligné sur le début de la vidéo ou si videoStartedAt est absent)
    SessionTelemetrySample? best;
    for (final s in filtered) {
      if (s.ptsMs <= currentPosMs) {
        best = s;
      } else {
        break;
      }
    }
    return best ?? filtered.first;
  }

  double _alertVideoOffsetMs(SessionAlert a) {
    final rec = _currentRecording;
    if (rec?.videoStartedAt != null && a.ts > 0) {
      final startMs = rec!.videoStartedAt!.millisecondsSinceEpoch.toDouble();
      final diff = a.ts - startMs;
      if (diff >= 0) {
        return diff;
      }
    }
    return a.ptsMs;
  }

  String _formatDuration(Duration d) {
    final totalSec = d.inSeconds;
    final mins = (totalSec ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSec % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: LKColors.background,
        appBar: AppBar(
          backgroundColor: LKColors.surface,
          title: Text(
            detail?.displayTitle ?? widget.roomName,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (detail != null && !detail.finished)
              IconButton(
                icon: const Icon(Icons.videocam_rounded, color: LKColors.success),
                tooltip: 'Rejoindre en direct',
                onPressed: () {
                  final canControl =
                      AccountController.instance.canManageSessions;
                  final room = MobileRoom(
                    name: detail.roomName,
                    title: detail.title,
                    orgId: detail.orgId,
                    participantCount: 0,
                    recording: detail.recording,
                    recordingStatus: detail.recordingStatus,
                    canControlRecording: canControl,
                  );
                  context.push(
                    '/connect/${Uri.encodeComponent(detail.roomName)}',
                    extra: room,
                  );
                },
              ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Actualiser (et rafraîchir les liens vidéo)',
              onPressed: _loadAll,
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Padding(
                  padding: UIUtils.paddingXL,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: LKColors.danger,
                        size: 40,
                      ),
                      SizedBox(height: UIUtils.md),
                      Text(_error!, textAlign: TextAlign.center),
                      SizedBox(height: UIUtils.lg),
                      FilledButton(
                        onPressed: _loadAll,
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                ),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  // Réserve l'espace pour les contrôles vidéo, la bande télémétrie,
                  // la TabBar et un minimum de contenu dans la TabBarView, afin
                  // qu'une vidéo portrait (9:16) ou un écran paysage ne déborde jamais.
                  final maxVideoHeight = math
                      .min(
                        constraints.maxHeight * 0.45,
                        math.max(120.0, constraints.maxHeight - 220.0),
                      )
                      .clamp(120.0, 420.0);
                  return Column(
                    children: [
                      _buildVideoSection(
                        detail!,
                        maxVideoHeight: maxVideoHeight,
                      ),
                      _buildTelemetryStrip(),
                      const TabBar(
                        indicatorColor: LKColors.primary,
                        labelColor: LKColors.primary,
                        unselectedLabelColor: LKColors.textSecondary,
                        tabs: [
                          Tab(text: 'Marqueurs'),
                          Tab(text: 'Alertes'),
                          Tab(text: 'Participants'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildMarkersTab(),
                            _buildAlertsTab(),
                            _buildParticipantsTab(detail),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _buildVideoSection(
    SessionDetail detail, {
    required double maxVideoHeight,
  }) {
    if (detail.recordings.isEmpty) {
      return Container(
        height: math.min(160.0, maxVideoHeight),
        width: double.infinity,
        color: LKColors.surface,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.video_library_outlined,
              color: LKColors.textHint,
              size: 36,
            ),
            SizedBox(height: UIUtils.sm),
            Text(
              'Aucun enregistrement MP4 finalisé pour cette séance.',
              style: UIUtils.bodySmall(context),
            ),
          ],
        ),
      );
    }

    final ctrl = _videoCtrl;
    final initialized = ctrl != null && ctrl.value.isInitialized;
    final rawRatio = initialized ? ctrl.value.aspectRatio : (16 / 9);
    final aspectRatio =
        rawRatio.isFinite && rawRatio > 0 ? rawRatio : (16 / 9);
    final maxMs = _totalDuration.inMilliseconds > 0
        ? _totalDuration.inMilliseconds.toDouble()
        : 1.0;
    final posMs = _currentPosition.inMilliseconds
        .clamp(0, maxMs.round())
        .toDouble();

    return Container(
      color: Colors.black,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxVideoHeight),
            child: SizedBox(
              width: double.infinity,
              child: Center(
                child: AspectRatio(
                  aspectRatio: aspectRatio,
                  child: _videoInitializing
                      ? const Center(child: CircularProgressIndicator())
                      : _videoError != null
                      ? Center(
                          child: SingleChildScrollView(
                            padding: UIUtils.paddingLG,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _videoError!,
                                  textAlign: TextAlign.center,
                                  style: UIUtils.bodySmall(
                                    context,
                                  ).copyWith(color: LKColors.danger),
                                ),
                                SizedBox(height: UIUtils.sm),
                                FilledButton.icon(
                                  onPressed: _refreshPresignedUrlsAndResume,
                                  icon: const Icon(
                                    Icons.refresh_rounded,
                                    size: 16,
                                  ),
                                  label: const Text('Renouveler le lien vidéo'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : initialized
                      ? VideoPlayer(ctrl)
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ),
          Container(
            color: LKColors.surface,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                IconButton(
                  onPressed: initialized
                      ? () {
                          setState(() {
                            if (ctrl.value.isPlaying) {
                              ctrl.pause();
                            } else {
                              ctrl.play();
                            }
                          });
                        }
                      : null,
                  icon: Icon(
                    initialized && ctrl.value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
                Text(
                  _formatDuration(_currentPosition),
                  style: UIUtils.bodySmall(context),
                ),
                Expanded(
                  child: Slider(
                    min: 0,
                    max: maxMs,
                    value: posMs,
                    activeColor: LKColors.primary,
                    onChanged: initialized
                        ? (v) => _seekToMs(v)
                        : null,
                  ),
                ),
                Text(
                  _formatDuration(_totalDuration),
                  style: UIUtils.bodySmall(context),
                ),
                if (detail.recordings.length > 1)
                  DropdownButton<int>(
                    value: _selectedRecordingIdx,
                    dropdownColor: LKColors.surfaceElevated,
                    underline: const SizedBox.shrink(),
                    items: List.generate(
                      detail.recordings.length,
                      (i) => DropdownMenuItem(
                        value: i,
                        child: Text('Clip ${i + 1}'),
                      ),
                    ),
                    onChanged: (idx) {
                      if (idx != null) _initRecordingAt(idx);
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryStrip() {
    final sample = _sampleAtCurrentPosition();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: LKColors.surfaceElevated,
        border: Border(
          top: BorderSide(color: LKColors.border, width: 0.6),
          bottom: BorderSide(color: LKColors.border, width: 0.6),
        ),
      ),
      child: Row(
        children: [
          _KpiBadge(
            label: 'VITESSE',
            value: sample != null ? '${sample.speed.toStringAsFixed(1)} km/h' : '--',
            color: LKColors.primary,
          ),
          _KpiBadge(
            label: 'FC',
            value: sample != null && sample.heartRate > 0
                ? '${sample.heartRate} bpm'
                : '--',
            color: LKColors.danger,
          ),
          _KpiBadge(
            label: 'CADENCE',
            value: sample != null && sample.cadence > 0
                ? '${sample.cadence.round()} rpm'
                : '--',
            color: LKColors.success,
          ),
        ],
      ),
    );
  }

  Widget _buildMarkersTab() {
    if (_markers.isEmpty) {
      return Center(
        child: Text(
          'Aucun marqueur enregistré sur cette séance.',
          style: UIUtils.bodySmall(context),
        ),
      );
    }
    return ListView.separated(
      padding: UIUtils.paddingLG,
      itemCount: _markers.length,
      separatorBuilder: (_, _) => SizedBox(height: UIUtils.sm),
      itemBuilder: (context, index) {
        final m = _markers[index];
        return ListTile(
          tileColor: LKColors.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: UIUtils.borderRadiusAllMD,
            side: const BorderSide(color: LKColors.border),
          ),
          leading: Chip(
            label: Text(
              _formatDuration(
                Duration(milliseconds: m.ptsMs.round()),
              ),
            ),
          ),
          title: Text(m.label),
          subtitle: Text(
            [
              m.category,
              if (m.authorName.isNotEmpty) m.authorName,
              if (m.note != null && m.note!.isNotEmpty) m.note!,
            ].join(' • '),
          ),
          trailing: const Icon(
            Icons.play_circle_outline_rounded,
            color: LKColors.primary,
          ),
          onTap: () => _seekToMs(m.ptsMs),
        );
      },
    );
  }

  Widget _buildAlertsTab() {
    if (_alerts.isEmpty) {
      return Center(
        child: Text(
          'Aucune alerte physiologique sur cette séance.',
          style: UIUtils.bodySmall(context),
        ),
      );
    }
    return ListView.separated(
      padding: UIUtils.paddingLG,
      itemCount: _alerts.length,
      separatorBuilder: (_, _) => SizedBox(height: UIUtils.sm),
      itemBuilder: (context, index) {
        final a = _alerts[index];
        final alertPosMs = _alertVideoOffsetMs(a);
        return ListTile(
          tileColor: LKColors.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: UIUtils.borderRadiusAllMD,
            side: BorderSide(color: LKColors.danger.withValues(alpha: 0.4)),
          ),
          leading: const Icon(
            Icons.warning_amber_rounded,
            color: LKColors.danger,
          ),
          title: Text(a.message.isNotEmpty ? a.message : a.type),
          subtitle: Text(
            '${_formatDuration(Duration(milliseconds: alertPosMs.round()))}'
            '${a.value != null ? ' • Valeur: ${a.value!.toStringAsFixed(0)}' : ''}'
            '${a.threshold != null ? ' / Seuil: ${a.threshold!.toStringAsFixed(0)}' : ''}',
          ),
          onTap: () => _seekToMs(alertPosMs),
        );
      },
    );
  }

  Widget _buildParticipantsTab(SessionDetail detail) {
    if (detail.participants.isEmpty) {
      return Center(
        child: Text(
          'Aucun participant listé.',
          style: UIUtils.bodySmall(context),
        ),
      );
    }
    return ListView.separated(
      padding: UIUtils.paddingLG,
      itemCount: detail.participants.length,
      separatorBuilder: (_, _) => SizedBox(height: UIUtils.sm),
      itemBuilder: (context, index) {
        final p = detail.participants[index];
        final selected = _selectedParticipantUid == p.uid;
        return ListTile(
          tileColor: LKColors.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: UIUtils.borderRadiusAllMD,
            side: BorderSide(
              color: selected ? LKColors.primary : LKColors.border,
            ),
          ),
          leading: CircleAvatar(
            backgroundColor: LKColors.primary.withValues(alpha: 0.2),
            child: Text(
              p.displayName.isNotEmpty ? p.displayName[0].toUpperCase() : '?',
              style: const TextStyle(color: LKColors.primary),
            ),
          ),
          title: Text(p.displayName),
          subtitle: Text(
            [p.role, if (p.email != null) p.email!].join(' • '),
          ),
          trailing: selected
              ? const Icon(Icons.filter_alt_rounded, color: LKColors.primary)
              : null,
          onTap: () {
            setState(() {
              _selectedParticipantUid = selected ? null : p.uid;
            });
          },
        );
      },
    );
  }
}

class _KpiBadge extends StatelessWidget {
  const _KpiBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: UIUtils.bodySmall(context).copyWith(
              fontSize: 10,
              color: LKColors.textHint,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            style: UIUtils.titleSmall(context).copyWith(
              fontFamily: LiveKitTheme.fontFamily,
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
