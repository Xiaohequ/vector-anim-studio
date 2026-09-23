import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/animation.dart';
import 'palette.dart';

/// Bottom sheet « Réglages de la couche » : couleur, remplissage, sliders et
/// suppression — l'équivalent couche du bottom sheet propriétés du studio.
class LayerPropertiesSheet extends StatefulWidget {
  const LayerPropertiesSheet({
    super.key,
    required this.layer,
    required this.canDelete,
    required this.onChanged,
    required this.onDelete,
  });

  final ShapeLayer layer;

  /// Faux quand il ne reste qu'une couche (la suppression est refusée).
  final bool canDelete;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  State<LayerPropertiesSheet> createState() => _LayerPropertiesSheetState();
}

class _LayerPropertiesSheetState extends State<LayerPropertiesSheet> {
  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final layer = widget.layer;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Réglages · ${layer.name}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Supprimer la couche',
                  onPressed: widget.canDelete
                      ? () {
                          Navigator.of(context).pop();
                          widget.onDelete();
                        }
                      : null,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            _ColorRow(layer: layer, onChanged: _onChanged),
            Row(
              children: <Widget>[
                const Text('Remplissage', style: TextStyle(fontSize: 12)),
                Switch(
                  value: layer.filled,
                  onChanged: (value) {
                    layer.filled = value;
                    _onChanged();
                  },
                ),
              ],
            ),
            for (final property in LayerProperty.values)
              _LayerSlider(layer: layer, property: property, onChanged: _onChanged),
          ],
        ),
      ),
    );
  }

  void _onChanged() {
    widget.onChanged();
    _refresh();
  }
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
