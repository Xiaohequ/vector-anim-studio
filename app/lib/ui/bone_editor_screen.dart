import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/rig_overlay_painter.dart';
import '../engine/scene_painter.dart';
import '../engine/selection_geometry.dart';
import '../models/animation.dart';
import '../models/skeleton.dart';

/// Renvoyé par [BoneEditorScreen] quand l'utilisateur valide (✓).
///
/// Les os sont livrés en **coordonnées projet** (la conversion depuis
/// l'espace de l'éditeur est déjà faite) ; [replacedIds] liste les os qui
/// existaient déjà et doivent être remplacés (même id → pistes de
/// keyframes conservées), les autres sont à ajouter.
class BoneEditorResult {
  const BoneEditorResult({
    required this.bones,
    required this.replacedIds,
    required this.carrierBoneId,
  });

  /// Chaîne complète de la forme, en coordonnées projet.
  final List<RigBone> bones;

  /// Ids des os préexistants remplacés par leur version éditée.
  final List<String> replacedIds;

  /// Os porteur de la forme (racine de la chaîne) à lier.
  final String carrierBoneId;
}

/// Éditeur d'os (v0.20) — « l'os n'existe que par une forme ».
///
/// Contient **la seule forme sélectionnée**, recentrée et ancrée au milieu
/// de l'écran (l'espace de l'éditeur est translaté : la forme est posée au
/// centre d'un canvas calé sur sa boîte englobante, et les os racines sont
/// retranslatés en coordonnées projet à la validation).
///
/// - **Dessin** : tap ① = articulation, tap ② = extrémité. Un tap ① près
///   d'un os existant (poignet ou segment) attache le nouvel os dessus →
///   chaînes et IK restent possibles.
/// - **Déplacement** : glisser un os le déplace SANS déplacer la forme
///   (`translateBoneRest`, sans `carryBoundPieces` — la forme est ancrée au
///   milieu de l'écran).
class BoneEditorScreen extends StatefulWidget {
  const BoneEditorScreen({
    super.key,
    required this.project,
    required this.shape,
    this.timeMs = 0,
  });

  final AnimationProject project;
  final VectorShape shape;
  final int timeMs;

  @override
  State<BoneEditorScreen> createState() => _BoneEditorScreenState();
}

class _BoneEditorScreenState extends State<BoneEditorScreen> {
  /// Projet d'aperçu : SEULE la forme sélectionnée, recentrée, canvas calé
  /// sur sa boîte englobante (×1,6 de marge) pour que le dessin soit précis.
  late final AnimationProject _editor;

  /// Chaîne d'os en cours d'édition, en coordonnées ÉDITEUR.
  late final List<RigBone> _bones;

  /// Os qui existaient déjà (à remplacer à la validation).
  late final List<String> _existingIds;

  /// Os racine de la chaîne (ceux à retranslater à la validation).
  late final List<RigBone> _roots;

  /// Translation éditeur ↔ projet (voir [_toProject]).
  late final Offset _shift;

  Offset? _pendingJoint;
  String? _pendingParentId;
  RigBone? _dragBone;
  Offset? _dragLast;

  @override
  void initState() {
    super.initState();
    final shape = widget.shape;
    final project = widget.project;
    final bounds =
        ScenePainter.shapeBounds(shape, widget.timeMs) ??
        Rect.fromCenter(center: Offset.zero, width: 200, height: 200);

    // Canvas calé sur la boîte englobante (marge 1,6) — ScenePainter fait
    // entrer tout le projet dans la vue, donc la boîte englobante devient
    // l'écran : la forme occupe le centre, échelle maximale.
    final width = math.max(bounds.width * 1.6, 320.0);
    final height = math.max(bounds.height * 1.6, 320.0);
    _shift = Offset(shape.x - width / 2, shape.y - height / 2);

    _editor = AnimationProject.fromJson(project.toJson());
    _editor.width = width;
    _editor.height = height;
    _editor.fps = project.fps;
    _editor.skeleton = null;
    _editor.shapes
      ..clear()
      ..add(
        shape.copy()
          ..x = width / 2
          ..y = height / 2,
      );

    // Chaîne de la forme (le rig n'existe peut-être pas encore).
    final rig = project.skeleton;
    final carrierId = rig?.carrierBoneId(shape.id);
    final chain = (rig == null || carrierId == null)
        ? const <RigBone>[]
        : [for (final bone in rig.chainFrom(carrierId)) bone.copy()];
    _existingIds = [for (final bone in chain) bone.id];
    final chainIds = <String>{for (final bone in chain) bone.id};
    // Liste MODIFIABLE : le cas « aucune pièce liée » arrive avec une liste
    // `const` vide, qui refuse l'ajout au premier dessin.
    _bones = List<RigBone>.of(chain);
    _roots = [
      for (final bone in chain)
        if (bone.parentId == null || !chainIds.contains(bone.parentId)) bone,
    ];
    // Translater la chaîne dans l'espace de l'éditeur (la forme aussi).
    final pose = SkeletonPose.evaluate(rig ?? SkeletonRig(), widget.timeMs);
    final toEditor = Offset(-_shift.dx, -_shift.dy);
    for (final root in _roots) {
      _translate(root, pose, toEditor, project.skeleton);
    }
  }

  /// Déplace un os racine d'un delta de MONDE en coordonnées projet/éditeur
  /// — enchaîné dans le repère du parent quand il existe. [rigRef] sert
  /// seulement à résoudre le repère du parent (pose d'origine).
  void _translate(
    RigBone bone,
    SkeletonPose pose,
    Offset delta,
    SkeletonRig? rigRef,
  ) {
    final parentId = bone.parentId;
    final parent = rigRef?.boneById(parentId);
    if (parentId == null || parent == null) {
      bone.offsetX += delta.dx;
      bone.offsetY += delta.dy;
      return;
    }
    final parentFrame = pose.frameOf(parent.id);
    final local = parentFrame == null
        ? delta
        : rotateVector(delta, -parentFrame.worldAngleRest);
    bone.offsetX += local.dx;
    bone.offsetY += local.dy;
  }

  /// Rig d'aperçu (chaîne seule, coordonnées éditeur).
  SkeletonRig get _previewRig => SkeletonRig(
    name: 'Os',
    bones: List<RigBone>.from(_bones),
    bindings: const <BoneBinding>[],
    tracks: <String, List<BoneKeyframe>>{},
  );

  // ------------------------------------------------------------- gestes

  /// Tap : ① articulation (aimantée sur un os existant) ② extrémité.
  /// [point] est en coordonnées CANVAS (local du geste) ; les os vivent en
  /// coordonnées SCÈNE (espace d'éditeur) — conversion par [geo].
  void _onTapUp(Offset point, SceneGeometry geo) {
    final scenePoint = geo.canvasToScene(point);
    final rig = _previewRig;
    final pose = SkeletonPose.evaluate(rig, 0);
    final hitId = RigOverlayPainter.hitBone(pose, rig, geo, point);
    if (_pendingJoint == null) {
      String? parent;
      Offset joint = scenePoint;
      if (hitId != null) {
        // Aimantation : l'os 2 naît ATTACHÉ à l'os 1 — l'articulation se
        // pose sur le POIGNET quand le tap est près de l'extrémité (le reste
        // du segment garde le point touché comme articulation).
        parent = hitId;
        final frame = pose.frameOf(hitId);
        final tipCanvas = frame == null ? null : geo.sceneToCanvas(frame.tip);
        if (frame != null &&
            tipCanvas != null &&
            (point - tipCanvas).distance <= RigOverlayPainter.tipTouchSlop) {
          joint = frame.tip;
        }
      }
      setState(() {
        _pendingJoint = joint;
        _pendingParentId = parent;
      });
      return;
    }
    final joint = _pendingJoint!;
    final parent = rig.boneById(_pendingParentId);
    final bone = boneBetween(
      joint,
      scenePoint,
      name: 'Os ${_bones.length + 1}',
      parentId: parent?.id,
      parentFrame: parent == null ? null : pose.frameOf(parent.id),
    );
    setState(() {
      _bones.add(bone);
      _pendingJoint = null;
      _pendingParentId = null;
    });
  }

  /// Glisser un os : il bouge, la forme reste ancrée au centre.
  void _onDragStart(Offset point, SceneGeometry geo) {
    final rig = _previewRig;
    final pose = SkeletonPose.evaluate(rig, 0);
    final hitId = RigOverlayPainter.hitBone(pose, rig, geo, point);
    if (hitId == null) return;
    _dragBone = rig.boneById(hitId);
    _dragLast = point;
  }

  void _onDragUpdate(Offset point, SceneGeometry geo) {
    final bone = _dragBone;
    final last = _dragLast;
    if (bone == null || last == null) return;
    // Delta CANVAS → SCÈNE : `translateBoneRest` travaille en repère projet.
    final delta = geo.canvasToScene(point) - geo.canvasToScene(last);
    if (delta == Offset.zero) return;
    // `_previewRig` partage les objets de `_bones` : la translation est écrite
    // directement dans la chaîne en cours d'édition.
    final rig = _previewRig;
    final pose = SkeletonPose.evaluate(rig, 0);
    final live = rig.boneById(bone.id);
    if (live == null) return;
    // SANS carryBoundPieces : la forme ne bouge pas (elle est ancrée au
    // centre de l'écran), seul l'os se déplace.
    rig.translateBoneRest(live, pose, delta);
    setState(() {});
    _dragLast = point;
  }

  void _onDragEnd() {
    _dragBone = null;
    _dragLast = null;
  }

  // --------------------------------------------------------- validation

  BoneEditorResult? _buildResult() {
    if (_bones.isEmpty) return null;
    // Repères d'origine : les angles de repos ne changent pas pendant
    // l'édition, la pose réelle sert de référence pour les deux sens de
    // conversion (aller = −_shift, retour = _shift).
    final rigRef = widget.project.skeleton;
    final poseRef = rigRef == null
        ? SkeletonPose.evaluate(SkeletonRig(), widget.timeMs)
        : SkeletonPose.evaluate(rigRef, widget.timeMs);
    // Racines de la CHAÎNE COURANTE — y compris les os dessinés pendant
    // l'édition (calculés ici, pas à l'ouverture) : seuls eux portent des
    // coords éditeur à reconvertir ; les os enfants sont exprimés dans le
    // repère de leur parent (inchangés par une translation du groupe).
    final ids = <String>{for (final bone in _bones) bone.id};
    final roots = <RigBone>[
      for (final bone in _bones)
        if (bone.parentId == null || !ids.contains(bone.parentId)) bone,
    ];
    for (final root in roots) {
      _translate(root, poseRef, _shift, rigRef);
    }
    // Porteur = racine de la chaîne (celle qui porte la forme).
    final carrier = _roots.isNotEmpty ? _roots.first : _bones.first;
    return BoneEditorResult(
      bones: _bones,
      replacedIds: _existingIds,
      carrierBoneId: carrier.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hint = _pendingJoint == null
        ? 'Tap : articulation puis extrémité — tape près d’un os pour '
              'l’enchaîner, glisse un os pour le déplacer'
        : 'Tap : extrémité de l’os — ✕ pour annuler l’articulation';
    return Scaffold(
      appBar: AppBar(
        title: Text('Os de « ${widget.shape.name} »'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Enregistrer l’os',
            onPressed: _bones.isEmpty
                ? null
                : () => Navigator.of(context).pop(_buildResult()),
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Container(
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
                  final geo = SceneGeometry.fitFor(_editor, canvasSize);
                  final rig = _previewRig;
                  final pose = SkeletonPose.evaluate(rig, 0);
                  return Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (details) =>
                              _onTapUp(details.localPosition, geo),
                          onScaleStart: (details) =>
                              _onDragStart(details.localFocalPoint, geo),
                          onScaleUpdate: (details) {
                            if (_dragBone != null) {
                              _onDragUpdate(details.localFocalPoint, geo);
                            }
                          },
                          onScaleEnd: (_) => _onDragEnd(),
                          child: CustomPaint(
                            painter: ScenePainter(
                              project: _editor,
                              timeMs: widget.timeMs,
                              selectedShapeId: widget.shape.id,
                              showFrame: true,
                            ),
                            foregroundPainter: RigOverlayPainter(
                              rig: rig,
                              pose: pose,
                              geo: geo,
                              selectedBoneId: _dragBone?.id ?? _pendingParentId,
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                      if (_pendingJoint != null)
                        Positioned(
                          left: 8,
                          top: 8,
                          child: IconButton(
                            tooltip: 'Annuler l’articulation en attente',
                            onPressed: () => setState(() {
                              _pendingJoint = null;
                              _pendingParentId = null;
                            }),
                            icon: const Icon(Icons.close, size: 20),
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xCC151922),
                              foregroundColor: Colors.white70,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Text(
              hint,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
