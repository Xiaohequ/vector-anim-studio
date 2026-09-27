import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../models/animation.dart';
import '../models/skeleton.dart';
import 'selection_geometry.dart';

/// Reciblage « sans saut » (v0.14) : re-lier une pièce ou une couche à un
/// autre os en RÉÉCRIVANT ses poses pour que sa position MONDE reste
/// identique au changement. La correction est rigide (translation +
/// rotation) : l'échelle, l'épaisseur et l'opacité ne sont pas touchées.
///
/// Exact tant que les os ne sont pas étirés (stretchX/Y = 1) ; sous stretch
/// la pose d'os devient non-rigide : le gond reste exact, la pose de la
/// pièce est approchée. Entre deux keyframes (interpolation linéaire de la
/// pose contre composition rigide de l'os), la position monde dérive un peu
/// : seules les poses existantes (base + keyframes) sont préservées.
class BindingRetarget {
  BindingRetarget._();

  /// Re-lie la pièce entière vers [newBoneId]. Pièce non liée (ou déjà
  /// liée au même os) → liaison simple, aucune pose réécrite.
  static void retargetShape(
    SkeletonRig rig,
    VectorShape shape,
    String newBoneId,
    int timeMs,
  ) {
    final oldBinding = rig.bindingForShape(shape.id);
    if (oldBinding == null || oldBinding.boneId == newBoneId) {
      rig.bindShape(shape.id, newBoneId);
      return;
    }
    final oldBoneId = oldBinding.boneId;

    // 1. Capturer la pose de chaque instant AVANT toute écriture — valueAt
    //    porte les valeurs des keyframes précédentes (« carried »), la
    //    première écriture fausserait les poses capturées ensuite.
    final times = <int>{timeMs, for (final k in shape.keyframes) k.timeMs};
    final poses = <int, Pose2D>{
      for (final t in times) t: SelectionGeometry.shapePose(shape, t),
    };

    // 2. Pointer la liaison vers le nouvel os. Le rig ne dépend pas des
    //    liaisons : la même évaluation sert l'ancien et le nouvel os.
    rig.bindShape(shape.id, newBoneId);

    // 3. Réécrire chaque pose : le GOND (centre + S·pivot) et la rotation
    //    monde sont conservés — tout le contenu de la pièce suit (même
    //    chaîne rigide que celle du painter).
    for (final entry in poses.entries) {
      final pose = SkeletonPose.evaluate(rig, entry.key);
      final oldBone = pose.frameOf(oldBoneId);
      final newBone = pose.frameOf(newBoneId);
      if (oldBone == null || newBone == null) continue;
      final sp = entry.value;
      final sx = sp.sx == 0 ? 0.0001 : sp.sx;
      final sy = sp.sy == 0 ? 0.0001 : sp.sy;
      final gond = sp.rotationCenterScene();
      final newGond = newBone.mapPointInverse(oldBone.mapPoint(gond));
      final newRotation = sp.rotation + oldBone.worldDelta - newBone.worldDelta;
      final newX = newGond.dx - sx * sp.pivotDx;
      final newY = newGond.dy - sy * sp.pivotDy;
      if (entry.key == timeMs) {
        shape.setBase(AnimatableProperty.x, newX);
        shape.setBase(AnimatableProperty.y, newY);
        shape.setBase(AnimatableProperty.rotation, newRotation);
      }
      for (final keyframe in shape.keyframes) {
        if (keyframe.timeMs != entry.key) continue;
        keyframe.values[AnimatableProperty.x] = newX;
        keyframe.values[AnimatableProperty.y] = newY;
        keyframe.values[AnimatableProperty.rotation] = newRotation;
      }
    }
  }

  /// Re-lie une couche vers [newBoneId]. Les couches ne sont pas animables :
  /// une seule correction (au temps du curseur) suffit ; l'origine monde est
  /// exacte, la rotation recalée du delta d'angle entre les deux os.
  static void retargetLayer(
    SkeletonRig rig,
    VectorShape shape,
    ShapeLayer layer,
    String newBoneId,
    int timeMs,
  ) {
    final oldBinding = rig.bindingForLayer(shape.id, layer.id);
    if (oldBinding == null || oldBinding.boneId == newBoneId) {
      rig.bindLayer(shape.id, layer.id, newBoneId);
      return;
    }
    // Pose de la couche AVANT changement (les couches sont statiques).
    final sp = SelectionGeometry.shapePose(shape, timeMs);
    final origin = _layerOrigin(sp, layer);
    rig.bindLayer(shape.id, layer.id, newBoneId);
    final pose = SkeletonPose.evaluate(rig, timeMs);
    final oldBone = pose.frameOf(oldBinding.boneId);
    final newBone = pose.frameOf(newBoneId);
    if (oldBone == null || newBone == null) return;
    final local = _layerLocalFromOrigin(
      sp,
      newBone.mapPointInverse(oldBone.mapPoint(origin)),
    );
    layer.x = local.dx;
    layer.y = local.dy;
    layer.rotation += oldBone.worldDelta - newBone.worldDelta;
  }

  /// Origine (centre) d'une couche en coordonnées scène — même composition
  /// que SelectionGeometry.layerPose (chaîne pivot de la forme gérée).
  static Offset _layerOrigin(Pose2D sp, ShapeLayer layer) {
    final lx = (layer.x - sp.pivotDx) * sp.sx;
    final ly = (layer.y - sp.pivotDy) * sp.sy;
    final cosR = math.cos(sp.rotation);
    final sinR = math.sin(sp.rotation);
    return Offset(
      sp.origin.dx + sp.sx * sp.pivotDx + lx * cosR - ly * sinR,
      sp.origin.dy + sp.sy * sp.pivotDy + lx * sinR + ly * cosR,
    );
  }

  /// Inverse de [_layerOrigin] : une origine scène → coords locales de la
  /// couche.
  static Offset _layerLocalFromOrigin(Pose2D sp, Offset origin) {
    final rpx = sp.sx * sp.pivotDx;
    final rpy = sp.sy * sp.pivotDy;
    final rel = origin - sp.origin - Offset(rpx, rpy);
    final cosR = math.cos(-sp.rotation);
    final sinR = math.sin(-sp.rotation);
    final rotated = Offset(
      rel.dx * cosR - rel.dy * sinR,
      rel.dx * sinR + rel.dy * cosR,
    );
    final sx = sp.sx == 0 ? 0.0001 : sp.sx;
    final sy = sp.sy == 0 ? 0.0001 : sp.sy;
    return Offset(sp.pivotDx + rotated.dx / sx, sp.pivotDy + rotated.dy / sy);
  }
}
