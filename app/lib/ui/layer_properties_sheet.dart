import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/animation.dart';
import '../settings/language_settings.dart';
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
    return ValueListenableBuilder<String>(
      valueListenable: AppStrings.language,
      builder: (context, _, _) => _buildLocalized(context),
    );
  }

  Widget _buildLocalized(BuildContext context) {
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
                    '${AppStrings.text('Réglages · ')}${layer.name}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: AppStrings.text('Supprimer la couche'),
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
            if (layer.kind == ShapeKind.rect) ...<Widget>[
              _CornerRadiusSlider(layer: layer, onChanged: _onChanged),
              _CornerSelection(layer: layer, onChanged: _onChanged),
            ],
            Row(
              children: <Widget>[
                Text(
                  AppStrings.text('Remplissage'),
                  style: const TextStyle(fontSize: 12),
                ),
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
              _LayerSlider(
                layer: layer,
                property: property,
                onChanged: _onChanged,
              ),
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
        Text(AppStrings.text('Couleur'), style: const TextStyle(fontSize: 12)),
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
              GestureDetector(
                key: const ValueKey('custom-layer-color'),
                onTap: () async {
                  final initial = Color(layer.colorValue);
                  var red = initial.r;
                  var green = initial.g;
                  var blue = initial.b;
                  final picked = await showDialog<Color>(
                    context: context,
                    builder: (dialogContext) => StatefulBuilder(
                      builder: (context, setDialogState) => AlertDialog(
                        title: Text(AppStrings.text('Couleur personnalisée')),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Container(
                              width: 56,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Color.fromARGB(
                                  255,
                                  (red * 255).round(),
                                  (green * 255).round(),
                                  (blue * 255).round(),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            for (final entry in <(String, double)>[
                              ('Rouge', red),
                              ('Vert', green),
                              ('Bleu', blue),
                            ])
                              Row(
                                children: <Widget>[
                                  SizedBox(width: 54, child: Text(entry.$1)),
                                  Expanded(
                                    child: Slider(
                                      min: 0,
                                      max: 1,
                                      divisions: 255,
                                      value: entry.$2,
                                      onChanged: (value) => setDialogState(() {
                                        if (entry.$1 == 'Rouge') red = value;
                                        if (entry.$1 == 'Vert') green = value;
                                        if (entry.$1 == 'Bleu') blue = value;
                                      }),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        actions: <Widget>[
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: Text(AppStrings.text('Annuler')),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(
                              dialogContext,
                              Color.fromARGB(
                                255,
                                (red * 255).round(),
                                (green * 255).round(),
                                (blue * 255).round(),
                              ),
                            ),
                            child: Text(AppStrings.text('Valider')),
                          ),
                        ],
                      ),
                    ),
                  );
                  if (picked == null) return;
                  layer.colorValue = picked.toARGB32();
                  onChanged();
                },
                child: Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Color(layer.colorValue),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white70, width: 1.5),
                  ),
                  child: const Icon(Icons.colorize, size: 13),
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
            AppStrings.text(layerPropertyLabel(property)),
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

class _CornerRadiusSlider extends StatelessWidget {
  const _CornerRadiusSlider({required this.layer, required this.onChanged});

  final ShapeLayer layer;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final maxRadius = math.min(layer.width.abs(), layer.height.abs()) / 2;
    final automaticRadius = math.min(
      24.0,
      math.min(layer.width.abs(), layer.height.abs()) * 0.15,
    );
    final value =
        (layer.cornerRadius < 0 ? automaticRadius : layer.cornerRadius)
            .clamp(0.0, math.max(1.0, maxRadius))
            .toDouble();
    return Row(
      children: <Widget>[
        SizedBox(
          width: 92,
          child: Text(
            AppStrings.text('Rayon des coins'),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        Expanded(
          child: Slider(
            min: 0,
            max: math.max(1.0, maxRadius),
            divisions: 100,
            value: value,
            onChanged: (next) {
              layer.cornerRadius = next;
              onChanged();
            },
          ),
        ),
        SizedBox(
          width: 36,
          child: Text('${value.round()}', textAlign: TextAlign.end),
        ),
      ],
    );
  }
}

class _CornerSelection extends StatelessWidget {
  const _CornerSelection({required this.layer, required this.onChanged});

  final ShapeLayer layer;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    spacing: 4,
    children: <Widget>[
      _cornerButton('Haut gauche', layer.roundTopLeft, (value) {
        layer.roundTopLeft = value;
      }),
      _cornerButton('Haut droit', layer.roundTopRight, (value) {
        layer.roundTopRight = value;
      }),
      _cornerButton('Bas droit', layer.roundBottomRight, (value) {
        layer.roundBottomRight = value;
      }),
      _cornerButton('Bas gauche', layer.roundBottomLeft, (value) {
        layer.roundBottomLeft = value;
      }),
    ],
  );

  Widget _cornerButton(
    String label,
    bool selected,
    ValueChanged<bool> update,
  ) => FilterChip(
    label: Text(label, style: const TextStyle(fontSize: 11)),
    selected: selected,
    onSelected: (value) {
      update(value);
      onChanged();
    },
  );
}
