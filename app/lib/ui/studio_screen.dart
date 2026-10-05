import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../data/project_repository.dart';
import '../engine/animation_presets.dart';
import '../engine/export_service.dart';
import '../engine/json_project_import.dart';
import '../engine/rig_overlay_painter.dart';
import '../engine/scene_painter.dart';
import '../engine/selection_geometry.dart';
import '../engine/timeline_controller.dart';
import '../engine/timeline_zoom.dart';
import '../engine/undo_stack.dart';
import '../models/animation.dart';
import '../models/skeleton.dart';
import 'bone_editor_screen.dart';
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
  Timer? _bannerTimer;
  OverlayEntry? _messageOverlay;

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

  /// Un os est visible/interactif s'il porte au moins une forme visible au
  /// playhead. Un os importé sans liaison reste éditable pour compatibilité.
  bool _boneVisibleAt(RigBone bone, int timeMs) {
    final project = _project;
    final rig = _rig;
    if (project == null || rig == null) return false;
    var attached = false;
    for (final shape in project.shapes) {
      final carrierId = rig.carrierBoneId(shape.id);
      if (carrierId == null ||
          !rig.chainFrom(carrierId).any((item) => item.id == bone.id)) {
        continue;
      }
      attached = true;
      if (shape.isVisibleAt(timeMs)) return true;
    }
    return !attached;
  }

  bool _selectedBoneIsVisible(int timeMs) {
    final bone = _selectedBone;
    return bone != null && _boneVisibleAt(bone, timeMs);
  }

  /// Os à montrer quand un groupe lié à un rig embarqué est sélectionné.
  /// L'overlay Studio réduit le dessin au groupe actif, mais inclut toute sa chaîne porteuse.
  Set<String>? _visibleBonesForSelectedGroup(int timeMs) {
    final project = _project;
    final rig = _rig;
    final shape = _selected;
    if (project == null ||
        rig == null ||
        shape == null ||
        !shape.isInstance ||
        !shape.embeddedIsSkeleton ||
        !shape.isVisibleAt(timeMs)) {
      return null;
    }
    final carrierId = rig.carrierBoneId(shape.id);
    if (carrierId == null) return null;
    return <String>{for (final bone in rig.chainFrom(carrierId)) bone.id};
  }

  /// Os en cours de rotation (glisser de la poignée) ou de déplacement
  /// (glisser du bouton ✥).
  String? _dragBoneId;

  /// Zoom/défilement de la timeline (mémoire de session, non persisté).
  TimelineZoomState? _zoom;

  /// Caméra du preview, indépendante des transformations des objets.
  double _previewZoom = 1;
  Offset _previewPan = Offset.zero;
  bool _previewPanMode = false;
  Offset _panStart = Offset.zero;
  Offset _panBase = Offset.zero;
  bool _previewFullscreen = false;

  SceneGeometry _canvasGeometry(AnimationProject project, Size size) =>
      SceneGeometry.fitFor(project, size, zoom: _previewZoom, pan: _previewPan);

  void _changePreviewZoom(double factor) {
    setState(() => _previewZoom = (_previewZoom * factor).clamp(0.5, 8.0));
  }

  void _fitPreview() => setState(() {
    _previewZoom = 1;
    _previewPan = Offset.zero;
  });

  void _startPreviewPan(Offset position) {
    _panStart = position;
    _panBase = _previewPan;
  }

  void _updatePreviewPan(Offset position) {
    setState(() => _previewPan = _panBase + position - _panStart);
  }

  void _togglePreviewPanMode() =>
      setState(() => _previewPanMode = !_previewPanMode);

  void _togglePreviewFullscreen() {
    final entering = !_previewFullscreen;
    setState(() {
      _previewFullscreen = entering;
      if (entering) {
        _selectedId = null;
        _selectedBoneId = null;
      }
    });
    SystemChrome.setEnabledSystemUIMode(
      entering ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

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

  /// Insère une animation depuis un projet existant.
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
                  '${summary.shapeCount} élément(s)',
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
    await _insertSubproject(sub);
  }

  /// Importe un fichier JSON VASF et l'insère comme instance de groupe.
  Future<void> _importVasfAsGroup() async {
    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(
        dialogTitle: 'Importer un projet squelette VASF',
        type: FileType.custom,
        allowedExtensions: <String>['json'],
      );
    } catch (error) {
      _snack('Sélecteur de fichiers indisponible : $error');
      return;
    }
    if (picked.isEmpty || !mounted) return;
    try {
      final text = utf8.decode(await picked.first.readAsBytes());
      final raw = jsonDecode(text);
      if (raw is! Map || !raw.containsKey('version')) {
        await _showImportProblems('Un fichier VASF est attendu.');
        return;
      }
      final result = JsonProjectImport.parse(text);
      final sub = result.project;
      if (sub == null) {
        await _showImportProblems(result.error ?? 'VASF invalide');
        return;
      }
      if (!result.isVasf) {
        await _showImportProblems('Le fichier doit être au format JSON VASF.');
        return;
      }
      if (sub.skeleton == null) {
        await _showImportProblems(
          'Ce fichier VASF ne décrit pas un projet squelette.',
        );
        return;
      }
      await widget.repository.save(sub);
      if (!mounted) return;
      await _insertSubproject(sub);
    } catch (error) {
      if (mounted) await _showImportProblems('Fichier illisible : $error');
    }
  }

  Future<void> _showImportProblems(String problems) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Import impossible'),
      content: SingleChildScrollView(child: Text(problems)),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Fermer'),
        ),
      ],
    ),
  );

  Future<void> _insertSubproject(AnimationProject sub) async {
    final project = _project;
    final controller = _controller;
    if (project == null || controller == null) return;
    _pushUndo(); // annuler l'insertion restaure le projet hôte sans instance
    final start = controller.timeMs;
    final shape = VectorShape(
      name: sub.name,
      embeddedProjectId: sub.id,
      embeddedWidth: sub.width,
      embeddedHeight: sub.height,
      embeddedIsSkeleton: sub.skeleton != null,
      x: project.width / 2,
      y: project.height / 2,
      startMs: start,
      endMs: start + math.max(sub.durationMs, 100),
    );
    setState(() {
      project.shapes.add(shape);
      _selectedId = shape.id;
      _selectedBoneId = null;
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
    _dismissTopMessage();
    if (_previewFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
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

  void _snack(String message) => _showTopMessage(message);

  void _showTopMessage(String message) {
    _dismissTopMessage();
    _messageOverlay = OverlayEntry(
      builder: (overlayContext) {
        final top =
            MediaQuery.paddingOf(overlayContext).top +
            (_previewFullscreen ? 8 : kToolbarHeight + 8);
        return Positioned(
          top: top,
          left: 12,
          right: 12,
          child: Material(
            key: const ValueKey<String>('keyform-top-message'),
            color: const Color(0xFF242B3A),
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.only(
                left: 14,
                right: 4,
                top: 4,
                bottom: 4,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.info_outline, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fermer le message',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    onPressed: _dismissTopMessage,
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context, rootOverlay: true).insert(_messageOverlay!);
    _bannerTimer = Timer(const Duration(seconds: 5), _dismissTopMessage);
  }

  void _dismissTopMessage() {
    _bannerTimer?.cancel();
    _bannerTimer = null;
    _messageOverlay?.remove();
    _messageOverlay = null;
  }

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
    final controller = _controller;
    if (project == null) return;
    final edited = await Navigator.of(context).push<VectorShape>(
      MaterialPageRoute<VectorShape>(
        builder: (_) => ShapeEditorScreen(
          project: project,
          shape: shape,
          // Curseur de l'éditeur = playhead courant du studio (v0.16.3) :
          // l'instant scrubé reste affiché dans l'éditeur, l'auto-key
          // morph écrit bien à CET instant (et non à 0 s).
          initialTimeMs: controller?.timeMs,
        ),
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

  /// Couleur d'une couche (v0.15) : base si la forme n'a aucune keyframe,
  /// sinon entrée de couleur dans la pose au curseur (auto-key).
  void _setLayerColor(ShapeLayer layer, int color) {
    final shape = _selected;
    final controller = _controller;
    if (shape == null || controller == null) return;
    _pushUndo(tag: 'layerColor:${shape.id}:${layer.id}');
    setState(() {
      shape.applyLayerColor(
        layer,
        color,
        controller.timeMs,
        autoKey: true,
        toleranceMs: controller.snapToleranceMs,
      );
    });
    _scheduleSave();
  }

  /// Losange de couleur d'une couche (v0.15) : pose la couleur COURANTE
  /// (échantillonnée au curseur) dans la pose au curseur, ou retire
  /// l'entrée de couleur de la pose s'il y en a déjà une.
  void _toggleLayerColor(ShapeLayer layer) {
    final shape = _selected;
    final controller = _controller;
    if (shape == null || controller == null) return;
    _pushUndo(tag: 'layerColor:${shape.id}:${layer.id}');
    setState(() {
      final nearest = shape.keyframeNear(
        controller.timeMs,
        controller.snapToleranceMs,
      );
      if (nearest != null && nearest.layerColors.containsKey(layer.id)) {
        nearest.layerColors.remove(layer.id);
      } else {
        final color = shape.colorAtLayer(
          layer.id,
          controller.timeMs,
          layer.colorValue,
        );
        shape.applyLayerColor(
          layer,
          color,
          controller.timeMs,
          autoKey: true,
          toleranceMs: controller.snapToleranceMs,
        );
      }
    });
    _scheduleSave();
  }

  /// Pivot de rotation (v0.13) : statique, pas d'auto-key — un glisser des
  /// deux sliders coalescé en une seule entrée d'annulation.
  void _setPivot(double dx, double dy) {
    final shape = _selected;
    if (shape == null) return;
    _pushUndo(tag: 'pivot:${shape.id}');
    setState(() {
      shape.pivotDx = dx;
      shape.pivotDy = dy;
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

  /// Miroir H/V du groupe de couches (v0.19) : une pression = une entrée
  /// d'annulation (action discrète, pas de coalescing).
  void _mirrorShape(bool horizontal) {
    final shape = _selected;
    if (shape == null) return;
    _pushUndo();
    setState(() => shape.mirror(horizontal: horizontal));
    _scheduleSave();
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
        onPivotChanged: _setPivot,
        onLayerColorChanged: _setLayerColor,
        onToggleLayerColor: _toggleLayerColor,
        skeletonPiece: project.skeleton?.isAttached(shape.id) ?? false,
        skeletonNote: _bindingNote(shape),
        skeletonRig: project.skeleton,
        onOpenBoneEditor: () => _editShapeBone(shape),
        onDeleteBone: () => _deleteShapeBone(shape),
        onMirror: _mirrorShape,
        allowBoneEditorForInstance: shape.isInstance,
      ),
    );
    if (mounted) setState(() {});
  }

  /// État de liaison d'une pièce au rig, affiché dans sa bottom sheet.
  String? _bindingNote(VectorShape shape) {
    if (shape.isInstance) {
      final rig = _rig;
      final carrier = rig?.boneById(rig.carrierBoneId(shape.id));
      return carrier == null
          ? 'Groupe non lié au rig'
          : 'Groupe lié à l’os « ${carrier.name} »';
    }
    final rig = _rig;
    if (rig == null) return null;
    final boneId = rig.carrierBoneId(shape.id);
    final bone = rig.boneById(boneId);
    return bone == null
        ? 'Pièce non liée au rig (os : —)'
        : 'Pièce liée à l’os « ${bone.name} »';
  }

  // ------------------------------------------------------------- squelette

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
    final geo = _canvasGeometry(project, canvasSize);
    setState(() {
      _translateBoneFollow(
        project,
        rig,
        bone,
        controller,
        details.delta / geo.scale,
        keyframed: true,
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

  // ------------------------------------------------- os d'une forme (v0.20)

  /// Ouvre l'éditeur d'os de [shape] (dessin + déplacement, forme ancrée au
  /// milieu de l'écran) : création ou modification de la chaîne.
  ///
  /// Confirmation AVANT : les transformations d'une pièce sont supprimées à
  /// la liaison. Pour un groupe squelette, toutes ses keyframes de forme sont
  /// supprimées : le segment devient celui de l'os porteur.
  Future<void> _editShapeBone(VectorShape shape) async {
    final project = _project;
    if (project == null) {
      return;
    }
    final transforms = shape.isInstance ? 0 : shape.transformKeyframeCount;
    final groupKeyframes = shape.isInstance ? shape.keyframes.length : 0;
    if (transforms > 0 || groupKeyframes > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            shape.isInstance
                ? 'Lier le groupe à un os ?'
                : 'Lier la pièce à un os ?',
          ),
          content: Text(
            shape.isInstance
                ? '« ${shape.name} » porte $groupKeyframes keyframe(s) de groupe. '
                      'Elles seront toutes supprimées à la liaison ; le segment '
                      'et son animation dépendront ensuite de l’os.'
                : '« ${shape.name} » porte $transforms transformation(s) '
                      'keyframée(s) (position, rotation, échelle). Les lier à un os '
                      'les supprimera — morph, couleurs et opacité sont conservées.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Ouvrir l’éditeur'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    final result = await Navigator.of(context).push<BoneEditorResult>(
      MaterialPageRoute(
        builder: (context) => BoneEditorScreen(
          project: project,
          shape: shape,
          timeMs: _controller?.timeMs ?? 0,
          embeddedProjects: _embedded,
        ),
      ),
    );
    if (result == null || !mounted) return;
    _pushUndo();
    setState(() {
      final rig = project.skeleton ?? SkeletonRig(name: 'Squelette');
      project.skeleton = rig;
      // Les os édités remplacent leurs anciennes versions (mêmes ids →
      // pistes de keyframes conservées), les nouveaux s'ajoutent.
      rig.bones.removeWhere((bone) => result.replacedIds.contains(bone.id));
      rig.bones.addAll(result.bones);
      rig.bindShape(shape.id, result.carrierBoneId);
      if (shape.isInstance) {
        // Un groupe lié suit l'os, sans piste d'animation de forme concurrente.
        shape.keyframes.clear();
      } else {
        shape.clearTransformKeyframes();
      }
      // Sélection exclusive : l'os porte la pièce ou le groupe désormais.
      _selectedBoneId = result.carrierBoneId;
      _selectedId = null;
    });
    await _flushSave();
    final bone = project.skeleton?.boneById(result.carrierBoneId);
    _snack('« ${shape.name} » liée à l’os « ${bone?.name ?? '?'} »');
  }

  /// Ouvre l'éditeur d'os depuis la feuille des PROPRIÉTÉS D'OS (v0.20.2) :
  /// retrouve la forme portée par cet os (racine ou descendance) puis ouvre
  /// le même écran que « Ajouter un os… » de la feuille de la forme.
  Future<void> _editBoneInEditor() async {
    final project = _project;
    final rig = _rig;
    final bone = _selectedBone;
    if (project == null || rig == null || bone == null) return;
    VectorShape? shape;
    for (final candidate in project.shapes) {
      final carrierId = rig.carrierBoneId(candidate.id);
      if (carrierId == null) continue;
      if (rig.chainFrom(carrierId).any((b) => b.id == bone.id)) {
        shape = candidate;
        break;
      }
    }
    if (shape == null) {
      _snack('« ${bone.name} » n’est lié à aucune forme');
      return;
    }
    await _editShapeBone(shape);
  }

  /// « Supprimer l'os » (sheet ⚙, v0.20) : confirmation, puis l'os porteur,
  /// TOUTE sa descendance et la totalité de leurs keyframes partent avec le
  /// lien (la pièce redevient libre et sélectionnable).
  Future<void> _deleteShapeBone(VectorShape shape) async {
    final project = _project;
    final rig = project?.skeleton;
    if (project == null || rig == null) return;
    if (shape.isInstance) {
      final carrier = rig.boneById(rig.carrierBoneId(shape.id));
      final chain = carrier == null
          ? const <RigBone>[]
          : rig.chainFrom(carrier.id);
      var keyframes = 0;
      for (final bone in chain) {
        keyframes += rig.trackOf(bone.id)?.length ?? 0;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Délier le groupe ?'),
          content: Text(
            'Le groupe « ${shape.name} » sera détaché. Les os du rig hôte '
            'restent dans le projet.'
            '${keyframes > 0 ? ' Les $keyframes keyframes associées aux os restent sur le rig.' : ''}',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Délier'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      _pushUndo();
      setState(() => rig.unbindShape(shape.id));
      await _flushSave();
      _snack('Groupe dissocié de l’os');
      return;
    }
    final carrier = rig.boneById(rig.carrierBoneId(shape.id));
    if (carrier == null) return;
    final chain = rig.chainFrom(carrier.id);
    var keyframes = 0;
    for (final bone in chain) {
      keyframes += rig.trackOf(bone.id)?.length ?? 0;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer l’os ?'),
        content: Text(
          'L’os « ${carrier.name} » et sa descendance '
          '(${chain.length} os, $keyframes keyframes) seront supprimés '
          'avec le lien — « ${shape.name} » redevient libre.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _pushUndo();
    setState(() {
      rig.removeBoneForShape(shape.id);
      if (_selectedBoneId != null && rig.boneById(_selectedBoneId) == null) {
        _selectedBoneId = null;
      }
    });
    await _flushSave();
    _snack('Os supprimé (descendance et keyframes compris)');
  }

  /// Autorise une keyframe d'os si le curseur est sur une pièce ou un groupe
  /// qui est attaché à cet os (un groupe squelette a son propre segment).
  bool _boneKeyframeAllowed(RigBone bone, int timeMs) {
    final project = _project;
    final rig = _rig;
    if (project == null || rig == null) return false;
    var attached = false;
    for (final shape in project.shapes) {
      final carrierId = rig.carrierBoneId(shape.id);
      if (carrierId == null ||
          !rig.chainFrom(carrierId).any((item) => item.id == bone.id)) {
        continue;
      }
      attached = true;
      if (shape.isVisibleAt(timeMs)) return true;
    }
    // Os importé sans forme : conserver l'ancien comportement.
    return !attached;
  }

  Future<void> _toggleBoneKeyframe() async {
    final rig = _rig;
    final bone = _selectedBone;
    final controller = _controller;
    if (rig == null || bone == null || controller == null) return;
    if (!_boneKeyframeAllowed(bone, controller.timeMs)) {
      _snack('Le curseur doit être sur le segment de la forme liée');
      return;
    }
    _pushUndo();
    setState(() => controller.toggleBoneKeyframe(rig, bone));
    await _flushSave();
  }

  Future<void> _setBoneEasing(EasingKind easing) async {
    final rig = _rig;
    final bone = _selectedBone;
    final controller = _controller;
    if (rig == null || bone == null || controller == null) return;
    if (!_boneKeyframeAllowed(bone, controller.timeMs)) return;
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
    if (!_boneKeyframeAllowed(bone, controller.timeMs)) return;
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

  /// Miroir de l'os sélectionné et de sa descendance, avec les pièces liées,
  /// autour du centre de la première pièce portée au playhead. Si aucune
  /// pièce n'est liée, l'articulation de l'os sert de pivot.
  void _mirrorBoneChain(RigBone selectedBone, bool horizontal) {
    final project = _project;
    final rig = _rig;
    final controller = _controller;
    if (project == null || rig == null || controller == null) return;
    final subtree = rig.chainFrom(selectedBone.id);
    final ids = <String>{for (final item in subtree) item.id};
    if (ids.isEmpty) return;

    final pose = SkeletonPose.evaluate(rig, controller.timeMs);
    var pivot = pose.frameOf(selectedBone.id)?.joint ?? Offset.zero;
    for (final shape in project.shapes) {
      final carrierId = rig.carrierBoneId(shape.id);
      if (carrierId == null || !ids.contains(carrierId)) continue;
      final frame = pose.frameOf(carrierId);
      if (frame == null) continue;
      pivot = SelectionGeometry.shapePoseWithRig(
        shape,
        controller.timeMs,
        frame,
      ).origin;
      break;
    }

    double reflectX(double x) => horizontal ? 2 * pivot.dx - x : x;
    double reflectY(double y) => horizontal ? y : 2 * pivot.dy - y;
    // Les formes reçoivent le flip du contenu dans leur repère local ; leur
    // rotation de groupe change donc de signe quel que soit l'axe réfléchi.
    double reflectShapeAngle(double angle) => -angle;

    _pushUndo();
    setState(() {
      rig.mirrorSubtree(selectedBone.id, horizontal: horizontal, pivot: pivot);
      for (final shape in project.shapes) {
        final carrierId = rig.carrierBoneId(shape.id);
        if (carrierId == null || !ids.contains(carrierId)) continue;
        final shapeWasAnimated = shape.keyframes.isNotEmpty;
        final baseX = shape.x;
        final baseY = shape.y;
        final baseRotation = shape.rotation;
        shape
          ..x = reflectX(baseX)
          ..y = reflectY(baseY)
          ..rotation = reflectShapeAngle(baseRotation)
          ..pivotDx = horizontal ? -shape.pivotDx : shape.pivotDx
          ..pivotDy = horizontal ? shape.pivotDy : -shape.pivotDy;
        for (final key in shape.keyframes) {
          final x = key.values[AnimatableProperty.x] ?? baseX;
          final y = key.values[AnimatableProperty.y] ?? baseY;
          final angle = key.values[AnimatableProperty.rotation] ?? baseRotation;
          key.values[AnimatableProperty.x] = reflectX(x);
          key.values[AnimatableProperty.y] = reflectY(y);
          key.values[AnimatableProperty.rotation] = reflectShapeAngle(angle);
        }
        if (shapeWasAnimated) {
          // Every keyframe is a complete pose; use base values for sparse
          // properties so mirror animation samples correctly at all times.
          shape
            ..x = reflectX(baseX)
            ..y = reflectY(baseY)
            ..rotation = reflectShapeAngle(baseRotation);
        }
        if (shape.isInstance) {
          if (horizontal) {
            shape.flipH = !shape.flipH;
          } else {
            shape.flipV = !shape.flipV;
          }
        } else if (shape.layers.isNotEmpty) {
          shape.mirror(horizontal: horizontal);
        }
      }
    });
    _scheduleSave();
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
        onOpenEditor: _editBoneInEditor,
        onKeyframeAllowed: (timeMs) => _boneKeyframeAllowed(bone, timeMs),
        onMirror: (horizontal) => _mirrorBoneChain(bone, horizontal),
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
    if (project.skeleton == null) return null;
    return SkeletonPose.evaluate(
      project.skeleton!,
      timeMs,
    ).frameOf(project.skeleton!.carrierBoneId(shape.id));
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
      // La fenêtre start → end du segment contrôle aussi les pièces d'un
      // projet squelette. Les keyframes d'os au-delà du segment ne prolongent
      // pas la visibilité dans le preview.
      if (!shape.isVisibleAt(controller.timeMs)) continue;
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

  /// Translate l'ancrage d'un os de [step] (coordonnées scène).
  /// Os SANS keyframes : pose de repos (translateBoneRest) + emport des
  /// pièces liées à l'os et à sa descendance — l'os suit le doigt ET la
  /// pièce du doigt suit (collée à l'os).
  /// Os ANIMÉ (v0.15) : translation KEYFRAMÉE au curseur (auto-key) — la
  /// pose de repos reste intacte, les pièces liées suivent par la
  /// transformée os(t) aux autres instants.
  void _translateBoneFollow(
    AnimationProject project,
    SkeletonRig rig,
    RigBone bone,
    TimelineController controller,
    Offset step, {

    /// Glisser explicite de l'OS (poignée ✥) : si l'os est animé, écrire une
    /// translation keyframée. Le glisser d'une PIÈCE liée garde la sémantique
    /// repos (translateBoneRest + carry) même quand l'os est animé.
    bool keyframed = false,
  }) {
    if (keyframed &&
        rig.hasKeyframes(bone.id) &&
        !_boneKeyframeAllowed(bone, controller.timeMs)) {
      return;
    }
    if (keyframed && rig.hasKeyframes(bone.id)) {
      final pose = SkeletonPose.evaluate(rig, controller.timeMs);
      final parentFrame = pose.frameOf(bone.parentId);
      final local = parentFrame == null
          ? step
          : rotateVector(step, -parentFrame.worldAngle);
      final snapped =
          rig
              .keyframeNear(
                bone.id,
                controller.timeMs,
                controller.snapToleranceMs,
              )
              ?.timeMs ??
          controller.timeMs;
      final current = rig.translationAt(bone.id, snapped);
      rig.upsertKeyframe(
        bone.id,
        snapped,
        rig.angleDeltaAt(bone.id, snapped),
        tx: current.dx + local.dx,
        ty: current.dy + local.dy,
      );
      return;
    }
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
    // Priorité rig : poignée de rotation de l'os sélectionné uniquement —
    // v0.9.3 : pivoter via l'extrémité de l'os (2e point) est désactivé.
    final rig = project.skeleton;
    if (rig != null && rig.bones.isNotEmpty) {
      final selectedBone = rig.boneById(_selectedBoneId);
      final pose = SkeletonPose.evaluate(rig, controller.timeMs);
      final geo = _canvasGeometry(project, canvasSize);
      // IK (v0.10, généralisé v0.15) : glisser l'EXTRÉMITÉ du dernier os de
      // la chaîne résout toute la chaîne (2 os = solveur analytique, N os =
      // CCD) — prioritaire sur la poignée de rotation. L'os touché est
      // l'effecteur : la racine (ikEnabled) est un ancêtre strict… ou lui-
      // même si sa chaîne va plus loin. v0.10.1 : parent OU effecteur OU
      // aucune sélection — le losange vert est une vraie poignée.
      RigBone? ikParent;
      if (selectedBone != null) {
        if (selectedBone.ikEnabled) {
          // ① L'os sélectionné est une racine IK (v0.10) : le losange est
          // sur l'extrémité du DERNIER os de sa chaîne (descendant).
          ikParent = selectedBone;
        } else {
          // ② L'os sélectionné est l'EFFECTEUR d'une chaîne (v0.15) : la
          // racine (ikEnabled) est un ancêtre strict dont la chaîne
          // d'enfants uniques mène à cet os.
          var current = rig.boneById(selectedBone.parentId);
          while (current != null && ikParent == null) {
            if (current.ikEnabled &&
                rig.ikEffectorOf(current.id)?.id == selectedBone.id) {
              ikParent = current;
            }
            current = rig.boneById(current.parentId);
          }
        }
      }
      if (ikParent != null &&
          _boneVisibleAt(ikParent, controller.timeMs) &&
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
          if (!candidate.ikEnabled ||
              !_boneVisibleAt(candidate, controller.timeMs)) {
            continue;
          }
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
      if (selectedBone != null &&
          _boneVisibleAt(selectedBone, controller.timeMs)) {
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
    final geo = _canvasGeometry(project, canvasSize);
    _gestureBoneFrame = _frameForShape(project, shape, controller.timeMs);
    final pose = SelectionGeometry.shapePoseWithRig(
      shape,
      controller.timeMs,
      _gestureBoneFrame,
    );
    // v0.19.1 : pièce PORTÉE par un os → AUCUN geste de transformation
    // (déplacement, rotation, échelle) : seul l'os la bouge, ou une
    // dissociation (Squelettes ▸ Délier). Le message n'apparaît que si le
    // doigt est posé SUR la pièce (ailleurs = geste ignoré, comme avant).
    // Les gestes d'os (IK, poignée de rotation) sont traités AU-DESSUS et
    // restent libres.
    if (rig != null && rig.isAttached(shape.id) && !shape.isInstance) {
      _gesture = _CanvasGesture.none;
      if (SelectionGeometry.hit(bounds, pose, geo, details.localFocalPoint)) {
        final bone = rig.boneById(rig.carrierBoneId(shape.id));
        _snack(
          '« ${shape.name} » est liée à l’os « ${bone?.name ?? '?'} » : '
          'transformations bloquées — bougez l’os, ou dissociez la pièce '
          '(Squelettes ▸ Délier).',
        );
      }
      return;
    }
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
      // Corps de la forme : déplacement (le verrou des pièces liées est
      // traité plus haut, avant les gestes d'échelle et de rotation).
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
        final root = rig?.boneById(_dragBoneId);
        if (rig == null || root == null || !root.ikEnabled) break;
        final chain = rig.ikChain(root.id);
        if (chain.isEmpty) break;
        final pose = SkeletonPose.evaluate(rig, controller.timeMs);
        final geo = _canvasGeometry(project, canvasSize);
        final target = geo.canvasToScene(details.localFocalPoint);
        List<double> desired;
        if (chain.length == 2) {
          // 2 os : solveur analytique précis (v0.10, coude contrôlé).
          final parentFrame = pose.frameOf(chain[0].id);
          final childFrame = pose.frameOf(chain[1].id);
          if (parentFrame == null || childFrame == null) break;
          final (parentAngle, childAngle) = solveTwoBoneIk(
            joint: parentFrame.joint,
            length1: math.max(1.0, parentFrame.length * parentFrame.stretchX),
            length2: math.max(1.0, childFrame.length * childFrame.stretchX),
            target: target,
            bend: root.bendSign,
          );
          desired = <double>[parentAngle, childAngle];
        } else {
          // N os (v0.15) : CCD itératif sur la chaîne.
          final frames = <BoneFrame>[];
          var missing = false;
          for (final bone in chain) {
            final frame = pose.frameOf(bone.id);
            if (frame == null) {
              missing = true;
              break;
            }
            frames.add(frame);
          }
          if (missing) break;
          desired = solveChainIk(
            rootJoint: frames.first.joint,
            lengths: <double>[
              for (final frame in frames)
                math.max(1.0, frame.length * frame.stretchX),
            ],
            angles: <double>[for (final frame in frames) frame.worldAngle],
            target: target,
          );
        }
        // setState à chaque update : repeint canvas + timeline en direct.
        setState(() {
          _poseChainAnglesTo(project, rig, chain, desired, pose, controller);
        });
        _gestureMutated = true;
      case _CanvasGesture.boneRotate:
        final rig = project.skeleton;
        final bone = rig?.boneById(_dragBoneId);
        if (rig == null || bone == null) break;
        final pose = SkeletonPose.evaluate(rig, controller.timeMs);
        final frame = pose.frameOf(bone.id);
        if (frame == null) break;
        final geo = _canvasGeometry(project, canvasSize);
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
        final geo = _canvasGeometry(project, canvasSize);
        final frame = _gestureBoneFrame;
        final rig = project.skeleton;
        // Pièce liée à un os au repos (pièce non animée) : le glisser
        // déplace l'ANCRAGE de l'os (offset de repos) — l'os suit la pièce,
        // qui reste collée à l'os ; la chaîne descendante suit (offsets
        // relatifs). Delta par pas : l'offset est muté à chaque update.
        if (frame != null &&
            frame.worldDelta == 0 &&
            rig != null &&
            !shape!.isInstance &&
            shape.keyframes.isEmpty) {
          final bone = rig.boneById(rig.carrierBoneId(shape.id));
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
        final geo = _canvasGeometry(project, canvasSize);
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

  /// IK (v0.10 2 os, v0.15 chaînes N os) : pose les angles MONDE désirés de
  /// chaque os de la chaîne (ordre racine → effecteur) — keyframe au curseur
  /// pour un os animé (auto-key), angle de repos sinon (chaque os est posé
  /// DANS l'état APRÈS la mutation de son parent, d'où la ré-évaluation `mid`
  /// à chaque étape). Os posé : les pièces liées sont emportées par la
  /// nouvelle pose de repos.
  void _poseChainAnglesTo(
    AnimationProject project,
    SkeletonRig rig,
    List<RigBone> chain,
    List<double> desiredAngles,
    SkeletonPose before,
    TimelineController controller,
  ) {
    assert(chain.length == desiredAngles.length);
    for (var i = 0; i < chain.length; i++) {
      final bone = chain[i];
      final mid = SkeletonPose.evaluate(rig, controller.timeMs);
      final frame = mid.frameOf(bone.id);
      final parentFrame = mid.frameOf(bone.parentId);
      if (frame == null) continue;
      final delta =
          desiredAngles[i] -
          frame.worldAngleRest -
          (parentFrame?.worldDelta ?? 0);
      if (rig.hasKeyframes(bone.id)) {
        final target =
            rig
                .keyframeNear(
                  bone.id,
                  controller.timeMs,
                  controller.snapToleranceMs,
                )
                ?.timeMs ??
            controller.timeMs;
        rig.upsertKeyframe(bone.id, target, delta);
      } else {
        bone.restAngle = desiredAngles[i] - (parentFrame?.worldAngle ?? 0);
      }
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

  /// Tap sur le canvas : sélection d'os d'abord (extrémités/segments),
  /// puis sélection de forme (du premier plan vers l'arrière-plan).
  void _onCanvasTapUp(
    TapUpDetails details,
    AnimationProject project,
    TimelineController controller,
    Size canvasSize,
  ) {
    final geo = _canvasGeometry(project, canvasSize);
    // Sélection d'os d'abord (mode squelette) — exclusive avec la pièce :
    // soit un os, soit une forme (jamais les deux).
    final rig = project.skeleton;
    if (rig != null && rig.bones.isNotEmpty) {
      final pose = SkeletonPose.evaluate(rig, controller.timeMs);
      final boneId = RigOverlayPainter.hitBone(
        pose,
        rig,
        geo,
        details.localPosition,
        isVisible: (candidate) => _boneVisibleAt(candidate, controller.timeMs),
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
      // v0.19.1 : une pièce PORTÉE par un os n'est plus sélectionnable au
      // doigt (aucune manipulation possible) — elle reste choisissable via
      // le menu Formes pour l'ouvrir dans la sheet ⚙ ou la délier.
      if (rig != null && rig.isAttached(hit.id) && !hit.isInstance) {
        final bone = rig.boneById(rig.carrierBoneId(hit.id));
        _snack(
          '« ${hit.name} » est liée à l’os « ${bone?.name ?? '?'} » : '
          'non sélectionnable — bougez l’os, ou choisissez-la dans le menu '
          'Formes (Squelettes ▸ Délier pour libérer).',
        );
        return;
      }
      setState(() {
        _selectedId = hit.id;
        _selectedBoneId = null;
      });
    }
  }

  /// Dialogue des options avant export : fps et définition MP4.
  Future<({int fps, int? resolution})?> _askExportOptions(
    VideoFormat format,
  ) async {
    final fpsChoices = format == VideoFormat.mp4
        ? <int>[15, 24, 25, 30, 60]
        : <int>[10, 12, 15, 25];
    final project = _project;
    final initialFps = format == VideoFormat.mp4 ? (project?.fps ?? 30) : 12;
    var selectedFps = fpsChoices.contains(initialFps)
        ? initialFps
        : fpsChoices.last;
    var selectedResolution = 720;
    return showDialog<({int fps, int? resolution})>(
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
                '${((project?.durationMs ?? 0) / 1000).toStringAsFixed(2)} s',
                style: const TextStyle(fontSize: 12),
              ),
              if (format == VideoFormat.mp4) ...<Widget>[
                const SizedBox(height: 14),
                const Text('Résolution vidéo'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    for (final choice in mp4ResolutionPresets)
                      ChoiceChip(
                        label: Text('${choice}p'),
                        selected: choice == selectedResolution,
                        onSelected: (_) =>
                            setDialogState(() => selectedResolution = choice),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                if (project != null)
                  Text(
                    _resolutionDimensions(project, selectedResolution),
                    style: const TextStyle(fontSize: 11, color: Colors.white60),
                  ),
              ],
              const SizedBox(height: 14),
              const Text('Images par seconde'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final choice in fpsChoices)
                    ChoiceChip(
                      label: Text('$choice fps'),
                      selected: choice == selectedFps,
                      onSelected: (_) =>
                          setDialogState(() => selectedFps = choice),
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
              onPressed: () => Navigator.of(context).pop((
                fps: selectedFps,
                resolution: format == VideoFormat.mp4
                    ? selectedResolution
                    : null,
              )),
              child: const Text('Exporter'),
            ),
          ],
        ),
      ),
    );
  }

  String _resolutionDimensions(AnimationProject project, int longEdge) {
    final size = mp4DimensionsForLongEdge(project, longEdge);
    return '${size.width}×${size.height} px · proportions du projet conservées';
  }

  // ----------------------------------------------------------------- export

  Future<void> _exportVideo(VideoFormat format) async {
    final project = _project;
    if (project == null) return;
    final options = await _askExportOptions(format);
    if (options == null || !mounted) return;
    final fps = options.fps;
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
        width: options.resolution == null
            ? null
            : mp4WidthForLongEdge(project, options.resolution!),
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
      canPop: !_previewFullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (_previewFullscreen) {
          if (!didPop) _togglePreviewFullscreen();
        } else if (didPop) {
          _flushSave();
        }
      },
      child: Scaffold(
        appBar: _previewFullscreen
            ? null
            : AppBar(
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
                if (_previewFullscreen) {
                  return SafeArea(
                    child: SizedBox.expand(
                      child: _buildCanvas(project, controller),
                    ),
                  );
                }
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
      margin: _previewFullscreen
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0D12),
        borderRadius: _previewFullscreen
            ? BorderRadius.zero
            : BorderRadius.circular(16),
        border: _previewFullscreen
            ? null
            : Border.all(color: const Color(0xFF232733)),
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
                    onScaleStart: (_previewFullscreen || _previewPanMode)
                        ? null
                        : (details) => _onCanvasGestureStart(
                            details,
                            project,
                            controller,
                            canvasSize,
                          ),
                    onScaleUpdate: (_previewFullscreen || _previewPanMode)
                        ? null
                        : (details) => _onCanvasGestureUpdate(
                            details,
                            project,
                            controller,
                            canvasSize,
                          ),
                    onScaleEnd: (_previewFullscreen || _previewPanMode)
                        ? null
                        : _onCanvasGestureEnd,
                    onPanStart: _previewPanMode
                        ? (details) => _startPreviewPan(details.localPosition)
                        : null,
                    onPanUpdate: _previewPanMode
                        ? (details) => _updatePreviewPan(details.localPosition)
                        : null,
                    onTapUp: (details) {
                      if (!_previewFullscreen && !_previewPanMode) {
                        _onCanvasTapUp(
                          details,
                          project,
                          controller,
                          canvasSize,
                        );
                      }
                    },
                    child: CustomPaint(
                      painter: ScenePainter(
                        project: project,
                        timeMs: controller.timeMs,
                        selectedShapeId: _previewFullscreen
                            ? null
                            : _selectedId,
                        selectedBoneId: _previewFullscreen
                            ? null
                            : _selectedBoneId,
                        showFrame: true,
                        embeddedProjects: _embedded,
                        previewZoom: _previewZoom,
                        previewPan: _previewPan,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
              if (project.skeleton != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: RigOverlayPainter(
                        rig: project.skeleton!,
                        pose: SkeletonPose.evaluate(
                          project.skeleton!,
                          controller.timeMs,
                        ),
                        geo: _canvasGeometry(project, canvasSize),
                        selectedBoneId:
                            _selectedBoneIsVisible(controller.timeMs)
                            ? _selectedBoneId
                            : null,
                        showOnlySelected: true,
                        visibleBoneIds: _visibleBonesForSelectedGroup(
                          controller.timeMs,
                        ),
                      ),
                    ),
                  ),
                ),
              if (!_previewFullscreen &&
                  shape != null &&
                  shape.isVisibleAt(controller.timeMs))
                _buildPropertiesButton(shape, controller, canvasSize),
              // Os sélectionné : ⚙ propriétés + ✥ déplacement (comme pour
              // les formes, ancrés au segment).
              if (!_previewFullscreen &&
                  bone != null &&
                  _selectedBoneIsVisible(controller.timeMs))
                _buildBoneButtons(project, controller, canvasSize),
              Positioned(right: 8, top: 8, child: _buildPreviewControls()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPreviewControls() => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xCC151922),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          tooltip: _previewPanMode
              ? 'Désactiver le déplacement de la vue'
              : 'Déplacer la vue',
          isSelected: _previewPanMode,
          visualDensity: VisualDensity.compact,
          onPressed: _togglePreviewPanMode,
          icon: Icon(
            _previewPanMode ? Icons.pan_tool : Icons.pan_tool_outlined,
            size: 18,
          ),
        ),
        IconButton(
          tooltip: 'Zoom arrière du preview',
          visualDensity: VisualDensity.compact,
          onPressed: () => _changePreviewZoom(1 / 1.2),
          icon: const Icon(Icons.zoom_out, size: 20),
        ),
        Text(
          '${(_previewZoom * 100).round()}%',
          style: const TextStyle(fontSize: 11),
        ),
        IconButton(
          tooltip: 'Zoom avant du preview',
          visualDensity: VisualDensity.compact,
          onPressed: () => _changePreviewZoom(1.2),
          icon: const Icon(Icons.zoom_in, size: 20),
        ),
        IconButton(
          tooltip: 'Ajuster le preview',
          visualDensity: VisualDensity.compact,
          onPressed: _fitPreview,
          icon: const Icon(Icons.fit_screen_outlined, size: 18),
        ),
        IconButton(
          tooltip: _previewFullscreen
              ? 'Quitter le plein écran'
              : 'Plein écran',
          visualDensity: VisualDensity.compact,
          onPressed: _togglePreviewFullscreen,
          icon: Icon(
            _previewFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
            size: 20,
          ),
        ),
      ],
    ),
  );

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
      return const Positioned(
        left: 0,
        top: 0,
        width: 0,
        height: 0,
        child: SizedBox.shrink(),
      );
    }
    final geo = _canvasGeometry(project, canvasSize);
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
    // Ce widget est dans un Stack : rester positionné même si toutes les
    // couches de la forme sont masquées. Un enfant shrink non-positionné
    // peut sinon participer au calcul de taille du Stack et écraser le preview.
    if (project == null || bounds == null || canvasSize.isEmpty) {
      return const Positioned(
        left: 0,
        top: 0,
        width: 0,
        height: 0,
        child: SizedBox.shrink(),
      );
    }
    final geo = _canvasGeometry(project, canvasSize);
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
                      onSelect: (shape) => setState(() {
                        _selectedId = shape.id;
                        _selectedBoneId = null;
                      }),
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
                      skeletonRig: project.skeleton,
                      selectedBoneId: _selectedBoneId,
                      // Sélection depuis le segment (v0.21.0) : un segment
                      // LIÉ sélectionne l'OS dans le preview (sélection
                      // exclusive — la pièce n'est plus sélectionnable).
                      onSelectBone: (bone) => setState(() {
                        _selectedBoneId = bone.id;
                        _selectedId = null;
                      }),
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
    final rig = _rig;
    final shape = _selected;
    final bone = _selectedBone;
    final keyframe = shape == null ? null : controller.nearestKeyframe(shape);
    // Projet squelette : le ◆ cible l'OS sélectionné s'il y en a un, sinon la
    // PIÈCE sélectionnée (bugfix v0.16.1 — avant, le ◆ no-opait dès qu'une
    // pièce remplaçait un os : aucune pose de pièce n'était créable).
    final boneSelected = bone != null;
    final boneKeyframeAllowed = boneSelected
        ? _boneKeyframeAllowed(bone, controller.timeMs)
        : false;
    final boneKeyframe = boneSelected && rig != null
        ? controller.nearestBoneKeyframe(rig, bone)
        : null;
    final hasKeyframes = boneSelected
        ? (rig != null && rig.hasKeyframes(bone.id))
        : (shape?.hasKeyframes ?? false);
    final diamondKeyframe = boneSelected ? boneKeyframe : keyframe;
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
          ...<Widget>[
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
              tooltip: boneSelected && !boneKeyframeAllowed
                  ? 'Keyframe d’os indisponible hors du segment'
                  : diamondKeyframe != null
                  ? 'Retirer la keyframe au curseur'
                  : boneSelected
                  ? 'Ajouter une keyframe d’angle à l’os au curseur'
                  : 'Ajouter une keyframe au curseur',
              onPressed: boneSelected
                  ? (boneKeyframeAllowed ? _toggleBoneKeyframe : null)
                  : _toggleKeyframe,
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

  /// Actions fréquentes regroupées en bas ; l'export occasionnel reste en haut.
  Widget _buildToolbar(AnimationProject project) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
        decoration: const BoxDecoration(
          color: Color(0xFF11141B),
          border: Border(top: BorderSide(color: Color(0xFF282D38))),
        ),
        child: Row(
          children: <Widget>[
            _toolbarButton(
              icon: Icons.category_outlined,
              label: 'Éléments',
              onPressed: () => _showElementsSheet(project),
            ),
            _toolbarButton(
              icon: Icons.animation,
              label: 'Animation',
              onPressed: _showAnimationSheet,
            ),
            _toolbarButton(
              icon: Icons.accessibility_new,
              label: 'Os',
              onPressed: () => _showRigSheet(project),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbarButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) => Expanded(
    child: TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
  );

  Future<void> _showToolSheet({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFF151922),
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: <Widget>[
                  Icon(icon, color: Theme.of(sheetContext).colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _toolSection(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 1.1,
        color: Colors.white54,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _toolAction(
    BuildContext sheetContext, {
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback? onTap,
    bool destructive = false,
  }) => ListTile(
    leading: Icon(icon, color: destructive ? Colors.redAccent : null),
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle),
    enabled: onTap != null,
    onTap: onTap == null
        ? null
        : () {
            Navigator.of(sheetContext).pop();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) onTap();
            });
          },
  );

  Future<void> _showElementsSheet(AnimationProject project) => _showToolSheet(
    title: 'Éléments',
    icon: Icons.category_outlined,
    children: <Widget>[
      _toolSection('Ajouter'),
      Builder(
        builder: (sheetContext) => _toolAction(
          sheetContext,
          icon: Icons.add,
          title: 'Ajouter une forme…',
          onTap: _addShape,
        ),
      ),
      Builder(
        builder: (sheetContext) => _toolAction(
          sheetContext,
          icon: Icons.movie_outlined,
          title: 'Insérer une animation…',
          onTap: _insertAnimation,
        ),
      ),
      Builder(
        builder: (sheetContext) => _toolAction(
          sheetContext,
          icon: Icons.file_open_outlined,
          title: 'Importer un VASF comme groupe…',
          onTap: _importVasfAsGroup,
        ),
      ),
      _toolSection('Dans le projet · ${project.shapes.length} éléments'),
      if (project.shapes.isEmpty)
        const ListTile(
          leading: Icon(Icons.layers_clear_outlined),
          title: Text('Aucun élément pour le moment'),
        ),
      for (final shape in project.shapes.reversed)
        Builder(
          builder: (sheetContext) => ListTile(
            leading: Icon(
              shape.id == _selectedId
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: shape.visible ? null : Colors.white38,
            ),
            title: Text(
              shape.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${shape.visible ? 'Visible' : 'Masqué'} · '
              '${(shape.durationMs / 1000).toStringAsFixed(1)} s · '
              '${shape.layers.length} couche(s)',
            ),
            trailing: IconButton(
              tooltip: shape.visible ? 'Masquer' : 'Afficher',
              icon: Icon(
                shape.visible ? Icons.visibility : Icons.visibility_off,
              ),
              onPressed: () => _toggleVisibility(shape),
            ),
            onTap: () {
              Navigator.of(sheetContext).pop();
              setState(() {
                _selectedId = shape.id;
                _selectedBoneId = null;
              });
            },
          ),
        ),
      if (_selected != null) ...<Widget>[
        _toolSection('Élément sélectionné · ${_selected!.name}'),
        Builder(
          builder: (sheetContext) => _toolAction(
            sheetContext,
            icon: Icons.tune,
            title: 'Propriétés',
            onTap: () {
              Navigator.of(sheetContext).pop();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _showPropertiesSheet();
              });
            },
          ),
        ),
        if (!_selected!.isInstance)
          Builder(
            builder: (sheetContext) => _toolAction(
              sheetContext,
              icon: Icons.edit_outlined,
              title: 'Modifier les couches',
              onTap: () => _editShape(_selected!),
            ),
          ),
        Builder(
          builder: (sheetContext) => _toolAction(
            sheetContext,
            icon: Icons.drive_file_rename_outline,
            title: 'Renommer',
            onTap: () => _renameShape(_selected!),
          ),
        ),
        Builder(
          builder: (sheetContext) => _toolAction(
            sheetContext,
            icon: Icons.content_copy,
            title: 'Dupliquer avec les keyframes',
            onTap: () => _cloneShape(_selected!),
          ),
        ),
        Builder(
          builder: (sheetContext) => _toolAction(
            sheetContext,
            icon: Icons.vertical_align_top,
            title: 'Monter dans l’ordre d’affichage',
            onTap: () => _moveShape(_selected!, 1),
          ),
        ),
        Builder(
          builder: (sheetContext) => _toolAction(
            sheetContext,
            icon: Icons.vertical_align_bottom,
            title: 'Descendre dans l’ordre d’affichage',
            onTap: () => _moveShape(_selected!, -1),
          ),
        ),
        Builder(
          builder: (sheetContext) => _toolAction(
            sheetContext,
            icon: Icons.delete_outline,
            title: 'Supprimer',
            destructive: true,
            onTap: () => _deleteShape(_selected!),
          ),
        ),
      ],
    ],
  );

  Future<void> _showAnimationSheet() {
    final shape = _selected;
    return _showToolSheet(
      title: 'Animation',
      icon: Icons.animation,
      children: <Widget>[
        if (shape == null)
          const ListTile(
            leading: Icon(Icons.touch_app_outlined),
            title: Text('Sélectionne un élément pour l’animer'),
          )
        else ...<Widget>[
          _toolSection('Animations rapides · ${shape.name}'),
          for (final preset in AnimationPreset.values)
            Builder(
              builder: (sheetContext) => _toolAction(
                sheetContext,
                icon: preset.icon,
                title: preset.label,
                subtitle: preset.description,
                onTap: () => _applyPreset(preset),
              ),
            ),
          _toolSection('Autres actions'),
          Builder(
            builder: (sheetContext) => _toolAction(
              sheetContext,
              icon: Icons.delete_sweep_outlined,
              title: 'Effacer les animations de cet élément',
              onTap: _clearAnimations,
              destructive: true,
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'La pose au curseur se gère avec ◆ dans la barre de lecture.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _showRigSheet(AnimationProject project) {
    final rig = project.skeleton;
    final shape = _selected;
    final bone = _selectedBone;
    final children = <Widget>[
      _toolSection('Élément sélectionné'),
      if (shape == null)
        const ListTile(
          leading: Icon(Icons.touch_app_outlined),
          title: Text('Sélectionne un élément pour créer ou gérer son os'),
        )
      else ...<Widget>[
        ListTile(
          leading: Icon(
            rig?.isAttached(shape.id) == true ? Icons.link : Icons.link_off,
          ),
          title: Text(shape.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(_bindingNote(shape) ?? 'Aucun os associé'),
        ),
        Builder(
          builder: (sheetContext) => _toolAction(
            sheetContext,
            icon: Icons.add_link,
            title: rig?.isAttached(shape.id) == true
                ? 'Modifier l’os de cet élément'
                : 'Créer et lier un os',
            subtitle: 'Ouvrir l’éditeur d’os',
            onTap: () => _editShapeBone(shape),
          ),
        ),
        if (rig?.isAttached(shape.id) == true)
          Builder(
            builder: (sheetContext) => _toolAction(
              sheetContext,
              icon: Icons.link_off,
              title: 'Délier et supprimer cet os',
              subtitle: 'L’élément redevient libre',
              destructive: true,
              onTap: () => _deleteShapeBone(shape),
            ),
          ),
      ],
      _toolSection('Os du projet · ${rig?.bones.length ?? 0}'),
      if (rig == null || rig.bones.isEmpty)
        const ListTile(
          leading: Icon(Icons.accessibility_new_outlined),
          title: Text('Aucun os créé'),
          subtitle: Text('Choisis un élément pour commencer.'),
        ),
      if (rig != null)
        for (final item in rig.bones)
          Builder(
            builder: (sheetContext) => ListTile(
              leading: Icon(
                item.id == _selectedBoneId
                    ? Icons.radio_button_checked
                    : Icons.accessibility_new,
                color: item.id == _selectedBoneId
                    ? const Color(0xFF3ECF8E)
                    : null,
              ),
              title: Text(item.name),
              subtitle: Text(item.parentId == null ? 'Os racine' : 'Os enfant'),
              trailing: IconButton(
                tooltip: 'Propriétés de ${item.name}',
                icon: const Icon(Icons.tune),
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  setState(() {
                    _selectedBoneId = item.id;
                    _selectedId = null;
                  });
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _showBoneSheet();
                  });
                },
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                setState(() {
                  _selectedBoneId = item.id;
                  _selectedId = null;
                });
              },
            ),
          ),
      if (bone != null)
        Builder(
          builder: (sheetContext) => _toolAction(
            sheetContext,
            icon: Icons.tune,
            title: 'Propriétés de l’os sélectionné · ${bone.name}',
            onTap: () {
              Navigator.of(sheetContext).pop();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _showBoneSheet();
              });
            },
          ),
        ),
    ];
    return _showToolSheet(
      title: 'Os',
      icon: Icons.accessibility_new,
      children: children,
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
      ],
    );
  }
}
