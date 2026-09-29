import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/timeline_layout.dart';
import '../engine/timeline_zoom.dart';
import '../models/animation.dart';
import '../models/skeleton.dart';

/// Timeline : une ligne par piste, une barre par forme ANIMÉE (span de son
/// contenu : 1re → dernière keyframe).
///
/// L'échelle de temps est donnée par [zoom] (temps affiché sur la largeur +
/// défilement) : pincement à deux doigts = zoom ancré, glisser à deux doigts
/// = défilement horizontal. Appui long sur une barre = décaler toutes les
/// keyframes (courbes conservées) ; la ligne d'atterrissage est recalculée
/// automatiquement par l'empilement anti-chevauchement. Les fenêtres
/// d'affichage start/end ont été supprimées (v0.18) — pas de poignées de
/// redimensionnement, une forme est affichée tant qu'elle est visible.
class TimelineView extends StatefulWidget {
  const TimelineView({
    super.key,
    required this.project,
    required this.timeMs,
    required this.zoom,
    required this.selectedShapeId,
    required this.onSelect,
    required this.onMoveChanged,
    required this.onMoveEnd,
    required this.onSeek,
    required this.onDeleteKeyframe,
    required this.onZoomChanged,
    required this.onGestureStart,
    this.skeletonRig,
    this.selectedBoneId,
    this.onSelectBone,
    this.onBoneMoveChanged,
    this.onBoneMoveEnd,
    this.onBoneGestureStart,
    this.onDeleteBoneKeyframe,
  });

  final AnimationProject project;
  final int timeMs;

  /// Fenêtre de temps affichée (détenue et persistée par l'écran, mutée ici).
  final TimelineZoomState zoom;

  final String? selectedShapeId;
  final ValueChanged<VectorShape> onSelect;

  /// Déplace la piste : [targetStartMs] = nouvelle origine du span (1re
  /// keyframe ; bornée à ≥ 0 par l'appelant, sans limite au-delà de la fin
  /// du projet — la durée suit). Les keyframes sont décalées en bloc.
  final void Function(VectorShape shape, int targetStartMs) onMoveChanged;
  final ValueChanged<VectorShape> onMoveEnd;
  final ValueChanged<int> onSeek;
  final void Function(VectorShape shape, int timeMs) onDeleteKeyframe;

  /// Notifie l'écran d'un zoom/défilement (setState).
  final VoidCallback onZoomChanged;

  /// Début d'un geste modifiant la timeline (appui long ou poignée) : l'écran
  /// y prend le snapshot d'annulation AVANT modification.
  final void Function(VectorShape shape) onGestureStart;

  /// Mode squelette : rig du projet — les barres des os animés s'ajoutent
  /// sous les barres de pièces (qui restent affichées). Null → comportement
  /// vectoriel historique.
  final SkeletonRig? skeletonRig;
  final String? selectedBoneId;
  final ValueChanged<RigBone>? onSelectBone;

  /// Déplace la piste d'os : [targetFirstMs] = nouveau temps de la première
  /// keyframe (décalage relatif, keyframes rabotées à zéro).
  final void Function(RigBone bone, int targetFirstMs)? onBoneMoveChanged;
  final ValueChanged<RigBone>? onBoneMoveEnd;
  final void Function(RigBone bone)? onBoneGestureStart;
  final void Function(RigBone bone, int timeMs)? onDeleteBoneKeyframe;

  static const double rulerHeight = 20;
  static const double laneHeight = 30;

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

  /// Piste d'os en cours de déplacement (appui long, mode squelette).
  RigBone? _movingBone;
  int _movingBoneOriginMs = 0;

  bool get _pinching => _pointers.length >= 2;

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 2) {
      _pinchDistance = _distance();
      _pinchFocal = _midpoint();
      HapticFeedback.selectionClick();
      // Un pincement interrompt un déplacement de segment (forme ou os).
      final moving = _movingShape;
      final movingBone = _movingBone;
      if (moving != null) {
        _movingShape = null;
        widget.onMoveEnd(moving);
      }
      if (movingBone != null) {
        _movingBone = null;
        widget.onBoneMoveEnd?.call(movingBone);
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
      _movingOriginMs = shape.spanStartMs;
    });
  }

  void _handleMoveUpdate(VectorShape shape, int targetStartMs) {
    if (_movingShape?.id != shape.id) return;
    if (_pinching) {
      _cancelMove(shape);
      return;
    }
    widget.onMoveChanged(shape, targetStartMs);
    // La fin du span doit rester visible : défilement automatique quand
    // le geste dépasse le bord droit (sinon le doigt bute sur l'écran).
    _followEdge(shape.spanEndMs);
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

  // --------------------------------------------- déplacement de piste d'os

  void _handleBoneMoveStart(RigBone bone) {
    if (_pinching) return;
    final rig = widget.skeletonRig;
    final track = rig?.trackOf(bone.id);
    if (rig == null || track == null || track.isEmpty) return;
    widget.onBoneGestureStart?.call(bone);
    HapticFeedback.mediumImpact();
    setState(() {
      _movingBone = bone;
      _movingBoneOriginMs = track.first.timeMs;
    });
  }

  void _handleBoneMoveUpdate(RigBone bone, int targetFirstMs) {
    if (_movingBone?.id != bone.id) return;
    if (_pinching) {
      _cancelBoneMove(bone);
      return;
    }
    widget.onBoneMoveChanged?.call(bone, targetFirstMs);
    final track = widget.skeletonRig?.trackOf(bone.id);
    if (track != null && track.isNotEmpty) _followEdge(track.last.timeMs);
  }

  void _handleBoneMoveEnd(RigBone bone) {
    if (_movingBone?.id != bone.id) return;
    setState(() => _movingBone = null);
    widget.onBoneMoveEnd?.call(bone);
  }

  void _cancelBoneMove(RigBone bone) {
    if (_movingBone?.id != bone.id) return;
    _movingBone = null;
    widget.onBoneMoveEnd?.call(bone);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final zoom = widget.zoom;
    final rig = widget.skeletonRig;
    // Barres de pièces toujours affichées, barres d'os (si rig) posées en
    // dessous : v0.9.0 masquait les pièces dès qu'un os existait.
    final fullSpanMs = math.max(widget.project.durationMs, 4000);
    final lanes = TimelineLayout.packLanes(
      widget.project.shapes,
      fullSpanMs: fullSpanMs,
    );
    final boneLanes = rig == null
        ? const <List<RigBone>>[]
        : TimelineLayout.packBoneLanes(rig);
    final laneCount = math.max(1, lanes.length + boneLanes.length);
    final boneLaneOffset = lanes.length;
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
                  for (final shape in lanes[lane])
                    _ShapeBar(
                      shape: shape,
                      zoom: zoom,
                      timeMs: widget.timeMs,
                      toleranceMs: keyframeSnapToleranceMs(
                        widget.project.durationMs,
                      ),
                      laneTop:
                          TimelineView.rulerHeight +
                          lane * TimelineView.laneHeight,
                      width: width,
                      fullSpanMs: fullSpanMs,
                      pinching: _pinching,
                      moving: _movingShape?.id == shape.id,
                      movingOriginMs: _movingOriginMs,
                      selected: shape.id == widget.selectedShapeId,
                      onSelect: () => widget.onSelect(shape),
                      onSeek: (t) => widget.onSeek(t),
                      onMoveStart: () => _handleMoveStart(shape),
                      onMoveChanged: (target) =>
                          _handleMoveUpdate(shape, target),
                      onMoveEnd: () => _handleMoveEnd(shape),
                      onDeleteKeyframe: (time) =>
                          widget.onDeleteKeyframe(shape, time),
                    ),
                for (var lane = 0; lane < boneLanes.length; lane++)
                  for (final bone in boneLanes[lane])
                    _BoneBar(
                      bone: bone,
                      rig: rig!,
                      zoom: zoom,
                      timeMs: widget.timeMs,
                      toleranceMs: keyframeSnapToleranceMs(
                        widget.project.durationMs,
                      ),
                      laneTop:
                          TimelineView.rulerHeight +
                          (boneLaneOffset + lane) * TimelineView.laneHeight,
                      width: width,
                      pinching: _pinching,
                      moving: _movingBone?.id == bone.id,
                      movingOriginMs: _movingBoneOriginMs,
                      selected: bone.id == widget.selectedBoneId,
                      onSelect: () => widget.onSelectBone?.call(bone),
                      onSeek: (t) => widget.onSeek(t),
                      onMoveStart: () => _handleBoneMoveStart(bone),
                      onMoveChanged: (target) =>
                          _handleBoneMoveUpdate(bone, target),
                      onMoveEnd: () => _handleBoneMoveEnd(bone),
                      onDeleteKeyframe: (time) =>
                          widget.onDeleteBoneKeyframe?.call(bone, time),
                      onFollowEdge: _followEdge,
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

/// Rectangle d'une forme animée : sélection, keyframes supprimables près
/// de la tête de lecture et décalage de tout le span par appui long +
/// glisser horizontal (fenêtre de visibilité supprimée).
class _ShapeBar extends StatelessWidget {
  const _ShapeBar({
    required this.shape,
    required this.zoom,
    required this.timeMs,
    required this.toleranceMs,
    required this.laneTop,
    required this.width,
    required this.fullSpanMs,
    required this.pinching,
    required this.moving,
    required this.movingOriginMs,
    required this.selected,
    required this.onSelect,
    required this.onSeek,
    required this.onMoveStart,
    required this.onMoveChanged,
    required this.onMoveEnd,
    required this.onDeleteKeyframe,
  });

  final VectorShape shape;
  final TimelineZoomState zoom;
  final int timeMs;
  final int toleranceMs;
  final double laneTop;
  final double width;

  /// Durée de référence des barres sans keyframe (instances) :
  /// max(durée du projet, 4 s).
  final int fullSpanMs;

  /// Pincement en cours : les gestes de la barre (déplacement, scrub) sont
  /// gelés pour laisser la main au zoom/défilement à deux doigts.
  final bool pinching;

  /// Segment soulevé par un appui long (état détenu par la vue parente).
  final bool moving;
  final int movingOriginMs;
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<int> onSeek;
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
    // Barre = span du CONTENU (1re → dernière keyframe) : les fenêtres
    // d'affichage ont été supprimées (v0.18). Sans keyframe, seule une
    // INSTANCE garde une barre — pleine durée (elle s'anime en boucle).
    final hasKeys = shape.keyframes.isNotEmpty;
    final spanStart = hasKeys ? shape.spanStartMs : 0;
    final spanEnd = hasKeys ? shape.spanEndMs : fullSpanMs;
    final left = zoom.xFor(spanStart, width);
    // Bornée à la vue : une barre plus large est coupée, pas débordante.
    final barWidth = math.min(
      math.max(24.0, (spanEnd - spanStart) / msPerPx),
      width,
    );
    // Épinglée au bord droit : une barre plus large que son minimum doit
    // rester visible quand sa fin touche le bord droit de la vue.
    final pinnedLeft = math.min(left, math.max(0.0, width - 24));
    final color = shape.isInstance
        ? const Color(0xFFC084FC)
        : Theme.of(context).colorScheme.primary;
    final keyTimes = <int>{
      for (final key in shape.keyframes) key.timeMs,
    }.toList()..sort();

    return Positioned(
      left: pinnedLeft,
      top: laneTop + 3,
      width: barWidth,
      height: TimelineView.laneHeight - 8,
      child: GestureDetector(
        onTap: onSelect,
        onHorizontalDragUpdate: (details) {
          // Scrub de la tête de lecture, même au-dessus d'une barre : la
          // position LOCALE (repère de la barre) est ramenée en espace vue.
          if (pinching || moving) return;
          onSeek(zoom.timeFor(details.localPosition.dx + pinnedLeft, width));
        },
        onLongPressStart: (details) => onMoveStart(),
        onLongPressMoveUpdate: (details) {
          if (!moving) return;
          final deltaMs = (details.localOffsetFromOrigin.dx * msPerPx).round();
          // Sans borne haute : dépasser la fin du projet l'étend (durée
          // dérivée du contenu), et le défilement automatique suit le geste.
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
                  ((keyTime - spanStart) /
                                  math.max(1, spanEnd - spanStart))
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
          ],
        ),
      ),
    );
  }
}

/// Barre d'une piste d'os (mode squelette) : plage première → dernière
/// keyframe de la piste, losanges de keyframes supprimables près de la tête
/// de lecture, déplacement de toute la piste par appui long + glisser
/// horizontal (keyframes décalées en bloc, courbes conservées). Pas de
/// poignées de fenêtre : une piste d'os n'a pas de fenêtre d'affichage.
class _BoneBar extends StatelessWidget {
  const _BoneBar({
    required this.bone,
    required this.rig,
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
    required this.onMoveStart,
    required this.onMoveChanged,
    required this.onMoveEnd,
    required this.onDeleteKeyframe,
    required this.onFollowEdge,
  });

  final RigBone bone;
  final SkeletonRig rig;
  final TimelineZoomState zoom;
  final int timeMs;
  final int toleranceMs;
  final double laneTop;
  final double width;
  final bool pinching;
  final bool moving;
  final int movingOriginMs;
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<int> onSeek;
  final VoidCallback onMoveStart;
  final ValueChanged<int> onMoveChanged;
  final VoidCallback onMoveEnd;
  final ValueChanged<int> onDeleteKeyframe;
  final ValueChanged<int> onFollowEdge;

  static const Color _color = Color(0xFF3ECF8E);

  @override
  Widget build(BuildContext context) {
    final track = rig.trackOf(bone.id)!;
    final first = track.first.timeMs;
    final last = track.last.timeMs;
    final msPerPx = zoom.msPerPixel(width);
    final left = zoom.xFor(first, width);
    // Bornée à la vue : une barre plus large est coupée, pas débordante.
    final barWidth = math.min(
      math.max(24.0, (last - first) / msPerPx),
      width,
    );
    final pinnedLeft = math.min(left, math.max(0.0, width - 24));

    return Positioned(
      left: pinnedLeft,
      top: laneTop + 3,
      width: barWidth,
      height: TimelineView.laneHeight - 8,
      child: GestureDetector(
        onTap: onSelect,
        onHorizontalDragUpdate: (details) {
          // Scrub de la tête de lecture, même au-dessus d'une barre : la
          // position LOCALE (repère de la barre) est ramenée en espace vue.
          if (pinching || moving) return;
          onSeek(zoom.timeFor(details.localPosition.dx + pinnedLeft, width));
        },
        onLongPressStart: (details) => onMoveStart(),
        onLongPressMoveUpdate: (details) {
          if (!moving) return;
          final deltaMs = (details.localOffsetFromOrigin.dx * msPerPx).round();
          final target = math.max(0, movingOriginMs + deltaMs);
          onMoveChanged(target);
          onFollowEdge(math.max(0, last + (target - movingOriginMs)));
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
                color: _color.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: moving
                      ? Colors.white
                      : selected
                      ? _color
                      : _color.withValues(alpha: 0.5),
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
                '\u{1F9B4} ${bone.name}',
                style: const TextStyle(fontSize: 11, color: Colors.white),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            for (final key in track)
              Align(
                alignment: Alignment(
                  ((key.timeMs - first) / math.max(1, last - first)).clamp(
                            0.0,
                            1.0,
                          ) *
                          2 -
                      1,
                  0.75,
                ),
                child: (key.timeMs - timeMs).abs() <= toleranceMs
                    ? GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onDeleteKeyframe(key.timeMs),
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
          ],
        ),
      ),
    );
  }
}
