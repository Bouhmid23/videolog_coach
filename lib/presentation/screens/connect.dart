import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../../core/call_foreground_service.dart';
import '../../data/user_role.dart';
import '../../exts.dart';
import '../../theme.dart';
import '../../utils.dart';
import '../utils/ui_utils.dart';

const String kApiBaseUrl = 'https://api.videolog.app';

// Config POC
const String kLiveKitWsUrl = 'wss://livekit.videolog.app';
const String kDefaultRoom = 'poc-room';

class JoinArgs {
  JoinArgs({
    required this.url,
    required this.token,
    required this.username,
    this.role = UserRole.trainee,
    this.e2ee = false,
    this.e2eeKey,
    this.simulcast = false,
    this.adaptiveStream = true,
    this.dynacast = false,
    this.preferredCodec = 'H264',
    this.enableBackupVideoCodec = true,
  });

  final String url;
  final String token;
  final String username;
  final UserRole role;
  final bool e2ee;
  final String? e2eeKey;
  final bool simulcast;
  final bool adaptiveStream;
  final bool dynacast;
  final String preferredCodec;
  final bool enableBackupVideoCodec;
}

// ─── PreJoinPage ────────────────────────────────────────────────────────────

class PreJoinPage extends StatefulWidget {
  const PreJoinPage({required this.args, super.key});
  final JoinArgs args;
  @override
  State<StatefulWidget> createState() => _PreJoinPageState();
}

class _PreJoinPageState extends State<PreJoinPage> {
  static const _prefKeyEnableVideo = 'prejoin-enable-video';
  static const _prefKeyEnableAudio = 'prejoin-enable-audio';
  static const _prefKeyCameraPosition = 'prejoin-camera-position';
  static const _prefKeyVideoResolution = 'prejoin-video-resolution';

  static final List<VideoParameters> _videoResolutionOptions = [
    VideoParametersPresets.h480_43,
    VideoParametersPresets.h540_169,
    VideoParametersPresets.h720_169,
    VideoParametersPresets.h1080_169,
  ];

  List<MediaDevice> _audioInputs = [];
  List<MediaDevice> _videoInputs = [];
  StreamSubscription? _subscription;

  bool _busy = false;
  bool _enableVideo = true;
  bool _enableAudio = true;
  LocalAudioTrack? _audioTrack;
  LocalVideoTrack? _videoTrack;
  CameraPosition _cameraPosition = CameraPosition.front;
  MediaDevice? _selectedAudioDevice;
  VideoParameters _videoParameters = VideoParametersPresets.h480_43;

  static String _resolutionKey(VideoParameters parameters) =>
      '${parameters.dimensions.width}x${parameters.dimensions.height}';

  @override
  void initState() {
    super.initState();
    unawaited(_initStateAsync());
  }

  Future<void> _initStateAsync() async {
    await _readPrefs();
    _subscription = Hardware.instance.onDeviceChange.stream.listen(_loadDevices);
    final devices = await Hardware.instance.enumerateDevices();
    await _loadDevices(devices);
  }

  @override
  void deactivate() {
    unawaited(_subscription?.cancel());
    super.deactivate();
  }

  Future<void> _loadDevices(List<MediaDevice> devices) async {
    _audioInputs = devices.where((d) => d.kind == 'audioinput').toList();
    _videoInputs = devices.where((d) => d.kind == 'videoinput').toList();
    if (_selectedAudioDevice != null && !_audioInputs.contains(_selectedAudioDevice)) {
      _selectedAudioDevice = null;
    }
    if (_audioInputs.isEmpty) { await _audioTrack?.stop(); _audioTrack = null; }
    if (_videoInputs.isEmpty) { await _videoTrack?.stop(); _videoTrack = null; }
    if (_enableAudio && _audioInputs.isNotEmpty && _selectedAudioDevice == null) {
      _selectedAudioDevice = _audioInputs.first;
      Future.delayed(const Duration(milliseconds: 100), () async {
        if (!mounted) return;
        await _changeLocalAudioTrack();
        if (mounted) setState(() {});
      });
    }
    if (_enableVideo && _videoInputs.isNotEmpty && _videoTrack == null) {
      Future.delayed(const Duration(milliseconds: 100), () async {
        if (!mounted) return;
        await _changeLocalVideoTrack();
        if (mounted) setState(() {});
      });
    }
    if (mounted) setState(() {});
  }

  Future<void> _setEnableVideo(bool value) async {
    _enableVideo = value;
    await _writePrefs();
    if (!_enableVideo) {
      await _videoTrack?.stop();
      _videoTrack = null;
    } else {
      await _changeLocalVideoTrack();
    }
    setState(() {});
  }

  Future<void> _setEnableAudio(bool value) async {
    _enableAudio = value;
    await _writePrefs();
    if (!_enableAudio) {
      await _audioTrack?.stop();
      _audioTrack = null;
      _selectedAudioDevice = null;
    } else {
      if (_selectedAudioDevice == null && _audioInputs.isNotEmpty) {
        _selectedAudioDevice = _audioInputs.first;
      }
      await _changeLocalAudioTrack();
    }
    setState(() {});
  }

  Future<void> _changeLocalAudioTrack() async {
    if (!_enableAudio) return;
    if (_audioTrack != null) { await _audioTrack!.stop(); _audioTrack = null; }
    if (_selectedAudioDevice != null) {
      _audioTrack = await LocalAudioTrack.create(
        AudioCaptureOptions(deviceId: _selectedAudioDevice!.deviceId),
      );
      await _audioTrack!.start();
    }
  }

  Future<void> _changeLocalVideoTrack() async {
    if (!_enableVideo) return;
    
    if (Platform.isAndroid) {
      await CallForegroundService.start(
        roomName: 'preview',
        username: 'preview',
      );
    }
    
    if (_videoTrack != null) { await _videoTrack!.stop(); _videoTrack = null; }
    _videoTrack = await LocalVideoTrack.createCameraTrack(CameraCaptureOptions(
      cameraPosition: _cameraPosition,
      params: _videoParameters,
    ));
    await _videoTrack!.start();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    if (Platform.isAndroid) {
      unawaited(CallForegroundService.stop());
    }
    super.dispose();
  }

  Future<void> _join(BuildContext context) async {
    _busy = true;
    setState(() {});

    final args = widget.args;

    try {
      E2EEOptions? e2eeOptions;
      if (args.e2ee && args.e2eeKey != null) {
        final keyProvider = await BaseKeyProvider.create();
        e2eeOptions = E2EEOptions(keyProvider: keyProvider);
        await keyProvider.setKey(args.e2eeKey!);
      }

      const cameraEncoding = VideoEncoding(maxBitrate: 2 * 1000 * 1000, maxFramerate: 30);
      const screenEncoding = VideoEncoding(maxBitrate: 3 * 1000 * 1000, maxFramerate: 15);

      final room = Room(
        roomOptions: RoomOptions(
          adaptiveStream: args.adaptiveStream,
          dynacast: args.dynacast,
          defaultAudioPublishOptions: const AudioPublishOptions(
            name: 'custom_audio_track_name',
          ),
          defaultCameraCaptureOptions: const CameraCaptureOptions(
            maxFrameRate: 30,
            params: VideoParameters(dimensions: VideoDimensions(640, 480)),
          ),
          defaultVideoPublishOptions: VideoPublishOptions(
            simulcast: args.simulcast,
            videoCodec: args.preferredCodec,
            backupVideoCodec: BackupVideoCodec(enabled: args.enableBackupVideoCodec),
            videoEncoding: cameraEncoding,
            screenShareEncoding: screenEncoding,
          ),
          encryption: e2eeOptions,
        ),
      );

      final listener = room.createListener();
      await room.prepareConnection(args.url, args.token);

      await room.connect(
        args.url,
        args.token,
        fastConnectOptions: FastConnectOptions(
          microphone: TrackOption(track: _audioTrack),
          camera: TrackOption(track: _videoTrack),
        ),
      );

      if (!context.mounted) return;
      await context.push<void>(
        '/room',
        extra: (room, listener, args.role),
      );
    } catch (error) {
      debugPrint('Could not connect $error');
      if (!context.mounted) return;
      await context.showErrorDialog(error);
    } finally {
      setState(() { _busy = false; });
      if (context.mounted) context.go('/home/${widget.args.username}');
    }
  }

  void _actionBack(BuildContext context) async {
    await _setEnableVideo(false);
    await _setEnableAudio(false);
    if (!context.mounted) return;
    context.pop();
  }

  Future<void> _readPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _enableVideo = prefs.getBool(_prefKeyEnableVideo) ?? true;
      _enableAudio = prefs.getBool(_prefKeyEnableAudio) ?? true;
      final positionName = prefs.getString(_prefKeyCameraPosition);
      _cameraPosition = CameraPosition.values.firstWhere(
        (position) => position.name == positionName,
        orElse: () => CameraPosition.front,
      );
      final resolutionKey = prefs.getString(_prefKeyVideoResolution);
      _videoParameters = _videoResolutionOptions.firstWhere(
        (parameters) => _resolutionKey(parameters) == resolutionKey,
        orElse: () => VideoParametersPresets.h480_43,
      );
    });
  }

  Future<void> _writePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyEnableVideo, _enableVideo);
    await prefs.setBool(_prefKeyEnableAudio, _enableAudio);
    await prefs.setString(_prefKeyCameraPosition, _cameraPosition.name);
    await prefs.setString(
      _prefKeyVideoResolution,
      _resolutionKey(_videoParameters),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LKColors.background,
      appBar: AppBar(
        backgroundColor: LKColors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        foregroundColor: LKColors.textPrimary,
        title: Text('Configurer les appareils', style: UIUtils.titleMedium(context)),
        leading: IconButton(
          icon: UIUtils.textPrimaryIcon(Icons.arrow_back_rounded),
          onPressed: () => _actionBack(context),
        ),
        elevation: 0,
        shadowColor: Colors.transparent,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: UIUtils.paddingLG,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Video Preview
                Card(
                  color: LKColors.surface,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: UIUtils.borderRadiusAllLG,
                    side: BorderSide(color: LKColors.border, width: 0.5),
                  ),
                  child: Container(
                    height: 240,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: LKColors.background,
                      borderRadius: UIUtils.borderRadiusAllLG,
                    ),
                    child: _videoTrack != null
                        ? ClipRRect(
                            borderRadius: UIUtils.borderRadiusAllLG,
                            child: VideoTrackRenderer(
                              renderMode: VideoRenderMode.auto,
                              _videoTrack!,
                            ),
                          )
                        : AnimatedOpacity(
                            opacity: _enableVideo ? 1.0 : 0.5,
                            duration: UIUtils.animationDuration,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.videocam_off_rounded,
                                  color: LKColors.textHint,
                                  size: 60,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Caméra désactivée',
                                  style: UIUtils.bodySmall(context).copyWith(
                                        color: LKColors.textHint,
                                      ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
                SizedBox(height: UIUtils.lg),
                
                // Camera Section
                _buildToggleSection(
                  icon: Icons.videocam_rounded,
                  title: 'Caméra',
                  value: _enableVideo,
                  onChanged: _setEnableVideo,
                  disabled: _videoInputs.isEmpty,
                ),
                SizedBox(height: UIUtils.sm),
                
                if (_enableVideo && _videoInputs.isNotEmpty) ...[
                  _buildCameraPositionSelector(context),
                  SizedBox(height: UIUtils.sm),
                  _buildVideoResolutionSelector(context),
                ],
                SizedBox(height: UIUtils.lg),
                
                // Microphone Section
                _buildToggleSection(
                  icon: Icons.mic_rounded,
                  title: 'Microphone',
                  value: _enableAudio,
                  onChanged: _setEnableAudio,
                  disabled: _audioInputs.isEmpty,
                ),
                SizedBox(height: UIUtils.sm),
                
                if (_enableAudio && _audioInputs.isNotEmpty)
                  _buildDropdown<MediaDevice>(
                    label: 'Sélectionner le microphone',
                    items: _audioInputs,
                    value: _selectedAudioDevice,
                    onChanged: (MediaDevice? value) async {
                      if (value != null) {
                        _selectedAudioDevice = value;
                        await _changeLocalAudioTrack();
                        setState(() {});
                      }
                    },
                    itemBuilder: (d) => Text(d.label, style: UIUtils.bodySmall(context)),
                  ),
                SizedBox(height: UIUtils.xxl),
                
                // Join Button
                FilledButton(
                  onPressed: _busy ? null : () async => await _join(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: LKColors.primary,
                    foregroundColor: Colors.white,
                    padding: UIUtils.paddingVerticalLG.add(UIUtils.paddingHorizontalXXL),
                    shape: RoundedRectangleBorder(borderRadius: UIUtils.borderRadiusAllMD),
                    elevation: 0,
                    shadowColor: Colors.transparent,
                  ),
                  child: _busy
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            ),
                            SizedBox(width: UIUtils.sm),
                            Text('REJOINDRE', style: UIUtils.labelLarge(context).copyWith(color: Colors.white)),
                          ],
                        )
                      : Text('REJOINDRE', style: UIUtils.labelLarge(context).copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPositionSelector(BuildContext context) {
    return Container(
      padding: UIUtils.paddingMD,
      decoration: BoxDecoration(
        color: LKColors.surface,
        borderRadius: UIUtils.borderRadiusAllMD,
        border: Border.all(color: LKColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.cameraswitch_rounded,
                color: LKColors.textPrimary,
                size: 20,
              ),
              SizedBox(width: UIUtils.sm),
              Text(
                'Orientation de la caméra',
                style: UIUtils.labelMedium(context).copyWith(
                  color: LKColors.textPrimary,
                ),
              ),
            ],
          ),
          SizedBox(height: UIUtils.sm),
          SegmentedButton<CameraPosition>(
            segments: [
              ButtonSegment<CameraPosition>(
                value: CameraPosition.front,
                label: Text('Frontale', style: UIUtils.bodySmall(context)),
                icon: const Icon(Icons.camera_front_rounded, size: 18),
              ),
              ButtonSegment<CameraPosition>(
                value: CameraPosition.back,
                label: Text('Dorsale', style: UIUtils.bodySmall(context)),
                icon: const Icon(Icons.camera_rear_rounded, size: 18),
              ),
            ],
            selected: {_cameraPosition},
            showSelectedIcon: false,
            onSelectionChanged: (selection) async {
              _cameraPosition = selection.first;
              await _writePrefs();
              await _changeLocalVideoTrack();
              if (mounted) setState(() {});
            },
            style: SegmentedButton.styleFrom(
              backgroundColor: LKColors.surface,
              foregroundColor: LKColors.textPrimary,
              selectedBackgroundColor: LKColors.primary,
              selectedForegroundColor: Colors.white,
              padding: UIUtils.paddingVerticalSM.add(
                UIUtils.paddingHorizontalSM,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: UIUtils.borderRadiusAllSM,
              ),
              side: BorderSide(color: LKColors.border, width: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoResolutionSelector(BuildContext context) {
    return Container(
      padding: UIUtils.paddingMD,
      decoration: BoxDecoration(
        color: LKColors.surface,
        borderRadius: UIUtils.borderRadiusAllMD,
        border: Border.all(color: LKColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.high_quality_rounded,
                color: LKColors.textPrimary,
                size: 20,
              ),
              SizedBox(width: UIUtils.sm),
              Text(
                'Résolution vidéo',
                style: UIUtils.labelMedium(context).copyWith(
                  color: LKColors.textPrimary,
                ),
              ),
            ],
          ),
          SizedBox(height: UIUtils.sm),
          DropdownButtonHideUnderline(
            child: DropdownButton2<VideoParameters>(
              isExpanded: true,
              value: _videoParameters,
              items: _videoResolutionOptions
                  .map(
                    (parameters) => DropdownMenuItem<VideoParameters>(
                      value: parameters,
                      child: Text(
                        '${parameters.dimensions.width} x ${parameters.dimensions.height}',
                        style: UIUtils.bodySmall(context),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) async {
                if (value == null || value == _videoParameters) return;
                _videoParameters = value;
                await _writePrefs();
                await _changeLocalVideoTrack();
                if (mounted) setState(() {});
              },
              buttonStyleData: ButtonStyleData(
                padding: UIUtils.paddingHorizontalMD,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: UIUtils.borderRadiusAllSM,
                ),
              ),
              menuItemStyleData: MenuItemStyleData(
                height: 44,
                padding: UIUtils.paddingHorizontalMD,
              ),
              dropdownStyleData: DropdownStyleData(
                maxHeight: 200,
                decoration: BoxDecoration(
                  color: LKColors.surfaceElevated,
                  borderRadius: UIUtils.borderRadiusAllMD,
                  border: Border.all(color: LKColors.border, width: 0.5),
                ),
                elevation: 8,
                offset: const Offset(0, 4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleSection({
    required IconData icon,
    required String title,
    required bool value,
    required Future<void> Function(bool) onChanged,
    bool disabled = false,
  }) {
    return Container(
      padding: UIUtils.paddingMD,
      decoration: BoxDecoration(
        color: LKColors.surface,
        borderRadius: UIUtils.borderRadiusAllMD,
        border: Border.all(color: LKColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, color: disabled ? LKColors.textHint : LKColors.textPrimary, size: 20),
          SizedBox(width: UIUtils.sm),
          Expanded(
            child: Text(
              title,
              style: UIUtils.labelMedium(context).copyWith(
                    color: disabled ? LKColors.textHint : LKColors.textPrimary,
                  ),
            ),
          ),
          Switch(
            value: value,
            onChanged: disabled ? null : onChanged,
            activeThumbColor: LKColors.primary,
            inactiveThumbColor: LKColors.textHint,
            inactiveTrackColor: LKColors.border,
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required List<T> items,
    required T? value,
    required void Function(T?) onChanged,
    required Widget Function(T) itemBuilder,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: LKColors.surface,
        borderRadius: UIUtils.borderRadiusAllMD,
        border: Border.all(color: LKColors.border, width: 0.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton2<T>(
          isExpanded: true,
          hint: Padding(
            padding: UIUtils.paddingHorizontalMD,
            child: Text(
              label,
              style: UIUtils.bodySmall(context).copyWith(color: LKColors.textHint),
            ),
          ),
          items: items.map((item) => DropdownMenuItem<T>(
            value: item,
            child: Padding(
              padding: UIUtils.paddingHorizontalMD,
              child: itemBuilder(item),
            ),
          )).toList(),
          value: value,
          onChanged: onChanged,
          buttonStyleData: ButtonStyleData(
            padding: UIUtils.paddingHorizontalMD,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: UIUtils.borderRadiusAllSM,
            ),
          ),
          menuItemStyleData: MenuItemStyleData(
            height: 44,
            padding: UIUtils.paddingHorizontalMD,
          ),
          dropdownStyleData: DropdownStyleData(
            maxHeight: 200,
            decoration: BoxDecoration(
              color: LKColors.surfaceElevated,
              borderRadius: UIUtils.borderRadiusAllMD,
              border: Border.all(color: LKColors.border, width: 0.5),
            ),
            elevation: 8,
            offset: const Offset(0, 4),
          ),
        ),
      ),
    );
  }
}

// ─── ConnectPage ────────────────────────────────────────────────────────────

class ConnectPage extends StatefulWidget {
  const ConnectPage({
    super.key,
    this.initialUsername,
    this.roomName = kDefaultRoom,
  });

  final String? initialUsername;
  final String roomName;
  @override
  State<StatefulWidget> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final _usernameCtrl = TextEditingController();
  bool _busy = false;
  final UserRole _role = UserRole.trainee;
  final bool _simulcast = false;
  final bool _adaptiveStream = true;
  final bool _dynacast = true;
  final bool _e2ee = false;
  final String _preferredCodec = 'H264';

  @override
  void initState() {
    super.initState();
    _usernameCtrl.text = widget.initialUsername ?? '';
    if (lkPlatformIs(PlatformType.android)) {
      unawaited(_checkPermissions());
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    super.dispose();
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

  Future<String> _fetchToken({
    required String identity,
    required String room,
  }) async {
    final response = await http.post(
      Uri.parse('$kApiBaseUrl/token'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'identity': identity, 'room': room}),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['token'] as String;
    } else {
      throw Exception('Token fetch failed (${response.statusCode}): ${response.body}');
    }
  }

  Future<void> _connect(BuildContext ctx) async {
    if (_usernameCtrl.text.trim().isEmpty) {
      await ctx.showErrorDialog('Veuillez entrer un nom d\'utilisateur');
      return;
    }

    setState(() { _busy = true; });

    try {
      final username = _usernameCtrl.text.trim();
      // LiveKit identifie un participant par son identité : deux personnes avec
      // le même nom se déconnectent mutuellement. On ajoute un suffixe unique
      // à l'identité et on ne l'affiche pas (voir displayNameForIdentity).
      final suffix = Random().nextInt(0xFFFFFF).toRadixString(36);
      final identity = '$username$kIdentitySuffixSeparator$suffix';
      debugPrint('Connexion → room=${widget.roomName} user=$username identity=$identity');

      final token = await _fetchToken(identity: identity, room: widget.roomName);

      if (!ctx.mounted) return;
      await ctx.push<void>(
        '/prejoin',
        extra: JoinArgs(
          url: kLiveKitWsUrl,
          username: username,
          token: token,
          role: _role,
          e2ee: _e2ee,
          simulcast: _simulcast,
          adaptiveStream: _adaptiveStream,
          dynacast: _dynacast,
          preferredCodec: _preferredCodec,
          enableBackupVideoCodec: _preferredCodec != 'VP8',
        ),
      );
    } catch (error) {
      debugPrint('Erreur connexion: $error');
      if (!ctx.mounted) return;
      await ctx.showErrorDialog(error);
    } finally {
      setState(() { _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LKColors.background,
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo
                    AnimatedContainer(
                      duration: UIUtils.animationDuration,
                      padding: UIUtils.paddingXXL,
                      child: Image.asset(
                        'images/v.png',
                        height: 80,
                        fit: BoxFit.contain,
                      ),
                    ),


                    SizedBox(height: UIUtils.xxl),

                    // Username Field
                    TextField(
                      controller: _usernameCtrl,
                      decoration: UIUtils.inputDecoration(
                        labelText: 'Nom du participant',
                        hintText: 'ex: driver-01',
                        prefixIcon: Icons.person_rounded,
                      ),
                      style: UIUtils.bodyLarge(context),
                      cursorColor: LKColors.primary,
                    ),
                    SizedBox(height: UIUtils.lg),

                    // Role Selection
                    /*Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        *//*Text(
                          'Votre rôle',
                          style: UIUtils.labelMedium(context),
                        ),
                        SizedBox(height: UIUtils.sm),
                        Card(
                          color: LKColors.surface,
                          surfaceTintColor: Colors.transparent,
                          elevation: 0,
                          margin: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: UIUtils.borderRadiusAllMD,
                            side: BorderSide(color: LKColors.border, width: 0.5),
                          ),
                          child: Padding(
                            padding: UIUtils.paddingSM,
                            child: SegmentedButton<UserRole>(
                              segments: [
                                ButtonSegment<UserRole>(
                                  value: UserRole.trainee,
                                  label: Text('Trainee', style: UIUtils.bodySmall(context)),
                                  icon: Icon(Icons.directions_run_rounded, size: 18),
                                ),
                                ButtonSegment<UserRole>(
                                  value: UserRole.coach,
                                  label: Text('Coach', style: UIUtils.bodySmall(context)),
                                  icon: Icon(Icons.sports_rounded, size: 18),
                                ),
                              ],
                              selected: {_role},
                              onSelectionChanged: (selection) =>
                                  setState(() => _role = selection.first),
                              style: SegmentedButton.styleFrom(
                                backgroundColor: LKColors.surface,
                                foregroundColor: LKColors.textPrimary,
                                selectedBackgroundColor: LKColors.primary,
                                selectedForegroundColor: Colors.white,
                                padding: UIUtils.paddingVerticalSM.add(UIUtils.paddingHorizontalLG),
                                shape: RoundedRectangleBorder(
                                  borderRadius: UIUtils.borderRadiusAllSM,
                                ),
                                side: BorderSide(color: LKColors.border, width: 0.5),
                              ),
                            ),
                          ),
                        ),*//*
                      ],
                    ),*/
                    SizedBox(height: UIUtils.xxl),

                    // Connect Button
                    AnimatedContainer(
                      duration: UIUtils.animationDuration,
                      width: _busy ? 200 : double.infinity,
                      child: FilledButton(
                        onPressed: _busy ? null : () => _connect(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: LKColors.primary,
                          foregroundColor: Colors.white,
                          padding: UIUtils.paddingVerticalLG.add(UIUtils.paddingHorizontalXXL),
                          shape: RoundedRectangleBorder(borderRadius: UIUtils.borderRadiusAllMD),
                          elevation: 0,
                          shadowColor: Colors.transparent,
                        ),
                        child: _busy
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: UIUtils.sm),
                                  Text('CONNEXION...', style: UIUtils.labelLarge(context).copyWith(color: Colors.white)),
                                ],
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.login_rounded, size: 20, color: Colors.white),
                                  SizedBox(width: UIUtils.sm),
                                  Text('CONNECTER', style: UIUtils.labelLarge(context).copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                                ],
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
}
