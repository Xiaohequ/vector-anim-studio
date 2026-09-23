import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../data/project_repository.dart';
import '../engine/animation_presets.dart';
import '../engine/export_service.dart';
import '../engine/scene_painter.dart';
import '../engine/timeline_controller.dart';
import '../models/animation.dart';
import 'shape_editor_screen.dart';
import 'timeline_view.dart';

/// Éditeur d'un projet : canvas, inspecteur, timeline, menus Formes/Animations.
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
      setState(() {
        _project = project;
        _controller = TimelineController(project);
        _selectedId = project.shapes.isEmpty ? null : project.shapes.last.id;
      });
      _syncTicker();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
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
      final service = ExportService(project);
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
      final file = await ExportService(project).exportFramePng(controller.timeMs);
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
            _shapesMenu(project),
            _animationsMenu(),
            _layersMenu(project),
            _exportMenu(),
          ],
        ),
        body: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return Column(
              children: <Widget>[
                Expanded(child: _buildCanvas(project, controller)),
                _buildInspector(project, controller),
                _buildTimeline(project, controller),
                _buildPlaybar(project, controller),
              ],
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
      child: InteractiveViewer(
        maxScale: 5,
        child: Center(
          child: AspectRatio(
            aspectRatio: project.width / project.height,
            child: CustomPaint(
              painter: ScenePainter(
                project: project,
                timeMs: controller.timeMs,
                selectedShapeId: _selectedId,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInspector(AnimationProject project, TimelineController controller) {
    final shape = _selected;
    if (shape == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text('Aucune forme — commence par « Formes › Ajouter une forme ».'),
      );
    }
    final keyframe = controller.nearestKeyframe(shape);
    final hasKeyframes = shape.hasKeyframes;
    return SizedBox(
      height: 196,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  shape.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: keyframe == null
                    ? 'Ajouter une keyframe au curseur'
                    : 'Retirer la keyframe au curseur',
                iconSize: 20,
                icon: Icon(
                  keyframe == null ? Icons.diamond_outlined : Icons.diamond,
                  color: hasKeyframes ? const Color(0xFFF2C94C) : null,
                ),
                onPressed: _toggleKeyframe,
              ),
              TextButton.icon(
                onPressed: () => _editShape(shape),
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
                child: Text('Interpolation', style: TextStyle(fontSize: 12)),
              ),
              Expanded(
                child: DropdownButton<EasingKind>(
                  isExpanded: true,
                  value: keyframe?.easing ?? EasingKind.easeInOut,
                  onChanged: keyframe == null
                      ? null
                      : (value) {
                          if (value != null) _setKeyframeEasing(value);
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
    );
  }

  Widget _buildPropertyRow(
    VectorShape shape,
    AnimatableProperty property,
    TimelineController controller,
  ) {
    final value = shape.valueAt(property, controller.timeMs);
    final (min, max, step) = switch (property) {
      AnimatableProperty.x => (0.0, _project!.width, 1.0),
      AnimatableProperty.y => (0.0, _project!.height, 1.0),
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
          child: Text(propertyLabel(property), style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: Slider(
            min: min,
            max: max,
            divisions: ((max - min) / step).round().clamp(1, 2000),
            value: value.clamp(min, max),
            onChanged: (next) => _setProperty(property, next),
          ),
        ),
        SizedBox(
          width: 32,
          child: Tooltip(
            message: animated ? 'Propriété animée' : 'Valeur fixe',
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

  Widget _buildTimeline(AnimationProject project, TimelineController controller) {
    return Container(
      height: 110,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: const Color(0xFF151922),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${(controller.timeMs / 1000).toStringAsFixed(2)} s'
            ' / ${(project.durationMs / 1000).toStringAsFixed(2)} s'
            ' · ${project.fps} fps',
            style: const TextStyle(fontSize: 11),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: SingleChildScrollView(
              child: TimelineView(
                project: project,
                timeMs: controller.timeMs,
                selectedShapeId: _selectedId,
                onSelect: (shape) => setState(() => _selectedId = shape.id),
                onSeek: controller.setTime,
                onRangeChanged: (shape, start, end) {
                  setState(() {
                    shape.startMs = start;
                    shape.endMs = end;
                  });
                  _scheduleSave();
                },
                onDeleteKeyframe: (shape, timeMs) {
                  setState(() => shape.removeKeyframeAt(timeMs));
                  _scheduleSave();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybar(AnimationProject project, TimelineController controller) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Row(
        children: <Widget>[
          IconButton(
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
            onPressed: () => controller.setLoop(!controller.loop),
            icon: Icon(controller.loop ? Icons.repeat_on : Icons.repeat),
          ),
          const Spacer(),
          Text('${project.shapes.length} forme(s)', style: const TextStyle(fontSize: 12)),
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
        } else if (value.startsWith('select:')) {
          setState(() => _selectedId = value.substring(7));
        } else if (value == 'edit') {
          final shape = _selected;
          if (shape != null) _editShape(shape);
        } else if (value == 'rename') {
          final shape = _selected;
          if (shape != null) _renameShape(shape);
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
          enabled: _selected != null,
          child: const Text('Modifier les couches…'),
        ),
        PopupMenuItem<String>(
          value: 'rename',
          enabled: _selected != null,
          child: const Text('Renommer…'),
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
