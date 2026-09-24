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
import '../engine/scene_painter.dart';
import '../engine/selection_geometry.dart';
import '../engine/timeline_controller.dart';
import '../engine/timeline_zoom.dart';
import '../models/animation.dart';
import 'shape_editor_screen.dart';
import 'shape_properties_sheet.dart';
import 'timeline_view.dart';

/// Geste en cours sur le canvas.
enum _CanvasGesture { none, move, scale, rotate }

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

  // Option : aimanter la rotation aux multiples de 90° (bouton de la barre).
  bool _snapRotation = false;

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
        _zoom = TimelineZoomState(durationMs: project.durationMs);
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
        builder: (_) => StudioScreen(projectId: id, repository: widget.repository),
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

  void _snack(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

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
    setState(() {
      project.shapes.remove(shape);
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
    setState(() => shape.name = name.trim());
    await _flushSave();
  }

  Future<void> _toggleVisibility(VectorShape shape) async {
    setState(() => shape.visible = !shape.visible);
    await _flushSave();
  }

  Future<void> _moveShape(VectorShape shape, int delta) async {
    final project = _project;
    if (project == null) return;
    final index = project.shapes.indexWhere((s) => s.id == shape.id);
    if (index < 0) return;
    setState(() => project.moveShape(index, index + delta));
    await _flushSave();
  }

  // ------------------------------------------------------------ animations

  Future<void> _applyPreset(AnimationPreset preset) async {
    final shape = _selected;
    if (shape == null) return;
    setState(() => applyPreset(shape, preset));
    await _flushSave();
  }

  Future<void> _clearAnimations() async {
    final shape = _selected;
    if (shape == null) return;
    setState(() => clearAnimations(shape));
    await _flushSave();
  }

  /// Ajoute ou retire la keyframe (pose complète) au curseur.
  Future<void> _toggleKeyframe() async {
    final shape = _selected;
    final controller = _controller;
    if (shape == null || controller == null) return;
    setState(() => controller.toggleKeyframe(shape));
    await _flushSave();
  }

  /// Écrit une propriété : dans la pose au curseur si la forme est animée,
  /// sinon dans la valeur de base (auto-key).
  void _setProperty(AnimatableProperty property, double value) {
    final shape = _selected;
    final controller = _controller;
    if (shape == null || controller == null) return;
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
    setState(() => shape.applyValue(
          property,
          value,
          controller.timeMs,
          autoKey: true,
          toleranceMs: controller.snapToleranceMs,
        ));
  }

  void _onCanvasGestureStart(
    ScaleStartDetails details,
    AnimationProject project,
    TimelineController controller,
    Size canvasSize,
  ) {
    _gestureStartPoint = details.localFocalPoint;
    final shape = _selected;
    final bounds = shape == null
        ? null
        : ScenePainter.shapeBounds(shape, controller.timeMs);
    if (shape == null || bounds == null) {
      _gesture = _CanvasGesture.none;
      return;
    }
    final geo = SceneGeometry.fitFor(project, canvasSize);
    final pose = SelectionGeometry.shapePose(shape, controller.timeMs);
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
    _gestureBaseRotation =
        shape.valueAt(AnimatableProperty.rotation, controller.timeMs);
    _gestureBaseScale =
        shape.valueAt(AnimatableProperty.scale, controller.timeMs);
  }

  void _onCanvasGestureUpdate(
    ScaleUpdateDetails details,
    AnimationProject project,
    TimelineController controller,
    Size canvasSize,
  ) {
    final shape = _selected;
    if (shape == null || _gesture == _CanvasGesture.none) return;
    switch (_gesture) {
      case _CanvasGesture.move:
        final geo = SceneGeometry.fitFor(project, canvasSize);
        final sceneDelta = geo.canvasToScene(details.localFocalPoint) -
            geo.canvasToScene(_gestureStartPoint);
        _applyGestureValue(shape, controller, AnimatableProperty.x,
            _gestureBaseX + sceneDelta.dx);
        _applyGestureValue(shape, controller, AnimatableProperty.y,
            _gestureBaseY + sceneDelta.dy);
      case _CanvasGesture.scale:
        final next = (_gestureBaseScale * details.scale).clamp(0.05, 4.0);
        _applyGestureValue(
            shape, controller, AnimatableProperty.scale, next.toDouble());
      case _CanvasGesture.rotate:
        final geo = SceneGeometry.fitFor(project, canvasSize);
        final pose = SelectionGeometry.shapePose(shape, controller.timeMs);
        final center = SelectionGeometry.center(pose, geo);
        final angle = math.atan2(
          details.localFocalPoint.dy - center.dy,
          details.localFocalPoint.dx - center.dx,
        );
        var next = _gestureBaseRotation + (angle - _gestureStartAngle);
        if (_snapRotation) next = _snapAngle(next);
        _applyGestureValue(
            shape, controller, AnimatableProperty.rotation, next);
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
    if (_gesture != _CanvasGesture.none) _scheduleSave();
    _gesture = _CanvasGesture.none;
  }

  /// Tap sur une forme : la sélectionne (du premier plan vers l'arrière-plan).
  void _onCanvasTapUp(
    TapUpDetails details,
    AnimationProject project,
    TimelineController controller,
    Size canvasSize,
  ) {
    final geo = SceneGeometry.fitFor(project, canvasSize);
    for (final shape in project.shapes.reversed) {
      if (!shape.isVisibleAt(controller.timeMs)) continue;
      final bounds = ScenePainter.shapeBounds(shape, controller.timeMs);
      if (bounds == null) continue;
      if (SelectionGeometry.hit(
        bounds,
        SelectionGeometry.shapePose(shape, controller.timeMs),
        geo,
        details.localPosition,
      )) {
        setState(() => _selectedId = shape.id);
        return;
      }
    }
  }

  // ----------------------------------------------------------------- export

  Future<void> _exportVideo(VideoFormat format) async {
    final project = _project;
    if (project == null) return;
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
            child: Text('Projet illisible :\n$_error', textAlign: TextAlign.center),
          ),
        ),
      );
    }
    if (project == null || controller == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _flushSave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(project.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: <Widget>[
            _exportMenu(),
          ],
        ),
        body: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return LayoutBuilder(
              builder: (context, constraints) {
                // Le preview prend ~40 % de la hauteur : le reste va à la
                // barre de lecture, à la timeline et à la barre d'outils.
                final previewHeight =
                    (constraints.maxHeight * 0.40).clamp(200.0, 380.0);
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
                        details, project, controller, canvasSize),
                    onScaleUpdate: (details) => _onCanvasGestureUpdate(
                        details, project, controller, canvasSize),
                    onScaleEnd: _onCanvasGestureEnd,
                    onTapUp: (details) =>
                        _onCanvasTapUp(details, project, controller, canvasSize),
                    child: CustomPaint(
                      painter: ScenePainter(
                        project: project,
                        timeMs: controller.timeMs,
                        selectedShapeId: _selectedId,
                        showFrame: true,
                        embeddedProjects: _embedded,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
              if (shape != null && shape.isVisibleAt(controller.timeMs))
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

  Widget _buildTimeline(AnimationProject project, TimelineController controller) {
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
                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                  icon: const Icon(Icons.zoom_in, size: 18),
                  onPressed: () => setState(zoom.zoomIn),
                ),
                IconButton(
                  tooltip: 'Zoom arrière',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                  icon: const Icon(Icons.zoom_out, size: 18),
                  onPressed: () => setState(zoom.zoomOut),
                ),
                IconButton(
                  tooltip: 'Ajuster au projet',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
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
                      onDeleteKeyframe: (shape, timeMs) {
                        setState(() => shape.removeKeyframeAt(timeMs));
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
    final shape = _selected;
    final keyframe = shape == null ? null : controller.nearestKeyframe(shape);
    final hasKeyframes = shape?.hasKeyframes ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
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
            tooltip: keyframe == null
                ? 'Ajouter une keyframe au curseur'
                : 'Retirer la keyframe au curseur',
            onPressed: _toggleKeyframe,
            icon: Icon(
              keyframe == null ? Icons.diamond_outlined : Icons.diamond,
              color: hasKeyframes ? const Color(0xFFF2C94C) : null,
            ),
          ),
          IconButton(
            tooltip: 'Boucle',
            onPressed: () => controller.setLoop(!controller.loop),
            icon: Icon(controller.loop ? Icons.repeat_on : Icons.repeat),
          ),
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

  /// Barre d'outils en bas : menus Formes, Animations, Calques.
  Widget _buildToolbar(AnimationProject project) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(
        children: <Widget>[
          _shapesMenu(project),
          _animationsMenu(),
          _layersMenu(project),
          const Spacer(),
          Text(
            '${project.shapes.length} forme(s)',
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
        PopupMenuItem<String>(value: 'clipboard', child: Text('Copier le JSON')),
      ],
    );
  }
}
