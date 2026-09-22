import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../engine/scene_painter.dart';
import '../engine/timeline_controller.dart';
import '../models/animation.dart';

class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key});

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationProject _project = AnimationProject.demo();
  late final TimelineController _controller = TimelineController(_project);
  late final Ticker _ticker = createTicker(_onTick);
  Duration _lastTick = Duration.zero;
  String? _selectedId;

  VectorShape? get _selected => _project.shapeById(_selectedId);

  @override
  void initState() {
    super.initState();
    _selectedId = _project.shapes.isEmpty ? null : _project.shapes.first.id;
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final delta = elapsed - _lastTick;
    _lastTick = elapsed;
    if (delta.inMilliseconds >= 0) _controller.advance(delta);
  }

  void _addShape(ShapeKind kind) {
    final id = 'shape-${DateTime.now().microsecondsSinceEpoch}';
    final shape = VectorShape(
      id: id,
      name: switch (kind) {
        ShapeKind.rect => 'Rectangle',
        ShapeKind.circle => 'Cercle',
        ShapeKind.line => 'Ligne',
        ShapeKind.path => 'Chemin',
      },
      kind: kind,
      x: _project.width / 2,
      y: _project.height / 2,
      width: kind == ShapeKind.line ? 160 : 110,
      height: kind == ShapeKind.line ? 0 : 110,
      colorValue: _palette[_project.shapes.length % _palette.length],
      filled: kind != ShapeKind.line,
      points: kind == ShapeKind.path
          ? const <Offset>[
              Offset(110, 0),
              Offset(80, 110),
              Offset(0, 84),
              Offset(30, 30),
            ]
          : null,
    );
    setState(() {
      _project.shapes.add(shape);
      _selectedId = shape.id;
    });
  }

  static const List<int> _palette = <int>[
    0xFF5B8DEF,
    0xFF3ECF8E,
    0xFFFF5C5C,
    0xFFF2C94C,
    0xFFC084FC,
    0xFF7DD3FC,
  ];

  void _deleteSelected() {
    final shape = _selected;
    if (shape == null) return;
    setState(() {
      _project.shapes.remove(shape);
      _selectedId = _project.shapes.isEmpty ? null : _project.shapes.first.id;
    });
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _exportJson() async {
    final file = File(
      '${Directory.systemTemp.path}/vector_anim_'
      '${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(_project.toJson()),
    );
    _snack('Projet exporté : ${file.path}');
  }

  Future<void> _exportPng() async {
    final image = await renderProjectToImage(_project, _controller.timeMs);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) {
      _snack('Export PNG impossible');
      return;
    }
    final file = File(
      '${Directory.systemTemp.path}/vector_anim_frame_'
      '${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(data.buffer.asUint8List());
    _snack('Image exportée : ${file.path}');
  }

  Future<void> _copyJson() async {
    await Clipboard.setData(
      ClipboardData(text: jsonEncode(_project.toJson())),
    );
    _snack('Projet copié dans le presse-papier');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vector Anim Studio'),
        actions: <Widget>[
          PopupMenuButton<String>(
            icon: const Icon(Icons.ios_share),
            onSelected: (value) {
              switch (value) {
                case 'json':
                  _exportJson();
                case 'png':
                  _exportPng();
                case 'clipboard':
                  _copyJson();
              }
            },
            itemBuilder: (context) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'json', child: Text('Exporter JSON')),
              PopupMenuItem<String>(value: 'png', child: Text('Exporter PNG')),
              PopupMenuItem<String>(
                value: 'clipboard',
                child: Text('Copier le JSON'),
              ),
            ],
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Column(
            children: <Widget>[
              _buildShapeStrip(),
              Expanded(child: _buildCanvas()),
              _buildInspector(),
              _buildTimeline(),
              _buildPlaybar(),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddSheet(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildShapeStrip() {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: <Widget>[
          for (final shape in _project.shapes)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: ChoiceChip(
                label: Text(shape.name),
                selected: shape.id == _selectedId,
                onSelected: (_) => setState(() => _selectedId = shape.id),
              ),
            ),
          if (_selected != null)
            IconButton(
              tooltip: 'Supprimer',
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteSelected,
            ),
        ],
      ),
    );
  }

  Widget _buildCanvas() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0D12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF232733)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InteractiveViewer(
        maxScale: 4,
        child: Center(
          child: AspectRatio(
            aspectRatio: _project.width / _project.height,
            child: CustomPaint(
              painter: ScenePainter(
                project: _project,
                timeMs: _controller.timeMs,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInspector() {
    final shape = _selected;
    if (shape == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Ajoute une forme pour commencer.'),
      );
    }
    const properties = <AnimatableProperty>[
      AnimatableProperty.x,
      AnimatableProperty.y,
      AnimatableProperty.width,
      AnimatableProperty.height,
      AnimatableProperty.rotation,
      AnimatableProperty.scale,
      AnimatableProperty.opacity,
      AnimatableProperty.strokeWidth,
    ];
    return SizedBox(
      height: 150,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text('Couleur'),
              const SizedBox(width: 12),
              for (final color in _palette)
                GestureDetector(
                  onTap: () => setState(() => shape.colorValue = color),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Color(color),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: shape.colorValue == color
                            ? Colors.white
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              Switch(
                value: shape.filled,
                onChanged: (value) => setState(() => shape.filled = value),
              ),
            ],
          ),
          for (final property in properties)
            _buildPropertyRow(shape, property),
        ],
      ),
    );
  }

  Widget _buildPropertyRow(VectorShape shape, AnimatableProperty property) {
    final value = shape.baseOf(property);
    final (min, max, step) = switch (property) {
      AnimatableProperty.x => (0.0, _project.width, 1.0),
      AnimatableProperty.y => (0.0, _project.height, 1.0),
      AnimatableProperty.width => (0.0, 300.0, 1.0),
      AnimatableProperty.height => (0.0, 300.0, 1.0),
      AnimatableProperty.rotation => (-3.15, 3.15, 0.01),
      AnimatableProperty.scale => (0.05, 4.0, 0.01),
      AnimatableProperty.opacity => (0.0, 1.0, 0.01),
      AnimatableProperty.strokeWidth => (0.0, 40.0, 0.5),
    };
    final hasKey = _controller.hasKeyframeAtPlayhead(shape, property);
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
            value: value.clamp(min, max),
            divisions: ((max - min) / step).round().clamp(1, 2000),
            onChanged: (next) => setState(() => shape.setBase(property, next)),
          ),
        ),
        IconButton(
          tooltip: hasKey ? 'Retirer la keyframe' : 'Ajouter une keyframe',
          iconSize: 18,
          icon: Icon(
            hasKey ? Icons.diamond : Icons.diamond_outlined,
            color: shape.isAnimated(property) ? const Color(0xFFF2C94C) : null,
          ),
          onPressed: () => setState(
            () => _controller.toggleKeyframe(shape, property),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeline() {
    final shape = _selected;
    final animated = shape == null
        ? const <AnimatableProperty>[]
        : shape.tracks.keys.where((p) => shape.isAnimated(p)).toList();
    return Container(
      height: 92,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF151922),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '${(_controller.timeMs / 1000).toStringAsFixed(2)} s'
              ' / ${(_project.durationMs / 1000).toStringAsFixed(2)} s'
              ' · ${_project.fps} fps',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(child: _buildScrubber()),
          if (animated.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'Aucune keyframe — utilise ◆ dans l’inspecteur.',
                style: TextStyle(fontSize: 11, color: Colors.white54),
              ),
            )
          else
            SizedBox(
              height: 18,
              child: Row(
                children: <Widget>[
                  const SizedBox(width: 10),
                  for (final property in animated)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF232733),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        propertyLabel(property),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildScrubber() {
    return LayoutBuilder(
      builder: (context, constraints) {
        void update(Offset local) {
          final ratio = (local.dx / constraints.maxWidth).clamp(0.0, 1.0);
          _controller.setProgress(ratio);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => update(details.localPosition),
          onHorizontalDragUpdate: (details) => update(details.localPosition),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Stack(
              children: <Widget>[
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: const Color(0xFF232733),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                for (final shape in _project.shapes)
                  for (final track in shape.tracks.values)
                    for (final key in track.keys)
                      if (shape.id == _selectedId)
                        Align(
                          alignment: Alignment(
                            (key.timeMs / _project.durationMs) * 2 - 1,
                            0,
                          ),
                          child: Transform.rotate(
                            angle: 0.785398,
                            child: Container(
                              width: 8,
                              height: 8,
                              color: const Color(0xFFF2C94C),
                            ),
                          ),
                        ),
                Align(
                  alignment: Alignment(_controller.progress * 2 - 1, 0),
                  child: Container(
                    width: 3,
                    height: 26,
                    color: const Color(0xFFFF5C5C),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlaybar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 14),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: _controller.rewind,
            icon: const Icon(Icons.skip_previous),
          ),
          IconButton.filledTonal(
            onPressed: _controller.togglePlay,
            icon: Icon(_controller.playing ? Icons.pause : Icons.play_arrow),
          ),
          IconButton(
            onPressed: () => _controller.setLoop(!_controller.loop),
            icon: Icon(_controller.loop ? Icons.repeat_on : Icons.repeat),
          ),
          const Spacer(),
          Text('${_project.shapes.length} forme(s)'),
        ],
      ),
    );
  }

  void _showAddSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final kind in ShapeKind.values)
              ListTile(
                leading: Icon(switch (kind) {
                  ShapeKind.rect => Icons.crop_square,
                  ShapeKind.circle => Icons.circle_outlined,
                  ShapeKind.line => Icons.horizontal_rule,
                  ShapeKind.path => Icons.polyline,
                }),
                title: Text(switch (kind) {
                  ShapeKind.rect => 'Rectangle',
                  ShapeKind.circle => 'Cercle',
                  ShapeKind.line => 'Ligne',
                  ShapeKind.path => 'Chemin',
                }),
                onTap: () {
                  Navigator.of(context).pop();
                  _addShape(kind);
                },
              ),
          ],
        ),
      ),
    );
  }
}