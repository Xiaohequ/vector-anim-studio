import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_anim_studio/engine/selection_geometry.dart';
import 'package:vector_anim_studio/models/animation.dart';
import 'package:vector_anim_studio/models/skeleton.dart';

void main() {
  group('évaluation FK', () {
    test('chaîne statique : racine + enfant orthogonal', () {
      final rig = SkeletonRig();
      final root = RigBone(
        name: 'Torse',
        offsetX: 100,
        offsetY: 100,
        restAngle: 0,
        length: 100,
      );
      final child = RigBone(
        name: 'Bras',
        parentId: root.id,
        offsetX: 100, // attaché au bout du torse
        offsetY: 0,
        restAngle: math.pi / 2,
        length: 50,
      );
      rig.addBone(root);
      rig.addBone(child);

      final pose = SkeletonPose.evaluate(rig, 0);
      final rootFrame = pose.frameOf(root.id)!;
      final childFrame = pose.frameOf(child.id)!;

      // Racine : joint posé en projet, pointe vers +X.
      expect(rootFrame.joint, const Offset(100, 100));
      expect(rootFrame.worldAngle, 0);
      expect(rootFrame.tip, const Offset(200, 100));
      // Enfant : articulation au bout du parent, direction orthogonale (y bas).
      expect(childFrame.joint, const Offset(200, 100));
      expect(childFrame.worldAngle, closeTo(math.pi / 2, 1e-9));
      expect(childFrame.tip, const Offset(200, 150));
    });

    test('le delta de la racine entraîne la chaîne (positions et angles)', () {
      final rig = SkeletonRig();
      final root = RigBone(
        name: 'R',
        offsetX: 100,
        offsetY: 100,
        length: 100,
      );
      final child = RigBone(
        name: 'C',
        parentId: root.id,
        offsetX: 100,
        offsetY: 0,
        restAngle: math.pi / 2,
        length: 50,
      );
      rig.addBone(root);
      rig.addBone(child);
      // Rotation de la racine de 90° au temps 1000 ms.
      rig.upsertKeyframe(root.id, 1000, math.pi / 2);

      final pose = SkeletonPose.evaluate(rig, 1000);
      final rootFrame = pose.frameOf(root.id)!;
      final childFrame = pose.frameOf(child.id)!;

      // Racine : pointe vers +Y (bas) — tip = (100, 200).
      expect(rootFrame.worldAngle, closeTo(math.pi / 2, 1e-9));
      expect(rootFrame.tip, const Offset(100, 200));
      // L'enfant orbite : son articulation suit le bout du parent.
      expect(childFrame.joint, const Offset(100, 200));
      // Son angle de repos relatif s'ajoute au delta du parent.
      expect(childFrame.worldAngle, closeTo(math.pi, 1e-9));
      expect(childFrame.tip, closeToOffset(const Offset(50, 200)));
    });

    test('repos tenu avant la première et après la dernière keyframe', () {
      final rig = SkeletonRig();
      final bone = RigBone(name: 'B', offsetX: 0, offsetY: 0, length: 10);
      rig.addBone(bone);
      rig.upsertKeyframe(bone.id, 1000, 0.5);
      rig.upsertKeyframe(bone.id, 2000, 1.0);
      expect(rig.angleDeltaAt(bone.id, 0), 0.5);
      expect(rig.angleDeltaAt(bone.id, 500), closeTo(0.5, 1e-9));
      expect(rig.angleDeltaAt(bone.id, 1500), closeTo(0.75, 1e-9));
      expect(rig.angleDeltaAt(bone.id, 9999), 1.0);
    });
  });

  group('piste d\'os : édition', () {
    test('upsert/remplace/tri, keyframeNear, suppression', () {
      final rig = SkeletonRig();
      rig.upsertKeyframe('b', 1000, 0.4);
      rig.upsertKeyframe('b', 500, 0.2);
      expect(rig.trackOf('b')!.map((k) => k.timeMs), <int>[500, 1000]);
      // Remplacement au même temps.
      rig.upsertKeyframe('b', 1000, 0.6);
      expect(rig.trackOf('b')!.singleWhere((k) => k.timeMs == 1000).angleDelta,
          0.6);
      expect(rig.keyframeNear('b', 990, 20)!.timeMs, 1000);
      expect(rig.keyframeNear('b', 100, 20), isNull);
      rig.removeKeyframeAt('b', 1000);
      expect(rig.trackOf('b')!.single.timeMs, 500);
      rig.removeKeyframeAt('b', 500);
      expect(rig.hasKeyframes('b'), isFalse);
      // Piste vide retirée de la map (pas de barre fantôme).
      expect(rig.tracks.containsKey('b'), isFalse);
    });

    test('shiftTrackTo préserve les écarts et courbes', () {
      final rig = SkeletonRig();
      rig.upsertKeyframe('b', 1000, 0.1, easing: EasingKind.easeOut);
      rig.upsertKeyframe('b', 2000, 0.3, easing: EasingKind.linear);
      rig.shiftTrackTo('b', 2500);
      final track = rig.trackOf('b')!;
      expect(track.first.timeMs, 2500);
      expect(track.last.timeMs, 3500);
      expect(track.first.easing, EasingKind.easeOut);
      expect(track.last.easing, EasingKind.linear);
      // Rabotage à zéro quand le décalage descend sous 0.
      rig.shiftTrack('b', -5000);
      expect(rig.trackOf('b')!.map((k) => k.timeMs), everyElement(0));
    });

    test('maxKeyframeTimeMs → durée du projet squelette (plancher 4 s)', () {
      final project = AnimationProject.blank(type: ProjectType.skeleton);
      expect(project.durationMs, 0); // pas de rig → pas de durée
      final rig = SkeletonRig();
      project.skeleton = rig;
      expect(project.durationMs, 0); // rig sans os
      rig.addBone(RigBone(name: 'B'));
      expect(project.durationMs, 4000); // plancher éditable, sans keyframe
      rig.upsertKeyframe('b1', 1800, 1);
      expect(project.durationMs, 4000);
      rig.upsertKeyframe('b1', 9000, 1);
      expect(project.durationMs, 9000); // les keyframes dépassent le plancher
    });
  });

  group('édition du rig', () {
    test('bindShape remplace la liaison précédente', () {
      final rig = SkeletonRig();
      final a = RigBone(name: 'A');
      final b = RigBone(name: 'B');
      rig.addBone(a);
      rig.addBone(b);
      rig.bindShape('s1', a.id);
      expect(rig.boneIdForShape('s1'), a.id);
      rig.bindShape('s1', b.id);
      expect(rig.bindings.length, 1);
      expect(rig.boneIdForShape('s1'), b.id);
    });

    test('removeBone re-parente les enfants et purge liaisons + piste', () {
      final rig = SkeletonRig();
      final root = RigBone(name: 'Root');
      final mid = RigBone(name: 'Mid', parentId: root.id);
      final leaf = RigBone(name: 'Leaf', parentId: mid.id);
      rig.addBone(root);
      rig.addBone(mid);
      rig.addBone(leaf);
      rig.bindShape('corps', mid.id);
      rig.upsertKeyframe(mid.id, 500, 0.2);

      rig.removeBone(mid.id);

      expect(rig.bones.map((b) => b.id), containsAll(<String>[root.id, leaf.id]));
      expect(leaf.parentId, root.id); // re-parenté
      expect(rig.isBound('corps'), isFalse); // liaison purgée
      expect(rig.tracks.containsKey(mid.id), isFalse); // piste purgée
    });
  });

  test('round-trip JSON du rig complet', () {
    final rig = SkeletonRig(name: 'Rat');
    final root = RigBone(
      name: 'Torse',
      offsetX: 120,
      offsetY: 300,
      restAngle: -math.pi / 6,
      length: 90,
    );
    final child = RigBone(
      name: 'Cuisse',
      parentId: root.id,
      offsetX: 70,
      offsetY: -10,
      restAngle: 0.8,
      length: 40,
    );
    rig.addBone(root);
    rig.addBone(child);
    rig.bindShape('bloc-1', child.id);
    rig.upsertKeyframe(root.id, 0, 0, easing: EasingKind.linear);
    rig.upsertKeyframe(root.id, 1200, 0.7, easing: EasingKind.step);

    final restored = SkeletonRig.fromJson(
      (rig.toJson() as Map).cast<String, Object?>(),
    );
    expect(restored.name, 'Rat');
    expect(restored.bones.length, 2);
    expect(restored.bones[1].parentId, root.id);
    expect(restored.bones[1].offsetX, closeTo(70, 1e-9));
    expect(restored.bones[1].restAngle, closeTo(0.8, 1e-9));
    expect(restored.boneIdForShape('bloc-1'), child.id);
    expect(restored.trackOf(root.id)![1].angleDelta, 0.7);
    expect(restored.trackOf(root.id)![1].easing, EasingKind.step);
    expect(restored.maxKeyframeTimeMs, 1200);
  });

  test('pose rig-aware : l\'origine de la pièce orbite l\'articulation', () {
    final shape = VectorShape(name: 'P', x: 150, y: 250);
    final rig = SkeletonRig();
    final bone = RigBone(
      name: 'B',
      offsetX: 100,
      offsetY: 100,
      length: 50,
    );
    rig.addBone(bone);
    final pose = SkeletonPose.evaluate(rig, 500);
    final frame = pose.frameOf(bone.id)!;

    // Sans mouvement : identité (origine = placement de repos).
    final plain = SelectionGeometry.shapePose(shape, 500);
    final withRig = SelectionGeometry.shapePoseWithRig(shape, 500, frame);
    expect(withRig.origin, plain.origin);
    expect(withRig.rotation, plain.rotation);

    // Rotation de 180° : l'origine passe à l'opposé du joint.
    rig.upsertKeyframe(bone.id, 1000, math.pi);
    final rotatedPose = SkeletonPose.evaluate(rig, 1000);
    final rotatedFrame = rotatedPose.frameOf(bone.id)!;
    final moved =
        SelectionGeometry.shapePoseWithRig(shape, 1000, rotatedFrame);
    // p = (150, 250) ; jointRest = (100, 100) → p − joint = (50, 150)
    // R(180°) → (−50, −150) → origine = (50, −50).
    expect(moved.origin, closeToOffset(const Offset(50, -50)));
    // L'angle de repos (0) + delta 180° = π.
    expect(moved.rotation, closeTo(math.pi, 1e-9));
  });
}

Matcher closeToOffset(Offset expected, [double epsilon = 1e-6]) =>
    _CloseToOffset(expected, epsilon);

class _CloseToOffset extends Matcher {
  const _CloseToOffset(this.expected, this.epsilon);

  final Offset expected;
  final double epsilon;

  @override
  bool matches(Object? item, Map<dynamic, dynamic> matchState) =>
      item is Offset &&
      (item.dx - expected.dx).abs() <= epsilon &&
      (item.dy - expected.dy).abs() <= epsilon;

  @override
  Description describe(Description description) =>
      description.add('proche de $expected (±$epsilon)');
}
