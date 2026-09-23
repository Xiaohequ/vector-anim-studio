import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/scene_painter.dart';
import '../engine/selection_geometry.dart';
import '../models/animation.dart';
import 'layer_properties_sheet.dart';
import 'palette.dart';

/// Geste en cours sur le preview de l'éditeur.
enum _EditorGesture { none, move, scale, rotate }

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
  });

  final AnimationProject project;

  /// Forme à modifier ; `null` pour en créer une nouvelle.
  final VectorShape? shape;

  @override
  State<ShapeEditorScreen> createState() => _ShapeEditorScreenState();
}

class _ShapeEditorScreenState extends State<ShapeEditorScreen> {
  late VectorShape _draft;
  late final TextEditingController _name;
  String? _selectedLayerId;

  // Option : aimanter la rotation aux multiples de 90° (bouton du preview).
  bool _snapRotation = false;

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
    _draft = widget.shape?.copy() ??
        VectorShape(
          name: 'Forme ${project.shapes.length + 1}',
          x: project.width / 2,
          y: project.height / 2,
          startMs: 0,
          endMs: project.durationMs,
          layers: <ShapeLayer>[_defaultLayer(ShapeKind.rect, 0)],
        );
    _name = TextEditingController(text: _draft.name);
    _selectedLayerId = _draft.layers.isEmpty ? null : _draft.layers.last.id;
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

  void _snack(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  AnimationProject get _preview {
    final project = AnimationProject(
      name: _draft.name,
      width: widget.project.width,
      height: widget.project.height,
      durationMs: widget.project.durationMs,
      fps: widget.project.fps,
      backgroundValue: widget.project.backgroundValue,
      shapes: <VectorShape>[
        if (!_isNew)
          ...widget.project.shapes.where((s) => s.id != _draft.id),
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
              durationMs: widget.project.durationMs,
              selectedLayer: layer,
              onSelect: (value) => setState(() => _selectedLayerId = value.id),
              onAdd: _addLayer,
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
                  onPointerDown: (_) => _activePointers++,
                  onPointerUp: (_) => _pointerUp(),
                  onPointerCancel: (_) => _pointerUp(),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: (details) =>
                        _onGestureStart(details, canvasSize),
                    onScaleUpdate: (details) =>
                        _onGestureUpdate(details, canvasSize),
                    onScaleEnd: (_) => _gesture = _EditorGesture.none,
                    onTapUp: (details) => _onTapUp(details, canvasSize),
                    child: CustomPaint(
                      painter: ScenePainter(
                        project: _preview,
                        timeMs: _draft.startMs,
                        selectedShapeId: _draft.id,
                        selectedLayerId: _selectedLayerId,
                        showFrame: true,
                      ),
                      child: const SizedBox.expand(),
                    ),
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
                  icon: const Icon(Icons.rotate_90_degrees_ccw_outlined, size: 20),
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
              if (layer != null && layer.visible)
                _buildLayerButton(layer, canvasSize),
            ],
          );
        },
      ),
    );
  }

  /// Bouton « réglages » ancré au coin bas-gauche du rectangle de la couche.
  Widget _buildLayerButton(ShapeLayer layer, Size canvasSize) {
    if (canvasSize.isEmpty) return const SizedBox.shrink();
    final geo = SceneGeometry.fitFor(widget.project, canvasSize);
    final center = SelectionGeometry.propertiesButton(
      ScenePainter.layerBounds(layer),
      SelectionGeometry.layerPose(_draft, layer, _draft.startMs),
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

  void _onGestureStart(ScaleStartDetails details, Size canvasSize) {
    _gestureStartPoint = details.localFocalPoint;
    final layer = _selectedLayer;
    if (layer == null || !layer.visible) {
      _gesture = _EditorGesture.none;
      return;
    }
    final geo = SceneGeometry.fitFor(widget.project, canvasSize);
    final pose = SelectionGeometry.layerPose(_draft, layer, _draft.startMs);
    final bounds = ScenePainter.layerBounds(layer);
    if (_activePointers >= 2) {
      // Pinch : échelle de la couche sélectionnée.
      _gesture = _EditorGesture.scale;
    } else if (SelectionGeometry.hitRotationHandle(
      details.localFocalPoint,
      SelectionGeometry.rotationHandle(bounds, pose, geo),
    )) {
      // Poignée de rotation.
      _gesture = _EditorGesture.rotate;
      final center = SelectionGeometry.center(pose, geo);
      _gestureStartAngle = math.atan2(
        details.localFocalPoint.dy - center.dy,
        details.localFocalPoint.dx - center.dx,
      );
    } else if (SelectionGeometry.hit(
      bounds,
      pose,
      geo,
      details.localFocalPoint,
    )) {
      // Corps de la couche : déplacement.
      _gesture = _EditorGesture.move;
    } else {
      _gesture = _EditorGesture.none;
    }
    _gestureBaseX = layer.x;
    _gestureBaseY = layer.y;
    _gestureBaseRotation = layer.rotation;
    _gestureBaseScale = layer.scale;
  }

  void _onGestureUpdate(ScaleUpdateDetails details, Size canvasSize) {
    final layer = _selectedLayer;
    if (layer == null || _gesture == _EditorGesture.none) return;
    switch (_gesture) {
      case _EditorGesture.move:
        final geo = SceneGeometry.fitFor(widget.project, canvasSize);
        final sceneDelta = geo.canvasToScene(details.localFocalPoint) -
            geo.canvasToScene(_gestureStartPoint);
        // La couche vit dans le repère de la forme : le delta de scène est
        // repassé en local (rotation et échelle de la forme inversées).
        final shapePose = SelectionGeometry.shapePose(_draft, _draft.startMs);
        final cosR = math.cos(-shapePose.rotation);
        final sinR = math.sin(-shapePose.rotation);
        final safeScale = math.max(0.0001, shapePose.scale.abs());
        final local = Offset(
          (sceneDelta.dx * cosR - sceneDelta.dy * sinR) / safeScale,
          (sceneDelta.dx * sinR + sceneDelta.dy * cosR) / safeScale,
        );
        setState(() {
          layer.x = _gestureBaseX + local.dx;
          layer.y = _gestureBaseY + local.dy;
        });
      case _EditorGesture.scale:
        final next = (_gestureBaseScale * details.scale).clamp(0.05, 4.0);
        setState(() => layer.scale = next.toDouble());
      case _EditorGesture.rotate:
        final geo = SceneGeometry.fitFor(widget.project, canvasSize);
        final pose = SelectionGeometry.layerPose(_draft, layer, _draft.startMs);
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

  /// Tap sur une couche : la sélectionne (du premier plan vers l'arrière-plan).
  /// Tap dans le vide : la sélection actuelle est conservée.
  void _onTapUp(TapUpDetails details, Size canvasSize) {
    final geo = SceneGeometry.fitFor(widget.project, canvasSize);
    for (final layer in _draft.layers.reversed) {
      if (!layer.visible) continue;
      if (SelectionGeometry.hit(
        ScenePainter.layerBounds(layer),
        SelectionGeometry.layerPose(_draft, layer, _draft.startMs),
        geo,
        details.localPosition,
      )) {
        setState(() => _selectedLayerId = layer.id);
        return;
      }
    }
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
    required this.onMove,
    required this.onChanged,
  });

  final VectorShape shape;
  final int durationMs;
  final ShapeLayer? selectedLayer;
  final ValueChanged<ShapeLayer> onSelect;
  final ValueChanged<ShapeKind> onAdd;
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
            Text('${shape.layers.length}', style: const TextStyle(fontSize: 12)),
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
              final start = values.start.round().clamp(
                    0,
                    math.max(0, durationMs - TimelineViewMinSpan.ms),
                  ).toInt();
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
              tooltip: layer.visible ? 'Masquer' : 'Afficher',
              iconSize: 18,
              onPressed: () {
                layer.visible = !layer.visible;
                onChanged();
              },
              icon: Icon(layer.visible ? Icons.visibility : Icons.visibility_off),
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
