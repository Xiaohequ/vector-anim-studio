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
import '../engine/simple_animation_format.dart';
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
enum _CanvasGesture { none, move, scale, rotate, boneRotate, boneIk }

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

  /// Os en cours de rotation (glisser de la poignée) ou de déplacement
  /// (glisser du bouton ✥).
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
                  '${summary.type.label} · '
                  '${(summary.durationMs / 1000).toStringAsFixed(1)} s · '
                  '${summary.shapeCount} '
                  '${summary.type == ProjectType.skeleton ? 'pièce(s)' : 'forme(s)'}',
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
    _importControllerTimer?.cancel();
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
      // Liaisons emportées (forme entière et couches) : les ids de couches
      // sont régénérés dans le clone — correspondance par ordre.
      project.skeleton?.duplicateBindings(shape.id, clone.id, <String, String>{
        for (var i = 0; i < shape.layers.length; i++)
          shape.layers[i].id: clone.layers[i].id,
      });
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
        skeletonRig: project.isSkeleton ? project.skeleton : null,
        onBindLayer: (layer) => _bindLayer(shape, layer),
        onUnbindLayer: (layer) => _unbindLayer(shape, layer),
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
    });
    if (_addBoneMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Mode rig : articulation puis extrémité — tap sur un os ou une pièce = os attaché automatiquement',
          ),
        ),
      );
    }
  }

  /// Début du glisser du bouton ✥ : snapshot d'annulation en attente.
  void _onBonePanStart(DragStartDetails details) {
    final bone = _selectedBone;
    if (bone == null || _project == null) return;
    _dragBoneId = bone.id;
    _gestureUndo = AnimationProject.fromJson(_project!.toJson());
    _gestureMutated = false;
  }

  /// Glisser du bouton ✥ : l'ancrage de l'os suit le doigt (delta écran →
  /// scène), la chaîne et les pièces liées sont emportées. Pas de mode : le
  /// geste vit sur le bouton lui-même (choix utilisateur v0.9.5).
  void _onBonePanUpdate(
    DragUpdateDetails details,
    AnimationProject project,
    Size canvasSize,
  ) {
    final controller = _controller;
    final rig = project.skeleton;
    final bone = rig?.boneById(_dragBoneId);
    if (controller == null || rig == null || bone == null) return;
    final geo = SceneGeometry.fitFor(project, canvasSize);
    setState(() {
      _translateBoneFollow(
        project,
        rig,
        bone,
        controller,
        details.delta / geo.scale,
      );
    });
    _gestureMutated = true;
  }

  /// Fin du glisser ✥ : 1 geste = 1 entrée d'annulation, save différée.
  void _onBonePanEnd() {
    if (_gestureMutated && _gestureUndo != null) {
      _undoStack.push(_gestureUndo!);
      _undoTag = null;
      setState(() {});
    }
    _gestureUndo = null;
    _gestureMutated = false;
    _dragBoneId = null;
    _scheduleSave();
  }

  /// Deuxième tap du mode création : crée l'os entre l'articulation en
  /// attente et le point touché. Si un attachement est détecté (os touché,
  /// pièce liée → os porteur, os sélectionné), une confirmation propose
  /// d'attacher — refus = os racine ancré sur place.
  Future<void> _finishAddBone(Offset scenePoint, SceneGeometry geo) async {
    final project = _project;
    final joint = _pendingJoint;
    if (project == null || joint == null) return;
    var parent = project.skeleton?.boneById(_pendingParentId);
    if (parent != null) {
      final attach = await _askAttachBone(parent);
      if (attach == null || !mounted) return; // dialogue fermé : rien créé
      if (!attach) parent = null; // refus → os racine, ancré sur place
    }
    _pushUndo(); // couvre aussi la création du rig au premier os
    _createRigIfNeeded();
    final rig = project.skeleton!;
    final parentFrame = SkeletonPose.evaluate(
      rig,
      _controller?.timeMs ?? 0,
    ).frameOf(parent?.id);
    final bone = boneBetween(
      joint,
      scenePoint,
      name: 'Os ${rig.bones.length + 1}',
      parentId: parent?.id,
      parentFrame: parentFrame,
    );
    setState(() {
      rig.addBone(bone);
      _selectedBoneId = bone.id;
      _addBoneMode = false;
      _pendingJoint = null;
      _pendingParentId = null;
    });
    _scheduleSave();
    _snack(
      parent == null
          ? 'Os « ${bone.name} » créé (racine)'
          : 'Os « ${bone.name} » attaché à « ${parent.name} »',
    );
  }

  /// Confirmation d'attachement : oui → l'ancrage du nouvel os suit le
  /// parent ; non → os racine ancré sur place. Null = dialogue fermé.
  Future<bool?> _askAttachBone(RigBone parent) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Attacher le nouvel os ?'),
        content: Text(
          'L’os serait attaché à « ${parent.name} » : son ancrage suivra '
          'cet os dans tous ses mouvements.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Non, sans parent'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Attacher'),
          ),
        ],
      ),
    );
  }

  /// Sélecteur d’os (dialogue réutilisé : liaison de pièce ou de couche).
  Future<String?> _pickBone(SkeletonRig rig, String title) {
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: <Widget>[
          for (final bone in rig.bones)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(bone.id),
              child: Text('${'\u2500' * rig.depthOf(bone.id)} ${bone.name}'),
            ),
        ],
      ),
    );
  }

  /// Lie la pièce sélectionnée à un os (rig maître : ses sliders deviennent
  /// l’offset de repos dans le repère de l’os).
  Future<void> _bindSelectedShape() async {
    final project = _project;
    final rig = _rig;
    final shape = _selected;
    if (project == null || rig == null || shape == null) return;
    if (rig.bones.isEmpty) {
      _snack('Crée d’abord un os (Squelettes ▸ Ajouter un os…)');
      return;
    }
    final picked = await _pickBone(rig, 'Lier « ${shape.name} » à quel os ?');
    if (picked == null || !mounted) return;
    _pushUndo();
    setState(() => rig.bindShape(shape.id, picked));
    await _flushSave();
    final bone = rig.boneById(picked);
    _snack('Pièce liée à l’os « ${bone?.name ?? '?'} »');
  }

  /// Lie une couche précise de la pièce à un os (v0.9.6) — la couche suit
  /// SON os, indépendamment des couches voisines.
  Future<void> _bindLayer(VectorShape shape, ShapeLayer layer) async {
    final rig = _rig;
    if (rig == null) return;
    if (rig.bones.isEmpty) {
      _snack('Crée d’abord un os (Squelettes ▸ Ajouter un os…)');
      return;
    }
    final picked = await _pickBone(
      rig,
      'Lier la couche « ${layer.name} » à quel os ?',
    );
    if (picked == null || !mounted) return;
    _pushUndo();
    setState(() => rig.bindLayer(shape.id, layer.id, picked));
    await _flushSave();
    final bone = rig.boneById(picked);
    _snack('Couche « ${layer.name} » liée à « ${bone?.name ?? '?'} »');
  }

  Future<void> _unbindLayer(VectorShape shape, ShapeLayer layer) async {
    final rig = _rig;
    if (rig == null) return;
    _pushUndo();
    setState(() => rig.unbindLayer(shape.id, layer.id));
    await _flushSave();
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
    final controller = _controller;
    if (rig == null || bone == null || controller == null) return;
    _pushUndo();
    setState(() {
      // Re-parentage SANS saut visuel : l'offset et l'angle de repos sont
      // recalculés dans le repère du nouveau parent. « Racine » détache
      // l'os (et sa descendance, offsets relatifs) : les os restent ancrés
      // sur place au preview et l'ancien parent ne les entraîne plus.
      rig.reparentBone(
        bone,
        parentId,
        SkeletonPose.evaluate(rig, controller.timeMs),
      );
    });
    _flushSave();
  }

  /// Ordre de dessin (z, v0.10) : slider coalescé en une entrée d'annulation.
  void _setBoneZ(int value) {
    final bone = _selectedBone;
    if (bone == null) return;
    _pushUndo(tag: 'boneZ:${bone.id}');
    bone.z = value;
    _scheduleSave();
  }

  /// Propriété d'animation d'os (opacité/étirement/écrasement, v0.10) :
  /// keyframe au curseur — `upsertKeyframe` fusionne (l'angle et l'easing
  /// de la keyframe existante sont conservés). Slider coalescé.
  void _setBoneAnimatable(BoneAnimatable property, double value) {
    final rig = _rig;
    final bone = _selectedBone;
    final controller = _controller;
    if (rig == null || bone == null || controller == null) return;
    _pushUndo(tag: 'boneAnim:${bone.id}:${property.name}');
    setState(() {
      switch (property) {
        case BoneAnimatable.opacity:
          rig.upsertKeyframe(
            bone.id,
            controller.timeMs,
            rig.angleDeltaAt(bone.id, controller.timeMs),
            opacity: value,
          );
        case BoneAnimatable.stretch:
          rig.upsertKeyframe(
            bone.id,
            controller.timeMs,
            rig.angleDeltaAt(bone.id, controller.timeMs),
            stretch: value,
          );
        case BoneAnimatable.squash:
          rig.upsertKeyframe(
            bone.id,
            controller.timeMs,
            rig.angleDeltaAt(bone.id, controller.timeMs),
            squash: value,
          );
      }
    });
    _scheduleSave();
  }

  /// IK 2 os (v0.10) : bascule — la sheet n'active le switch que pour un os
  /// à enfant unique.
  void _toggleIk() {
    final bone = _selectedBone;
    if (bone == null) return;
    _pushUndo();
    setState(() => bone.ikEnabled = !bone.ikEnabled);
    _scheduleSave();
  }

  /// IK 2 os (v0.10) : inverse le côté du coude.
  void _flipBend() {
    final bone = _selectedBone;
    if (bone == null) return;
    _pushUndo();
    setState(() => bone.bendSign = -bone.bendSign);
    _scheduleSave();
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
        onZChanged: _setBoneZ,
        onAnimatableChanged: _setBoneAnimatable,
        onToggleIk: _toggleIk,
        onFlipBend: _flipBend,
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

  /// Translate l'ancrage de repos d'un os de [step] (coordonnées scène) et
  /// emporte les pièces liées à l'os et à sa descendance : l'os suit le
  /// doigt ET la pièce du doigt suit (collée à l'os).
  void _translateBoneFollow(
    AnimationProject project,
    SkeletonRig rig,
    RigBone bone,
    TimelineController controller,
    Offset step,
  ) {
    final before = SkeletonPose.evaluate(rig, controller.timeMs);
    rig.translateBoneRest(bone, before, step);
    final after = SkeletonPose.evaluate(rig, controller.timeMs);
    carryBoundPieces(
      project,
      rig,
      before,
      after,
      controller.timeMs,
      toleranceMs: controller.snapToleranceMs,
    );
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
    // Priorité rig : poignée de rotation de l'os sélectionné uniquement —
    // v0.9.3 : pivoter via l'extrémité de l'os (2e point) est désactivé.
    final rig = project.skeleton;
    if (project.isSkeleton && rig != null && rig.bones.isNotEmpty) {
      final selectedBone = rig.boneById(_selectedBoneId);
      final pose = SkeletonPose.evaluate(rig, controller.timeMs);
      final geo = SceneGeometry.fitFor(project, canvasSize);
      // IK 2 os (v0.10) : glisser l'EXTRÉMITÉ de l'enfant unique résout la
      // chaîne — prioritaire sur la poignée de rotation. v0.10.1 : le
      // losange vert est une vraie poignée — l'IK démarre que l'os PARENT
      // (ikEnabled) ou l'ENFANT (effecteur) soit sélectionné, voire SANS
      // sélection du tout (les v0.10.0 exigeaient le parent : glisser le
      // poignet fraîchement tapé ne faisait rien).
      RigBone? ikParent;
      if (selectedBone != null) {
        if (selectedBone.ikEnabled) {
          ikParent = selectedBone;
        } else {
          final parent = rig.boneById(selectedBone.parentId);
          if (parent != null &&
              parent.ikEnabled &&
              rig.onlyChildOf(parent.id)?.id == selectedBone.id) {
            ikParent = parent;
          }
        }
      }
      if (ikParent != null &&
          RigOverlayPainter.hitIkEndEffector(
            pose,
            rig,
            geo,
            ikParent.id,
            details.localFocalPoint,
          )) {
        _startBoneIk(ikParent, project);
        return;
      }
      if (selectedBone == null) {
        // Aucune sélection : le losange vert sous le doigt démarre l'IK.
        for (final candidate in rig.bones.reversed) {
          if (!candidate.ikEnabled) continue;
          if (RigOverlayPainter.hitIkEndEffector(
            pose,
            rig,
            geo,
            candidate.id,
            details.localFocalPoint,
          )) {
            _startBoneIk(candidate, project);
            return;
          }
        }
      }
      if (selectedBone != null) {
        if (RigOverlayPainter.hitRotationHandle(
          pose,
          rig,
          geo,
          selectedBone.id,
          details.localFocalPoint,
        )) {
          _gesture = _CanvasGesture.boneRotate;
          _dragBoneId = selectedBone.id;
          _gestureBoneFrame = null;
          _gestureUndo = AnimationProject.fromJson(project.toJson());
          _gestureMutated = false;
          setState(() {
            _selectedBoneId = selectedBone.id;
            _selectedId = null; // sélection exclusive : os OU forme
          });
          return;
        }
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
    // Les gestes d'os ne portent pas de forme (sélection exclusive : un os
    // sélectionné laisse la forme à null).
    if (shape == null &&
        _gesture != _CanvasGesture.boneRotate &&
        _gesture != _CanvasGesture.boneIk) {
      return;
    }
    switch (_gesture) {
      case _CanvasGesture.boneIk:
        final rig = project.skeleton;
        final bone = rig?.boneById(_dragBoneId);
        if (rig == null || bone == null) break;
        final child = rig.onlyChildOf(bone.id);
        if (child == null) break;
        final pose = SkeletonPose.evaluate(rig, controller.timeMs);
        final parentFrame = pose.frameOf(bone.id);
        final childFrame = pose.frameOf(child.id);
        if (parentFrame == null || childFrame == null) break;
        final geo = SceneGeometry.fitFor(project, canvasSize);
        final target = geo.canvasToScene(details.localFocalPoint);
        final (parentAngle, childAngle) = solveTwoBoneIk(
          joint: parentFrame.joint,
          length1: math.max(1.0, parentFrame.length * parentFrame.stretchX),
          length2: math.max(1.0, childFrame.length * childFrame.stretchX),
          target: target,
          bend: bone.bendSign,
        );
        // setState à chaque update : repeint canvas + timeline en direct.
        setState(() {
          _poseChainTo(
            project,
            rig,
            bone,
            parentAngle,
            childAngle,
            pose,
            controller,
          );
        });
        _gestureMutated = true;
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
            // L'os suit la pièce ET la pièce suit le doigt : translation
            // de l'ancrage + emport des pièces liées à l'os.
            _translateBoneFollow(
              project,
              rig,
              bone,
              controller,
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

  /// Démarre le geste IK sur la chaîne dont [ikParent] est l'os parent :
  /// snapshot d'annulation en attente, sélection exclusive sur le parent
  /// (la sheet IK y reste accessible).
  void _startBoneIk(RigBone ikParent, AnimationProject project) {
    _gesture = _CanvasGesture.boneIk;
    _dragBoneId = ikParent.id;
    _gestureBoneFrame = null;
    _gestureUndo = AnimationProject.fromJson(project.toJson());
    _gestureMutated = false;
    setState(() {
      _selectedBoneId = ikParent.id;
      _selectedId = null; // sélection exclusive : os OU forme
    });
  }

  /// IK 2 os (v0.10) : pose les angles MONDE résolus du parent et de
  /// l'enfant — keyframe au curseur pour un os animé (auto-key), angle de
  /// repos sinon (l'enfant est relatif à l'angle monde du parent APRÈS sa
  /// propre mutation, d'où la ré-évaluation `mid`). Os posé : les pièces
  /// liées sont emportées par la nouvelle pose de repos.
  void _poseChainTo(
    AnimationProject project,
    SkeletonRig rig,
    RigBone ikParent,
    double parentAngle,
    double childAngle,
    SkeletonPose before,
    TimelineController controller,
  ) {
    final child = rig.onlyChildOf(ikParent.id);
    if (child == null) return;
    final grandFrame = before.frameOf(ikParent.parentId);
    final parentFrameBefore = before.frameOf(ikParent.id);
    if (parentFrameBefore == null) return;
    if (rig.hasKeyframes(ikParent.id)) {
      final target =
          rig
              .keyframeNear(
                ikParent.id,
                controller.timeMs,
                controller.snapToleranceMs,
              )
              ?.timeMs ??
          controller.timeMs;
      rig.upsertKeyframe(
        ikParent.id,
        target,
        parentAngle -
            parentFrameBefore.worldAngleRest -
            (grandFrame?.worldDelta ?? 0),
      );
    } else {
      ikParent.restAngle = parentAngle - (grandFrame?.worldAngle ?? 0);
    }
    // L'enfant est posé dans l'état APRÈS la mutation du parent.
    final mid = SkeletonPose.evaluate(rig, controller.timeMs);
    final midParent = mid.frameOf(child.parentId);
    final midChild = mid.frameOf(child.id);
    if (midParent == null || midChild == null) return;
    if (rig.hasKeyframes(child.id)) {
      final target =
          rig
              .keyframeNear(
                child.id,
                controller.timeMs,
                controller.snapToleranceMs,
              )
              ?.timeMs ??
          controller.timeMs;
      rig.upsertKeyframe(
        child.id,
        target,
        childAngle - midChild.worldAngleRest - midParent.worldDelta,
      );
    } else {
      child.restAngle = childAngle - midParent.worldAngle;
    }
    carryBoundPieces(
      project,
      rig,
      before,
      SkeletonPose.evaluate(rig, controller.timeMs),
      controller.timeMs,
      toleranceMs: controller.snapToleranceMs,
    );
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
        // Premier tap : le parent est détecté par priorité — ① extrémité
        // d'os touchée (l'articulation s'y accroche exactement, chaînes
        // naturelles), ② segment d'os touché, ③ pièce touchée → l'os qui
        // la porte, ④ os sélectionné. L'os 2 naît ATTACHÉ à l'os 1 : son
        // ancrage suit le parent (le poignet) dans tous ses mouvements.
        var parent = _selectedBoneId;
        var joint = scene;
        final rig = project.skeleton;
        if (rig != null && rig.bones.isNotEmpty) {
          final pose = SkeletonPose.evaluate(rig, controller.timeMs);
          final hitId = RigOverlayPainter.hitBone(
            pose,
            rig,
            geo,
            details.localPosition,
          );
          if (hitId != null) {
            parent = hitId;
            final frame = pose.frameOf(hitId);
            final tip = frame == null ? null : geo.sceneToCanvas(frame.tip);
            if (frame != null &&
                tip != null &&
                (details.localPosition - tip).distance <=
                    RigOverlayPainter.tipTouchSlop) {
              joint = frame.tip; // accroché au poignet de l'os parent
            }
          } else {
            final piece = _hitShapeAt(
              project,
              controller,
              geo,
              details.localPosition,
            );
            final carrier = piece == null
                ? null
                : rig.boneById(rig.boneIdForShape(piece.id));
            if (carrier != null) parent = carrier.id;
          }
        }
        setState(() {
          _pendingJoint = joint;
          _pendingParentId = parent;
        });
        return;
      }
      _finishAddBone(scene, geo);
      return;
    }
    // Sélection d'os d'abord (mode squelette) — exclusive avec la pièce :
    // soit un os, soit une forme (jamais les deux).
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
        setState(() {
          _selectedBoneId = boneId;
          _selectedId = null;
        });
        return;
      }
    }
    final hit = _hitShapeAt(project, controller, geo, details.localPosition);
    if (hit != null) {
      setState(() {
        _selectedId = hit.id;
        _selectedBoneId = null;
      });
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

  /// Export au format SIMPLE vasf-1 (pour agents IA).
  Future<void> _exportSimpleJson() async {
    final project = _project;
    if (project == null) return;
    try {
      final file = await ExportService(project).exportSimpleJson();
      await _share(file, 'application/json');
    } catch (error) {
      if (!mounted) return;
      _snack('Export JSON simple impossible : $error');
    }
  }

  /// Dernier projet importé (résultat du dialogue d'import) + dernier
  /// message d'erreur affiché DANS le dialogue (pour corriger sans perdre
  /// le texte collé).
  AnimationProject? _lastImported;
  String? _lastImportError;

  /// Dispose différé du controller de texte du dialogue d'import (annulé au
  /// dispose de l'écran — pas de timer pendent).
  Timer? _importControllerTimer;

  /// Décode le texte collé : format simple « vasf » (champ version) ou
  /// projet complet — null + [_lastImportError] en cas de problème.
  AnimationProject? _parseImportText(String text) {
    _lastImportError = null;
    Map<String, Object?> decoded;
    try {
      final value = jsonDecode(text);
      if (value is Map) {
        decoded = value.cast<String, Object?>();
      } else {
        throw const FormatException('objet JSON attendu');
      }
    } on FormatException catch (error) {
      _lastImportError = 'JSON illisible : ${error.message}';
      return null;
    }
    try {
      if (SimpleAnimationFormat.isSimpleFormat(decoded)) {
        return SimpleAnimationFormat.fromJson(
          decoded,
          fallbackName: 'Animation importée',
        );
      }
      return AnimationProject.fromJson(decoded);
    } on SimpleFormatException catch (error) {
      _lastImportError = error.toString();
      return null;
    }
  }

  /// Import d'une animation : dialogue avec collage (presse-papiers). La
  /// réussite crée un NOUVEAU projet (jamais de remplacement à l'aveugle)
  /// et l'ouvre.
  Future<void> _importJsonDialog() async {
    _lastImportError = null;
    _lastImported = null;
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Importer un JSON'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Colle un JSON « vasf » (simple, pour agents IA) ou un '
                  'projet complet. Un NOUVEAU projet sera créé.',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  maxLines: 12,
                  autofocus: true,
                ),
                if (_lastImportError != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Text(
                        _lastImportError!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFFF8A8A),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                final imported = _parseImportText(controller.text);
                if (imported == null) {
                  setDialogState(() {});
                  return;
                }
                _lastImported = imported;
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Importer'),
            ),
          ],
        ),
      ),
    );
    // Le controller est différé d'une seconde : le TextField reste vivant
    // pendant l'animation de sortie du dialogue (dispose immédiat = assert
    // « used after being disposed »). Annulé si l'écran est détruit avant
    // (pas de timer pendent à la fin des tests).
    _importControllerTimer?.cancel();
    _importControllerTimer = Timer(
      const Duration(seconds: 1),
      controller.dispose,
    );
    final imported = _lastImported;
    if (ok != true || imported == null || !mounted) return;
    await widget.repository.save(imported);
    if (!mounted) return;
    _lastImported = null;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) =>
            StudioScreen(projectId: imported.id, repository: widget.repository),
      ),
    );
    _snack('Projet importé : ${imported.name}');
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
          final bone = _selectedBone;
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
              // Os sélectionné : ⚙ propriétés + ✥ déplacement (comme pour
              // les formes, ancrés au segment).
              if (!_addBoneMode && bone != null)
                _buildBoneButtons(project, controller, canvasSize),
            ],
          );
        },
      ),
    );
  }

  /// Boutons flottants de l'os sélectionné : ⚙ propriétés (ancré au bout du
  /// segment, comme le bouton des formes) + ✥ mode déplacement à côté.
  /// v0.10.1 : si l'os sélectionné est l'ENFANT d'une chaîne IK, les boutons
  /// s'ancrent au JOINT DU PARENT (le coude) — posés près de l'enfant, le
  /// bouton ✥ recouvrait l'effecteur (losange vert) et avalait le glisser
  /// IK (« rien ne se passe » en v0.10.0).
  Widget _buildBoneButtons(
    AnimationProject project,
    TimelineController controller,
    Size canvasSize,
  ) {
    final bone = _selectedBone;
    final rig = project.skeleton!;
    final frame = bone == null
        ? null
        : SkeletonPose.evaluate(rig, controller.timeMs).frameOf(bone.id);
    if (bone == null || frame == null || canvasSize.isEmpty) {
      return const SizedBox.shrink();
    }
    final geo = SceneGeometry.fitFor(project, canvasSize);
    // Ancrage : l'os sélectionné, SAUF quand il est l'enfant unique d'un os
    // IK — dans ce cas les boutons se rangent au joint du parent (le coude),
    // loin de l'effecteur que le doigt doit saisir.
    var anchorFrame = frame;
    final parent = rig.boneById(bone.parentId);
    if (parent != null &&
        parent.ikEnabled &&
        rig.onlyChildOf(parent.id)?.id == bone.id) {
      final parentFrame = SkeletonPose.evaluate(
        rig,
        controller.timeMs,
      ).frameOf(parent.id);
      if (parentFrame != null) {
        anchorFrame = parentFrame;
      }
    }
    // Pose synthétique de l'os : segment = rect local de longueur
    // frame.length et hauteur nulle, orienté worldAngle — réutilise le
    // placement « coin bas-gauche » des boutons de forme.
    final bonePose = Pose2D(
      origin: (anchorFrame.joint + anchorFrame.tip) / 2,
      rotation: anchorFrame.worldAngle,
      scale: 1,
    );
    final boneBounds = Rect.fromCenter(
      center: Offset.zero,
      width: anchorFrame.length,
      height: 0,
    );
    final center = SelectionGeometry.propertiesButton(
      boneBounds,
      bonePose,
      geo,
    );
    const size = 38.0;
    const gap = 44.0;
    final left = (center.dx - size / 2)
        .clamp(0.0, math.max(0.0, canvasSize.width - size))
        .toDouble();
    final top = (center.dy - size / 2)
        .clamp(0.0, math.max(0.0, canvasSize.height - size))
        .toDouble();
    final moveLeft = (center.dx + gap - size / 2)
        .clamp(0.0, math.max(0.0, canvasSize.width - size))
        .toDouble();
    return Positioned.fill(
      child: Stack(
        children: <Widget>[
          Positioned(
            left: left,
            top: top,
            width: size,
            height: size,
            child: IconButton(
              tooltip: 'Propriétés de l’os',
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xCC151922),
                foregroundColor: const Color(0xFFC084FC),
              ),
              icon: const Icon(Icons.tune, size: 20),
              onPressed: _showBoneSheet,
            ),
          ),
          Positioned(
            left: moveLeft,
            top: top,
            width: size,
            height: size,
            child: Tooltip(
              message: 'Glisser pour déplacer l’os',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: _onBonePanStart,
                onPanUpdate: (details) =>
                    _onBonePanUpdate(details, project, canvasSize),
                onPanEnd: (_) => _onBonePanEnd(),
                onPanCancel: _onBonePanEnd,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xCC151922),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.open_with,
                    size: 20,
                    color: Color(0xFF7DD3FC),
                  ),
                ),
              ),
            ),
          ),
        ],
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
      SelectionGeometry.shapePoseWithRig(
        shape,
        controller.timeMs,
        _frameForShape(project, shape, controller.timeMs),
      ),
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
          setState(() {
            _selectedId = value.substring(7);
            _selectedBoneId = null; // sélection exclusive
          });
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
            _selectedId = null; // sélection exclusive
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
        'simple' => _exportSimpleJson(),
        'import' => _importJsonDialog(),
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
        PopupMenuItem<String>(
          value: 'simple',
          child: Text('JSON simple — agents IA (vasf)'),
        ),
        PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'import',
          child: Text('Importer un JSON…'),
        ),
      ],
    );
  }
}
