import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/map_tile_source.dart';

/// Entrée pour un participant sur la carte avec support de l'altitude et du bearing
class ParticipantsMapEntry {
  final String identity;
  final String? label;
  final double? lat;
  final double? lng;
  final double? altitude;      // En mètres
  final double? bearing;       // En degrés (0-360)
  final double? speed;         // En km/h
  final bool isLocal;

  const ParticipantsMapEntry({
    required this.identity,
    this.label,
    this.lat,
    this.lng,
    this.altitude,
    this.bearing,
    this.speed,
    this.isLocal = false,
  });

  bool get hasPosition => lat != null && lng != null;
}

class _MapTile {
  final ui.Image image;
  final Offset offset;
  const _MapTile(this.image, this.offset);
}

/// Widget de carte interactive pour afficher les positions des participants
///
/// Fonctionnalités :
/// - Auto-centrage sur les participants
/// - Zoom automatique et manuel (pinch-to-zoom)
/// - Déplacement par glissement (drag)
/// - Affichage des infobulles au tap sur un marqueur
/// - Design moderne avec ombres et animations
/// - Fallback esthétique en mode hors ligne
class ParticipantsMapWidget extends StatefulWidget {
  final List<ParticipantsMapEntry> participants;
  final MapTileSource tileSource;
  final bool showAltitude;      // Afficher l'altitude dans les infobulles
  final bool showBearing;       // Afficher le bearing dans les infobulles
  final bool showSpeed;         // Afficher la vitesse dans les infobulles

  const ParticipantsMapWidget({
    super.key,
    required this.participants,
    this.tileSource = MapTileSource.openStreetMap,
    this.showAltitude = true,
    this.showBearing = true,
    this.showSpeed = true,
  });

  static const double size = 140;  // Taille de la carte (compacte pour la galerie)

  @override
  State<ParticipantsMapWidget> createState() => _ParticipantsMapWidgetState();
} 

class _ParticipantsMapWidgetState extends State<ParticipantsMapWidget>
    with SingleTickerProviderStateMixin {
  final Map<String, _MapTile> _tiles = {};
  String _signature = '';
  
  // État pour le zoom et la position manuels
  int _zoom = 15;
  double _left = 0;
  double _top = 0;
  
  // Animation pour les transitions fluides
  late AnimationController _animationController;
  Animation<double>? _zoomAnimation;
  Animation<Offset>? _positionAnimation;
  
  // Target pour l'animation
  int _targetZoom = 15;
  Offset _targetOffset = Offset.zero;
  
  // État pour les infobulles
  ParticipantsMapEntry? _selectedParticipant;
  OverlayEntry? _tooltipOverlay;
  
  // Gestion du gesture (drag et zoom)
  Offset? _dragStart;
  double? _initialZoom;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _refresh();
  }

  @override
  void didUpdateWidget(covariant ParticipantsMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tileSource != widget.tileSource ||
        oldWidget.participants != widget.participants) {
      _refresh();
    }
  }

  @override
  void dispose() {
    _removeTooltip();
    for (final t in _tiles.values) {
      t.image.dispose();
    }
    _tiles.clear();
    _animationController.dispose();
    super.dispose();
  }

  void _removeTooltip() {
    _tooltipOverlay?.remove();
    _tooltipOverlay = null;
    if (mounted) setState(() => _selectedParticipant = null);
  }

  Future<void> _refresh() async {
    final pts = widget.participants.where((p) => p.hasPosition).toList();
    if (pts.isEmpty) {
      if (mounted) setState(() {});
      return;
    }

    double minLat = double.infinity, maxLat = -double.infinity;
    double minLng = double.infinity, maxLng = -double.infinity;
    
    // On se concentre sur les participants distants pour le centrage si possible
    final remotePts = pts.where((p) => !p.isLocal).toList();
    final targets = remotePts.isNotEmpty ? remotePts : pts;

    for (final p in targets) {
      minLat = math.min(minLat, p.lat!);
      maxLat = math.max(maxLat, p.lat!);
      minLng = math.min(minLng, p.lng!);
      maxLng = math.max(maxLng, p.lng!);
    }

    // Ajouter une marge plus généreuse pour une meilleure vue
    final latPadding = (maxLat - minLat).abs() * 0.35;
    final lngPadding = (maxLng - minLng).abs() * 0.35;
    minLat -= latPadding;
    maxLat += latPadding;
    minLng -= lngPadding;
    maxLng += lngPadding;

    final size = ParticipantsMapWidget.size;
    final zoom = _fitZoom(minLat, maxLat, minLng, maxLng, size);

    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;
    final cx = _lngToWorldX(centerLng, zoom);
    final cy = _latToWorldY(centerLat, zoom);
    final left = cx - size / 2;
    final top = cy - size / 2;

    final txMin = (left / 256).floor();
    final txMax = ((left + size) / 256).floor();
    final tyMin = (top / 256).floor();
    final tyMax = ((top + size) / 256).floor();

    final sig =
        '${widget.tileSource.urlTemplate}|$zoom|$txMin:$txMax|$tyMin:$tyMax';
    
    if (sig == _signature) {
      if (mounted) setState(() {});
      return;
    }
    
    _signature = sig;
    _targetZoom = zoom;
    _targetOffset = Offset(left, top);
    
    // Démarrer l'animation vers la nouvelle position
    _animateToTarget();

    final base = widget.tileSource.urlTemplate;

    final wanted = <String>[];
    for (var tx = txMin; tx <= txMax; tx++) {
      for (var ty = tyMin; ty <= tyMax; ty++) {
        wanted.add('$zoom/$tx/$ty');
      }
    }

    final newTiles = <String, _MapTile>{};
    for (final key in wanted) {
      final cacheKey = '${widget.tileSource.urlTemplate}|$key';
      final existing = _tiles[cacheKey];
      if (existing != null) {
        newTiles[cacheKey] = existing;
        continue;
      }
      try {
        final url = base
            .replaceAll('{z}', '$zoom')
            .replaceAll('{x}', key.split('/')[1])
            .replaceAll('{y}', key.split('/')[2]);
        final res = await http.get(
          Uri.parse(url),
          headers: const {'User-Agent': 'livekitapp-hud/1.0'},
        );
        if (res.statusCode != 200) continue;
        final codec = await ui.instantiateImageCodec(res.bodyBytes);
        final frame = await codec.getNextFrame();
        codec.dispose();
        final img = frame.image;
        final tx = int.parse(key.split('/')[1]);
        final ty = int.parse(key.split('/')[2]);
        newTiles[cacheKey] = _MapTile(
          img,
          Offset(tx * 256 - left, ty * 256 - top),
        );
      } catch (_) {
        // fallback: painted tiles remain visible
      }
    }

    for (final entry in _tiles.entries) {
      if (!newTiles.containsKey(entry.key)) {
        entry.value.image.dispose();
      }
    }
    _tiles
      ..clear()
      ..addAll(newTiles);
    if (mounted) setState(() {});
  }

  void _animateToTarget() {
    _zoomAnimation = Tween<double>(begin: _zoom.toDouble(), end: _targetZoom.toDouble())
        .animate(CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeOutBack,
        ));
    
    _positionAnimation = Tween<Offset>(
      begin: Offset(_left, _top),
      end: _targetOffset,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    ));

    _animationController
      ..reset()
      ..forward();
  }

  void _handleTap(Offset globalPosition, Size size) {
    // Convertir la position globale en position locale
    final localPosition = (context.findRenderObject() as RenderBox?)?.globalToLocal(globalPosition);
    if (localPosition == null) return;
    
    // Trouver le participant cliqué
    for (final p in widget.participants.where((e) => e.hasPosition)) {
      final px = _lngToWorldX(p.lng!, _zoom) - _left;
      final py = _latToWorldY(p.lat!, _zoom) - _top;
      final distance = (Offset(px, py) - localPosition).distance;
      
      if (distance < 16) { // Rayon de clic du marqueur
        _showTooltip(p, globalPosition, size);
        return;
      }
    }
    
    // Clic en dehors des marqueurs : fermer l'infobulle
    _removeTooltip();
  }

  void _showTooltip(ParticipantsMapEntry participant, Offset position, Size size) {
    _removeTooltip();
    
    if (!mounted) return;
    
    setState(() => _selectedParticipant = participant);
    
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    final tooltip = OverlayEntry(
      builder: (context) => _TooltipWidget(
        participant: participant,
        position: position,
        renderBox: renderBox,
        showAltitude: widget.showAltitude,
        showBearing: widget.showBearing,
        showSpeed: widget.showSpeed,
        onDismiss: _removeTooltip,
      ),
    );
    
    _tooltipOverlay = tooltip;
    Overlay.of(context).insert(tooltip);
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _dragStart = details.localFocalPoint;
    _initialZoom = _zoom.toDouble();
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (_dragStart == null || _initialZoom == null) return;
    
    // Gestion du zoom (pinch)
    final newZoom = (_initialZoom! * details.scale).clamp(10.0, 19.0);
    if (newZoom != _zoom) {
      setState(() {
        _zoom = newZoom.round();
        _left = _targetOffset.dx + (_dragStart!.dx - details.localFocalPoint.dx) * 2;
        _top = _targetOffset.dy + (_dragStart!.dy - details.localFocalPoint.dy) * 2;
        _targetOffset = Offset(_left, _top);
      });
      _refresh();
    }
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _dragStart = null;
    _initialZoom = null;
  }

  @override
  Widget build(BuildContext context) {
    final size = ParticipantsMapWidget.size;
    final hasPositions = widget.participants.any((p) => p.hasPosition);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.grey[900]!.withValues(alpha: 0.95),
              Colors.grey[850]!.withValues(alpha: 0.95),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 4),
              spreadRadius: 2,
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 0),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: GestureDetector(
          onTapDown: (details) => _handleTap(details.globalPosition, Size(size, size)),
          onScaleStart: _handleScaleStart,
          onScaleUpdate: _handleScaleUpdate,
          onScaleEnd: _handleScaleEnd,
          behavior: HitTestBehavior.opaque,
          child: !hasPositions
              ? _buildEmptyState(size)
              : AnimatedBuilder(
                  animation: _animationController,
                  builder: (context, child) {
                    final currentZoom = _zoomAnimation?.value ?? _zoom.toDouble();
                    final currentOffset = _positionAnimation?.value ?? Offset(_left, _top);
                    
                    return CustomPaint(
                      painter: _ParticipantsMapPainter(
                        participants: widget.participants,
                        zoom: currentZoom.round(),
                        left: currentOffset.dx,
                        top: currentOffset.dy,
                        tiles: _tiles,
                        source: widget.tileSource,
                        selectedIdentity: _selectedParticipant?.identity,
                      ),
                      size: Size(size, size),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(double size) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.location_searching,
            size: 36,
            color: Colors.white.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 8),
          Text(
            'Aucune position GPS',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            'Les données GPS des participants\nseront affichées ici',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 9,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Projections Web Mercator ───────────────────────────────────────────────
double _lngToWorldX(double lng, int z) =>
    (lng + 180.0) / 360.0 * (256.0 * math.pow(2, z).toDouble());

double _latToWorldY(double lat, int z) {
  final rad = lat * math.pi / 180.0;
  final merc = math.log(math.tan(rad) + 1.0 / math.cos(rad));
  return (1.0 - merc / math.pi) / 2.0 * (256.0 * math.pow(2, z).toDouble());
}

int _fitZoom(
  double minLat,
  double maxLat,
  double minLng,
  double maxLng,
  double size,
) {
  for (var z = 18; z >= 3; z--) {
    final w = (_lngToWorldX(maxLng, z) - _lngToWorldX(minLng, z)).abs();
    final h = (_latToWorldY(maxLat, z) - _latToWorldY(minLat, z)).abs();
    if (w <= size * 0.75 && h <= size * 0.75) return z;
  }
  return 3;
}

/// Peintre de la carte avec gestion des tuiles et des marqueurs
class _ParticipantsMapPainter extends CustomPainter {
  final List<ParticipantsMapEntry> participants;
  final int zoom;
  final double left;
  final double top;
  final Map<String, _MapTile> tiles;
  final MapTileSource source;
  final String? selectedIdentity;

  _ParticipantsMapPainter({
    required this.participants,
    required this.zoom,
    required this.left,
    required this.top,
    required this.tiles,
    required this.source,
    this.selectedIdentity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawFallbackTiles(canvas, size);

    for (final tile in tiles.values) {
      canvas.drawImage(tile.image, tile.offset, Paint());
    }

    _drawCompass(canvas, size);

    for (final p in participants.where((e) => e.hasPosition)) {
      final px = _lngToWorldX(p.lng!, zoom) - left;
      final py = _latToWorldY(p.lat!, zoom) - top;
      _drawMarker(canvas, Offset(px, py), p, size, p.identity == selectedIdentity);
    }
  }

  void _drawFallbackTiles(Canvas canvas, Size size) {
    // Fond dégradé pour le fallback
    final background = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF1A2C28),
          const Color(0xFF2D423A),
          const Color(0xFF1A2C28),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    
    canvas.drawRect(Offset.zero & size, background);

    // Grille subtile pour donner une impression de carte
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 0.5;
    
    const gridSpacing = 20.0;
    for (double x = 0; x <= size.width; x += gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Ligne de rue diagonale pour simuler une carte
    final streetPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 2.5;
    
    canvas.drawLine(
      Offset(0, size.height * 0.3),
      Offset(size.width, size.height * 0.7),
      streetPaint,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.6),
      Offset(size.width, size.height * 0.2),
      streetPaint,
    );
    
    // Nom de rue fictif
    final streetName = TextPainter(
      text: TextSpan(
        text: 'LiveKit Ave',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.3),
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    streetName.paint(canvas, Offset(size.width * 0.65, size.height * 0.5));
  }

  void _drawCompass(Canvas canvas, Size size) {
    // Boussole dans le coin supérieur gauche (dimensionnée pour la carte 140px)
    final compassSize = 24.0;
    final compassX = 6.0;
    final compassY = 6.0;
    
    // Fond de la boussole
    final compassBg = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;
    
    final compassBgPath = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(compassX, compassY, compassSize, compassSize),
        const Radius.circular(6),
      ));
    canvas.drawPath(compassBgPath, compassBg);
    
    // Bordure de la boussole
    final compassBorder = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawPath(compassBgPath, compassBorder);
    
    // Flèche de la boussole (N)
    final arrowPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    
    final arrowPath = Path()
      ..moveTo(compassX + compassSize / 2, compassY + 4)
      ..lineTo(compassX + compassSize / 2 - 3, compassY + 10)
      ..lineTo(compassX + compassSize / 2 + 3, compassY + 10)
      ..close();
    canvas.drawPath(arrowPath, arrowPaint);
    
    // Lettre N
    final northText = TextPainter(
      text: const TextSpan(
        text: 'N',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    northText.paint(
      canvas,
      Offset(
        compassX + compassSize / 2 - northText.width / 2,
        compassY + 12,
      ),
    );
  }

  void _drawMarker(
    Canvas canvas,
    Offset center,
    ParticipantsMapEntry p,
    Size size,
    bool isSelected,
  ) {
    final borderColor = p.isLocal 
        ? Colors.blueAccent 
        : source.markerBorderColor;
    final fillColor = p.isLocal 
        ? Colors.blueAccent 
        : source.markerBackgroundColor;

    // Halo de sélection
    if (isSelected) {
      final haloPaint = Paint()
        ..color = borderColor.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, 20, haloPaint);
      
      // Anneau de sélection
      final ringPaint = Paint()
        ..color = borderColor.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(center, 20, ringPaint);
    }

    // Halo principal
    final halo = Paint()
      ..color = borderColor.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 12, halo);

    // Remplissage du marqueur
    final fill = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 8, fill);

    // Bordure du marqueur
    final ring = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, 8, ring);

    // Point central pour le participant local
    if (p.isLocal) {
      canvas.drawCircle(
        center,
        2.5,
        Paint()..color = Colors.white,
      );
    }
    
    // Flèche de direction (bearing) si disponible
    if (p.bearing != null) {
      _drawBearingArrow(canvas, center, p.bearing!, borderColor);
    }

    // Label du participant
    final name = p.label ?? p.identity;
    final finalLabel = name.length > 10 ? '${name.substring(0, 10)}…' : name;
    final labelText = TextPainter(
      text: TextSpan(
        text: finalLabel,
        style: TextStyle(
          color: source.markerIconColor,
          fontSize: 8,
          fontWeight: FontWeight.w600,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final labelLeft = (center.dx - labelText.width / 2 - 4)
        .clamp(0.0, size.width - labelText.width - 6);
    final bgRect = Rect.fromLTWH(
      labelLeft,
      center.dy + 12,
      labelText.width + 8,
      labelText.height + 4,
    );
    
    // Fond du label
    final labelBg = Paint()
      ..color = Colors.black.withValues(alpha: 0.7);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(4)),
      labelBg,
    );
    
    // Texte du label
    labelText.paint(canvas, Offset(labelLeft + 4, center.dy + 14));
    
    // Indicateurs de données (altitude, vitesse)
    _drawDataIndicators(canvas, center, p, borderColor);
  }

  /// Dessine une flèche indiquant le bearing (direction)
  void _drawBearingArrow(Canvas canvas, Offset center, double bearing, Color color) {
    // Convertir le bearing en radians (0° = Nord, puis sens horaire)
    final radians = (bearing - 90) * math.pi / 180.0; // -90° pour aligner avec l'axe Y
    
    // Calculer la position de l'extrémité de la flèche (10px du centre)
    final arrowLength = 14.0;
    final endX = center.dx + math.cos(radians) * arrowLength;
    final endY = center.dy + math.sin(radians) * arrowLength;
    
    // Dessiner la ligne de la flèche
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    
    canvas.drawLine(center, Offset(endX, endY), linePaint);
    
    // Dessiner la pointe de la flèche
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    
    final arrowPath = Path()
      ..moveTo(endX, endY)
      ..lineTo(
        endX - math.cos(radians - math.pi / 6) * 4,
        endY - math.sin(radians - math.pi / 6) * 4,
      )
      ..lineTo(
        endX - math.cos(radians + math.pi / 6) * 4,
        endY - math.sin(radians + math.pi / 6) * 4,
      )
      ..close();
    
    canvas.drawPath(arrowPath, arrowPaint);
  }

  /// Dessine les indicateurs de données (altitude, vitesse) sous le marqueur
  void _drawDataIndicators(Canvas canvas, Offset center, ParticipantsMapEntry p, Color color) {
    final indicators = <String>[];
    
    if (p.altitude != null) {
      indicators.add('${p.altitude!.toStringAsFixed(0)}m');
    }
    if (p.speed != null) {
      indicators.add('${p.speed!.toStringAsFixed(1)}km/h');
    }
    
    if (indicators.isEmpty) return;
    
    final indicatorText = TextPainter(
      text: TextSpan(
        text: indicators.join(' • '),
        style: TextStyle(
          color: color,
          fontSize: 7,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    
    final textX = center.dx - indicatorText.width / 2;
    final textY = center.dy - 14;
    
    // Fond semi-transparent
    final bgRect = Rect.fromLTWH(
      textX - 4,
      textY - 2,
      indicatorText.width + 8,
      indicatorText.height + 4,
    );
    
    final bgPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(3)),
      bgPaint,
    );
    
    // Texte
    indicatorText.paint(canvas, Offset(textX, textY));
  }

  @override
  bool shouldRepaint(covariant _ParticipantsMapPainter oldDelegate) {
    return oldDelegate.participants != participants ||
        oldDelegate.zoom != zoom ||
        oldDelegate.left != left ||
        oldDelegate.top != top ||
        oldDelegate.tiles != tiles ||
        oldDelegate.source != source ||
        oldDelegate.selectedIdentity != selectedIdentity;
  }
}

/// Widget d'infobulle pour afficher les détails d'un participant
class _TooltipWidget extends StatelessWidget {
  final ParticipantsMapEntry participant;
  final Offset position;
  final RenderBox renderBox;
  final bool showAltitude;
  final bool showBearing;
  final bool showSpeed;
  final VoidCallback onDismiss;

  const _TooltipWidget({
    required this.participant,
    required this.position,
    required this.renderBox,
    required this.showAltitude,
    required this.showBearing,
    required this.showSpeed,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final localPosition = renderBox.globalToLocal(position);
    
    return Positioned(
      left: localPosition.dx,
      top: localPosition.dy - 80, // Position au-dessus du marqueur
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: onDismiss,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: participant.isLocal 
                    ? Colors.blueAccent 
                    : Colors.white.withValues(alpha: 0.2),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nom
                Text(
                  participant.label ?? participant.identity,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    overflow: TextOverflow.ellipsis,
                  ),
                  maxLines: 1,
                ),
                const SizedBox(height: 8),
                const Divider(
                  color: Colors.white24,
                  height: 1,
                ),
                const SizedBox(height: 8),
                
                // Données
                if (showAltitude && participant.altitude != null) ...[
                  _buildInfoRow(Icons.height, 'Altitude', '${participant.altitude!.toStringAsFixed(0)} m'),
                  const SizedBox(height: 4),
                ],
                if (showBearing && participant.bearing != null) ...[
                  _buildInfoRow(Icons.explore, 'Cap', '${participant.bearing!.toStringAsFixed(0)}°'),
                  const SizedBox(height: 4),
                ],
                if (showSpeed && participant.speed != null) ...[
                  _buildInfoRow(Icons.speed, 'Vitesse', '${participant.speed!.toStringAsFixed(1)} km/h'),
                  const SizedBox(height: 4),
                ],
                
                // Coordonnées GPS
                if (participant.lat != null && participant.lng != null) ...[
                  Text(
                    'Lat: ${participant.lat!.toStringAsFixed(6)}, Lng: ${participant.lng!.toStringAsFixed(6)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          icon,
          color: Colors.cyanAccent,
          size: 14,
        ),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 11,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
