import 'package:flutter/material.dart';

import '../engine/timeline_controller.dart';
import '../models/animation.dart';

/// Bottom sheet « Propriétés de la forme » : tous les réglages de la forme
/// sélectionnée (sliders, keyframe au curseur, interpolation), en suivant la
/// tête de lecture. Les sliders écrivent via l'auto-key (pose au curseur),
/// comme partout ailleurs.
class ShapePropertiesSheet extends StatefulWidget {
  const ShapePropertiesSheet({
    super.key,
    required this.project,
    required this.shape,
    required this.controller,
    required this.onPropertyChanged,
    required this.onToggleKeyframe,
    required this.onKeyframeEasing,
    required this.onEditLayers,
  });

  final AnimationProject project;
  final VectorShape shape;
  final TimelineController controller;

  /// Écrit une propriété via l'auto-key (pose au curseur).
  final void Function(AnimatableProperty property, double value)
      onPropertyChanged;
  final Future<void> Function() onToggleKeyframe;
  final Future<void> Function(EasingKind easing) onKeyframeEasing;
  final VoidCallback onEditLayers;

  @override
  State<ShapePropertiesSheet> createState() => _ShapePropertiesSheetState();
}

class _ShapePropertiesSheetState extends State<ShapePropertiesSheet> {
  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final shape = widget.shape;
    final controller = widget.controller;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.66;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final keyframe = controller.nearestKeyframe(shape);
        final hasKeyframes = shape.hasKeyframes;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        shape.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: keyframe == null
                          ? 'Ajouter une keyframe au curseur'
                          : 'Retirer la keyframe au curseur',
                      iconSize: 20,
                      icon: Icon(
                        keyframe == null
                            ? Icons.diamond_outlined
                            : Icons.diamond,
                        color: hasKeyframes ? const Color(0xFFF2C94C) : null,
                      ),
                      onPressed: () async {
                        await widget.onToggleKeyframe();
                        _refresh();
                      },
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onEditLayers();
                      },
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Couches'),
                    ),
                  ],
                ),
                Text(
                  'Affichée de ${(shape.startMs / 1000).toStringAsFixed(2)} s à '
                  '${(shape.endMs / 1000).toStringAsFixed(2)} s'
                  '${shape.visible ? '' : ' · masquée'}'
                  '${hasKeyframes ? '' : ' · aucune keyframe'}',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
                const SizedBox(height: 4),
                for (final property in AnimatableProperty.values)
                  _buildPropertyRow(shape, property, controller),
                Row(
                  children: <Widget>[
                    const SizedBox(
                      width: 92,
                      child:
                          Text('Interpolation', style: TextStyle(fontSize: 12)),
                    ),
                    Expanded(
                      child: DropdownButton<EasingKind>(
                        isExpanded: true,
                        value: keyframe?.easing ?? EasingKind.easeInOut,
                        onChanged: keyframe == null
                            ? null
                            : (value) async {
                                if (value == null) return;
                                await widget.onKeyframeEasing(value);
                                _refresh();
                              },
                        items: <DropdownMenuItem<EasingKind>>[
                          for (final easing in EasingKind.values)
                            DropdownMenuItem<EasingKind>(
                              value: easing,
                              child: Text(
                                easingLabel(easing),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    hasKeyframes
                        ? 'Forme animée : toute modification écrit une keyframe au curseur.'
                        : 'Ajoute une keyframe (◆) pour animer toutes les propriétés.',
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPropertyRow(
    VectorShape shape,
    AnimatableProperty property,
    TimelineController controller,
  ) {
    final value = shape.valueAt(property, controller.timeMs);
    final (min, max, step) = switch (property) {
      AnimatableProperty.x => (0.0, widget.project.width, 1.0),
      AnimatableProperty.y => (0.0, widget.project.height, 1.0),
      AnimatableProperty.rotation => (-3.15, 3.15, 0.01),
      AnimatableProperty.scale => (0.05, 4.0, 0.01),
      AnimatableProperty.opacity => (0.0, 1.0, 0.01),
      AnimatableProperty.strokeWidth => (0.0, 6.0, 0.05),
    };
    final animated = shape.isAnimated(property);
    return Row(
      children: <Widget>[
        SizedBox(
          width: 92,
          child: Text(
            propertyLabel(property),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        Expanded(
          child: Slider(
            min: min,
            max: max,
            divisions: ((max - min) / step).round().clamp(1, 2000),
            value: value.clamp(min, max),
            onChanged: (next) {
              widget.onPropertyChanged(property, next);
              _refresh();
            },
          ),
        ),
        SizedBox(
          width: 32,
          child: Tooltip(
            message: animated ? 'Propriété animée' : 'Valeur fixe',
            triggerMode: TooltipTriggerMode.tap,
            child: Icon(
              animated ? Icons.diamond : Icons.diamond_outlined,
              size: 16,
              color: animated ? const Color(0xFFF2C94C) : Colors.white24,
            ),
          ),
        ),
      ],
    );
  }
}
