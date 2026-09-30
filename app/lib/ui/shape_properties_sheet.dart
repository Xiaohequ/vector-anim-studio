import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/timeline_controller.dart';
import '../models/animation.dart';
import '../models/skeleton.dart';
import 'palette.dart';

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
    this.onOpenSource,
    this.onPivotChanged,
    this.onLayerColorChanged,
    this.onToggleLayerColor,
    this.skeletonPiece = false,
    this.skeletonNote,
    this.skeletonRig,
    this.onBindLayer,
    this.onUnbindLayer,
    this.onMirror,
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

  /// Ouvre le projet source (instances d'animation uniquement).
  final VoidCallback? onOpenSource;

  /// Pièce d'un projet squelette : la forme est un élément statique du rig,
  /// pas d'animation de pose propre — keyframes/interpolation masquées.
  final bool skeletonPiece;

  /// État de liaison au rig (projet squelette), affiché sous le titre.
  final String? skeletonNote;

  /// Rig du projet (projet squelette) : active la section « Couches liées
  /// au rig » (liaison au niveau couche, v0.9.6).
  final SkeletonRig? skeletonRig;

  /// Lie une couche à un os (dialogue de sélection côté écran).
  final Future<void> Function(ShapeLayer layer)? onBindLayer;

  /// Délie une couche de son os.
  final Future<void> Function(ShapeLayer layer)? onUnbindLayer;

  /// Miroir du groupe de couches (v0.19) : [horizontal] = miroir d'axe
  /// vertical (gauche ↔ droite), sinon d'axe horizontal (haut ↔ bas).
  final void Function(bool horizontal)? onMirror;

  /// Écrit le pivot de rotation (offset dx/dy depuis le centre, unités
  /// scène) — v0.13. Statique (non animable) : pas d'auto-key.
  final void Function(double dx, double dy)? onPivotChanged;

  /// Couleur d'une couche (v0.15, couleur animée) : base si la forme n'est
  /// pas animée, sinon entrée de couleur dans la pose au curseur.
  final void Function(ShapeLayer layer, int color)? onLayerColorChanged;

  /// Losange de couleur d'une couche : pose/retire l'entrée de couleur de
  /// la pose au curseur.
  final void Function(ShapeLayer layer)? onToggleLayerColor;

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
                    // Bugfix v0.16.1 : le ◆ de pose était masqué pour les
                    // pièces d'un projet squelette — les poses de pièces
                    // étaient donc incréables (le ◆ de la playbar no-opait).
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
                    if (shape.isInstance)
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onOpenSource?.call();
                        },
                        icon: const Icon(Icons.movie_outlined, size: 16),
                        label: const Text('Source'),
                      )
                    else
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
                  widget.skeletonPiece
                      ? '${widget.skeletonNote ?? 'Pièce du rig'}'
                            '${hasKeyframes ? '' : ' · aucune keyframe'}'
                      : 'Affichée de ${(shape.startMs / 1000).toStringAsFixed(2)} s à '
                            '${(shape.endMs / 1000).toStringAsFixed(2)} s'
                            '${shape.visible ? '' : ' · masquée'}'
                            '${hasKeyframes ? '' : ' · aucune keyframe'}',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
                const SizedBox(height: 4),
                // Miroir (v0.19) : reflète le groupe de couches — contenu
                // dessiné (flag de flip), position et rotation de chaque
                // couche. Non proposé pour les instances (pas de couches).
                if (widget.onMirror != null &&
                    !shape.isInstance &&
                    shape.layers.isNotEmpty)
                  Row(children: <Widget>[
                    TextButton.icon(
                      onPressed: () {
                        widget.onMirror!(true);
                        _refresh();
                      },
                      icon: const Icon(Icons.flip, size: 16),
                      label: const Text('Miroir H'),
                    ),
                    const SizedBox(width: 4),
                    TextButton.icon(
                      onPressed: () {
                        widget.onMirror!(false);
                        _refresh();
                      },
                      icon: Transform.rotate(
                        angle: math.pi / 2,
                        child: const Icon(Icons.flip, size: 16),
                      ),
                      label: const Text('Miroir V'),
                    ),
                  ]),
                for (final property in AnimatableProperty.values)
                  if (property != AnimatableProperty.strokeWidth ||
                      !shape.isInstance)
                    _buildPropertyRow(shape, property, controller),
                // Couleurs par couche (v0.15, couleur animée) : palette +
                // losange auto-key. Les instances n'ont pas de couches.
                if (!shape.isInstance && shape.layers.isNotEmpty)
                  ..._buildLayerColorRows(shape, controller),
                // Pivot (v0.13.1) : visible dans TOUS les projets — le pivot
                // est un réglage de forme qui s'applique aussi aux pièces
                // d'un projet squelette (ex. porte non liée de l'exemple G2).
                if (widget.onPivotChanged != null) ..._buildPivotRows(shape),
                if (widget.skeletonPiece &&
                    widget.skeletonRig != null &&
                    shape.layers.isNotEmpty)
                  ..._buildRigLayerRows(),
                // Bugfix v0.16.1 : l'interpolation et l'astuce ◆ valent pour
                // les pièces — leurs poses s'interpolent comme les formes.
                Row(
                  children: <Widget>[
                    const SizedBox(
                      width: 92,
                      child: Text(
                        'Interpolation',
                        style: TextStyle(fontSize: 12),
                      ),
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

  /// Lignes « Couleur » par couche (v0.15, couleur animée) : la couleur
  /// AFFICHÉE est la valeur interpolée au curseur (contour blanc = palette
  /// courante). Sans keyframe sur la forme, un choix écrit la base de la
  /// couche ; avec keyframes, une entrée de couleur dans la pose au curseur
  /// (auto-key). Le losange pose/retire l'entrée de la pose au curseur.
  List<Widget> _buildLayerColorRows(
    VectorShape shape,
    TimelineController controller,
  ) {
    final rows = <Widget>[
      const Padding(
        padding: EdgeInsets.only(top: 6, bottom: 2),
        child: Text(
          'Couleurs des couches',
          style: TextStyle(fontSize: 11, color: Colors.white70),
        ),
      ),
    ];
    for (final layer in shape.layers) {
      final current = shape.colorAtLayer(
        layer.id,
        controller.timeMs,
        layer.colorValue,
      );
      final nearest = shape.keyframeNear(
        controller.timeMs,
        controller.snapToleranceMs,
      );
      final hasColorKey = nearest?.layerColors.containsKey(layer.id) ?? false;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 92,
                child: Text(
                  layer.name,
                  style: const TextStyle(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    for (final color in kColorPalette)
                      GestureDetector(
                        onTap: () {
                          widget.onLayerColorChanged?.call(layer, color);
                          _refresh();
                        },
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: Color(color),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: current == color
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
              IconButton(
                tooltip: hasColorKey
                    ? 'Retirer la couleur de la pose au curseur'
                    : 'Poser la couleur au curseur',
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  hasColorKey ? Icons.diamond : Icons.diamond_outlined,
                  color: shape.layerColorAnimated(layer.id)
                      ? const Color(0xFFF2C94C)
                      : null,
                ),
                onPressed: () {
                  widget.onToggleLayerColor?.call(layer);
                  _refresh();
                },
              ),
            ],
          ),
        ),
      );
    }
    return rows;
  }

  /// Section « Couches liées au rig » (projet squelette) : une ligne par
  /// couche avec son os porteur et une action Lier…/Délier. La liaison de
  /// couche prend le pas sur la liaison de forme entière.
  List<Widget> _buildRigLayerRows() {
    final rig = widget.skeletonRig!;
    final shape = widget.shape;
    final rows = <Widget>[
      Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Text(
          'Couches liées au rig',
          style: TextStyle(fontSize: 11, color: Colors.white70),
        ),
      ),
    ];
    for (final layer in shape.layers) {
      final bone = rig.boneById(
        rig.bindingForLayer(shape.id, layer.id)?.boneId,
      );
      rows.add(
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                layer.name,
                style: const TextStyle(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              bone?.name ?? (rig.bones.isEmpty ? 'aucun os' : '—'),
              style: TextStyle(
                fontSize: 11,
                color: bone == null ? Colors.white24 : const Color(0xFFC084FC),
              ),
            ),
            TextButton(
              onPressed: bone == null
                  ? (rig.bones.isEmpty
                        ? null
                        : () async {
                            await widget.onBindLayer?.call(layer);
                            _refresh();
                          })
                  : () async {
                      await widget.onUnbindLayer?.call(layer);
                      _refresh();
                    },
              child: Text(bone == null ? 'Lier…' : 'Délier'),
            ),
          ],
        ),
      );
    }
    return rows;
  }

  /// Sliders du pivot de rotation (statique, unités scène, offset depuis le
  /// centre). Chaque slider passe les DEUX valeurs au callback (l'autre est
  /// relue sur la forme) pour coalescer en une seule entrée d'annulation.
  List<Widget> _buildPivotRows(VectorShape shape) {
    Widget row(String label, double value) {
      return Row(
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: Slider(
              min: -500,
              max: 500,
              divisions: 500,
              value: value.clamp(-500, 500),
              onChanged: (next) {
                final dx = label == 'Pivot X' ? next : shape.pivotDx;
                final dy = label == 'Pivot X' ? shape.pivotDy : next;
                widget.onPivotChanged?.call(dx, dy);
                _refresh();
              },
            ),
          ),
          SizedBox(
            width: 32,
            child: Text(
              '${value.round()}',
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 10, color: Colors.white54),
            ),
          ),
        ],
      );
    }

    return <Widget>[
      const Padding(
        padding: EdgeInsets.only(top: 6, bottom: 2),
        child: Text(
          'Pivot de rotation (offset depuis le centre)',
          style: TextStyle(fontSize: 11, color: Colors.white70),
        ),
      ),
      row('Pivot X', shape.pivotDx),
      row('Pivot Y', shape.pivotDy),
    ];
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
      AnimatableProperty.scaleX => (0.05, 4.0, 0.01),
      AnimatableProperty.scaleY => (0.05, 4.0, 0.01),
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
