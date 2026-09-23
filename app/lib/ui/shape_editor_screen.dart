import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/scene_painter.dart';
import '../models/animation.dart';
import 'palette.dart';

/// Création / édition d'une forme : aperçu en haut, couches en bas.
///
/// Une forme est un groupe de couches (formes basiques). Chaque couche se
/// règle indépendamment (position, taille, rotation, couleur, épaisseur).
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
          const SizedBox(height: 8),
          Expanded(
            child: LayerPanel(
              shape: _draft,
              durationMs: widget.project.durationMs,
              selectedLayer: layer,
              onSelect: (value) => setState(() => _selectedLayerId = value.id),
              onAdd: _addLayer,
              onRemove: _removeLayer,
              onMove: _moveLayer,
              onChanged: () => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

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
      child: InteractiveViewer(
        maxScale: 5,
        child: Center(
          child: AspectRatio(
            aspectRatio: widget.project.width / widget.project.height,
            child: CustomPaint(
              painter: ScenePainter(
                project: _preview,
                timeMs: _draft.startMs,
                selectedShapeId: _isNew ? null : _draft.id,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

/// Durée minimale de la fenêtre d'affichage d'une forme (ms).
class TimelineViewMinSpan {
  const TimelineViewMinSpan._();

  static const int ms = 100;
}

/// Liste des couches + réglages de la couche sélectionnée.
class LayerPanel extends StatelessWidget {
  const LayerPanel({
    super.key,
    required this.shape,
    required this.durationMs,
    required this.selectedLayer,
    required this.onSelect,
    required this.onAdd,
    required this.onRemove,
    required this.onMove,
    required this.onChanged,
  });

  final VectorShape shape;
  final int durationMs;
  final ShapeLayer? selectedLayer;
  final ValueChanged<ShapeLayer> onSelect;
  final ValueChanged<ShapeKind> onAdd;
  final ValueChanged<ShapeLayer> onRemove;
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
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Réglages · ${layer.name}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'Supprimer la couche',
                onPressed: () => onRemove(layer),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          _ColorRow(layer: layer, onChanged: onChanged),
          Row(
            children: <Widget>[
              const Text('Remplissage', style: TextStyle(fontSize: 12)),
              Switch(
                value: layer.filled,
                onChanged: (value) {
                  layer.filled = value;
                  onChanged();
                },
              ),
            ],
          ),
          for (final property in _layerProperties(shape))
            _LayerSlider(layer: layer, property: property, onChanged: onChanged),
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

  List<LayerProperty> _layerProperties(VectorShape shape) => const <LayerProperty>[
        LayerProperty.x,
        LayerProperty.y,
        LayerProperty.width,
        LayerProperty.height,
        LayerProperty.rotation,
        LayerProperty.scale,
        LayerProperty.opacity,
        LayerProperty.strokeWidth,
      ];
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.layer, required this.onChanged});

  final ShapeLayer layer;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Text('Couleur', style: TextStyle(fontSize: 12)),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final color in kColorPalette)
                GestureDetector(
                  onTap: () {
                    layer.colorValue = color;
                    onChanged();
                  },
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Color(color),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: layer.colorValue == color
                            ? Colors.white
                            : Colors.white24,
                        width: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LayerSlider extends StatelessWidget {
  const _LayerSlider({
    required this.layer,
    required this.property,
    required this.onChanged,
  });

  final ShapeLayer layer;
  final LayerProperty property;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final (min, max, step) = switch (property) {
      LayerProperty.x => (-240.0, 240.0, 1.0),
      LayerProperty.y => (-320.0, 320.0, 1.0),
      LayerProperty.width => (2.0, 400.0, 1.0),
      LayerProperty.height => (0.0, 400.0, 1.0),
      LayerProperty.rotation => (-3.15, 3.15, 0.01),
      LayerProperty.scale => (0.05, 4.0, 0.01),
      LayerProperty.opacity => (0.0, 1.0, 0.01),
      LayerProperty.strokeWidth => (0.0, 40.0, 0.5),
    };
    final value = layer.baseOf(property).clamp(min, max);
    return Row(
      children: <Widget>[
        SizedBox(
          width: 92,
          child: Text(
            layerPropertyLabel(property),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        Expanded(
          child: Slider(
            min: min,
            max: max,
            divisions: math.max(1, ((max - min) / step).round()),
            value: value,
            onChanged: (next) {
              layer.setBase(property, next);
              onChanged();
            },
          ),
        ),
        SizedBox(
          width: 46,
          child: Text(
            value.toStringAsFixed(step < 1 ? 2 : 0),
            style: const TextStyle(fontSize: 11),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
