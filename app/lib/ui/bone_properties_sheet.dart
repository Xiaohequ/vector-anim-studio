import 'package:flutter/material.dart';

import '../engine/timeline_controller.dart';
import '../models/animation.dart';
import '../models/skeleton.dart';

/// Propriété d'animation d'un os (keyframe d'os, v0.10).
enum BoneAnimatable { opacity, stretch, squash }

String boneAnimatableLabel(BoneAnimatable property) => switch (property) {
  BoneAnimatable.opacity => 'Opacité',
  BoneAnimatable.stretch => 'Étirement',
  BoneAnimatable.squash => 'Écrasement',
};

/// Bottom sheet « Propriétés de l'os » : parent, longueur, angle de repos,
/// keyframe d'angle au curseur et interpolation. Les mutations passent par
/// les callbacks de l'écran (undo + sauvegarde y sont gérés).
class BonePropertiesSheet extends StatefulWidget {
  const BonePropertiesSheet({
    super.key,
    required this.rig,
    required this.bone,
    required this.controller,
    required this.onLengthChanged,
    required this.onParentChanged,
    required this.onRenameBone,
    required this.onDeleteBone,
    required this.onToggleKeyframe,
    required this.onKeyframeEasing,
    this.onZChanged,
    this.onAnimatableChanged,
    this.onToggleIk,
    this.onFlipBend,
  });

  final SkeletonRig rig;
  final RigBone bone;
  final TimelineController controller;

  /// Slider de longueur (auto-coalescé côté écran).
  final ValueChanged<double> onLengthChanged;
  final ValueChanged<String?> onParentChanged;
  final Future<void> Function() onRenameBone;
  final Future<void> Function() onDeleteBone;
  final Future<void> Function() onToggleKeyframe;
  final Future<void> Function(EasingKind easing) onKeyframeEasing;

  /// Ordre de dessin (z, v0.10) : slider entier.
  final ValueChanged<int>? onZChanged;

  /// Propriété d'animation d'os (opacité/étirement/écrasement, v0.10) :
  /// écrit une keyframe d'os au curseur.
  final void Function(BoneAnimatable property, double value)?
  onAnimatableChanged;

  /// IK 2 os (v0.10) : bascule + inversion du coude.
  final VoidCallback? onToggleIk;
  final VoidCallback? onFlipBend;

  @override
  State<BonePropertiesSheet> createState() => _BonePropertiesSheetState();
}

class _BonePropertiesSheetState extends State<BonePropertiesSheet> {
  void _refresh() {
    if (mounted) setState(() {});
  }

  /// Os re-parentables : tout os sauf soi-même et ses descendants.
  List<RigBone> get _eligibleParents {
    final excluded = <String>{widget.bone.id};
    var grew = true;
    while (grew) {
      grew = false;
      for (final bone in widget.rig.bones) {
        if (excluded.contains(bone.id)) continue;
        final parent = bone.parentId;
        if (parent != null && excluded.contains(parent)) {
          excluded.add(bone.id);
          grew = true;
        }
      }
    }
    return <RigBone>[
      for (final bone in widget.rig.bones)
        if (!excluded.contains(bone.id)) bone,
    ];
  }

  String _indent(RigBone bone) {
    final depth = widget.rig.depthOf(bone.id);
    return depth == 0 ? '' : '${'\u2500' * depth} ';
  }

  @override
  Widget build(BuildContext context) {
    final bone = widget.bone;
    final rig = widget.rig;
    final controller = widget.controller;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.66;
    final degrees = (bone.restAngle * 180 / 3.141592653589793) % 360;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final keyframe = controller.nearestBoneKeyframe(rig, bone);
        final hasKeyframes = rig.hasKeyframes(bone.id);
        final deltaDegrees =
            rig.angleDeltaAt(bone.id, controller.timeMs) *
            180 /
            3.141592653589793;
        final sampledOpacity = rig.opacityAt(bone.id, controller.timeMs);
        final sampledStretch = rig.stretchAt(bone.id, controller.timeMs);
        final sampledSquash = rig.squashAt(bone.id, controller.timeMs);
        final ikChild = rig.onlyChildOf(bone.id);
        final boundShapes = <String>[
          for (final binding in rig.bindings)
            if (binding.boneId == bone.id) binding.shapeId,
        ];
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
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () async {
                          await widget.onRenameBone();
                          _refresh();
                        },
                        child: Text(
                          bone.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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
                    IconButton(
                      tooltip: 'Supprimer l’os',
                      iconSize: 20,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await widget.onDeleteBone();
                      },
                    ),
                  ],
                ),
                Text(
                  'Angle de repos ${degrees.toStringAsFixed(0)}°'
                  ' · à ${((controller.timeMs) / 1000).toStringAsFixed(2)} s : '
                  '${deltaDegrees >= 0 ? '+' : ''}${deltaDegrees.toStringAsFixed(0)}°',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    const SizedBox(
                      width: 92,
                      child: Text('Longueur', style: TextStyle(fontSize: 12)),
                    ),
                    Expanded(
                      child: Slider(
                        min: 10,
                        max: 400,
                        divisions: 390,
                        value: bone.length.clamp(10, 400),
                        onChanged: (value) {
                          widget.onLengthChanged(value);
                          _refresh();
                        },
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        '${bone.length.round()}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: <Widget>[
                    const SizedBox(
                      width: 92,
                      child: Text('Ordre (z)', style: TextStyle(fontSize: 12)),
                    ),
                    Expanded(
                      child: Slider(
                        min: -10,
                        max: 10,
                        divisions: 20,
                        value: bone.z.clamp(-10, 10).toDouble(),
                        onChanged: (value) {
                          widget.onZChanged?.call(value.round());
                          _refresh();
                        },
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        '${bone.z}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: <Widget>[
                    const SizedBox(
                      width: 92,
                      child: Text('Opacité', style: TextStyle(fontSize: 12)),
                    ),
                    Expanded(
                      child: Slider(
                        min: 0,
                        max: 1,
                        divisions: 100,
                        value: sampledOpacity.clamp(0.0, 1.0),
                        onChanged: (value) {
                          widget.onAnimatableChanged?.call(
                            BoneAnimatable.opacity,
                            value,
                          );
                          _refresh();
                        },
                      ),
                    ),
                  ],
                ),
                Row(
                  children: <Widget>[
                    const SizedBox(
                      width: 92,
                      child: Text('Étirement', style: TextStyle(fontSize: 12)),
                    ),
                    Expanded(
                      child: Slider(
                        min: 0.2,
                        max: 3,
                        divisions: 28,
                        value: sampledStretch.clamp(0.2, 3),
                        onChanged: (value) {
                          widget.onAnimatableChanged?.call(
                            BoneAnimatable.stretch,
                            value,
                          );
                          _refresh();
                        },
                      ),
                    ),
                  ],
                ),
                Row(
                  children: <Widget>[
                    const SizedBox(
                      width: 92,
                      child: Text('Écrasement', style: TextStyle(fontSize: 12)),
                    ),
                    Expanded(
                      child: Slider(
                        min: 0.2,
                        max: 3,
                        divisions: 28,
                        value: sampledSquash.clamp(0.2, 3),
                        onChanged: (value) {
                          widget.onAnimatableChanged?.call(
                            BoneAnimatable.squash,
                            value,
                          );
                          _refresh();
                        },
                      ),
                    ),
                  ],
                ),
                Row(
                  children: <Widget>[
                    const SizedBox(
                      width: 92,
                      child: Text('IK 2 os', style: TextStyle(fontSize: 12)),
                    ),
                    Expanded(
                      child: Text(
                        ikChild == null
                            ? 'Sans enfant unique — indisponible'
                            : 'Glisser l’extrémité de « ${ikChild.name} » résout la chaîne',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                    Switch(
                      value: bone.ikEnabled,
                      onChanged: ikChild == null
                          ? null
                          : (_) {
                              widget.onToggleIk?.call();
                              _refresh();
                            },
                    ),
                  ],
                ),
                if (bone.ikEnabled && ikChild != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        widget.onFlipBend?.call();
                        _refresh();
                      },
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: Text(
                        'Inverser le coude (${bone.bendSign > 0 ? '+' : '−'})',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                Row(
                  children: <Widget>[
                    const SizedBox(
                      width: 92,
                      child: Text('Os parent', style: TextStyle(fontSize: 12)),
                    ),
                    Expanded(
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: bone.parentId,
                        onChanged: (value) {
                          widget.onParentChanged(value);
                          _refresh();
                        },
                        items: <DropdownMenuItem<String?>>[
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text(
                              'Racine (aucun)',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          for (final candidate in _eligibleParents)
                            DropdownMenuItem<String?>(
                              value: candidate.id,
                              child: Text(
                                '${_indent(candidate)}${candidate.name}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
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
                const SizedBox(height: 4),
                Text(
                  boundShapes.isEmpty
                      ? 'Aucune pièce liée à cet os.'
                      : 'Pièces liées : ${boundShapes.join(', ')}',
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    hasKeyframes
                        ? 'Os animé : glisser la poignée de rotation écrit une keyframe au curseur.'
                        : 'Glisser la poignée de rotation pose le rig ; ◆ fige une keyframe d’angle.',
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
}
