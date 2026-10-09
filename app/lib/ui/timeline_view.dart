import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/timeline_layout.dart';
import '../engine/timeline_zoom.dart';
import '../models/animation.dart';
import '../models/skeleton.dart';

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
    required this.onGestureStart,
    this.skeletonRig,
    this.selectedBoneId,
    this.onSelectBone,
    this.onDeleteBoneKeyframe,
    this.selectedGroupId,
    this.onSelectGroup,
    this.onToggleGroupCollapsed,
    this.onToggleGroupVisibility,
    this.onGroupGestureStart,
    this.onGroupMoveChanged,
    this.onGroupMoveEnd,
  });

  final AnimationProject project;
  final int timeMs;

  /// Fenêtre de temps affichée (détenue et persistée par l'écran, mutée ici).
  final TimelineZoomState zoom;

  final String? selectedShapeId;
  final ValueChanged<VectorShape> onSelect;
  final void Function(VectorShape shape, int startMs, int endMs) onRangeChanged;

  /// Déplace le segment : [targetStartMs] est le nouveau début (borné à ≥ 0
  /// par l'appelant, sans limite au-delà de la fin du projet — la durée suit),
  /// la durée et les keyframes suivent.
  final void Function(VectorShape shape, int targetStartMs) onMoveChanged;
  final ValueChanged<VectorShape> onMoveEnd;
  final ValueChanged<int> onSeek;
  final void Function(VectorShape shape, int timeMs) onDeleteKeyframe;

  /// Notifie l'écran d'un zoom/défilement (setState).
  final VoidCallback onZoomChanged;

  /// Début d'un geste modifiant la timeline (appui long ou poignée) : l'écran
  /// y prend le snapshot d'annulation AVANT modification.
  final void Function(VectorShape shape) onGestureStart;

  /// Mode squelette : rig du projet — sert à repérer l'os porteur de chaque
  /// forme (segment coloré, keyframes de l'os, sélection). Null →
  /// comportement vectoriel historique.
  ///
  /// Les pistes d'os SÉPARÉES ont été supprimées (v0.21.0) : les keyframes
  /// d'un os s'affichent SUR le segment de la forme qu'il porte.
  final SkeletonRig? skeletonRig;
  final String? selectedBoneId;
  final ValueChanged<RigBone>? onSelectBone;
  final void Function(RigBone bone, int timeMs)? onDeleteBoneKeyframe;
  final String? selectedGroupId;
  final ValueChanged<ShapeGroup>? onSelectGroup;
  final ValueChanged<ShapeGroup>? onToggleGroupCollapsed;
  final ValueChanged<ShapeGroup>? onToggleGroupVisibility;
  final ValueChanged<ShapeGroup>? onGroupGestureStart;
  final void Function(ShapeGroup group, int deltaMs)? onGroupMoveChanged;
  final ValueChanged<ShapeGroup>? onGroupMoveEnd;

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
  ShapeGroup? _movingGroup;
  int _movingGroupOriginMs = 0;
  int _movingGroupCurrentStartMs = 0;

  bool get _pinching => _pointers.length >= 2;

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 2) {
      _pinchDistance = _distance();
      _pinchFocal = _midpoint();
      HapticFeedback.selectionClick();
      // Un pincement interrompt un déplacement de segment.
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
    // Snapshot d'annulation avant la moindre modification.
    widget.onGestureStart(shape);
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
    // La fin du segment doit rester visible : défilement automatique quand
    // le geste dépasse le bord droit (sinon le doigt bute sur l'écran).
    _followEdge(shape.endMs);
  }

  /// Défilement automatique : garde le bord manipulé dans la vue (95 % de la
  /// largeur), comme le suivi de la tête de lecture pendant la lecture.
  void _followEdge(int timeMs) {
    if (widget.zoom.followEdge(timeMs)) widget.onZoomChanged();
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

  void _handleGroupMoveStart(ShapeGroup group) {
    if (_pinching) return;
    widget.onGroupGestureStart?.call(group);
    HapticFeedback.mediumImpact();
    setState(() {
      _movingGroup = group;
      _movingGroupOriginMs = widget.project.groupSpanMs(group.id)?.$1 ?? 0;
      _movingGroupCurrentStartMs = _movingGroupOriginMs;
    });
  }

  void _handleGroupMoveUpdate(ShapeGroup group, int targetStartMs) {
    if (_movingGroup?.id != group.id || _pinching) return;
    final target = math.max(0, targetStartMs);
    final delta = target - _movingGroupCurrentStartMs;
    if (delta == 0) return;
    _movingGroupCurrentStartMs = target;
    widget.onGroupMoveChanged?.call(group, delta);
    final span = widget.project.groupSpanMs(group.id);
    if (span != null) _followEdge(span.$2);
  }

  void _handleGroupMoveEnd(ShapeGroup group) {
    if (_movingGroup?.id != group.id) return;
    setState(() => _movingGroup = null);
    widget.onGroupMoveEnd?.call(group);
  }

  Widget _groupBar(ShapeGroup group, int lane, double width) {
    final span = widget.project.groupSpanMs(group.id);
    if (span == null) return const SizedBox.shrink();
    return _GroupBar(
      group: group,
      startMs: span.$1,
      endMs: span.$2,
      zoom: widget.zoom,
      width: width,
      laneTop: TimelineView.rulerHeight + lane * TimelineView.laneHeight,
      pinching: _pinching,
      moving: _movingGroup?.id == group.id,
      movingOriginMs: _movingGroupOriginMs,
      selected: widget.selectedGroupId == group.id,
      onSelect: () => widget.onSelectGroup?.call(group),
      onToggleCollapsed: () => widget.onToggleGroupCollapsed?.call(group),
      onToggleVisibility: () => widget.onToggleGroupVisibility?.call(group),
      onMoveStart: () => _handleGroupMoveStart(group),
      onMoveChanged: (target) => _handleGroupMoveUpdate(group, target),
      onMoveEnd: () => _handleGroupMoveEnd(group),
    );
  }

  /// Os porteur d'une forme (null = pièce libre) — v0.21.0 : le segment
  /// d'une pièce liée affiche les keyframes de SON os et sélectionne l'os.
  RigBone? _carrierOf(VectorShape shape) {
    final rig = widget.skeletonRig;
    if (rig == null) return null;
    return rig.boneById(rig.carrierBoneId(shape.id));
  }

  /// Barre d'une pièce : pour une pièce LIÉE, le segment est coloré, affiche
  /// les keyframes de l'OS (pas les siennes), sélectionne l'os au clic et
  /// supprime ses keyframes près de la tête de lecture.
  Color? _groupColorFor(VectorShape shape) {
    final group = widget.project.groupById(shape.groupId);
    return group == null ? null : Color(group.colorValue);
  }

  Widget _shapeBar(
    VectorShape shape,
    int lane,
    double width, {
    Color? groupColor,
  }) {
    final carrier = _carrierOf(shape);
    return _ShapeBar(
      shape: shape,
      rig: widget.skeletonRig,
      carrier: carrier,
      zoom: widget.zoom,
      timeMs: widget.timeMs,
      toleranceMs: keyframeSnapToleranceMs(widget.project.durationMs),
      laneTop: TimelineView.rulerHeight + lane * TimelineView.laneHeight,
      width: width,
      pinching: _pinching,
      moving: _movingShape?.id == shape.id,
      movingOriginMs: _movingOriginMs,
      selected:
          shape.id == widget.selectedShapeId ||
          (carrier != null && carrier.id == widget.selectedBoneId),
      onSelect: () {
        if (carrier != null) {
          widget.onSelectBone?.call(carrier);
        } else {
          widget.onSelect(shape);
        }
      },
      onSeek: widget.onSeek,
      onRangeChanged: (start, end) => widget.onRangeChanged(shape, start, end),
      onMoveStart: () => _handleMoveStart(shape),
      onMoveChanged: (target) => _handleMoveUpdate(shape, target),
      onMoveEnd: () => _handleMoveEnd(shape),
      onDeleteKeyframe: (time) {
        if (carrier != null) {
          widget.onDeleteBoneKeyframe?.call(carrier, time);
        } else {
          widget.onDeleteKeyframe(shape, time);
        }
      },
      onGestureStart: () => widget.onGestureStart(shape),
      onFollowEdge: _followEdge,
      groupColor: groupColor,
      groupVisible: widget.project.groupById(shape.groupId)?.visible,
    );
  }

  @override
  Widget build(BuildContext context) {
    final zoom = widget.zoom;
    // Une ligne par pièce : les pistes d'os SÉPARÉES ont disparu (v0.21.0),
    // les keyframes d'un os vivent sur le segment de la forme qu'il porte.
    final lanes = TimelineLayout.packRows(widget.project);
    final laneCount = math.max(1, lanes.length);
    final laneArea = laneCount * TimelineView.laneHeight;

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
                    onTapDown: (details) => widget.onSeek(
                      zoom.timeFor(details.localPosition.dx, width),
                    ),
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
                for (var lane = 0; lane < laneCount; lane++)
                  Positioned(
                    left: 0,
                    right: 0,
                    top:
                        TimelineView.rulerHeight +
                        lane * TimelineView.laneHeight,
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
                  for (final row in lanes[lane])
                    if (row.group case final group?)
                      _groupBar(group, lane, width)
                    else if (row.shape case final shape?)
                      _shapeBar(
                        shape,
                        lane,
                        width,
                        groupColor: _groupColorFor(shape),
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
    required this.rig,
    required this.carrier,
    required this.zoom,
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
    required this.onGestureStart,
    required this.onFollowEdge,
    this.groupColor,
    this.groupVisible,
  });

  final VectorShape shape;

  /// Rig du projet et os PORTANT cette forme (null = pièce libre) — v0.21.0 :
  /// le segment lié affiche les keyframes de l'os et sélectionne l'os.
  final SkeletonRig? rig;
  final RigBone? carrier;

  final TimelineZoomState zoom;
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

  /// Début d'un geste sur les poignées (redimensionnement) : snapshot undo.
  final VoidCallback onGestureStart;

  /// Défilement automatique pendant l'étirement : garde la fin dans la vue.
  final ValueChanged<int> onFollowEdge;
  final Color? groupColor;
  final bool? groupVisible;

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
    final effectiveVisible = shape.visible && (groupVisible ?? true);
    // Tout élément lié représente son os sur la timeline (y compris un groupe
    // squelette importé) ; seul un groupe non lié garde sa couleur orange.
    final bound = carrier != null;
    final color = bound
        ? const Color(0xFF3ECF8E)
        : shape.isInstance && shape.embeddedIsSkeleton
        ? const Color(0xFFFF9F43)
        : shape.isInstance
        ? const Color(0xFFC084FC)
        : Theme.of(context).colorScheme.primary;
    // Keyframes affichées : celles de l'OS pour tout élément lié, y compris
    // un groupe squelette ; sinon celles de la forme.
    final List<int> keyTimes;
    if (bound) {
      keyTimes = <int>{
        for (final key in rig!.trackOf(carrier!.id) ?? const <BoneKeyframe>[])
          if (key.timeMs >= shape.startMs && key.timeMs <= shape.endMs)
            key.timeMs,
      }.toList()..sort();
    } else {
      keyTimes = <int>{
        for (final key in shape.keyframes)
          if (key.timeMs >= shape.startMs && key.timeMs <= shape.endMs)
            key.timeMs,
      }.toList()..sort();
    }

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
          // Sans borne haute : dépasser la fin du projet l'étend (durée
          // dérivée), et le défilement automatique suit le geste.
          final target = math.max(0, movingOriginMs + deltaMs);
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
                color: color.withValues(alpha: effectiveVisible ? 0.30 : 0.12),
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
                shape.name,
                style: TextStyle(
                  fontSize: 11,
                  color: effectiveVisible ? Colors.white : Colors.white38,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (groupColor != null)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 3,
                child: IgnorePointer(child: ColoredBox(color: groupColor!)),
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
              onDragStart: () => onGestureStart(),
              onDragEnd: () {},
              onDrag: (deltaMs) {
                final next = (shape.startMs + deltaMs).clamp(
                  0,
                  shape.endMs - TimelineView.minSpanMs,
                );
                onRangeChanged(next, shape.endMs);
              },
            ),
            _Handle(
              alignment: Alignment.centerRight,
              msPerPixel: zoom.msPerPixel(width),
              tooltip: 'Fin d’affichage',
              onDragStart: () => onGestureStart(),
              onDragEnd: () {},
              onDrag: (deltaMs) {
                // Sans borne haute : allonger la fin au-delà de la fin du
                // projet étend la durée (dérivée du contenu) ; le
                // défilement automatique garde la fin dans la vue.
                final next = math.max(
                  shape.startMs + TimelineView.minSpanMs,
                  shape.endMs + deltaMs,
                );
                onRangeChanged(shape.startMs, next);
                onFollowEdge(next);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupBar extends StatelessWidget {
  const _GroupBar({
    required this.group,
    required this.startMs,
    required this.endMs,
    required this.zoom,
    required this.width,
    required this.laneTop,
    required this.pinching,
    required this.moving,
    required this.movingOriginMs,
    required this.selected,
    required this.onSelect,
    required this.onToggleCollapsed,
    required this.onToggleVisibility,
    required this.onMoveStart,
    required this.onMoveChanged,
    required this.onMoveEnd,
  });

  final ShapeGroup group;
  final int startMs;
  final int endMs;
  final TimelineZoomState zoom;
  final double width;
  final double laneTop;
  final bool pinching;
  final bool moving;
  final int movingOriginMs;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onToggleVisibility;
  final VoidCallback onMoveStart;
  final ValueChanged<int> onMoveChanged;
  final VoidCallback onMoveEnd;

  @override
  Widget build(BuildContext context) {
    final color = Color(group.colorValue);
    final left = zoom.xFor(startMs, width);
    final msPerPx = zoom.msPerPixel(width);
    final barWidth = math.max(110.0, (endMs - startMs) / msPerPx);
    final pinnedLeft = math.min(left, math.max(0.0, width - 24));
    return Positioned(
      left: pinnedLeft,
      top: laneTop + 3,
      width: barWidth,
      height: TimelineView.laneHeight - 8,
      child: GestureDetector(
        onTap: onSelect,
        onLongPressStart: (_) => onMoveStart(),
        onLongPressMoveUpdate: (details) {
          if (!moving || pinching) return;
          final deltaMs = (details.localOffsetFromOrigin.dx * msPerPx).round();
          onMoveChanged(math.max(0, movingOriginMs + deltaMs));
        },
        onLongPressEnd: (_) {
          if (moving) onMoveEnd();
        },
        onLongPressCancel: () {
          if (moving) onMoveEnd();
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: group.visible ? 0.28 : 0.10),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: moving
                  ? Colors.white
                  : selected
                  ? color
                  : color.withValues(alpha: 0.7),
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
          child: Row(
            children: <Widget>[
              IconButton(
                tooltip: group.collapsed
                    ? 'Déplier le groupe'
                    : 'Replier le groupe',
                onPressed: onToggleCollapsed,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 24,
                  height: 22,
                ),
                icon: Icon(
                  group.collapsed ? Icons.chevron_right : Icons.expand_more,
                  size: 18,
                  color: color,
                ),
              ),
              Expanded(
                child: Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: group.visible ? Colors.white : Colors.white38,
                  ),
                ),
              ),
              IconButton(
                tooltip: group.visible
                    ? 'Masquer le groupe'
                    : 'Afficher le groupe',
                onPressed: onToggleVisibility,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 24,
                  height: 22,
                ),
                icon: Icon(
                  group.visible ? Icons.visibility : Icons.visibility_off,
                  size: 14,
                  color: group.visible ? color : Colors.white38,
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
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
    this.onDragStart,
    this.onDragEnd,
  });

  final Alignment alignment;
  final String tooltip;
  final ValueChanged<int> onDrag;
  final double msPerPixel;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) => onDragStart?.call(),
          onHorizontalDragUpdate: (details) {
            if (details.delta.dx == 0) return;
            onDrag((details.delta.dx * msPerPixel).round());
          },
          onHorizontalDragEnd: (details) => onDragEnd?.call(),
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
