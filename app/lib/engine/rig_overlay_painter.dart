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
    this.showOnlySelected = false,
  });

  final SkeletonRig rig;
  final SkeletonPose pose;
  final SceneGeometry geo;
  final String? selectedBoneId;

  /// En studio, l'overlay est volontairement réduit à l'os sélectionné.
  /// L'éditeur d'os conserve la valeur par défaut pour afficher toute la
  /// chaîne en cours de dessin.
  final bool showOnlySelected;

  static const Color _idle = Color(0xFFC084FC);
  static const Color _selected = Color(0xFFF2C94C);

  /// Rayons de toucher, en pixels écran (constants à toute échelle de vue).
  static const double tipTouchSlop = 26;
  static const double segmentTouchSlop = 13;

  /// Poignée de rotation (v0.9.3) : distance écran entre l'extrémité de
  /// l'os et la poignée (dans le prolongement de l'os), et tolérance de
  /// toucher. La poignée n'existe que pour l'os sélectionné — pivoter via
  /// l'extrémité (2e point) de l'os est désactivé.
  static const double rotationHandleDistance = 26;
  static const double rotationHandleTouchSlop = 24;

  /// Canvas point de la poignée de rotation d'un os, ou null.
  static Offset? rotationHandle(
    SkeletonPose pose,
    SkeletonRig rig,
    SceneGeometry geo,
    String boneId,
  ) {
    final frame = pose.frameOf(boneId);
    if (frame == null) return null;
    final tip = geo.sceneToCanvas(frame.tip);
    return tip + Offset.fromDirection(frame.worldAngle, rotationHandleDistance);
  }

  /// Le point canvas touche-t-il la poignée de rotation de [boneId] ?
  static bool hitRotationHandle(
    SkeletonPose pose,
    SkeletonRig rig,
    SceneGeometry geo,
    String boneId,
    Offset canvasPoint,
  ) {
    final handle = rotationHandle(pose, rig, geo, boneId);
    if (handle == null) return false;
    return (canvasPoint - handle).distance <= rotationHandleTouchSlop;
  }

  /// Le point canvas touche-t-il l'effecteur IK (extrémité du DERNIER os de
  /// la chaîne — v0.15 : chaînes N os, l'ancien enfant unique est le cas
  /// longueur 2) de l'os racine [boneId] ?
  static bool hitIkEndEffector(
    SkeletonPose pose,
    SkeletonRig rig,
    SceneGeometry geo,
    String boneId,
    Offset canvasPoint,
  ) {
    final end = rig.ikEffectorOf(boneId);
    if (end == null || end.id == boneId) {
      // Chaîne d'un seul os : l'effecteur est la poignée de rotation de
      // l'os lui-même — pas de losange dédié (évite le recouvrement).
      return false;
    }
    final frame = pose.frameOf(end.id);
    if (frame == null) return false;
    final tip = geo.sceneToCanvas(frame.tip);
    return (canvasPoint - tip).distance <= tipTouchSlop;
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final bone in rig.bones) {
      if (showOnlySelected &&
          (selectedBoneId == null || bone.id != selectedBoneId)) {
        continue;
      }
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
      canvas.drawCircle(joint, 4.5, Paint()..color = const Color(0xFF0B0D12));
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
        // Poignée de rotation : dans le prolongement de l'os (v0.9.3).
        final handle =
            tip +
            Offset.fromDirection(frame.worldAngle, rotationHandleDistance);
        canvas.drawLine(
          tip,
          handle,
          Paint()
            ..color = color
            ..strokeWidth = 1.5
            ..isAntiAlias = true,
        );
        canvas.drawCircle(
          handle,
          7.5,
          Paint()..color = const Color(0xFF0B0D12),
        );
        canvas.drawCircle(
          handle,
          7.5,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        final painter = TextPainter(
          text: TextSpan(
            text: bone.name,
            style: const TextStyle(fontSize: 10, color: Colors.white70),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, tip + const Offset(10, -16));
      }
      // Marqueur IK (v0.10) : losange vert sur l'effecteur — glisser cette
      // extrémité résout la CHAÎNE (v0.15 : N os, l'enfant unique = cas 2 os)
      // au lieu de sélectionner/pivoter.
      if (bone.ikEnabled) {
        final end = rig.ikEffectorOf(bone.id);
        final endFrame = end == null || end.id == bone.id
            ? null
            : pose.frameOf(end.id);
        if (endFrame != null) {
          final effector = geo.sceneToCanvas(endFrame.tip);
          final path = Path()
            ..moveTo(effector.dx, effector.dy - 9)
            ..lineTo(effector.dx + 9, effector.dy)
            ..lineTo(effector.dx, effector.dy + 9)
            ..lineTo(effector.dx - 9, effector.dy)
            ..close();
          canvas.drawPath(path, Paint()..color = const Color(0x663ECF8E));
          canvas.drawPath(
            path,
            Paint()
              ..color = const Color(0xFF3ECF8E)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        }
      }
    }
  }

  /// Os touché par un point canvas : les extrémités d'abord (attachement
  /// d'un nouvel os et sélection), puis les segments (sélection). Itère du
  /// dernier os vers le premier (dessiné au-dessus = touché en premier).
  /// NB : depuis la v0.9.3, la rotation d'os passe par la poignée dédiée —
  /// toucher l'extrémité sélectionne, ne pivote plus.
  static String? hitBone(
    SkeletonPose pose,
    SkeletonRig rig,
    SceneGeometry geo,
    Offset canvasPoint, {
    bool Function(RigBone bone)? isVisible,
  }) {
    String? segmentHit;
    for (final bone in rig.bones.reversed) {
      if (isVisible != null && !isVisible(bone)) continue;
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
    final t = ((point - a).dx * ab.dx + (point - a).dy * ab.dy) / lengthSquared;
    final clamped = t.clamp(0.0, 1.0);
    return (point - (a + ab * clamped)).distance;
  }

  @override
  bool shouldRepaint(covariant RigOverlayPainter oldDelegate) => true;
}
