import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../data/project_repository.dart';
import '../engine/animation_presets.dart';
import '../engine/export_service.dart';
import '../engine/rig_overlay_painter.dart';
import '../engine/scene_painter.dart';
import '../engine/selection_geometry.dart';
import '../engine/timeline_controller.dart';
import '../engine/timeline_zoom.dart';
import '../engine/undo_stack.dart';
import '../models/animation.dart';
import '../models/skeleton.dart';
import 'bone_properties_sheet.dart';
import 'shape_editor_screen.dart';
import 'shape_properties_sheet.dart';
import 'timeline_view.dart';

/// Geste en cours sur le canvas.
enum _CanvasGesture { none, move, scale, rotate, boneRotate }

/// Éditeur d'un projet : canvas, timeline, menus Formes/Animations.
class StudioScreen extends StatefulWidget {
  const StudioScreen({
    super.key,
    required this.projectId,
    required this.repository,
  });

  final String projectId;
  final ProjectRepository repository;

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen>
    with SingleTickerProviderStateMixin {
  AnimationProject? _project;
  TimelineController? _controller;
  Ticker? _ticker;
  Duration _lastTick = Duration.zero;
  String? _selectedId;
  String? _error;
  Timer? _saveTimer;

  /// Projets imbriqués préchargés (instances d'animation), indexés par id.
  final Map<String, AnimationProject> _embedded = <String, AnimationProject>{};

  /// Pile d'annulation : l'état du projet avant chaque action mutante.
  final UndoStack _undoStack = UndoStack(limit: 20);

  /// Coalescing : une série continue (slider, geste) = une seule entrée.
  String? _undoTag;
  DateTime _lastUndoAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Snapshot en attente d'un geste canvas (poussé à la fin si le geste a
  /// réellement modifié la scène).
  AnimationProject? _gestureUndo;
  bool _gestureMutated = false;

  // Option : aimanter la rotation aux multiples de 90° (bouton de la barre).
  bool _snapRotation = false;

  // ------------------------------------------------------------- squelette

  /// Os sélectionné (mode squelette) ; null → aucune sélection d'os.
  String? _selectedBoneId;

  /// Mode « ajouter un os » : premier tap = articulation, second = extrémité.
  bool _addBoneMode = false;

  /// Articulation du nouvel os en attente de son extrémité (scène).
  Offset? _pendingJoint;

  /// Parent de l'os en attente (os sélectionné au moment du premier tap).
  String? _pendingParentId;

  /// Pièce touchée au premier tap du mode rig : le nouvel os naîtra lié à
  /// cette pièce (ancrage automatique).
  String? _pendingShapeId;

  /// Os en cours de rotation (glisser de son extrémité).
  String? _dragBoneId;

  /// Zoom/défilement de la timeline (mémoire de session, non persisté).
  TimelineZoomState? _zoom;

  // Geste en cours sur le canvas (déplacement, pinch, rotation par poignée).
  _CanvasGesture _gesture = _CanvasGesture.none;
  int _activePointers = 0;
  double _gestureBaseX = 0;
  double _gestureBaseY = 0;
  double _gestureBaseRotation = 0;
  double _gestureBaseScale = 1;
  double _gestureStartAngle = 0;
  Offset _gestureStartPoint = Offset.zero;

  VectorShape? get _selected => _project?.shapeById(_selectedId);

  /// Rig du projet squelette courant (null pour un projet vectoriel).
  SkeletonRig? get _rig => _project?.skeleton;

  RigBone? get _selectedBone => _rig?.boneById(_selectedBoneId);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final project = await widget.repository.load(widget.projectId);
      if (!mounted) return;
      await _preloadEmbedded(project);
      if (!mounted) return;
      setState(() {
        _project = project;
        _controller = TimelineController(project);
        _selectedId = project.shapes.isEmpty ? null : project.shapes.last.id;
        _zoom = TimelineZoomState(durationOf: () => _project!.durationMs);
      });
      _syncTicker();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  /// Précharge les projets imbriqués (instances) : le painter est synchrone,
  /// il a besoin des sous-projets en mémoire avant le premier rendu.
  Future<void> _preloadEmbedded(AnimationProject project) async {
    for (final shape in project.shapes) {
      final id = shape.embeddedProjectId;
      if (id == null || _embedded.containsKey(id)) continue;
      try {
        _embedded[id] = await widget.repository.load(id);
      } catch (_) {
        // Projet introuvable : l'instance affichera le cadre « manquant ».
      }
    }
  }

  /// Insère une instance d'animation : barre violette sur la timeline, la
  /// source tourne en boucle sur la fenêtre d'affichage, début posé à la
  /// tête de lecture.
  Future<void> _insertAnimation() async {
    final project = _project;
    if (project == null) return;
    final controller = _controller;
    if (controller == null) return;
    final summaries = await widget.repository.listSummaries();
    if (!mounted) return;
    final others = summaries.where((s) => s.id != widget.projectId).toList();
    final picked = await showModalBottomSheet<ProjectSummary>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Choisir le projet à imbriquer',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (others.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Aucun autre projet.'),
              ),
            for (final summary in others)
              ListTile(
                leading: const Icon(Icons.movie_outlined),
                title: Text(summary.name),
                subtitle: Text(
                  '${(summary.durationMs / 1000).toStringAsFixed(1)} s · '
                  '${summary.shapeCount} forme(s)',
                ),
                onTap: () => Navigator.of(context).pop(summary),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final sub = await widget.repository.load(picked.id);
    if (!mounted) return;
    _pushUndo(); // annuler l'insertion doit restaurer l'état sans l'instance
    final start = controller.timeMs;
    final end = math.min(
      project.durationMs,
      math.max(start + sub.durationMs, start + 100),
    );
    final shape = VectorShape(
      name: sub.name,
      embeddedProjectId: sub.id,
      embeddedWidth: sub.width,
      embeddedHeight: sub.height,
      x: project.width / 2,
      y: project.height / 2,
      startMs: start,
      endMs: end,
    );
    setState(() {
      project.shapes.add(shape);
      _selectedId = shape.id;
      _embedded[sub.id] = sub;
    });
    await _flushSave();
  }

  /// Ouvre le projet source d'une instance pour l'éditer, puis rafraîchit le
  /// cache : l'instance rend automatiquement la version à jour.
  Future<void> _openSourceProject(VectorShape instance) async {
    final id = instance.embeddedProjectId;
    if (id == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            StudioScreen(projectId: id, repository: widget.repository),
      ),
    );
    if (!mounted) return;
    try {
      final fresh = await widget.repository.load(id);
      if (!mounted) return;
      setState(() => _embedded[id] = fresh);
    } catch (_) {
      // Le projet a été supprimé entre-temps : on garde l'ancienne version.
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _ticker?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final delta = elapsed - _lastTick;
    _lastTick = elapsed;
    final controller = _controller;
    if (controller == null) return;
    if (delta.inMilliseconds >= 0) controller.advance(delta);
    // Lecture : la tête de lecture reste visible dans la vue zoomée (l'offset
    // est muté avant le rebuild déclenché par le tick, pas de setState).
    _zoom?.follow(controller.timeMs);
    // Fin de lecture sans boucle : on arrête le ticker.
    if (!controller.playing) _syncTicker();
  }

  /// Le ticker ne tourne que pendant la lecture : au repos (pause) aucun frame
  /// n'est produit, ce qui évite de faire tourner l'application à vide — et
  /// laisse l'arbre de widgets se stabiliser (tests, captures, économie de
  /// batterie sur mobile).
  void _syncTicker() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.playing) {
      _lastTick = Duration.zero;
      _ticker ??= createTicker(_onTick)..start();
      if (!_ticker!.isActive) _ticker!.start();
    } else {
      _ticker?.stop();
    }
  }

  /// Sauvegarde différée (l'édition ne doit pas écrire à chaque frame).
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () {
      final project = _project;
      if (project != null) widget.repository.save(project);
    });
  }

  Future<void> _flushSave() async {
    _saveTimer?.cancel();
    final project = _project;
    if (project != null) await widget.repository.save(project);
  }

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  // ------------------------------------------------------------------ undo

  /// Copie l'état courant pour annulation. [tag] coalesce une série continue
  /// (sliders, gestes) en une seule entrée ; 900 ms d'inactivité rouvrent
  /// une nouvelle entrée.
  void _pushUndo({String? tag}) {
    final project = _project;
    if (project == null) return;
    final now = DateTime.now();
    if (tag != null &&
        _undoTag == tag &&
        now.difference(_lastUndoAt).inMilliseconds < 900) {
      _lastUndoAt = now;
      return;
    }
    _undoTag = tag;
    _lastUndoAt = now;
    _undoStack.push(project);
    setState(() {}); // le bouton undo devient actif
  }

  /// Annule la dernière action : l'état restauré remplace le projet courant
  /// (nouveau TimelineController, temps préservé, zoom réaligné). Non
  /// annulable en sens inverse : pas de redo.
  void _undo() {
    final previous = _undoStack.pop();
    if (previous == null) return;
    _undoTag = null;
    _gestureUndo = null;
    final controller = _controller;
    final timeMs = math.min(controller?.timeMs ?? 0, previous.durationMs);
    final selectedId = _selectedId;
    final old = _controller;
    setState(() {
      _project = previous;
      _controller = TimelineController(previous)..setTime(timeMs);
      _selectedId = previous.shapeById(selectedId) != null
          ? selectedId
          : (previous.shapes.isEmpty ? null : previous.shapes.last.id);
      _selectedBoneId = previous.skeleton?.boneById(_selectedBoneId) != null
          ? _selectedBoneId
          : null;
      _addBoneMode = false;
      _pendingJoint = null;
      _pendingShapeId = null;
      _zoom = TimelineZoomState(durationOf: () => _project!.durationMs);
    });
    // L'ancien controller est désabonné par le rebuild : on le dispose après.
    SchedulerBinding.instance.addPostFrameCallback((_) => old?.dispose());
    _syncTicker();
    widget.repository.save(previous);
  }

  // ---------------------------------------------------------------- formes

  Future<void> _addShape() async {
    final project = _project;
    if (project == null) return;
    final shape = await Navigator.of(context).push<VectorShape>(
      MaterialPageRoute<VectorShape>(
        builder: (_) => ShapeEditorScreen(project: project),
      ),
    );
    if (shape == null || !mounted) return;
    _pushUndo(); // annuler l'ajout doit restaurer l'état sans la forme
    setState(() {
      project.shapes.add(shape);
      _selectedId = shape.id;
    });
    await _flushSave();
  }

  Future<void> _editShape(VectorShape shape) async {
    if (shape.isInstance) return; // une instance n'a pas de couches propres
    final project = _project;
    if (project == null) return;
    final edited = await Navigator.of(context).push<VectorShape>(
      MaterialPageRoute<VectorShape>(
        builder: (_) => ShapeEditorScreen(project: project, shape: shape),
      ),
    );
    if (edited == null || !mounted) return;
    _pushUndo();
    setState(() {
      final index = project.shapes.indexWhere((s) => s.id == edited.id);
      if (index >= 0) {
        project.shapes[index] = edited;
      } else {
        project.shapes.add(edited);
      }
      _selectedId = edited.id;
    });
    await _flushSave();
  }

  Future<void> _deleteShape(VectorShape shape) async {
    final project = _project;
    if (project == null) return;
    _pushUndo();
    setState(() {
      project.shapes.remove(shape);
      project.skeleton?.unbindShape(shape.id);
      _selectedId = project.shapes.isEmpty ? null : project.shapes.last.id;
    });
    await _flushSave();
  }

  /// Duplique la forme sélectionnée (couches + keyframes) à la même fenêtre :
  /// le clone se superpose à l'original, qui atterrit sur la ligne du dessous.
  void _cloneShape(VectorShape shape) {
    final project = _project;
    if (project == null) return;
    final index = project.shapes.indexOf(shape);
    if (index < 0) return;
    final clone = shape.duplicated();
    _pushUndo();
    setState(() {
      project.shapes.insert(index + 1, clone);
      _selectedId = clone.id;
    });
    _scheduleSave();
    _snack('Forme dupliquée (keyframes incluses)');
  }

  Future<void> _renameShape(VectorShape shape) async {
    final controller = TextEditingController(text: shape.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renommer la forme'),
        content: TextField(controller: controller, autofocus: true),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    _pushUndo();
    setState(() => shape.name = name.trim());
    await _flushSave();
  }

  Future<void> _toggleVisibility(VectorShape shape) async {
    _pushUndo();
    setState(() => shape.visible = !shape.visible);
    await _flushSave();
  }

  Future<void> _moveShape(VectorShape shape, int delta) async {
    final project = _project;
    if (project == null) return;
    final index = project.shapes.indexWhere((s) => s.id == shape.id);
    if (index < 0) return;
    _pushUndo();
    setState(() => project.moveShape(index, index + delta));
    await _flushSave();
  }

  // ------------------------------------------------------------ animations

  Future<void> _applyPreset(AnimationPreset preset) async {
    final shape = _selected;
    if (shape == null) return;
    _pushUndo();
    setState(() => applyPreset(shape, preset));
    await _flushSave();
  }

  Future<void> _clearAnimations() async {
    final shape = _selected;
    if (shape == null) return;
    _pushUndo();
    setState(() => clearAnimations(shape));
    await _flushSave();
  }

  /// Ajoute ou retire la keyframe (pose complète) au curseur.
  Future<void> _toggleKeyframe() async {
    final shape = _selected;
    final controller = _controller;
    if (shape == null || controller == null) return;
    _pushUndo();
    setState(() => controller.toggleKeyframe(shape));
    await _flushSave();
  }

  /// Écrit une propriété : dans la pose au curseur si la forme est animée,
  /// sinon dans la valeur de base (auto-key).
  void _setProperty(AnimatableProperty property, double value) {
    final shape = _selected;
    final controller = _controller;
    if (shape == null || controller == null) return;
    _pushUndo(tag: 'prop:${property.name}:${shape.id}');
    setState(() {
      shape.applyValue(
        property,
        value,
        controller.timeMs,
        autoKey: true,
        toleranceMs: controller.snapToleranceMs,
      );
    });
    _scheduleSave();
  }

  Future<void> _setKeyframeEasing(EasingKind easing) async {
    final shape = _selected;
    final controller = _controller;
    if (shape == null || controller == null) return;
    final near = controller.nearestKeyframe(shape);
    if (near == null) return;
    _pushUndo();
    setState(() => shape.setKeyframeEasing(near.timeMs, easing));
    await _flushSave();
  }

  /// Ouvre la bottom sheet « Propriétés de la forme ».
  Future<void> _showPropertiesSheet() async {
    final project = _project;
    final controller = _controller;
    final shape = _selected;
    if (project == null || controller == null || shape == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFF151922),
      builder: (sheetContext) => ShapePropertiesSheet(
        project: project,
        shape: shape,
        controller: controller,
        onPropertyChanged: _setProperty,
        onToggleKeyframe: _toggleKeyframe,
        onKeyframeEasing: _setKeyframeEasing,
        onEditLayers: () => _editShape(shape),
        onOpenSource: () => _openSourceProject(shape),
        skeletonPiece: project.isSkeleton,
        skeletonNote: _bindingNote(shape),
      ),
    );
    if (mounted) setState(() {});
  }

  /// État de liaison d'une pièce au rig, affiché dans sa bottom sheet.
  String? _bindingNote(VectorShape shape) {
    final rig = _rig;
    if (rig == null) return null;
    final boneId = rig.boneIdForShape(shape.id);
    final bone = rig.boneById(boneId);
    return bone == null
        ? 'Pièce non liée au rig (os : —)'
        : 'Pièce liée à l’os « ${bone.name} »';
  }

  // ------------------------------------------------------------- squelette

  /// Crée le rig au premier os (le projet passe en mode squelette animable).
  void _createRigIfNeeded() {
    final project = _project;
    if (project == null || project.skeleton != null) return;
    project.skeleton = SkeletonRig(name: 'Squelette');
  }

  void _startAddBone() {
    setState(() {
      _addBoneMode = !_addBoneMode;
      _pendingJoint = null;
      _pendingParentId = null;
      _pendingShapeId = null;
    });
    if (_addBoneMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mode rig : touche l’articulation, puis l’extrémité'),
        ),
      );
    }
  }

  /// Deuxième tap du mode création : crée l'os entre l'articulation en
  /// attente et le point touché, parenté à l'os sélectionné au premier tap.
  void _finishAddBone(Offset scenePoint, SceneGeometry geo) {
    final project = _project;
    final joint = _pendingJoint;
    if (project == null || joint == null) return;
    _pushUndo(); // couvre aussi la création du rig au premier os
    _createRigIfNeeded();
    final rig = project.skeleton!;
    String? boundName;
    final parent = rig.boneById(_pendingParentId);
    final parentFrame = SkeletonPose.evaluate(
      rig,
      _controller?.timeMs ?? 0,
    ).frameOf(parent?.id);
    final length = math.max(4.0, (scenePoint - joint).distance);
    final bone = RigBone(
      name: 'Os ${rig.bones.length + 1}',
      parentId: parent?.id,
      length: length,
    );
    bone.restAngle =
        math.atan2(scenePoint.dy - joint.dy, scenePoint.dx - joint.dx) -
        (parentFrame?.worldAngleRest ?? 0);
    if (parentFrame == null) {
      // Racine : articulation en coordonnées projet, angle monde.
      bone.offsetX = joint.dx;
      bone.offsetY = joint.dy;
    } else {
      // Enfant : offset dans le repère de repos du parent. Le point touché
      // est exprimé au temps courant : on le ramène dans le repos du parent
      // (identité quand le parent est au repos, le cas nominal du rigging).
      final restPoint =
          parentFrame.jointRest +
          rotateVector(scenePoint - parentFrame.joint, -parentFrame.worldDelta);
      final local = rotateVector(
        restPoint - parentFrame.jointRest,
        -parentFrame.worldAngleRest,
      );
      bone.offsetX = local.dx;
      bone.offsetY = local.dy;
    }
    setState(() {
      rig.addBone(bone);
      // Ancrage : si le premier tap du mode rig tombait sur une pièce, le
      // nouvel os naît lié à cette pièce (elle suit l'os, et au repos l'os
      // la suit quand on la déplace).
      final target = _pendingShapeId;
      if (target != null) {
        final piece = project.shapeById(target);
        if (piece != null) {
          rig.bindShape(piece.id, bone.id);
          boundName = piece.name;
        }
      }
      _selectedBoneId = bone.id;
      _addBoneMode = false;
      _pendingJoint = null;
      _pendingParentId = null;
      _pendingShapeId = null;
    });
    _scheduleSave();
    _snack(
      boundName == null
          ? 'Os « ${bone.name} » créé'
          : 'Os « ${bone.name} » créé et lié à « $boundName »',
    );
  }

  /// Lie la pièce sélectionnée à un os (rig maître : ses sliders deviennent
  /// l'offset de repos dans le repère de l'os).
  Future<void> _bindSelectedShape() async {
    final project = _project;
    final rig = _rig;
    final shape = _selected;
    if (project == null || rig == null || shape == null) return;
    if (rig.bones.isEmpty) {
      _snack('Crée d’abord un os (Squelettes ▸ Ajouter un os…)');
      return;
    }
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Lier « ${shape.name} » à quel os ?'),
        children: <Widget>[
          for (final bone in rig.bones)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(bone.id),
              child: Text('${'—' * rig.depthOf(bone.id)} ${bone.name}'),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    _pushUndo();
    setState(() => rig.bindShape(shape.id, picked));
    await _flushSave();
    final bone = rig.boneById(picked);
    _snack('Pièce liée à l’os « ${bone?.name ?? '?'} »');
  }

  Future<void> _unbindSelectedShape() async {
    final rig = _rig;
    final shape = _selected;
    if (rig == null || shape == null) return;
    _pushUndo();
    setState(() => rig.unbindShape(shape.id));
    await _flushSave();
  }

  Future<void> _toggleBoneKeyframe() async {
    final rig = _rig;
    final bone = _selectedBone;
    final controller = _controller;
    if (rig == null || bone == null || controller == null) return;
    _pushUndo();
    setState(() => controller.toggleBoneKeyframe(rig, bone));
    await _flushSave();
  }

  Future<void> _setBoneEasing(EasingKind easing) async {
    final rig = _rig;
    final bone = _selectedBone;
    final controller = _controller;
    if (rig == null || bone == null || controller == null) return;
    final near = controller.nearestBoneKeyframe(rig, bone);
    if (near == null) return;
    _pushUndo();
    setState(() => rig.setKeyframeEasing(bone.id, near.timeMs, easing));
    await _flushSave();
  }

  /// Longueur de l'os : slider coalescé en une entrée d'annulation.
  void _setBoneLength(double value) {
    final bone = _selectedBone;
    if (bone == null) return;
    _pushUndo(tag: 'boneLen:${bone.id}');
    bone.length = value;
    _scheduleSave();
  }

  /// Re-parente l'os (les descendants sont exclus par la sheet).
  void _setBoneParent(String? parentId) {
    final rig = _rig;
    final bone = _selectedBone;
    if (rig == null || bone == null) return;
    _pushUndo();
    setState(() => bone.parentId = parentId);
    _flushSave();
  }

  Future<void> _renameBone() async {
    final bone = _selectedBone;
    if (bone == null) return;
    final controller = TextEditingController(text: bone.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renommer l’os'),
        content: TextField(controller: controller, autofocus: true),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    _pushUndo();
    setState(() => bone.name = name.trim());
    await _flushSave();
  }

  Future<void> _deleteBone() async {
    final rig = _rig;
    final bone = _selectedBone;
    if (rig == null || bone == null) return;
    Navigator.of(context).pop(); // fermer la sheet
    _pushUndo();
    setState(() {
      rig.removeBone(bone.id);
      if (_selectedBoneId == bone.id) _selectedBoneId = null;
    });
    await _flushSave();
    _snack('Os supprimé (enfants re-parentés)');
  }

  Future<void> _renameRig() async {
    final rig = _rig;
    if (rig == null) return;
    final controller = TextEditingController(text: rig.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renommer le squelette'),
        content: TextField(controller: controller, autofocus: true),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    _pushUndo();
    setState(() => rig.name = name.trim());
    await _flushSave();
  }

  Future<void> _deleteRig() async {
    final project = _project;
    if (project == null || project.skeleton == null) return;
    _pushUndo();
    setState(() {
      project.skeleton = null;
      _selectedBoneId = null;
      _addBoneMode = false;
      _pendingJoint = null;
      _pendingShapeId = null;
    });
    await _flushSave();
    _snack('Squelette supprimé');
  }

  /// Bottom sheet « Propriétés de l'os » pour l'os sélectionné.
  Future<void> _showBoneSheet() async {
    final rig = _rig;
    final bone = _selectedBone;
    final controller = _controller;
    if (rig == null || bone == null || controller == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFF151922),
      builder: (sheetContext) => BonePropertiesSheet(
        rig: rig,
        bone: bone,
        controller: controller,
        onLengthChanged: _setBoneLength,
        onParentChanged: _setBoneParent,
        onRenameBone: _renameBone,
        onDeleteBone: _deleteBone,
        onToggleKeyframe: _toggleBoneKeyframe,
        onKeyframeEasing: _setBoneEasing,
      ),
    );
    if (mounted) setState(() {});
  }

  // ----------------------------------------------------------- gestes canvas

  void _pointerDown() => _activePointers++;

  void _pointerUp() => _activePointers = math.max(0, _activePointers - 1);

  /// Écrit une propriété pendant un geste (auto-key : pose au curseur).
  void _applyGestureValue(
    VectorShape shape,
    TimelineController controller,
    AnimatableProperty property,
    double value,
  ) {
    setState(
      () => shape.applyValue(
        property,
        value,
        controller.timeMs,
        autoKey: true,
        toleranceMs: controller.snapToleranceMs,
      ),
    );
    _gestureMutated = true;
  }

  /// Os portant la forme en cours de geste (composition rig), capturé au
  /// début du geste : le delta monde de l'os est constant pendant le geste.
  BoneFrame? _gestureBoneFrame;

  /// Os portant une forme (rig maître) — évalué au temps courant.
  BoneFrame? _frameForShape(
    AnimationProject project,
    VectorShape shape,
    int timeMs,
  ) {
    if (!project.isSkeleton || project.skeleton == null) return null;
    return SkeletonPose.evaluate(
      project.skeleton!,
      timeMs,
    ).frameOf(project.skeleton!.boneIdForShape(shape.id));
  }

  /// Pièce touchée par un point canvas (du premier plan vers l'arrière-plan),
  /// visible selon le mode du projet — ou null.
  VectorShape? _hitShapeAt(
    AnimationProject project,
    TimelineController controller,
    SceneGeometry geo,
    Offset canvasPoint,
  ) {
    for (final shape in project.shapes.reversed) {
      final show = project.isSkeleton
          ? shape.visible
          : shape.isVisibleAt(controller.timeMs);
      if (!show) continue;
      final bounds = ScenePainter.shapeBounds(shape, controller.timeMs);
      if (bounds == null) continue;
      if (SelectionGeometry.hit(
        bounds,
        SelectionGeometry.shapePoseWithRig(
          shape,
          controller.timeMs,
          _frameForShape(project, shape, controller.timeMs),
        ),
        geo,
        canvasPoint,
      )) {
        return shape;
      }
    }
    return null;
  }

  void _onCanvasGestureStart(
    ScaleStartDetails details,
    AnimationProject project,
    TimelineController controller,
    Size canvasSize,
  ) {
    _gestureStartPoint = details.localFocalPoint;
    // Mode création d'os : aucun geste de transformation, des taps seulement.
    if (_addBoneMode) {
      _gesture = _CanvasGesture.none;
      return;
    }
    // Priorité rig : extrémité (ou segment) d'os proche → rotation de l'os.
    final rig = project.skeleton;
    if (project.isSkeleton && rig != null && rig.bones.isNotEmpty) {
      final pose = SkeletonPose.evaluate(rig, controller.timeMs);
      final geo = SceneGeometry.fitFor(project, canvasSize);
      final boneId = RigOverlayPainter.hitBone(
        pose,
        rig,
        geo,
        details.localFocalPoint,
      );
      if (boneId != null) {
        _gesture = _CanvasGesture.boneRotate;
        _dragBoneId = boneId;
        _gestureBoneFrame = null;
        _gestureUndo = AnimationProject.fromJson(project.toJson());
        _gestureMutated = false;
        setState(() => _selectedBoneId = boneId);
        return;
      }
    }
    final shape = _selected;
    final bounds = shape == null
        ? null
        : ScenePainter.shapeBounds(shape, controller.timeMs);
    if (shape == null || bounds == null) {
      _gesture = _CanvasGesture.none;
      return;
    }
    final geo = SceneGeometry.fitFor(project, canvasSize);
    _gestureBoneFrame = _frameForShape(project, shape, controller.timeMs);
    final pose = SelectionGeometry.shapePoseWithRig(
      shape,
      controller.timeMs,
      _gestureBoneFrame,
    );
    if (_activePointers >= 2) {
      // Pinch : échelle de la forme sélectionnée.
      _gesture = _CanvasGesture.scale;
    } else if (SelectionGeometry.hitRotationHandle(
      details.localFocalPoint,
      SelectionGeometry.rotationHandle(bounds, pose, geo),
    )) {
      // Poignée de rotation.
      _gesture = _CanvasGesture.rotate;
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
      // Corps de la forme : déplacement.
      _gesture = _CanvasGesture.move;
    } else {
      _gesture = _CanvasGesture.none;
    }
    _gestureBaseX = shape.valueAt(AnimatableProperty.x, controller.timeMs);
    _gestureBaseY = shape.valueAt(AnimatableProperty.y, controller.timeMs);
    _gestureBaseRotation = shape.valueAt(
      AnimatableProperty.rotation,
      controller.timeMs,
    );
    _gestureBaseScale = shape.valueAt(
      AnimatableProperty.scale,
      controller.timeMs,
    );
    // Snapshot en attente : poussé dans la pile seulement si le geste
    // modifie réellement la scène (voir _onCanvasGestureEnd).
    _gestureUndo = AnimationProject.fromJson(project.toJson());
    _gestureMutated = false;
  }

  void _onCanvasGestureUpdate(
    ScaleUpdateDetails details,
    AnimationProject project,
    TimelineController controller,
    Size canvasSize,
  ) {
    final shape = _selected;
    if (_gesture == _CanvasGesture.none) return;
    if (shape == null && _gesture != _CanvasGesture.boneRotate) return;
    switch (_gesture) {
      case _CanvasGesture.boneRotate:
        final rig = project.skeleton;
        final bone = rig?.boneById(_dragBoneId);
        if (rig == null || bone == null) break;
        final pose = SkeletonPose.evaluate(rig, controller.timeMs);
        final frame = pose.frameOf(bone.id);
        if (frame == null) break;
        final geo = SceneGeometry.fitFor(project, canvasSize);
        final scene = geo.canvasToScene(details.localFocalPoint);
        var desired = math.atan2(
          scene.dy - frame.joint.dy,
          scene.dx - frame.joint.dx,
        );
        if (_snapRotation) desired = _snapAngle(desired);
        final parentFrame = pose.frameOf(bone.parentId);
        // setState à chaque update : sans lui, ni le canvas ni la timeline
        // ne se repeignent pendant le glisser (saccades de v0.9.0).
        setState(() {
          if (rig.hasKeyframes(bone.id)) {
            // Auto-key : pose d'angle au curseur (snap sur une keyframe
            // proche). Les pièces suivent par la transformée os(t).
            final target =
                rig
                    .keyframeNear(
                      bone.id,
                      controller.timeMs,
                      controller.snapToleranceMs,
                    )
                    ?.timeMs ??
                controller.timeMs;
            rig.upsertKeyframe(
              bone.id,
              target,
              desired - frame.worldAngleRest - (parentFrame?.worldDelta ?? 0),
            );
          } else {
            // Rig non animé : glisser = poser le rig (angle de repos relatif
            // au parent, évalué au temps courant pour suivre le doigt). La
            // pose de repos change : les pièces liées à l'os et à ses
            // descendants sont emportées par la nouvelle pose.
            bone.restAngle = desired - (parentFrame?.worldAngle ?? 0);
            carryBoundPieces(
              project,
              rig,
              pose,
              SkeletonPose.evaluate(rig, controller.timeMs),
              controller.timeMs,
              toleranceMs: controller.snapToleranceMs,
            );
          }
        });
        _gestureMutated = true;
      case _CanvasGesture.move:
        final geo = SceneGeometry.fitFor(project, canvasSize);
        final frame = _gestureBoneFrame;
        final rig = project.skeleton;
        // Pièce liée à un os au repos (pièce non animée) : le glisser
        // déplace l'ANCRAGE de l'os (offset de repos) — l'os suit la pièce,
        // qui reste collée à l'os ; la chaîne descendante suit (offsets
        // relatifs). Delta par pas : l'offset est muté à chaque update.
        if (frame != null &&
            frame.worldDelta == 0 &&
            rig != null &&
            shape!.keyframes.isEmpty) {
          final bone = rig.boneById(rig.boneIdForShape(shape.id));
          if (bone != null) {
            rig.translateBoneRest(
              bone,
              SkeletonPose.evaluate(rig, controller.timeMs),
              details.focalPointDelta / geo.scale,
            );
            _gestureMutated = true;
          }
          break;
        }
        final sceneDelta =
            geo.canvasToScene(details.localFocalPoint) -
            geo.canvasToScene(_gestureStartPoint);
        var dx = _gestureBaseX + sceneDelta.dx;
        var dy = _gestureBaseY + sceneDelta.dy;
        // Pièce liée à un os animé : écrire le décalage dans le repère de
        // repos pour que la pièce suive exactement le doigt dans le monde.
        if (frame != null && frame.worldDelta != 0) {
          final corrected = rotateVector(sceneDelta, -frame.worldDelta);
          dx = _gestureBaseX + corrected.dx;
          dy = _gestureBaseY + corrected.dy;
        }
        _applyGestureValue(shape!, controller, AnimatableProperty.x, dx);
        _applyGestureValue(shape, controller, AnimatableProperty.y, dy);
      case _CanvasGesture.scale:
        final next = (_gestureBaseScale * details.scale).clamp(0.05, 4.0);
        _applyGestureValue(
          shape!,
          controller,
          AnimatableProperty.scale,
          next.toDouble(),
        );
      case _CanvasGesture.rotate:
        final geo = SceneGeometry.fitFor(project, canvasSize);
        final pose = SelectionGeometry.shapePoseWithRig(
          shape!,
          controller.timeMs,
          _gestureBoneFrame,
        );
        final center = SelectionGeometry.center(pose, geo);
        final angle = math.atan2(
          details.localFocalPoint.dy - center.dy,
          details.localFocalPoint.dx - center.dx,
        );
        var next = _gestureBaseRotation + (angle - _gestureStartAngle);
        if (_snapRotation) next = _snapAngle(next);
        _applyGestureValue(
          shape,
          controller,
          AnimatableProperty.rotation,
          next,
        );
      case _CanvasGesture.none:
        break;
    }
  }

  /// Option : aimante la rotation aux multiples de 90° à ±3°.
  double _snapAngle(double angle) {
    const step = math.pi / 2;
    const tolerance = 3 * math.pi / 180;
    final snapped = (angle / step).roundToDouble() * step;
    return (angle - snapped).abs() <= tolerance ? snapped : angle;
  }

  void _onCanvasGestureEnd(ScaleEndDetails details) {
    if (_gesture != _CanvasGesture.none) {
      if (_gestureMutated && _gestureUndo != null) {
        _undoStack.push(_gestureUndo!);
        _undoTag = null;
        setState(() {});
      }
      _scheduleSave();
    }
    _gestureUndo = null;
    _gestureBoneFrame = null;
    _dragBoneId = null;
    _gesture = _CanvasGesture.none;
  }

  /// Tap sur le canvas : en mode rig (création d'os) tap 1 = articulation,
  /// tap 2 = extrémité ; sinon sélection d'os (extrémités/segments) puis
  /// sélection de forme (du premier plan vers l'arrière-plan).
  void _onCanvasTapUp(
    TapUpDetails details,
    AnimationProject project,
    TimelineController controller,
    Size canvasSize,
  ) {
    final geo = SceneGeometry.fitFor(project, canvasSize);
    if (_addBoneMode) {
      final scene = geo.canvasToScene(details.localPosition);
      if (_pendingJoint == null) {
        // Premier tap : le parent = os sélectionné ; si le tap tombe sur une
        // extrémité d'os, elle devient l'articulation (chaînes naturelles).
        String? parent = _selectedBoneId;
        var joint = scene;
        final rig = project.skeleton;
        if (rig != null && rig.bones.isNotEmpty) {
          final pose = SkeletonPose.evaluate(rig, controller.timeMs);
          for (final bone in rig.bones.reversed) {
            final frame = pose.frameOf(bone.id);
            if (frame == null) continue;
            final tip = geo.sceneToCanvas(frame.tip);
            if ((details.localPosition - tip).distance <=
                RigOverlayPainter.tipTouchSlop) {
              parent = bone.id;
              joint = frame.tip;
              break;
            }
          }
        }
        // Ancrage : une pièce sous le premier tap → le nouvel os naîtra
        // lié à cette pièce (elle suit l'os, et au repos l'os la suit).
        final anchor = _hitShapeAt(
          project,
          controller,
          geo,
          details.localPosition,
        );
        setState(() {
          _pendingJoint = joint;
          _pendingParentId = parent;
          _pendingShapeId = anchor?.id;
        });
        return;
      }
      _finishAddBone(scene, geo);
      return;
    }
    // Sélection d'os d'abord (mode squelette).
    final rig = project.skeleton;
    if (project.isSkeleton && rig != null && rig.bones.isNotEmpty) {
      final pose = SkeletonPose.evaluate(rig, controller.timeMs);
      final boneId = RigOverlayPainter.hitBone(
        pose,
        rig,
        geo,
        details.localPosition,
      );
      if (boneId != null) {
        setState(() => _selectedBoneId = boneId);
        return;
      }
    }
    final hit = _hitShapeAt(project, controller, geo, details.localPosition);
    if (hit != null) {
      setState(() => _selectedId = hit.id);
    }
  }

  /// Dialogue de réglage des fps avant un export MP4 ou GIF.
  Future<int?> _askExportFps(VideoFormat format) async {
    final choices = format == VideoFormat.mp4
        ? <int>[15, 24, 25, 30, 60]
        : <int>[10, 12, 15, 25];
    final initial = format == VideoFormat.mp4 ? (_project?.fps ?? 30) : 12;
    var selected = choices.contains(initial) ? initial : choices.last;
    return showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Export ${format.label}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Durée du projet : '
                '${((_project?.durationMs ?? 0) / 1000).toStringAsFixed(2)} s',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              const Text('Images par seconde'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final choice in choices)
                    ChoiceChip(
                      label: Text('$choice'),
                      selected: choice == selected,
                      onSelected: (_) =>
                          setDialogState(() => selected = choice),
                    ),
                ],
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(selected),
              child: const Text('Exporter'),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- export

  Future<void> _exportVideo(VideoFormat format) async {
    final project = _project;
    if (project == null) return;
    final fps = await _askExportFps(format);
    if (fps == null || !mounted) return;
    project.fps = fps; // défaut du prochain export
    await _flushSave();
    if (!mounted) return;
    final progress = ValueNotifier<double>(0);
    final navigator = Navigator.of(context);

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: Text('Export ${format.label}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ValueListenableBuilder<double>(
                valueListenable: progress,
                builder: (context, value, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    LinearProgressIndicator(value: value == 0 ? null : value),
                    const SizedBox(height: 12),
                    Text('${(value * 100).round()} %'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Rendu des images en cours…',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final service = ExportService(project, embeddedProjects: _embedded);
      final file = await service.exportVideo(
        format: format,
        fps: fps,
        onProgress: (value) => progress.value = value,
      );
      navigator.pop();
      await _share(file, format.mimeType);
    } catch (error) {
      navigator.pop();
      if (!mounted) return;
      _snack('Export impossible : $error');
    }
  }

  Future<void> _exportPng() async {
    final project = _project;
    final controller = _controller;
    if (project == null || controller == null) return;
    try {
      final file = await ExportService(
        project,
        embeddedProjects: _embedded,
      ).exportFramePng(controller.timeMs);
      await _share(file, 'image/png');
    } catch (error) {
      if (!mounted) return;
      _snack('Export PNG impossible : $error');
    }
  }

  Future<void> _exportJson() async {
    final project = _project;
    if (project == null) return;
    try {
      final file = await ExportService(project).exportJson();
      await _share(file, 'application/json');
    } catch (error) {
      if (!mounted) return;
      _snack('Export JSON impossible : $error');
    }
  }

  Future<void> _copyJson() async {
    final project = _project;
    if (project == null) return;
    await Clipboard.setData(
      ClipboardData(text: jsonEncode(_project!.toJson())),
    );
    _snack('JSON du projet copié');
  }

  Future<void> _share(File file, String mimeType) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path, mimeType: mimeType)],
          text: _project?.name ?? 'Animation',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _snack('Partage impossible : $error');
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final project = _project;
    final controller = _controller;

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Projet illisible :\n$_error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    if (project == null || controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _flushSave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            project.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: <Widget>[_exportMenu()],
        ),
        body: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return LayoutBuilder(
              builder: (context, constraints) {
                // Le preview prend ~40 % de la hauteur : le reste va à la
                // barre de lecture, à la timeline et à la barre d'outils.
                final previewHeight = (constraints.maxHeight * 0.40).clamp(
                  200.0,
                  380.0,
                );
                return Column(
                  children: <Widget>[
                    SizedBox(
                      height: previewHeight,
                      child: _buildCanvas(project, controller),
                    ),
                    _buildPlaybar(controller),
                    Expanded(child: _buildTimeline(project, controller)),
                    _buildToolbar(project),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildCanvas(AnimationProject project, TimelineController controller) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0D12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF232733)),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final canvasSize = constraints.biggest;
          final shape = _selected;
          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: Listener(
                  onPointerDown: (_) => _pointerDown(),
                  onPointerUp: (_) => _pointerUp(),
                  onPointerCancel: (_) => _pointerUp(),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: (details) => _onCanvasGestureStart(
                      details,
                      project,
                      controller,
                      canvasSize,
                    ),
                    onScaleUpdate: (details) => _onCanvasGestureUpdate(
                      details,
                      project,
                      controller,
                      canvasSize,
                    ),
                    onScaleEnd: _onCanvasGestureEnd,
                    onTapUp: (details) => _onCanvasTapUp(
                      details,
                      project,
                      controller,
                      canvasSize,
                    ),
                    child: CustomPaint(
                      painter: ScenePainter(
                        project: project,
                        timeMs: controller.timeMs,
                        selectedShapeId: _addBoneMode ? null : _selectedId,
                        showFrame: true,
                        embeddedProjects: _embedded,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
              if (project.isSkeleton && project.skeleton != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: RigOverlayPainter(
                        rig: project.skeleton!,
                        pose: SkeletonPose.evaluate(
                          project.skeleton!,
                          controller.timeMs,
                        ),
                        geo: SceneGeometry.fitFor(project, canvasSize),
                        selectedBoneId: _selectedBoneId,
                      ),
                    ),
                  ),
                ),
              if (!_addBoneMode &&
                  shape != null &&
                  (project.isSkeleton
                      ? shape.visible
                      : shape.isVisibleAt(controller.timeMs)))
                _buildPropertiesButton(shape, controller, canvasSize),
            ],
          );
        },
      ),
    );
  }

  /// Bouton « propriétés » ancré au coin bas-gauche du rectangle de sélection.
  Widget _buildPropertiesButton(
    VectorShape shape,
    TimelineController controller,
    Size canvasSize,
  ) {
    final project = _project;
    final bounds = ScenePainter.shapeBounds(shape, controller.timeMs);
    if (project == null || bounds == null || canvasSize.isEmpty) {
      return const SizedBox.shrink();
    }
    final geo = SceneGeometry.fitFor(project, canvasSize);
    final center = SelectionGeometry.propertiesButton(
      bounds,
      SelectionGeometry.shapePose(shape, controller.timeMs),
      geo,
    );
    const size = 38.0;
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
        tooltip: 'Propriétés de la forme',
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xCC151922),
          foregroundColor: const Color(0xFF7DD3FC),
        ),
        icon: const Icon(Icons.tune, size: 20),
        onPressed: _showPropertiesSheet,
      ),
    );
  }

  Widget _buildTimeline(
    AnimationProject project,
    TimelineController controller,
  ) {
    final zoom = _zoom;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: const Color(0xFF151922),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '${(controller.timeMs / 1000).toStringAsFixed(2)} s'
                ' / ${(project.durationMs / 1000).toStringAsFixed(2)} s'
                ' · ${project.fps} fps',
                style: const TextStyle(fontSize: 11),
              ),
              const Spacer(),
              if (zoom != null) ...<Widget>[
                IconButton(
                  tooltip: 'Zoom avant',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 34,
                    minHeight: 34,
                  ),
                  icon: const Icon(Icons.zoom_in, size: 18),
                  onPressed: () => setState(zoom.zoomIn),
                ),
                IconButton(
                  tooltip: 'Zoom arrière',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 34,
                    minHeight: 34,
                  ),
                  icon: const Icon(Icons.zoom_out, size: 18),
                  onPressed: () => setState(zoom.zoomOut),
                ),
                IconButton(
                  tooltip: 'Ajuster au projet',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 34,
                    minHeight: 34,
                  ),
                  icon: const Icon(Icons.fit_screen_outlined, size: 18),
                  onPressed: () => setState(zoom.fit),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Expanded(
            child: zoom == null
                ? const SizedBox.shrink()
                : SingleChildScrollView(
                    child: TimelineView(
                      project: project,
                      timeMs: controller.timeMs,
                      zoom: zoom,
                      selectedShapeId: _selectedId,
                      onSelect: (shape) =>
                          setState(() => _selectedId = shape.id),
                      onSeek: controller.setTime,
                      onRangeChanged: (shape, start, end) {
                        setState(() {
                          shape.startMs = start;
                          shape.endMs = end;
                        });
                        _scheduleSave();
                      },
                      onMoveChanged: (shape, targetStartMs) {
                        setState(
                          () => shape.shiftBy(targetStartMs - shape.startMs),
                        );
                      },
                      onMoveEnd: (_) => _scheduleSave(),
                      onGestureStart: (shape) => _pushUndo(),
                      onDeleteKeyframe: (shape, timeMs) {
                        setState(() => shape.removeKeyframeAt(timeMs));
                        _scheduleSave();
                      },
                      skeletonRig: project.isSkeleton ? project.skeleton : null,
                      selectedBoneId: _selectedBoneId,
                      onSelectBone: (bone) =>
                          setState(() => _selectedBoneId = bone.id),
                      onBoneMoveChanged: (bone, target) {
                        setState(
                          () => project.skeleton!.shiftTrackTo(bone.id, target),
                        );
                      },
                      onBoneMoveEnd: (_) => _scheduleSave(),
                      onBoneGestureStart: (_) => _pushUndo(),
                      onDeleteBoneKeyframe: (bone, timeMs) {
                        setState(
                          () => project.skeleton!.removeKeyframeAt(
                            bone.id,
                            timeMs,
                          ),
                        );
                        _scheduleSave();
                      },
                      onZoomChanged: () => setState(() {}),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybar(TimelineController controller) {
    final project = _project;
    final skeleton = project?.isSkeleton ?? false;
    final rig = _rig;
    final shape = _selected;
    final bone = _selectedBone;
    final keyframe = shape == null ? null : controller.nearestKeyframe(shape);
    final boneKeyframe = skeleton && rig != null && bone != null
        ? controller.nearestBoneKeyframe(rig, bone)
        : null;
    final hasKeyframes = skeleton
        ? (rig != null && bone != null && rig.hasKeyframes(bone.id))
        : (shape?.hasKeyframes ?? false);
    final diamondKeyframe = skeleton ? boneKeyframe : keyframe;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          IconButton(
            tooltip: 'Annuler la dernière action',
            onPressed: _undoStack.canUndo ? _undo : null,
            icon: const Icon(Icons.undo),
          ),
          if (_addBoneMode)
            IconButton(
              tooltip: 'Terminer le mode rig',
              onPressed: _startAddBone,
              icon: const Icon(Icons.check_circle, color: Color(0xFF3ECF8E)),
            )
          else ...<Widget>[
            IconButton(
              tooltip: 'Retour au début',
              onPressed: controller.rewind,
              icon: const Icon(Icons.skip_previous),
            ),
            IconButton.filledTonal(
              onPressed: () {
                controller.togglePlay();
                _syncTicker();
              },
              icon: Icon(controller.playing ? Icons.pause : Icons.play_arrow),
            ),
            IconButton(
              tooltip: diamondKeyframe == null
                  ? (skeleton
                        ? 'Ajouter une keyframe d’angle à l’os au curseur'
                        : 'Ajouter une keyframe au curseur')
                  : 'Retirer la keyframe au curseur',
              onPressed: skeleton ? _toggleBoneKeyframe : _toggleKeyframe,
              icon: Icon(
                diamondKeyframe == null
                    ? Icons.diamond_outlined
                    : Icons.diamond,
                color: hasKeyframes ? const Color(0xFFF2C94C) : null,
              ),
            ),
            IconButton(
              tooltip: 'Boucle',
              onPressed: () => controller.setLoop(!controller.loop),
              icon: Icon(controller.loop ? Icons.repeat_on : Icons.repeat),
            ),
          ],
          IconButton(
            tooltip: 'Snap rotation 90°',
            isSelected: _snapRotation,
            onPressed: () => setState(() => _snapRotation = !_snapRotation),
            icon: const Icon(Icons.rotate_90_degrees_ccw_outlined),
            selectedIcon: const Icon(Icons.rotate_90_degrees_ccw),
          ),
        ],
      ),
    );
  }

  /// Barre d'outils en bas : menus Formes, Animations (ou Squelettes),
  /// Calques.
  Widget _buildToolbar(AnimationProject project) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(
        children: <Widget>[
          _shapesMenu(project),
          project.isSkeleton ? _skeletonsMenu(project) : _animationsMenu(),
          _layersMenu(project),
          const Spacer(),
          Text(
            '${project.shapes.length} ${project.isSkeleton ? 'pièce(s)' : 'forme(s)'}',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ menus

  Widget _shapesMenu(AnimationProject project) {
    return PopupMenuButton<String>(
      tooltip: 'Formes',
      icon: const Icon(Icons.category_outlined),
      onSelected: (value) {
        if (value == 'add') {
          _addShape();
        } else if (value == 'insert_anim') {
          _insertAnimation();
        } else if (value.startsWith('select:')) {
          setState(() => _selectedId = value.substring(7));
        } else if (value == 'edit') {
          final shape = _selected;
          if (shape != null && !shape.isInstance) _editShape(shape);
        } else if (value == 'rename') {
          final shape = _selected;
          if (shape != null) _renameShape(shape);
        } else if (value == 'duplicate') {
          final shape = _selected;
          if (shape != null) _cloneShape(shape);
        } else if (value == 'delete') {
          final shape = _selected;
          if (shape != null) _deleteShape(shape);
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'add',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.add),
            title: Text('Ajouter une forme…'),
          ),
        ),
        // Projet squelette : pas d'instances imbriquées (0.9 — l'import
        // d'animation squelette dans le vectoriel arrive en 0.9.1).
        if (!project.isSkeleton)
          const PopupMenuItem<String>(
            value: 'insert_anim',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.movie_outlined),
              title: Text('Insérer une animation…'),
            ),
          ),
        const PopupMenuDivider(),
        if (project.shapes.isEmpty)
          const PopupMenuItem<String>(
            enabled: false,
            value: 'none',
            child: Text('Aucune forme'),
          ),
        for (final shape in project.shapes.reversed)
          PopupMenuItem<String>(
            value: 'select:${shape.id}',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                shape.id == _selectedId
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 18,
              ),
              title: Text(shape.name),
              subtitle: Text(
                '${(shape.durationMs / 1000).toStringAsFixed(1)} s · '
                '${shape.layers.length} couche(s)',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'edit',
          enabled: _selected != null && !_selected!.isInstance,
          child: const Text('Modifier les couches…'),
        ),
        PopupMenuItem<String>(
          value: 'rename',
          enabled: _selected != null,
          child: const Text('Renommer…'),
        ),
        PopupMenuItem<String>(
          value: 'duplicate',
          enabled: _selected != null,
          child: const Text('Dupliquer (avec ses keyframes)'),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          enabled: _selected != null,
          child: const Text('Supprimer'),
        ),
      ],
    );
  }

  Widget _animationsMenu() {
    final shape = _selected;
    return PopupMenuButton<String>(
      tooltip: 'Animations',
      enabled: shape != null,
      icon: const Icon(Icons.animation),
      onSelected: (value) {
        if (value == 'clear') {
          _clearAnimations();
          return;
        }
        if (value.startsWith('preset:')) {
          final preset = AnimationPreset.values.firstWhere(
            (p) => p.name == value.substring(7),
            orElse: () => AnimationPreset.apparition,
          );
          _applyPreset(preset);
          return;
        }
        if (value == 'keyframe') {
          _toggleKeyframe();
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          enabled: false,
          value: 'header',
          child: Text('Animations rapides'),
        ),
        for (final preset in AnimationPreset.values)
          PopupMenuItem<String>(
            value: 'preset:${preset.name}',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(preset.icon, size: 20),
              title: Text(preset.label),
              subtitle: Text(
                preset.description,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'keyframe',
          child: Text('Ajouter/retirer la keyframe au curseur'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'clear',
          child: Text('Effacer toutes les animations'),
        ),
      ],
    );
  }

  /// Menu « Squelettes » (projet squelette) : création d'os, liaison des
  /// pièces, sélection d'os, propriétés.
  Widget _skeletonsMenu(AnimationProject project) {
    final rig = project.skeleton;
    final bone = _selectedBone;
    final bound = _selected != null && (rig?.isBound(_selectedId!) ?? false);
    return PopupMenuButton<String>(
      tooltip: 'Squelettes',
      icon: const Icon(Icons.accessibility_new),
      onSelected: (value) {
        if (value == 'add_bone') {
          _startAddBone();
        } else if (value == 'bind') {
          _bindSelectedShape();
        } else if (value == 'unbind') {
          _unbindSelectedShape();
        } else if (value == 'bone_props') {
          _showBoneSheet();
        } else if (value == 'rename_rig') {
          _renameRig();
        } else if (value == 'delete_rig') {
          _deleteRig();
        } else if (value.startsWith('select:')) {
          setState(() {
            _selectedBoneId = value.substring(7);
            _addBoneMode = false;
            _pendingJoint = null;
          });
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'add_bone',
          child: Text(_addBoneMode ? 'Terminer le mode rig' : 'Ajouter un os…'),
        ),
        PopupMenuItem<String>(
          value: 'bind',
          enabled: _selected != null && rig != null && rig.bones.isNotEmpty,
          child: const Text('Lier la pièce à un os…'),
        ),
        PopupMenuItem<String>(
          value: 'unbind',
          enabled: bound,
          child: const Text('Délier la pièce'),
        ),
        const PopupMenuDivider(),
        if (rig == null || rig.bones.isEmpty)
          const PopupMenuItem<String>(
            enabled: false,
            value: 'none',
            child: Text('Aucun os'),
          ),
        for (final candidate in rig?.orderedParentsFirst() ?? const <RigBone>[])
          PopupMenuItem<String>(
            value: 'select:${candidate.id}',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                candidate.id == _selectedBoneId
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 18,
              ),
              title: Text(
                '${'\u2500' * rig!.depthOf(candidate.id)} ${candidate.name}',
              ),
              subtitle: Text(
                rig.hasKeyframes(candidate.id)
                    ? '${rig.trackOf(candidate.id)!.length} keyframe(s) · '
                          '${candidate.length.round()} px'
                    : 'repos · ${candidate.length.round()} px',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'bone_props',
          enabled: bone != null,
          child: const Text('Propriétés de l’os…'),
        ),
        PopupMenuItem<String>(
          value: 'rename_rig',
          enabled: rig != null,
          child: const Text('Renommer le squelette…'),
        ),
        PopupMenuItem<String>(
          value: 'delete_rig',
          enabled: rig != null,
          child: const Text('Supprimer le squelette'),
        ),
      ],
    );
  }

  Widget _layersMenu(AnimationProject project) {
    return PopupMenuButton<String>(
      tooltip: 'Calques',
      icon: const Icon(Icons.layers_outlined),
      onSelected: (value) {
        if (value.startsWith('vis:')) {
          final shape = project.shapeById(value.substring(4));
          if (shape != null) _toggleVisibility(shape);
        } else if (value == 'up' || value == 'down') {
          final shape = _selected;
          if (shape != null) _moveShape(shape, value == 'up' ? 1 : -1);
        } else if (value == 'delete') {
          final shape = _selected;
          if (shape != null) _deleteShape(shape);
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          enabled: false,
          value: 'header',
          child: Text('Ordre des calques (avant → arrière)'),
        ),
        for (final shape in project.shapes.reversed)
          PopupMenuItem<String>(
            value: 'vis:${shape.id}',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                shape.visible ? Icons.visibility : Icons.visibility_off,
                size: 18,
              ),
              title: Text(shape.name),
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'up',
          enabled: _selected != null,
          child: const Text('Monter la forme sélectionnée'),
        ),
        PopupMenuItem<String>(
          value: 'down',
          enabled: _selected != null,
          child: const Text('Descendre la forme sélectionnée'),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          enabled: _selected != null,
          child: const Text('Supprimer la forme sélectionnée'),
        ),
      ],
    );
  }

  Widget _exportMenu() {
    return PopupMenuButton<String>(
      tooltip: 'Export',
      icon: const Icon(Icons.ios_share),
      onSelected: (value) => switch (value) {
        'mp4' => _exportVideo(VideoFormat.mp4),
        'gif' => _exportVideo(VideoFormat.gif),
        'png' => _exportPng(),
        'json' => _exportJson(),
        'clipboard' => _copyJson(),
        _ => null,
      },
      itemBuilder: (context) => const <PopupMenuEntry<String>>[
        PopupMenuItem<String>(value: 'mp4', child: Text('Vidéo MP4 (H.264)')),
        PopupMenuItem<String>(value: 'gif', child: Text('GIF animé')),
        PopupMenuItem<String>(value: 'png', child: Text('Image PNG (frame)')),
        PopupMenuDivider(),
        PopupMenuItem<String>(value: 'json', child: Text('Projet JSON')),
        PopupMenuItem<String>(
          value: 'clipboard',
          child: Text('Copier le JSON'),
        ),
      ],
    );
  }
}
