import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/scene_painter.dart';
import '../engine/selection_geometry.dart';
import '../models/animation.dart';
import 'layer_properties_sheet.dart';
import 'palette.dart';

/// Geste en cours sur le preview de l'éditeur.
enum _EditorGesture { none, move, scale, rotate, pointDrag }

/// Création / édition d'une forme : aperçu manipulable en haut, couches en bas.
///
/// Une forme est un groupe de couches (formes basiques). La couche sélectionnée
/// se manipule directement sur le preview : déplacement au doigt (x, y),
/// pinch = échelle, poignée de rotation au-dessus du rectangle de sélection.
/// Les réglages fins sont dans la bottom sheet ouverte par le bouton ⚙ ancré
/// au coin bas-gauche de la sélection.
class ShapeEditorScreen extends StatefulWidget {
  const ShapeEditorScreen({
    super.key,
    required this.project,
    this.shape,
    this.initialTimeMs,
  });

  final AnimationProject project;

  /// Forme à modifier ; `null` pour en créer une nouvelle.
  final VectorShape? shape;

  /// Instant du studio à l'ouverture (playhead) : le curseur du preview
  /// démarre ICI (borné à la fenêtre de la forme) au lieu de startMs —
  /// bugfix v0.16.3 : scrubber le studio puis éditer écrivait tout à 0 s.
  final int? initialTimeMs;

  @override
  State<ShapeEditorScreen> createState() => _ShapeEditorScreenState();
}

class _ShapeEditorScreenState extends State<ShapeEditorScreen> {
  late VectorShape _draft;
  late final TextEditingController _name;
  String? _selectedLayerId;

  // Caméra du preview, indépendante des données de la forme.
  double _previewZoom = 1;
  Offset _previewPan = Offset.zero;
  bool _previewPanMode = false;
  Offset _panStart = Offset.zero;
  Offset _panBase = Offset.zero;

  SceneGeometry _previewGeometry(Size size) => SceneGeometry.fitFor(
    widget.project,
    size,
    zoom: _previewZoom,
    pan: _previewPan,
  );

  void _changePreviewZoom(double factor) {
    setState(() => _previewZoom = (_previewZoom * factor).clamp(0.5, 8.0));
  }

  void _fitPreview() => setState(() {
    _previewZoom = 1;
    _previewPan = Offset.zero;
  });

  void _startPreviewPan(Offset position) {
    _panStart = position;
    _panBase = _previewPan;
  }

  void _updatePreviewPan(Offset position) {
    setState(() => _previewPan = _panBase + position - _panStart);
  }

  void _togglePreviewPanMode() =>
      setState(() => _previewPanMode = !_previewPanMode);

  // Option : aimanter la rotation aux multiples de 90° (bouton du preview).
  bool _snapRotation = false;

  // Curseur du preview (dans la fenêtre de la forme) : les POSES y sont
  // échantillonnées et les points de chemin y auto-keyent (v0.16).
  int _previewMs = 0;

  // Le glisser de point en cours a écrit une POSE (morph) — snack au
  // relâchement pour rendre l'auto-key visible (v0.16.2).
  bool _gestureWrotePose = false;

  // Glisser d'un point de chemin : index visé, nuage de départ et temps
  // cible (keyframe snappée ou curseur).
  int _pointIndex = -1;
  List<Offset> _pointSeed = const [];
  int _pointTargetMs = 0;

  // Mode « ajouter un point » (bouton ✚ du preview).
  bool _addPointMode = false;

  // Position BRUTE du premier doigt (hit des poignées avant reconnaissance
  // du geste : onScaleStart arrive avec le foyer déjà déplacé).
  Offset _downPos = Offset.zero;

  // Geste en cours (déplacement, pinch, rotation par poignée).
  _EditorGesture _gesture = _EditorGesture.none;
  int _activePointers = 0;
  double _gestureBaseX = 0;
  double _gestureBaseY = 0;
  double _gestureBaseRotation = 0;
  double _gestureBaseScale = 1;
  double _gestureStartAngle = 0;
  Offset _gestureStartPoint = Offset.zero;

  bool get _isNew => widget.shape == null;

  @override
  void initState() {
    super.initState();
    final project = widget.project;
    _draft =
        widget.shape?.copy() ??
        VectorShape(
          name: 'Forme ${project.shapes.length + 1}',
          x: project.width / 2,
          y: project.height / 2,
          startMs: 0,
          endMs: math.max(project.durationMs, 4000),
          layers: <ShapeLayer>[_defaultLayer(ShapeKind.rect, 0)],
        );
    _name = TextEditingController(text: _draft.name);
    _selectedLayerId = _draft.layers.isEmpty ? null : _draft.layers.last.id;
    // Curseur initial = playhead du STUDIO (bugfix v0.16.3) : ouvrir
    // l'éditeur après un scrub garde l'instant affiché — sinon le curseur
    // retombait à startMs (0 s) et TOUTES les poses de morph étaient
    // écrites à 0. Borné à la fenêtre de la forme.
    _previewMs = (widget.initialTimeMs ?? _draft.startMs).clamp(
      _draft.startMs,
      math.max(_draft.startMs, _draft.endMs),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  ShapeLayer _defaultLayer(ShapeKind kind, int index) {
    final offset = (index % 4) * 14.0;
    return ShapeLayer(
      name: shapeKindLabel(kind),
      kind: kind,
      x: offset,
      y: offset,
      width: kind == ShapeKind.line ? 150 : 110,
      height: kind == ShapeKind.line ? 0 : 110,
      colorValue: kColorPalette[index % 3],
      filled: kind != ShapeKind.line,
      points: kind == ShapeKind.path
          ? const <Offset>[
              Offset(110, 0),
              Offset(80, 110),
              Offset(0, 84),
              Offset(30, 30),
            ]
          : null,
    );
  }

  ShapeLayer? get _selectedLayer {
    for (final layer in _draft.layers) {
      if (layer.id == _selectedLayerId) return layer;
    }
    return _draft.layers.isEmpty ? null : _draft.layers.last;
  }

  void _addLayer(ShapeKind kind) {
    setState(() {
      final layer = _defaultLayer(kind, _draft.layers.length);
      _draft.layers.add(layer);
      _selectedLayerId = layer.id;
    });
  }

  void _duplicateLayer(ShapeLayer layer) {
    setState(() {
      final index = _draft.layers.indexOf(layer);
      final clone = layer.copy(
        id: generateId('layer'),
        name: '${layer.name} (copie)',
      );
      clone
        ..x = layer.x + 16
        ..y = layer.y + 16;
      _draft.layers.insert(index + 1, clone);
      _selectedLayerId = clone.id;
    });
  }

  void _removeLayer(ShapeLayer layer) {
    if (_draft.layers.length <= 1) {
      _snack('Une forme doit garder au moins une couche.');
      return;
    }
    setState(() {
      _draft.layers.remove(layer);
      _selectedLayerId = _draft.layers.last.id;
    });
  }

  void _moveLayer(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _draft.layers.length) return;
    setState(() {
      final layer = _draft.layers.removeAt(index);
      _draft.layers.insert(target, layer);
    });
  }

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  /// Bornée de la fenêtre d'affichage éditable : la fin du dernier AUTRE
  /// segment +10 s (le projet s'étend tout seul) — jamais sous la fin du
  /// brouillon pour ne pas casser le RangeSlider.
  int _windowMaxMs() {
    var other = 0;
    for (final shape in widget.project.shapes) {
      if (shape.id != _draft.id && shape.endMs > other) other = shape.endMs;
    }
    return math.max(other + 10000, _draft.endMs);
  }

  AnimationProject get _preview {
    final project = AnimationProject(
      name: _draft.name,
      width: widget.project.width,
      height: widget.project.height,
      fps: widget.project.fps,
      backgroundValue: widget.project.backgroundValue,
      shapes: <VectorShape>[
        if (!_isNew) ...widget.project.shapes.where((s) => s.id != _draft.id),
        _draft,
      ],
    );
    return project;
  }

  @override
  Widget build(BuildContext context) {
    final layer = _selectedLayer;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Nouvelle forme' : 'Modifier la forme'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Enregistrer',
            onPressed: () {
              final name = _name.text.trim();
              _draft.name = name.isEmpty ? _draft.name : name;
              Navigator.of(context).pop(_draft);
            },
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _buildPreview(),
          _buildPlayhead(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nom de la forme',
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: LayerPanel(
              shape: _draft,
              durationMs: _windowMaxMs(),
              selectedLayer: layer,
              onSelect: (value) => setState(() => _selectedLayerId = value.id),
              onAdd: _addLayer,
              onDuplicate: _duplicateLayer,
              onMove: _moveLayer,
              onChanged: () => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- preview

  Widget _buildPreview() {
    return Container(
      height: 240,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0D12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF232733)),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final canvasSize = constraints.biggest;
          final layer = _selectedLayer;
          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: Listener(
                  onPointerDown: (event) {
                    if (_activePointers == 0) _downPos = event.localPosition;
                    _activePointers++;
                  },
                  onPointerUp: (_) => _pointerUp(),
                  onPointerCancel: (_) => _pointerUp(),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: _previewPanMode
                        ? null
                        : (details) => _onGestureStart(details, canvasSize),
                    onScaleUpdate: _previewPanMode
                        ? null
                        : (details) => _onGestureUpdate(details, canvasSize),
                    onScaleEnd: _previewPanMode ? null : (_) => _endGesture(),
                    onTapUp: _previewPanMode
                        ? null
                        : (details) => _onTapUp(details, canvasSize),
                    onLongPressStart: _previewPanMode
                        ? null
                        : (details) => _onLongPress(details, canvasSize),
                    child: CustomPaint(
                      painter: ScenePainter(
                        project: _preview,
                        timeMs: _previewMs,
                        selectedShapeId: _draft.id,
                        selectedLayerId: _selectedLayerId,
                        showFrame: true,
                        showLayerPoints: true,
                        activePointIndex: _gesture == _EditorGesture.pointDrag
                            ? _pointIndex
                            : -1,
                        previewZoom: _previewZoom,
                        previewPan: _previewPan,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 8,
                top: 8,
                child: IconButton(
                  tooltip: 'Ajouter un point — touche un segment du chemin',
                  isSelected: _addPointMode,
                  onPressed: () =>
                      setState(() => _addPointMode = !_addPointMode),
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  selectedIcon: const Icon(
                    Icons.add_circle,
                    size: 20,
                    color: Color(0xFF3ECF8E),
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xCC151922),
                    foregroundColor: Colors.white70,
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: IconButton(
                  tooltip: 'Snap rotation 90°',
                  isSelected: _snapRotation,
                  onPressed: () =>
                      setState(() => _snapRotation = !_snapRotation),
                  icon: const Icon(
                    Icons.rotate_90_degrees_ccw_outlined,
                    size: 20,
                  ),
                  selectedIcon: const Icon(
                    Icons.rotate_90_degrees_ccw,
                    size: 20,
                    color: Color(0xFF7DD3FC),
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xCC151922),
                    foregroundColor: Colors.white70,
                  ),
                ),
              ),
              if (_previewPanMode)
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (event) =>
                        _startPreviewPan(event.localPosition),
                    onPointerMove: (event) =>
                        _updatePreviewPan(event.localPosition),
                    child: const SizedBox.expand(),
                  ),
                ),
              Positioned(
                right: 8,
                bottom: 8,
                child: _buildPreviewZoomControls(),
              ),
              if (layer != null && layer.visible)
                _buildLayerButton(layer, canvasSize),
            ],
          );
        },
      ),
    );
  }

  /// Curseur du preview : échantillonne les poses/nuages dans la fenêtre de
  /// la forme. Les poignées de points y auto-keyent (pas d'auto-key pour les
  /// autres propriétés de couche : elles restent statiques, comme partout).
  Widget _buildPlayhead() {
    final min = _draft.startMs.toDouble();
    final max = math.max(min + 100, _draft.endMs).toDouble();
    final near = _draft.keyframeNear(
      _previewMs,
      keyframeSnapToleranceMs(_draft.durationMs),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              // ◆ pose au curseur (v0.16.2) : le workflow morph devient
              // autonomé — scrubber, poser, déplacer les points, rejouer.
              IconButton(
                tooltip: near == null
                    ? 'Ajouter une keyframe au curseur'
                    : 'Retirer la keyframe au curseur',
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                icon: Icon(
                  near == null ? Icons.diamond_outlined : Icons.diamond,
                  color: near == null ? null : const Color(0xFFF2C94C),
                ),
                onPressed: () => setState(() {
                  if (near != null) {
                    _draft.removeKeyframeAt(near.timeMs);
                  } else {
                    _draft.addKeyframeAt(_previewMs);
                  }
                }),
              ),
              Expanded(
                child: Slider(
                  value: _previewMs.toDouble().clamp(min, max),
                  min: min,
                  max: max,
                  divisions: math.max(1, _draft.durationMs ~/ 50),
                  label: '${(_previewMs / 1000).toStringAsFixed(2)} s',
                  onChanged: (value) => setState(() {
                    _previewMs = value.round().clamp(
                      _draft.startMs,
                      math.max(_draft.startMs, _draft.endMs),
                    );
                  }),
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  '${(_previewMs / 1000).toStringAsFixed(2)} s',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
            ],
          ),
          if (_selectedLayer?.kind == ShapeKind.path)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: Text(
                _morphHint(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: Colors.white54),
              ),
            ),
        ],
      ),
    );
  }

  /// Aide contextuelle du morph (v0.16.2) : dit où va l'écriture du
  /// glisser et comment enchaîner deux poses pour animer.
  String _morphHint() {
    final layer = _selectedLayer;
    if (layer == null) {
      return 'Touche un point pour le déplacer · appui long : le '
          'supprimer · ✚ puis touche un segment pour en ajouter';
    }
    final clouded = _draft.keyframes
        .where((k) => (k.layerPoints[layer.id] ?? const <Offset>[]).isNotEmpty)
        .length;
    if (_draft.keyframes.isEmpty) {
      return widget.project.isSkeleton
          ? 'Déplace un point : la 1ʳᵉ pose se crée automatiquement · '
                '◆ pose d’autres instants · appui long : supprimer'
          : 'Sans keyframe : tu dessines la base · ◆ pour commencer à '
                'animer (morph) · appui long : supprimer un point';
    }
    if (clouded < 2) {
      return 'Une seule pose porte le morph (forme figée ailleurs) : '
          'scruble un autre instant, ◆ puis déplace les points';
    }
    return 'Morph : les points s’interpolent entre les poses · '
        '◆ au curseur ajoute/retire une pose';
  }

  Widget _buildPreviewZoomControls() => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xCC151922),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          tooltip: _previewPanMode
              ? 'Désactiver le déplacement de la vue'
              : 'Déplacer la vue',
          isSelected: _previewPanMode,
          visualDensity: VisualDensity.compact,
          onPressed: _togglePreviewPanMode,
          icon: Icon(
            _previewPanMode ? Icons.pan_tool : Icons.pan_tool_outlined,
            size: 18,
          ),
        ),
        IconButton(
          tooltip: 'Zoom arrière du preview',
          visualDensity: VisualDensity.compact,
          onPressed: () => _changePreviewZoom(1 / 1.2),
          icon: const Icon(Icons.zoom_out, size: 20),
        ),
        Text(
          '${(_previewZoom * 100).round()}%',
          style: const TextStyle(fontSize: 11),
        ),
        IconButton(
          tooltip: 'Zoom avant du preview',
          visualDensity: VisualDensity.compact,
          onPressed: () => _changePreviewZoom(1.2),
          icon: const Icon(Icons.zoom_in, size: 20),
        ),
        IconButton(
          tooltip: 'Ajuster le preview',
          visualDensity: VisualDensity.compact,
          onPressed: _fitPreview,
          icon: const Icon(Icons.fit_screen_outlined, size: 18),
        ),
      ],
    ),
  );

  /// Bouton « réglages » ancré au coin bas-gauche du rectangle de la couche.
  Widget _buildLayerButton(ShapeLayer layer, Size canvasSize) {
    if (canvasSize.isEmpty) return const SizedBox.shrink();
    final geo = _previewGeometry(canvasSize);
    final center = SelectionGeometry.propertiesButton(
      ScenePainter.layerBounds(layer),
      SelectionGeometry.layerPose(_draft, layer, _previewMs),
      geo,
    );
    const size = 34.0;
    final left = (center.dx - size / 2)
        .clamp(0.0, math.max(0.0, canvasSize.width - size))
        .toDouble();
    final top = (center.dy - size / 2)
        .clamp(0.0, math.max(0.0, canvasSize.height - size))
        .toDouble();
    return Positioned(
      left: left,
      top: top,
      width: size,
      height: size,
      child: IconButton(
        tooltip: 'Réglages de la couche',
        padding: EdgeInsets.zero,
        iconSize: 18,
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xCC151922),
          foregroundColor: const Color(0xFF7DD3FC),
        ),
        icon: const Icon(Icons.tune),
        onPressed: () => _showLayerSheet(layer),
      ),
    );
  }

  void _showLayerSheet(ShapeLayer layer) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFF151922),
      builder: (_) => LayerPropertiesSheet(
        layer: layer,
        canDelete: _draft.layers.length > 1,
        onChanged: () => setState(() {}),
        onDelete: () => _removeLayer(layer),
      ),
    );
  }

  // ----------------------------------------------------------------- gestes

  void _pointerUp() => _activePointers = math.max(0, _activePointers - 1);

  /// Relâchement : snack de confirmation quand le glisser a écrit une
  /// pose (auto-key visible), puis remise à zéro du geste.
  void _endGesture() {
    if (_gesture == _EditorGesture.pointDrag && _gestureWrotePose) {
      _snack(
        'Pose à ${(_pointTargetMs / 1000).toStringAsFixed(2)} s '
        'enregistrée (morph)',
      );
    }
    _gestureWrotePose = false;
    _gesture = _EditorGesture.none;
  }

  /// Pose de la couche sélectionnée au temps AFFICHÉ (curseur du preview).
  Pose2D _previewLayerPose(ShapeLayer layer) =>
      SelectionGeometry.layerPose(_draft, layer, _previewMs);

  /// Nuage échantillonné + positions écran des poignées de points de la
  /// couche sélectionnée, ou `null` (pas un chemin, couche cachée, vide).
  (List<Offset>, List<Offset>)? _pointHandles(Size canvasSize) {
    final layer = _selectedLayer;
    if (layer == null ||
        !layer.visible ||
        layer.kind != ShapeKind.path ||
        canvasSize.isEmpty) {
      return null;
    }
    final geo = _previewGeometry(canvasSize);
    final cloud = _draft.pointsAtLayer(layer.id, layer.points, _previewMs);
    final positions = SelectionGeometry.pointHandlePositions(
      cloud,
      layer,
      _previewLayerPose(layer),
      geo,
    );
    return (cloud, positions);
  }

  /// Prépare le glisser d'un point : temps cible (keyframe snappée à la
  /// tolérance de la timeline, sinon le curseur) et nuage de départ —
  /// l'entrée de la pose cible si elle existe, sinon le nuage échantillonné
  /// À LA CIBLE (l'extrémité du segment interpolé garde sa valeur : semer
  /// est visuellement neutre, seul le point déplacé bouge).
  void _beginPointDrag(ShapeLayer layer, int index) {
    final tolerance = keyframeSnapToleranceMs(_draft.durationMs);
    final targetKey = _draft.keyframeNear(_previewMs, tolerance);
    _pointTargetMs = targetKey?.timeMs ?? _previewMs;
    final entry = targetKey?.layerPoints[layer.id];
    _pointSeed = (entry != null && entry.isNotEmpty)
        ? List<Offset>.from(entry)
        : List<Offset>.from(
            _draft.pointsAtLayer(layer.id, layer.points, _pointTargetMs),
          );
    _pointIndex = index;
  }

  void _onGestureStart(ScaleStartDetails details, Size canvasSize) {
    _gestureStartPoint = details.localFocalPoint;
    final layer = _selectedLayer;
    if (layer == null || !layer.visible) {
      _gesture = _EditorGesture.none;
      return;
    }
    final geo = _previewGeometry(canvasSize);
    final pose = _previewLayerPose(layer);
    final bounds = ScenePainter.layerBounds(layer);
    var gesture = _EditorGesture.none;
    if (_activePointers >= 2) {
      // Pinch : échelle de la couche sélectionnée.
      gesture = _EditorGesture.scale;
    } else if (SelectionGeometry.hitRotationHandle(
      details.localFocalPoint,
      SelectionGeometry.rotationHandle(bounds, pose, geo),
    )) {
      // Poignée de rotation.
      gesture = _EditorGesture.rotate;
      final center = SelectionGeometry.center(pose, geo);
      _gestureStartAngle = math.atan2(
        details.localFocalPoint.dy - center.dy,
        details.localFocalPoint.dx - center.dx,
      );
    } else if (layer.kind == ShapeKind.path && !_addPointMode) {
      // Poignées de points : prioritaires (elles sont SUR le corps de la
      // couche). Le hit se fait sur la position BRUTE du doigt (_downPos,
      // enregistrée avant la reconnaissance du geste).
      final handles = _pointHandles(canvasSize);
      if (handles != null) {
        final index = SelectionGeometry.hitPointIndex(
          handles.$2,
          _downPos,
          SelectionGeometry.pointTouchSlop,
        );
        if (index >= 0) {
          gesture = _EditorGesture.pointDrag;
          _beginPointDrag(layer, index);
        }
      }
    }
    if (gesture == _EditorGesture.none &&
        SelectionGeometry.hit(bounds, pose, geo, details.localFocalPoint)) {
      // Corps de la couche : déplacement.
      gesture = _EditorGesture.move;
    }
    _gesture = gesture;
    _gestureBaseX = layer.x;
    _gestureBaseY = layer.y;
    _gestureBaseRotation = layer.rotation;
    _gestureBaseScale = layer.scale;
  }

  void _onGestureUpdate(ScaleUpdateDetails details, Size canvasSize) {
    final layer = _selectedLayer;
    if (layer == null || _gesture == _EditorGesture.none) return;
    switch (_gesture) {
      case _EditorGesture.pointDrag:
        // Le delta stocké = différence des conversions canvas → local
        // dessiné (pose figée au temps affiché pendant le geste) — la
        // recentrage (w/2, h/2) ne décale pas les deltas.
        final geo = _previewGeometry(canvasSize);
        final pose = _previewLayerPose(layer);
        final startLocal = SelectionGeometry.canvasToLocal(
          _gestureStartPoint,
          pose,
          geo,
        );
        final nowLocal = SelectionGeometry.canvasToLocal(
          details.localFocalPoint,
          pose,
          geo,
        );
        // Miroir (v0.19) : le contenu dessiné est reflété autour de
        // l'origine de la couche — le delta mesuré en espace dessiné est
        // reconverti dans le repère des DONNÉES (réflexion auto-inverse).
        final rawDelta = nowLocal - startLocal;
        final dataDelta = Offset(
          layer.flipH ? -rawDelta.dx : rawDelta.dx,
          layer.flipV ? -rawDelta.dy : rawDelta.dy,
        );
        final cloud = List<Offset>.from(_pointSeed);
        if (_pointIndex >= 0 && _pointIndex < cloud.length) {
          cloud[_pointIndex] = cloud[_pointIndex] + dataDelta;
        }
        setState(() {
          // Bugfix v0.16.2 : pièce d'un projet SQUELETTE sans AUCUNE
          // keyframe — le premier glisser CRÉE la première pose au lieu
          // d'éditer la base en silence (le rig est là pour animer ;
          // l'utilisateur s'attend à l'auto-key). La pose est semée du
          // rendu courant : visuellement neutre.
          if (_draft.keyframes.isEmpty && widget.project.isSkeleton) {
            _draft.addKeyframeAt(_pointTargetMs);
            _gestureWrotePose = true;
          } else if (_draft.keyframes.isNotEmpty) {
            _gestureWrotePose = true;
          }
          _draft.applyLayerPoints(layer, cloud, _pointTargetMs, autoKey: true);
        });
      case _EditorGesture.move:
        final geo = _previewGeometry(canvasSize);
        final sceneDelta =
            geo.canvasToScene(details.localFocalPoint) -
            geo.canvasToScene(_gestureStartPoint);
        // La couche vit dans le repère de la forme : le delta de scène est
        // repassé en local (rotation et échelles PAR AXE de la forme
        // inversées — v0.13 squash & stretch).
        final shapePose = SelectionGeometry.shapePose(_draft, _previewMs);
        final cosR = math.cos(-shapePose.rotation);
        final sinR = math.sin(-shapePose.rotation);
        final safeSx = math.max(0.0001, shapePose.sx.abs());
        final safeSy = math.max(0.0001, shapePose.sy.abs());
        final local = Offset(
          (sceneDelta.dx * cosR - sceneDelta.dy * sinR) / safeSx,
          (sceneDelta.dx * sinR + sceneDelta.dy * cosR) / safeSy,
        );
        setState(() {
          layer.x = _gestureBaseX + local.dx;
          layer.y = _gestureBaseY + local.dy;
        });
      case _EditorGesture.scale:
        final next = (_gestureBaseScale * details.scale).clamp(0.05, 4.0);
        setState(() => layer.scale = next.toDouble());
      case _EditorGesture.rotate:
        final geo = _previewGeometry(canvasSize);
        final pose = _previewLayerPose(layer);
        final center = SelectionGeometry.center(pose, geo);
        final angle = math.atan2(
          details.localFocalPoint.dy - center.dy,
          details.localFocalPoint.dx - center.dx,
        );
        var next = _gestureBaseRotation + (angle - _gestureStartAngle);
        if (_snapRotation) {
          const step = math.pi / 2;
          const tolerance = 3 * math.pi / 180;
          final snapped = (next / step).roundToDouble() * step;
          if ((next - snapped).abs() <= tolerance) next = snapped;
        }
        setState(() => layer.rotation = next);
      case _EditorGesture.none:
        break;
    }
  }

  /// Tap : en mode ✚, ajoute un point sur le segment le plus proche (dans
  /// une tolérance de 28 px écran) — une insertion par activation du mode.
  /// Sinon, tap sur une couche : la sélectionne (du premier plan vers
  /// l'arrière-plan). Tap dans le vide : la sélection actuelle est conservée.
  void _onTapUp(TapUpDetails details, Size canvasSize) {
    final layer = _selectedLayer;
    if (_addPointMode && layer != null && layer.visible) {
      if (layer.kind != ShapeKind.path) {
        _snack('Le mode ✚ s’applique aux couches « Chemin ».');
        return;
      }
      setState(() => _addPointMode = false);
      final handles = _pointHandles(canvasSize);
      if (handles == null) return;
      final pose = _previewLayerPose(layer);
      final geo = _previewGeometry(canvasSize);
      final local = SelectionGeometry.canvasToLocal(
        details.localPosition,
        pose,
        geo,
      );
      final stored = Offset(
        (layer.flipH ? -local.dx : local.dx) + layer.width / 2,
        (layer.flipV ? -local.dy : local.dy) + layer.height / 2,
      );
      if (handles.$1.length < 2) {
        setState(
          () => _draft.insertLayerPoint(layer, layer.points.length, stored),
        );
        _snack('Point ajouté');
        return;
      }
      final (segment, distance) = SelectionGeometry.nearestClosedSegment(
        handles.$2,
        details.localPosition,
      );
      if (distance > 28) {
        _snack('Touche un segment du chemin pour y ajouter un point.');
        return;
      }
      setState(() => _draft.insertLayerPoint(layer, segment + 1, stored));
      _snack('Point ajouté');
      return;
    }
    final geo = _previewGeometry(canvasSize);
    for (final layer in _draft.layers.reversed) {
      if (!layer.visible) continue;
      if (SelectionGeometry.hit(
        ScenePainter.layerBounds(layer),
        SelectionGeometry.layerPose(_draft, layer, _previewMs),
        geo,
        details.localPosition,
      )) {
        setState(() => _selectedLayerId = layer.id);
        return;
      }
    }
  }

  /// Appui long sur une poignée de point : supprime le point (base + tous
  /// les nuages de morph de la couche, même index).
  void _onLongPress(LongPressStartDetails details, Size canvasSize) {
    final layer = _selectedLayer;
    if (layer == null || !layer.visible || layer.kind != ShapeKind.path) {
      return;
    }
    final handles = _pointHandles(canvasSize);
    if (handles == null) return;
    final index = SelectionGeometry.hitPointIndex(
      handles.$2,
      details.localPosition,
      SelectionGeometry.pointTouchSlop,
    );
    if (index < 0) return;
    setState(() => _draft.removeLayerPoint(layer, index));
    _snack('Point supprimé');
  }
}

/// Durée minimale de la fenêtre d'affichage d'une forme (ms).
class TimelineViewMinSpan {
  const TimelineViewMinSpan._();

  static const int ms = 100;
}

/// Liste des couches + fenêtre d'affichage de la forme. Les réglages fins de
/// la couche sélectionnée sont dans la bottom sheet (`LayerPropertiesSheet`),
/// ouverte depuis le bouton ⚙ du preview.
class LayerPanel extends StatelessWidget {
  const LayerPanel({
    super.key,
    required this.shape,
    required this.durationMs,
    required this.selectedLayer,
    required this.onSelect,
    required this.onAdd,
    required this.onDuplicate,
    required this.onMove,
    required this.onChanged,
  });

  final VectorShape shape;
  final int durationMs;
  final ShapeLayer? selectedLayer;
  final ValueChanged<ShapeLayer> onSelect;
  final ValueChanged<ShapeKind> onAdd;
  final ValueChanged<ShapeLayer> onDuplicate;
  final void Function(int index, int delta) onMove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final layer = selectedLayer;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      children: <Widget>[
        Row(
          children: <Widget>[
            const Expanded(
              child: Text(
                'Couches (layers)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Text(
              '${shape.layers.length}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (var index = 0; index < shape.layers.length; index++)
          _buildLayerTile(context, shape.layers[index], index),
        const SizedBox(height: 8),
        const Text('Ajouter une couche', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final kind in ShapeKind.values)
              OutlinedButton.icon(
                onPressed: () => onAdd(kind),
                icon: Icon(shapeKindIcon(kind), size: 18),
                label: Text(shapeKindLabel(kind)),
              ),
          ],
        ),
        if (layer != null) ...<Widget>[
          const Divider(height: 28),
          const Text(
            'Fenêtre d’affichage (timeline)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Début ${(shape.startMs / 1000).toStringAsFixed(2)} s · '
            'Fin ${(shape.endMs / 1000).toStringAsFixed(2)} s',
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          RangeSlider(
            min: 0,
            max: durationMs.toDouble(),
            divisions: math.max(1, durationMs ~/ 50),
            values: RangeValues(
              shape.startMs.toDouble().clamp(0, durationMs.toDouble()),
              shape.endMs.toDouble().clamp(0, durationMs.toDouble()),
            ),
            onChanged: (values) {
              final start = values.start
                  .round()
                  .clamp(0, math.max(0, durationMs - TimelineViewMinSpan.ms))
                  .toInt();
              final end = values.end
                  .round()
                  .clamp(start + TimelineViewMinSpan.ms, durationMs)
                  .toInt();
              shape.startMs = start;
              shape.endMs = end;
              onChanged();
            },
          ),
        ],
      ],
    );
  }

  Widget _buildLayerTile(BuildContext context, ShapeLayer layer, int index) {
    final selected = layer.id == selectedLayer?.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: selected ? const Color(0xFF232A38) : null,
      child: ListTile(
        dense: true,
        onTap: () => onSelect(layer),
        leading: Icon(shapeKindIcon(layer.kind)),
        title: Text(layer.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${layer.width.round()} × ${layer.height.round()} · '
          '${layer.x.round()}, ${layer.y.round()}',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              tooltip: 'Dupliquer',
              iconSize: 18,
              onPressed: () => onDuplicate(layer),
              icon: const Icon(Icons.copy),
            ),
            IconButton(
              tooltip: layer.visible ? 'Masquer' : 'Afficher',
              iconSize: 18,
              onPressed: () {
                layer.visible = !layer.visible;
                onChanged();
              },
              icon: Icon(
                layer.visible ? Icons.visibility : Icons.visibility_off,
              ),
            ),
            IconButton(
              tooltip: 'Monter',
              iconSize: 18,
              onPressed: () => onMove(index, 1),
              icon: const Icon(Icons.arrow_upward),
            ),
            IconButton(
              tooltip: 'Descendre',
              iconSize: 18,
              onPressed: () => onMove(index, -1),
              icon: const Icon(Icons.arrow_downward),
            ),
          ],
        ),
      ),
    );
  }
}
