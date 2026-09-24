import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/timeline_layout.dart';
import '../engine/timeline_zoom.dart';
import '../models/animation.dart';

/// Timeline : une ligne par piste d'affichage, un rectangle par forme.
///
/// L'échelle de temps est donnée par [zoom] (temps affiché sur la largeur +
/// défilement) : pincement à deux doigts = zoom ancré, glisser à deux doigts
/// = défilement horizontal. Appui long sur un rectangle = déplacer tout le
/// segment (durée et keyframes conservées) ; la ligne d'atterrissage est
/// recalculée automatiquement par l'empilement anti-chevauchement.
class TimelineView extends StatefulWidget {
  const TimelineView({
    super.key,
    required this.project,
    required this.timeMs,
    required this.zoom,
    required this.selectedShapeId,
    required this.onSelect,
    required this.onRangeChanged,
    required this.onMoveChanged,
    required this.onMoveEnd,
    required this.onSeek,
    required this.onDeleteKeyframe,
    required this.onZoomChanged,
  });

  final AnimationProject project;
  final int timeMs;

  /// Fenêtre de temps affichée (détenue et persistée par l'écran, mutée ici).
  final TimelineZoomState zoom;

  final String? selectedShapeId;
  final ValueChanged<VectorShape> onSelect;
  final void Function(VectorShape shape, int startMs, int endMs) onRangeChanged;

  /// Déplace le segment : [targetStartMs] est le nouveau début (borne par
  /// l'appelant), la durée et les keyframes suivent.
  final void Function(VectorShape shape, int targetStartMs) onMoveChanged;
  final ValueChanged<VectorShape> onMoveEnd;
  final ValueChanged<int> onSeek;
  final void Function(VectorShape shape, int timeMs) onDeleteKeyframe;

  /// Notifie l'écran d'un zoom/défilement (setState).
  final VoidCallback onZoomChanged;

  static const double rulerHeight = 20;
  static const double laneHeight = 30;
  static const int minSpanMs = 100;

  @override
  State<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<TimelineView> {
  /// Pointeurs actifs : le pincement est détecté manuellement via [Listener],
  /// qui ne participe pas à l'arène de gestes — le scrub d'un doigt et le
  /// scroll vertical des lignes restent inchangés.
  final Map<int, Offset> _pointers = <int, Offset>{};
  double _pinchDistance = 0;
  Offset _pinchFocal = Offset.zero;
  double _width = 0;

  /// Segment en cours de déplacement (appui long) : détenu ici pour pouvoir
  /// l'annuler immédiatement dès qu'un pincement à deux doigts démarre.
  VectorShape? _movingShape;
  int _movingOriginMs = 0;

  bool get _pinching => _pointers.length >= 2;

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 2) {
      _pinchDistance = _distance();
      _pinchFocal = _midpoint();
      HapticFeedback.selectionClick();
      // Un pincement interrompt un déplacement de segment en cours.
      final moving = _movingShape;
      if (moving != null) {
        _movingShape = null;
        widget.onMoveEnd(moving);
      }
      setState(() {}); // reconstruire les barres avec le pincement en cours
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;
    if (!_pinching || _width <= 0) return;
    final distance = _distance();
    final focal = _midpoint();
    if (_pinchDistance > 0 && distance > 0) {
      // Écartement des doigts = zoom avant (la vue rétrécit).
      widget.zoom.zoomAt(
        distance / _pinchDistance,
        (focal.dx / _width).clamp(0.0, 1.0),
      );
    }
    widget.zoom.panByPixels(focal.dx - _pinchFocal.dx, _width);
    _pinchDistance = distance;
    _pinchFocal = focal;
    widget.onZoomChanged();
  }

  void _onPointerUp(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (!_pinching) _pinchDistance = 0;
  }

  double _distance() {
    final points = _pointers.values.toList();
    if (points.length < 2) return 0;
    return (points[0] - points[1]).distance;
  }

  Offset _midpoint() {
    final points = _pointers.values.toList();
    if (points.length < 2) return Offset.zero;
    return Offset(
      (points[0].dx + points[1].dx) / 2,
      (points[0].dy + points[1].dy) / 2,
    );
  }

  // ------------------------------------------------- déplacement de segment

  void _handleMoveStart(VectorShape shape) {
    if (_pinching) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _movingShape = shape;
      _movingOriginMs = shape.startMs;
    });
  }

  void _handleMoveUpdate(VectorShape shape, int targetStartMs) {
    if (_movingShape?.id != shape.id) return;
    if (_pinching) {
      _cancelMove(shape);
      return;
    }
    widget.onMoveChanged(shape, targetStartMs);
  }

  void _handleMoveEnd(VectorShape shape) {
    if (_movingShape?.id != shape.id) return;
    setState(() => _movingShape = null);
    widget.onMoveEnd(shape);
  }

  void _cancelMove(VectorShape shape) {
    if (_movingShape?.id != shape.id) return;
    _movingShape = null;
    widget.onMoveEnd(shape);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final zoom = widget.zoom;
    final lanes = TimelineLayout.packLanes(widget.project.shapes);
    final laneArea = math.max(1, lanes.length) * TimelineView.laneHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        _width = width;

        return SizedBox(
          height: TimelineView.rulerHeight + laneArea,
          child: Listener(
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerUp,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: <Widget>[
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) =>
                        widget.onSeek(zoom.timeFor(details.localPosition.dx, width)),
                    onHorizontalDragUpdate: (details) {
                      if (_pinching) return;
                      widget.onSeek(
                        zoom.timeFor(details.localPosition.dx, width),
                      );
                    },
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: TimelineView.rulerHeight,
                  child: CustomPaint(
                    painter: _RulerPainter(zoom: zoom, width: width),
                  ),
                ),
                for (var lane = 0; lane < lanes.length; lane++)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: TimelineView.rulerHeight + lane * TimelineView.laneHeight,
                    height: TimelineView.laneHeight,
                    child: IgnorePointer(
                      // Décoratif : ne doit pas bloquer le seek sur le fond.
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
                  ),
                for (var lane = 0; lane < lanes.length; lane++)
                  for (final shape in lanes[lane])
                    _ShapeBar(
                      shape: shape,
                      zoom: zoom,
                      durationMs: widget.project.durationMs,
                      timeMs: widget.timeMs,
                      toleranceMs:
                          keyframeSnapToleranceMs(widget.project.durationMs),
                      laneTop:
                          TimelineView.rulerHeight + lane * TimelineView.laneHeight,
                      width: width,
                      pinching: _pinching,
                      moving: _movingShape?.id == shape.id,
                      movingOriginMs: _movingOriginMs,
                      selected: shape.id == widget.selectedShapeId,
                      onSelect: () => widget.onSelect(shape),
                      onSeek: (t) => widget.onSeek(t),
                      onRangeChanged: (start, end) =>
                          widget.onRangeChanged(shape, start, end),
                      onMoveStart: () => _handleMoveStart(shape),
                      onMoveChanged: (target) =>
                          _handleMoveUpdate(shape, target),
                      onMoveEnd: () => _handleMoveEnd(shape),
                      onDeleteKeyframe: (time) =>
                          widget.onDeleteKeyframe(shape, time),
                    ),
                Positioned(
                  left: zoom.xFor(widget.timeMs, width) - 1,
                  top: 0,
                  bottom: 0,
                  width: 2,
                  child: const IgnorePointer(
                    child: ColoredBox(color: Color(0xFFFF5C5C)),
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

/// Règle graduée adaptative : le pas s'élargit avec le zoom (50 ms → 30 min),
/// graduations majeures labellisées + quintillés mineurs si la place suffit.
class _RulerPainter extends CustomPainter {
  const _RulerPainter({required this.zoom, required this.width});

  final TimelineZoomState zoom;
  final double width;

  static const List<int> _steps = <int>[
    50, 100, 250, 500, 1000, 2000, 5000, 10000, 15000, 30000, //
    60000, 120000, 300000, 600000, 1800000,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final pxPerMs = size.width / math.max(1, zoom.viewMs);
    var step = _steps.last;
    for (final candidate in _steps) {
      if (candidate * pxPerMs >= 64) {
        step = candidate;
        break;
      }
    }
    final minorStep = step ~/ 5;
    final showMinor = minorStep > 0 && minorStep * pxPerMs >= 6;

    final major = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    final minor = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;

    final tickStep = showMinor ? minorStep : step;
    final first = (zoom.offsetMs / tickStep).floor() * tickStep;
    final last = zoom.offsetMs + zoom.viewMs + step;
    for (var t = first; t <= last; t += tickStep) {
      if (t < 0) continue;
      final x = (t - zoom.offsetMs) * pxPerMs;
      if (t % step == 0) {
        canvas.drawLine(
          Offset(x, size.height - 8),
          Offset(x, size.height),
          major,
        );
        _label(canvas, size, _formatTime(t), x + 3);
      } else {
        canvas.drawLine(
          Offset(x, size.height - 4),
          Offset(x, size.height),
          minor,
        );
      }
    }
  }

  static String _formatTime(int ms) {
    if (ms < 60000) {
      final seconds = ms / 1000;
      if (seconds == seconds.truncateToDouble()) {
        return '${seconds.toStringAsFixed(0)} s';
      }
      return seconds < 1
          ? '${seconds.toStringAsFixed(2)} s'
          : '${seconds.toStringAsFixed(1)} s';
    }
    final minutes = ms ~/ 60000;
    final seconds = (ms % 60000) ~/ 1000;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _label(Canvas canvas, Size size, String text, double x) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(fontSize: 9, color: Colors.white38),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    if (x + painter.width > size.width) return;
    painter.paint(canvas, Offset(x, 2));
  }

  @override
  bool shouldRepaint(_RulerPainter oldDelegate) =>
      oldDelegate.zoom.viewMs != zoom.viewMs ||
      oldDelegate.zoom.offsetMs != zoom.offsetMs ||
      oldDelegate.width != width;
}

/// Rectangle d'une forme : sélection, poignées de redimensionnement,
/// keyframes supprimables près de la tête de lecture et déplacement du
/// segment entier par appui long + glisser horizontal.
class _ShapeBar extends StatelessWidget {
  const _ShapeBar({
    required this.shape,
    required this.zoom,
    required this.durationMs,
    required this.timeMs,
    required this.toleranceMs,
    required this.laneTop,
    required this.width,
    required this.pinching,
    required this.moving,
    required this.movingOriginMs,
    required this.selected,
    required this.onSelect,
    required this.onSeek,
    required this.onRangeChanged,
    required this.onMoveStart,
    required this.onMoveChanged,
    required this.onMoveEnd,
    required this.onDeleteKeyframe,
  });

  final VectorShape shape;
  final TimelineZoomState zoom;
  final int durationMs;
  final int timeMs;
  final int toleranceMs;
  final double laneTop;
  final double width;

  /// Pincement en cours : les gestes de la barre (déplacement, scrub) sont
  /// gelés pour laisser la main au zoom/défilement à deux doigts.
  final bool pinching;

  /// Segment soulevé par un appui long (état détenu par la vue parente).
  final bool moving;
  final int movingOriginMs;
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<int> onSeek;
  final void Function(int startMs, int endMs) onRangeChanged;
  final VoidCallback onMoveStart;
  final ValueChanged<int> onMoveChanged;
  final VoidCallback onMoveEnd;
  final ValueChanged<int> onDeleteKeyframe;

  @override
  Widget build(BuildContext context) {
    final shape = this.shape;
    final zoom = this.zoom;
    final width = this.width;
    final msPerPx = zoom.msPerPixel(width);
    final left = zoom.xFor(shape.startMs, width);
    // Largeur du segment : durée × pixels/ms — PAS ms/pixel (sinon la barre
    // couvre tout l'écran et bloque le seek et le défilement).
    final barWidth = math.max(24.0, shape.durationMs / msPerPx);
    // Épinglée au bord droit : une barre plus large que son minimum doit
    // rester visible quand sa fin touche le bord droit de la vue.
    final pinnedLeft = math.min(left, math.max(0.0, width - 24));
    final color = shape.isInstance
        ? const Color(0xFFC084FC)
        : Theme.of(context).colorScheme.primary;
    final keyTimes = <int>{
      for (final key in shape.keyframes)
        if (key.timeMs >= shape.startMs && key.timeMs <= shape.endMs) key.timeMs,
    }.toList()
      ..sort();

    return Positioned(
      left: pinnedLeft,
      top: laneTop + 3,
      width: barWidth,
      height: TimelineView.laneHeight - 8,
      child: GestureDetector(
        onTap: onSelect,
        onHorizontalDragUpdate: (details) {
          // Scrub de la tête de lecture, même au-dessus d'une barre.
          if (pinching || moving) return;
          onSeek(zoom.timeFor(details.localPosition.dx, width));
        },
        onLongPressStart: (details) => onMoveStart(),
        onLongPressMoveUpdate: (details) {
          if (!moving) return;
          final deltaMs = (details.localOffsetFromOrigin.dx * msPerPx).round();
          final target = math.max(
            0,
            math.min(movingOriginMs + deltaMs, durationMs - shape.durationMs),
          );
          onMoveChanged(target);
        },
        onLongPressEnd: (details) {
          if (moving) onMoveEnd();
        },
        onLongPressCancel: () {
          if (moving) onMoveEnd();
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Container(
              decoration: BoxDecoration(
                color: color.withValues(alpha: shape.visible ? 0.30 : 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: moving
                      ? Colors.white
                      : selected
                          ? color
                          : color.withValues(alpha: 0.5),
                  width: moving || selected ? 2 : 1,
                ),
                boxShadow: moving
                    ? <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
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
              msPerPixel: zoom.msPerPixel(width),
              tooltip: 'Début d’affichage',
              onDrag: (deltaMs) {
                final next = (shape.startMs + deltaMs)
                    .clamp(0, shape.endMs - TimelineView.minSpanMs);
                onRangeChanged(next, shape.endMs);
              },
            ),
            _Handle(
              alignment: Alignment.centerRight,
              msPerPixel: zoom.msPerPixel(width),
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
