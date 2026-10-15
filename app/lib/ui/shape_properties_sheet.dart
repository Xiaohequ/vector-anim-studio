import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/timeline_controller.dart';
import '../models/animation.dart';
import '../settings/language_settings.dart';
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
    this.onRename,
    this.onDuplicate,
    this.onMove,
    this.onToggleVisibility,
    this.onDelete,
    this.onZIndexChanged,
    this.onPivotChanged,
    this.onLayerColorChanged,
    this.onToggleLayerColor,
    this.skeletonPiece = false,
    this.skeletonNote,
    this.skeletonRig,
    this.onOpenBoneEditor,
    this.onDeleteBone,
    this.onMirror,
    this.allowBoneEditorForInstance = false,
    this.onGroupChanged,
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
  final VoidCallback? onRename;
  final VoidCallback? onDuplicate;
  final ValueChanged<int>? onMove;
  final VoidCallback? onToggleVisibility;
  final VoidCallback? onDelete;
  final ValueChanged<int>? onZIndexChanged;

  /// Tous les projets prennent en charge les rigs ; une pièce peut donc être
  /// attachée à un os et pilotée par lui.
  final bool skeletonPiece;

  /// État de liaison au rig, affiché sous le titre.
  final String? skeletonNote;

  /// Rig du projet : active la section « Os de la
  /// forme » (l'os n'existe que par une forme, v0.20).
  final SkeletonRig? skeletonRig;

  /// Ouvre l'éditeur d'os (dessin + déplacement) — création ou
  /// modification de la chaîne de cette forme.
  final VoidCallback? onOpenBoneEditor;

  /// « Supprimer l'os » : efface l'os, sa descendance et toutes leurs
  /// keyframes (dialogue de confirmation côté studio).
  final VoidCallback? onDeleteBone;

  /// Miroir du groupe de couches (v0.19) : [horizontal] = miroir d'axe
  /// vertical (gauche ↔ droite), sinon d'axe horizontal (haut ↔ bas).
  final void Function(bool horizontal)? onMirror;

  /// Un groupe squelette imbriqué peut être lié au rig du projet hôte.
  final bool allowBoneEditorForInstance;

  /// Affecte ou retire la forme d'un groupe existant.
  final ValueChanged<String?>? onGroupChanged;

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
      animation: Listenable.merge(<Listenable>[
        controller,
        AppStrings.language,
      ]),
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
                          ? AppStrings.text('Ajouter une keyframe au curseur')
                          : AppStrings.text('Retirer la keyframe au curseur'),
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
                        label: Text(AppStrings.text('Source')),
                      )
                    else
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onEditLayers();
                        },
                        icon: const Icon(Icons.edit, size: 16),
                        label: Text(AppStrings.text('Couches')),
                      ),
                  ],
                ),
                if (!shape.isInstance) ...<Widget>[
                  const SizedBox(height: 4),
                  _buildElementActions(context, shape),
                  if (widget.onGroupChanged != null) _buildGroupSelector(shape),
                  if (widget.onZIndexChanged != null) ...<Widget>[
                    _buildZIndexSlider(shape),
                    const SizedBox(height: 4),
                  ],
                ],
                Text(
                  widget.skeletonPiece
                      ? '${widget.skeletonNote ?? AppStrings.text('Pièce du rig')}'
                            '${hasKeyframes ? '' : ' · ${AppStrings.text('aucune keyframe')}'}'
                      : '${AppStrings.text('Affichée de ')}${(shape.startMs / 1000).toStringAsFixed(2)} ${AppStrings.text('s à ')}'
                            '${(shape.endMs / 1000).toStringAsFixed(2)} ${AppStrings.text('s')}'
                            '${shape.visible ? '' : ' · ${AppStrings.text('masquée')}'}'
                            '${hasKeyframes ? '' : ' · ${AppStrings.text('aucune keyframe')}'}',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
                const SizedBox(height: 4),
                // Os de la forme (v0.20) : l'os n'existe que par une forme.
                // Bugfix v0.20.1 : conditionnée à `skeletonRig != null`, la
                // section était INVISIBLE sur un projet squelette neuf (pas
                // encore de rig — il naît à la validation de l'éditeur) : on
                // conditionne au TYPE de projet, plus à l'existence du rig.
                // « Ajouter » ouvre l'éditeur d'os (dessin sur la forme,
                // forme ancrée au milieu de l'écran) ; « Supprimer » part
                // avec la descendance et toutes les keyframes de l'os.
                if (widget.onOpenBoneEditor != null &&
                    (!shape.isInstance || widget.allowBoneEditorForInstance))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            _boneName(shape) == null
                                ? AppStrings.text('Aucun os')
                                : 'Os « ${_boneName(shape)} »',
                            style: const TextStyle(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            widget.onOpenBoneEditor!();
                          },
                          icon: Icon(
                            _boneName(shape) == null ? Icons.add : Icons.edit,
                            size: 16,
                          ),
                          label: Text(
                            _boneName(shape) == null
                                ? AppStrings.text('Ajouter un os…')
                                : AppStrings.text('Modifier l’os…'),
                          ),
                        ),
                        if (_boneName(shape) != null &&
                            widget.onDeleteBone != null)
                          TextButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              widget.onDeleteBone!();
                            },
                            icon: Icon(
                              shape.isInstance
                                  ? Icons.link_off
                                  : Icons.delete_outline,
                              size: 16,
                              color: const Color(0xFFF2949A),
                            ),
                            label: Text(
                              shape.isInstance
                                  ? AppStrings.text('Délier du rig')
                                  : AppStrings.text('Supprimer l’os'),
                              style: const TextStyle(color: Color(0xFFF2949A)),
                            ),
                          ),
                      ],
                    ),
                  ),
                // Miroir (v0.19) : reflète le groupe de couches — contenu
                // dessiné (flag de flip), position et rotation de chaque
                // couche ; sur une instance, reflète le groupe complet.
                if (widget.onMirror != null &&
                    (shape.isInstance || shape.layers.isNotEmpty))
                  Row(
                    children: <Widget>[
                      TextButton.icon(
                        onPressed: () {
                          widget.onMirror!(true);
                          _refresh();
                        },
                        icon: const Icon(Icons.flip, size: 16),
                        label: Text(AppStrings.text('Miroir H')),
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
                        label: Text(AppStrings.text('Miroir V')),
                      ),
                    ],
                  ),
                // v0.19.1 : forme PORTÉE par un os → transformations
                // verrouillées au doigt ET dans les sliders (translation,
                // rotation, échelle) — seul l'os la bouge, ou une
                // dissociation (Squelettes ▸ Délier la pièce). Placé AVANT
                // les sliders : le message reste visible même si la liste
                // est paresseuse sous la hauteur max de la sheet.
                if (widget.skeletonRig != null &&
                    widget.skeletonRig!.isAttached(shape.id) &&
                    !shape.isInstance)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 2),
                    child: Text(
                      AppStrings.text(
                        '« ${shape.name} » est liée à l’os « ${_carrierName(shape)} » : transformations bloquées — seule l’os la bouge (« Supprimer l’os » pour libérer).',
                      ),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFF2C94C),
                      ),
                    ),
                  ),
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
                // Bugfix v0.16.1 : l'interpolation et l'astuce ◆ valent pour
                // les pièces — leurs poses s'interpolent comme les formes.
                Row(
                  children: <Widget>[
                    SizedBox(
                      width: 92,
                      child: Text(
                        AppStrings.text('Interpolation'),
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
                                AppStrings.text(easingLabel(easing)),
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
                    AppStrings.text(
                      hasKeyframes
                          ? 'Forme animée : toute modification écrit une keyframe au curseur.'
                          : 'Ajoute une keyframe (◆) pour animer toutes les propriétés.',
                    ),
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
      Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Text(
          AppStrings.text('Couleurs des couches'),
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
  /// Nom de l'os porteur de la forme (null = aucun os).
  String? _boneName(VectorShape shape) {
    final rig = widget.skeletonRig;
    if (rig == null) return null;
    final id = rig.carrierBoneId(shape.id);
    if (id == null) return null;
    return rig.boneById(id)?.name;
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
      Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Text(
          AppStrings.text('Pivot de rotation (offset depuis le centre)'),
          style: TextStyle(fontSize: 11, color: Colors.white70),
        ),
      ),
      row('Pivot X', shape.pivotDx),
      row('Pivot Y', shape.pivotDy),
    ];
  }

  /// Nom de l’os qui porte [shape] (liaison de la forme entière, sinon
  /// d’une de ses couches) — pour les messages de transformation bloquée.
  String _carrierName(VectorShape shape) {
    final rig = widget.skeletonRig!;
    return rig.boneById(rig.carrierBoneId(shape.id))?.name ?? '?';
  }

  /// Propriétés de TRANSFORMATION verrouillées pour une pièce portée par un
  /// os (v0.19.1) : translation, rotation et échelle (facteurs d'axe
  /// compris). Opacité et épaisseur de trait restent libres : elles ne
  /// déplacent pas la pièce.
  static const Set<AnimatableProperty> _transformProperties = {
    AnimatableProperty.x,
    AnimatableProperty.y,
    AnimatableProperty.rotation,
    AnimatableProperty.scale,
    AnimatableProperty.scaleX,
    AnimatableProperty.scaleY,
  };

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
    // v0.19.1 : transformations verrouillées pour une forme portée par un
    // os — translation, rotation ET échelle : les gestes canvas sont
    // bloqués du même coup (cf. StudioScreen).
    final rig = widget.skeletonRig;
    final transformLocked =
        rig != null &&
        rig.isAttached(shape.id) &&
        !shape.isInstance &&
        _transformProperties.contains(property);
    return Row(
      children: <Widget>[
        SizedBox(
          width: 92,
          child: Text(
            AppStrings.text(propertyLabel(property)),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        Expanded(
          child: Slider(
            min: min,
            max: max,
            divisions: ((max - min) / step).round().clamp(1, 2000),
            value: value.clamp(min, max),
            onChanged: transformLocked
                ? null
                : (next) {
                    widget.onPropertyChanged(property, next);
                    _refresh();
                  },
          ),
        ),
        SizedBox(
          width: 32,
          child: Tooltip(
            message: AppStrings.text(
              animated ? 'Propriété animée' : 'Valeur fixe',
            ),
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

  Widget _buildGroupSelector(VectorShape shape) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: DropdownButtonFormField<String?>(
      initialValue: widget.project.groupById(shape.groupId) == null
          ? null
          : shape.groupId,
      decoration: InputDecoration(
        labelText: AppStrings.text('Groupe'),
        isDense: true,
        border: OutlineInputBorder(),
      ),
      items: <DropdownMenuItem<String?>>[
        DropdownMenuItem<String?>(
          value: null,
          child: Text(AppStrings.text('Aucun')),
        ),
        for (final group in widget.project.groups)
          DropdownMenuItem<String?>(value: group.id, child: Text(group.name)),
      ],
      onChanged: (value) {
        widget.onGroupChanged?.call(value);
        _refresh();
      },
    ),
  );

  Widget _buildElementActions(BuildContext context, VectorShape shape) {
    Widget action(String label, IconData icon, VoidCallback? callback) =>
        TextButton.icon(
          onPressed: callback == null
              ? null
              : () {
                  Navigator.of(context).pop();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    callback();
                  });
                },
          icon: Icon(icon, size: 16),
          label: Text(label, style: const TextStyle(fontSize: 11)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        );
    return Wrap(
      alignment: WrapAlignment.start,
      spacing: 2,
      runSpacing: 0,
      children: <Widget>[
        action(
          AppStrings.text('Renommer'),
          Icons.drive_file_rename_outline,
          widget.onRename,
        ),
        action(
          AppStrings.text('Dupliquer'),
          Icons.content_copy,
          widget.onDuplicate,
        ),
        action(
          AppStrings.text(shape.visible ? 'Masquer' : 'Afficher'),
          shape.visible ? Icons.visibility_off : Icons.visibility,
          widget.onToggleVisibility,
        ),
        action(
          AppStrings.text('Monter'),
          Icons.vertical_align_top,
          () => widget.onMove?.call(1),
        ),
        action(
          AppStrings.text('Descendre'),
          Icons.vertical_align_bottom,
          () => widget.onMove?.call(-1),
        ),
        action(
          AppStrings.text('Supprimer'),
          Icons.delete_outline,
          widget.onDelete,
        ),
      ],
    );
  }

  Widget _buildZIndexSlider(VectorShape shape) => Row(
    children: <Widget>[
      SizedBox(
        width: 92,
        child: Text(
          AppStrings.text('Ordre Z'),
          style: const TextStyle(fontSize: 12),
        ),
      ),
      Expanded(
        child: Slider(
          min: -100,
          max: 100,
          divisions: 200,
          value: shape.zIndex.clamp(-100, 100).toDouble(),
          label: '${shape.zIndex}',
          onChanged: (value) {
            widget.onZIndexChanged?.call(value.round());
            _refresh();
          },
        ),
      ),
      SizedBox(
        width: 32,
        child: Text('${shape.zIndex}', textAlign: TextAlign.end),
      ),
    ],
  );
}
