import 'package:flutter/material.dart';

import '../models/skeleton.dart';
import 'selection_geometry.dart';

/// Overlay du rig, dessiné en espace écran (au-dessus de la scène) : un
/// segment + articulation par os, l'os sélectionné mis en évidence, poignées
/// d'extrémité tactiles. Jamais rendu dans les exports (l'écran seul l'ajoute).
class RigOverlayPainter extends CustomPainter {
  const RigOverlayPainter({
    required this.rig,
    required this.pose,
    required this.geo,
    this.selectedBoneId,
  });

  final SkeletonRig rig;
  final SkeletonPose pose;
  final SceneGeometry geo;
  final String? selectedBoneId;

  static const Color _idle = Color(0xFFC084FC);
  static const Color _selected = Color(0xFFF2C94C);

  /// Rayons de toucher, en pixels écran (constants à toute échelle de vue).
  static const double tipTouchSlop = 26;
  static const double segmentTouchSlop = 13;

  @override
  void paint(Canvas canvas, Size size) {
    for (final bone in rig.bones) {
      final frame = pose.frameOf(bone.id);
      if (frame == null) continue;
      final selected = bone.id == selectedBoneId;
      final color = selected ? _selected : _idle;
      final joint = geo.sceneToCanvas(frame.joint);
      final tip = geo.sceneToCanvas(frame.tip);

      canvas.drawLine(
        joint,
        tip,
        Paint()
          ..color = color
          ..strokeWidth = selected ? 4 : 3
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true,
      );
      canvas.drawCircle(
        joint,
        4.5,
        Paint()..color = const Color(0xFF0B0D12),
      );
      canvas.drawCircle(
        joint,
        4.5,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      // Poignée d'extrémité : cible de rotation (glisser = tourner l'os).
      canvas.drawCircle(tip, 6.5, Paint()..color = const Color(0xFF0B0D12));
      canvas.drawCircle(
        tip,
        6.5,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      if (selected) {
        final painter = TextPainter(
          text: TextSpan(
            text: bone.name,
            style: const TextStyle(fontSize: 10, color: Colors.white70),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(
          canvas,
          tip + const Offset(10, -16),
        );
      }
    }
  }

  /// Os touché par un point canvas : les extrémités d'abord (rotation),
  /// puis les segments (sélection). Itère du dernier os vers le premier
  /// (dessiné au-dessus = touché en premier).
  static String? hitBone(
    SkeletonPose pose,
    SkeletonRig rig,
    SceneGeometry geo,
    Offset canvasPoint,
  ) {
    String? segmentHit;
    for (final bone in rig.bones.reversed) {
      final frame = pose.frameOf(bone.id);
      if (frame == null) continue;
      final joint = geo.sceneToCanvas(frame.joint);
      final tip = geo.sceneToCanvas(frame.tip);
      if ((canvasPoint - tip).distance <= tipTouchSlop) return bone.id;
      if (segmentHit == null &&
          _distanceToSegment(canvasPoint, joint, tip) <= segmentTouchSlop) {
        segmentHit = bone.id;
      }
    }
    return segmentHit;
  }

  static double _distanceToSegment(Offset point, Offset a, Offset b) {
    final ab = b - a;
    final lengthSquared = ab.distanceSquared;
    if (lengthSquared < 0.0001) return (point - a).distance;
    final t = ((point - a).dx * ab.dx + (point - a).dy * ab.dy) /
        lengthSquared;
    final clamped = t.clamp(0.0, 1.0);
    return (point - (a + ab * clamped)).distance;
  }

  @override
  bool shouldRepaint(covariant RigOverlayPainter oldDelegate) => true;
}
