import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/timeline_layout.dart';
import '../models/animation.dart';

/// Timeline : une ligne par piste d'affichage, un rectangle par forme.
///
/// Côté gauche du rectangle = début d'affichage, côté droit = fin.
/// Deux fenêtres qui se chevauchent occupent deux lignes parallèles.
class TimelineView extends StatelessWidget {
  const TimelineView({
    super.key,
    required this.project,
    required this.timeMs,
    required this.selectedShapeId,
    required this.onSelect,
    required this.onRangeChanged,
    required this.onSeek,
    required this.onDeleteKeyframe,
  });

  final AnimationProject project;
  final int timeMs;
  final String? selectedShapeId;
  final ValueChanged<VectorShape> onSelect;
  final void Function(VectorShape shape, int startMs, int endMs) onRangeChanged;
  final ValueChanged<int> onSeek;
  final void Function(VectorShape shape, int timeMs) onDeleteKeyframe;

  static const double rulerHeight = 20;
  static const double laneHeight = 30;
  static const int minSpanMs = 100;

  int get _duration => math.max(1, project.durationMs);

  @override
  Widget build(BuildContext context) {
    final lanes = TimelineLayout.packLanes(project.shapes);
    final laneArea = math.max(1, lanes.length) * laneHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        int timeFor(double dx) =>
            ((dx / width).clamp(0.0, 1.0) * _duration).round();

        return SizedBox(
          height: rulerHeight + laneArea,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) =>
                      onSeek(timeFor(details.localPosition.dx)),
                  onHorizontalDragUpdate: (details) =>
                      onSeek(timeFor(details.localPosition.dx)),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: rulerHeight,
                child: _Ruler(durationMs: _duration),
              ),
              for (var lane = 0; lane < lanes.length; lane++)
                Positioned(
                  left: 0,
                  right: 0,
                  top: rulerHeight + lane * laneHeight,
                  height: laneHeight,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                    ),
                  ),
                ),
              for (var lane = 0; lane < lanes.length; lane++)
                for (final shape in lanes[lane])
                  _ShapeBar(
                    shape: shape,
                    durationMs: _duration,
                    timeMs: timeMs,
                    toleranceMs: keyframeSnapToleranceMs(_duration),
                    laneTop: rulerHeight + lane * laneHeight,
                    width: width,
                    selected: shape.id == selectedShapeId,
                    onSelect: () => onSelect(shape),
                    onRangeChanged: (start, end) =>
                        onRangeChanged(shape, start, end),
                    onDeleteKeyframe: (time) =>
                        onDeleteKeyframe(shape, time),
                  ),
              Positioned(
                left: (timeMs / _duration) * width - 1,
                top: 0,
                bottom: 0,
                width: 2,
                child: const IgnorePointer(
                  child: ColoredBox(color: Color(0xFFFF5C5C)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Ruler extends StatelessWidget {
  const _Ruler({required this.durationMs});

  final int durationMs;

  @override
  Widget build(BuildContext context) {
    const ticks = <double>[0, 0.25, 0.5, 0.75, 1];
    return Stack(
      children: <Widget>[
        for (final tick in ticks)
          Align(
            alignment: Alignment(tick * 2 - 1, 0),
            child: Text(
              '${(durationMs * tick / 1000).toStringAsFixed(1)} s',
              style: const TextStyle(fontSize: 9, color: Colors.white38),
            ),
          ),
      ],
    );
  }
}

class _ShapeBar extends StatelessWidget {
  const _ShapeBar({
    required this.shape,
    required this.durationMs,
    required this.timeMs,
    required this.toleranceMs,
    required this.laneTop,
    required this.width,
    required this.selected,
    required this.onSelect,
    required this.onRangeChanged,
    required this.onDeleteKeyframe,
  });

  final VectorShape shape;
  final int durationMs;
  final int timeMs;
  final int toleranceMs;
  final double laneTop;
  final double width;
  final bool selected;
  final VoidCallback onSelect;
  final void Function(int startMs, int endMs) onRangeChanged;
  final ValueChanged<int> onDeleteKeyframe;

  @override
  Widget build(BuildContext context) {
    final left = (shape.startMs / durationMs) * width;
    final barWidth = math.max(24.0, ((shape.endMs - shape.startMs) / durationMs) * width);
    final color = shape.isInstance
        ? const Color(0xFFC084FC)
        : Theme.of(context).colorScheme.primary;
    final keyTimes = <int>{
      for (final key in shape.keyframes)
        if (key.timeMs >= shape.startMs && key.timeMs <= shape.endMs) key.timeMs,
    }.toList()
      ..sort();

    return Positioned(
      left: math.min(left, math.max(0, width - 24)),
      top: laneTop + 3,
      width: barWidth,
      height: TimelineView.laneHeight - 8,
      child: GestureDetector(
        onTap: onSelect,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Container(
              decoration: BoxDecoration(
                color: color.withValues(alpha: shape.visible ? 0.30 : 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: selected ? color : color.withValues(alpha: 0.5),
                  width: selected ? 2 : 1,
                ),
              ),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                shape.isInstance ? '\u{1F3AC} ${shape.name}' : shape.name,
                style: TextStyle(
                  fontSize: 11,
                  color: shape.visible ? Colors.white : Colors.white38,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            for (final keyTime in keyTimes)
              Align(
                alignment: Alignment(
                  ((keyTime - shape.startMs) /
                              math.max(1, shape.endMs - shape.startMs))
                          .clamp(0.0, 1.0) *
                      2 -
                      1,
                  0.75,
                ),
                child: (keyTime - timeMs).abs() <= toleranceMs
                    ? GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onDeleteKeyframe(keyTime),
                        child: Tooltip(
                          message: 'Supprimer la keyframe',
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFF5C5C),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 11,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      )
                    : Transform.rotate(
                        angle: 0.785398,
                        child: Container(
                          width: 7,
                          height: 7,
                          color: const Color(0xFFF2C94C),
                        ),
                      ),
              ),
            _Handle(
              alignment: Alignment.centerLeft,
              msPerPixel: durationMs / width,
              tooltip: 'Début d’affichage',
              onDrag: (deltaMs) {
                final next = (shape.startMs + deltaMs)
                    .clamp(0, shape.endMs - TimelineView.minSpanMs);
                onRangeChanged(next, shape.endMs);
              },
            ),
            _Handle(
              alignment: Alignment.centerRight,
              msPerPixel: durationMs / width,
              tooltip: 'Fin d’affichage',
              onDrag: (deltaMs) {
                final next = (shape.endMs + deltaMs)
                    .clamp(shape.startMs + TimelineView.minSpanMs, durationMs);
                onRangeChanged(shape.startMs, next);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle({
    required this.alignment,
    required this.tooltip,
    required this.onDrag,
    required this.msPerPixel,
  });

  final Alignment alignment;
  final String tooltip;
  final ValueChanged<int> onDrag;
  final double msPerPixel;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) {
            if (details.delta.dx == 0) return;
            onDrag((details.delta.dx * msPerPixel).round());
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: Container(
              width: 14,
              height: double.infinity,
              margin: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Center(
                child: SizedBox(
                  width: 2,
                  height: 12,
                  child: ColoredBox(color: Colors.white70),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
