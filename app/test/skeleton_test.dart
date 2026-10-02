import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_anim_studio/engine/selection_geometry.dart';
import 'package:vector_anim_studio/models/animation.dart';
import 'package:vector_anim_studio/models/skeleton.dart';

void main() {
  group('miroir d’os', () {
    test(
      'miroir H du sous-arbre conserve une pose réfléchie et son inverse',
      () {
        final rig = SkeletonRig();
        final root = RigBone(
          id: 'r',
          name: 'R',
          offsetX: 100,
          offsetY: 200,
          restAngle: 0.2,
          length: 80,
          ikEnabled: true,
          bendSign: 1,
        );
        final child = RigBone(
          id: 'c',
          name: 'C',
          parentId: 'r',
          offsetX: 80,
          offsetY: 0,
          restAngle: 0.4,
          length: 50,
        );
        final outside = RigBone(
          id: 'o',
          name: 'O',
          offsetX: 20,
          offsetY: 20,
          length: 20,
        );
        rig.bones.addAll([root, child, outside]);
        rig.tracks['r'] = [
          BoneKeyframe(timeMs: 0, angleDelta: 0.1, tx: 4, ty: 3),
          BoneKeyframe(timeMs: 1000, angleDelta: 0.8, tx: 12, ty: -2),
        ];
        rig.tracks['c'] = [
          BoneKeyframe(timeMs: 0, angleDelta: -0.3, tx: 5, ty: 7),
          BoneKeyframe(timeMs: 1000, angleDelta: 0.2, tx: -3, ty: 4),
        ];
        final before = SkeletonPose.evaluate(rig, 500);
        final pivot = const Offset(180, 200);
        final subtreeIds = {'r', 'c'};
        final beforeFrames = {
          for (final id in subtreeIds) id: before.frameOf(id)!,
        };
        final outsideBefore = before.frameOf('o')!;

        rig.mirrorSubtree('r', horizontal: true, pivot: pivot);
        final after = SkeletonPose.evaluate(rig, 500);
        for (final id in subtreeIds) {
          final a = after.frameOf(id)!;
          final b = beforeFrames[id]!;
          expect(a.joint.dx, closeTo(2 * pivot.dx - b.joint.dx, 1e-6));
          expect(a.joint.dy, closeTo(b.joint.dy, 1e-6));
          expect(a.tip.dx, closeTo(2 * pivot.dx - b.tip.dx, 1e-6));
          expect(a.tip.dy, closeTo(b.tip.dy, 1e-6));
        }
        expect(after.frameOf('o')!.joint, outsideBefore.joint);
        expect(root.bendSign, -1);

        // Miroir une seconde fois autour du même pivot = données d'origine.
        rig.mirrorSubtree('r', horizontal: true, pivot: pivot);
        final restored = SkeletonPose.evaluate(rig, 500);
        for (final id in subtreeIds) {
          final a = restored.frameOf(id)!;
          final b = beforeFrames[id]!;
          expect(a.joint.dx, closeTo(b.joint.dx, 1e-6));
          expect(a.joint.dy, closeTo(b.joint.dy, 1e-6));
          expect(a.tip.dx, closeTo(b.tip.dx, 1e-6));
          expect(a.tip.dy, closeTo(b.tip.dy, 1e-6));
        }
        expect(root.bendSign, 1);
      },
    );
  });

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
      final root = RigBone(name: 'R', offsetX: 100, offsetY: 100, length: 100);
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
      expect(
        rig.trackOf('b')!.singleWhere((k) => k.timeMs == 1000).angleDelta,
        0.6,
      );
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

      expect(
        rig.bones.map((b) => b.id),
        containsAll(<String>[root.id, leaf.id]),
      );
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
    final bone = RigBone(name: 'B', offsetX: 100, offsetY: 100, length: 50);
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
    final moved = SelectionGeometry.shapePoseWithRig(shape, 1000, rotatedFrame);
    // p = (150, 250) ; jointRest = (100, 100) → p − joint = (50, 150)
    // R(180°) → (−50, −150) → origine = (50, −50).
    expect(moved.origin, closeToOffset(const Offset(50, -50)));
    // L'angle de repos (0) + delta 180° = π.
    expect(moved.rotation, closeTo(math.pi, 1e-9));
  });

  group('carry et translation du repos (v0.9.1)', () {
    test(
      'translateBoneRest : racine en projet, enfant dans le repère du parent',
      () {
        final rig = SkeletonRig();
        final root = RigBone(
          name: 'Root',
          offsetX: 100,
          offsetY: 100,
          restAngle: math.pi / 2,
          length: 100,
        );
        final child = RigBone(
          name: 'Child',
          parentId: root.id,
          offsetX: 100,
          offsetY: 0,
          restAngle: 0,
          length: 50,
        );
        rig.addBone(root);
        rig.addBone(child);
        final pose = SkeletonPose.evaluate(rig, 0);

        // Racine : delta monde appliqué tel quel à l'offset projet.
        rig.translateBoneRest(root, pose, const Offset(10, -5));
        expect(root.offsetX, 110);
        expect(root.offsetY, 95);

        // Enfant : delta monde (0, 10) = le long du parent (qui pointe +y) →
        // delta local +x.
        rig.translateBoneRest(child, pose, const Offset(0, 10));
        expect(child.offsetX, closeTo(110, 1e-9));
        expect(child.offsetY, closeTo(0, 1e-9));
      },
    );

    test('carryBoundPieces emporte la pièce liée lors d\'une pose du rig', () {
      final project = AnimationProject.blank(type: ProjectType.skeleton);
      final rig = SkeletonRig();
      project.skeleton = rig;
      final bone = RigBone(name: 'B', offsetX: 100, offsetY: 100, length: 80);
      rig.addBone(bone);
      final piece = VectorShape(name: 'P', x: 180, y: 100);
      project.shapes.add(piece);
      rig.bindShape(piece.id, bone.id);

      final before = SkeletonPose.evaluate(rig, 0);
      bone.restAngle = math.pi / 2; // pose : l'os tourne de 90°
      final after = SkeletonPose.evaluate(rig, 0);
      carryBoundPieces(project, rig, before, after, 0);

      // Centre (180,100) tourné de 90° autour du joint (100,100) → (100,180) ;
      // la rotation de la pièce suit.
      expect(piece.x, closeTo(100, 1e-6));
      expect(piece.y, closeTo(180, 1e-6));
      expect(piece.rotation, closeTo(math.pi / 2, 1e-6));
    });

    test('carryBoundPieces descend la chaîne : pièce liée à un enfant', () {
      final project = AnimationProject.blank(type: ProjectType.skeleton);
      final rig = SkeletonRig();
      project.skeleton = rig;
      final root = RigBone(name: 'Root', offsetX: 0, offsetY: 0, length: 100);
      final child = RigBone(
        name: 'Child',
        parentId: root.id,
        offsetX: 100,
        offsetY: 0,
        restAngle: 0,
        length: 50,
      );
      rig.addBone(root);
      rig.addBone(child);
      final piece = VectorShape(name: 'P', x: 100, y: 0);
      project.shapes.add(piece);
      rig.bindShape(piece.id, child.id);

      final before = SkeletonPose.evaluate(rig, 0);
      root.restAngle = math.pi / 2;
      final after = SkeletonPose.evaluate(rig, 0);
      carryBoundPieces(project, rig, before, after, 0);

      // La pièce collée à l'articulation enfant (100,0) suit le rig :
      // l'articulation passe à (0,100), rotation π/2.
      expect(piece.x, closeTo(0, 1e-6));
      expect(piece.y, closeTo(100, 1e-6));
      expect(piece.rotation, closeTo(math.pi / 2, 1e-6));
    });

    test('carryBoundPieces ne touche pas les pièces non liées', () {
      final project = AnimationProject.blank(type: ProjectType.skeleton);
      final rig = SkeletonRig();
      project.skeleton = rig;
      rig.addBone(RigBone(name: 'B', offsetX: 100, offsetY: 100, length: 80));
      final free = VectorShape(name: 'Libre', x: 42, y: 55);
      project.shapes.add(free);

      final before = SkeletonPose.evaluate(rig, 0);
      rig.bones.first.restAngle = 1.0;
      final after = SkeletonPose.evaluate(rig, 0);
      carryBoundPieces(project, rig, before, after, 0);

      expect(free.x, 42);
      expect(free.y, 55);
    });

    test('carryBoundPieces avec pièce animée : pose écrite au curseur', () {
      final project = AnimationProject.blank(type: ProjectType.skeleton);
      final rig = SkeletonRig();
      project.skeleton = rig;
      final bone = RigBone(name: 'B', offsetX: 0, offsetY: 0, length: 80);
      rig.addBone(bone);
      final piece = VectorShape(name: 'P', x: 100, y: 0);
      project.shapes.add(piece);
      rig.bindShape(piece.id, bone.id);
      piece.upsertKeyframe(0, piece.poseAt(0));
      piece.upsertKeyframe(1000, piece.poseAt(1000));

      final before = SkeletonPose.evaluate(rig, 500);
      bone.restAngle = math.pi / 2;
      final after = SkeletonPose.evaluate(rig, 500);
      carryBoundPieces(project, rig, before, after, 500);

      // La pose au curseur (500 ms) est mise à jour, les autres intactes.
      final pose = piece.keyframeNear(500, 100)!;
      expect(pose.valueOf(AnimatableProperty.x), closeTo(0, 1e-6));
      expect(pose.valueOf(AnimatableProperty.y), closeTo(100, 1e-6));
      expect(
        pose.valueOf(AnimatableProperty.rotation),
        closeTo(math.pi / 2, 1e-6),
      );
      expect(piece.keyframes.length, 3);
    });
  });

  group('création d\'os attaché (v0.9.2)', () {
    test('boneBetween : ancrage au poignet, l\'os 2 suit l\'os 1', () {
      final rig = SkeletonRig();
      final parent = RigBone(
        name: 'P',
        offsetX: 100,
        offsetY: 100,
        length: 100,
      );
      rig.addBone(parent);
      final frame = SkeletonPose.evaluate(rig, 0).frameOf(parent.id)!;

      // os 2 : ancrage à l'extrémité (poignet) du parent, extrémité vers le bas.
      final child = boneBetween(
        frame.tip,
        frame.tip + const Offset(0, 50),
        name: 'Os 2',
        parentId: parent.id,
        parentFrame: frame,
      );
      rig.addBone(child);
      final rest = SkeletonPose.evaluate(rig, 0);
      expect(
        rest.frameOf(child.id)!.joint,
        closeToOffset(const Offset(200, 100)),
      );

      // Pose du parent (rotation de repos) : l'ancrage de l'os 2 suit le
      // poignet — (200,100) → (100,200), le rig tourne rigidement.
      parent.restAngle = math.pi / 2;
      final posed = SkeletonPose.evaluate(rig, 0);
      final childFrame = posed.frameOf(child.id)!;
      expect(childFrame.jointRest, closeToOffset(const Offset(100, 200)));
    });

    test('boneBetween sans parent : os racine posé au point touché', () {
      final bone = boneBetween(
        const Offset(40, 60),
        const Offset(140, 60),
        name: 'Os libre',
      );
      expect(bone.parentId, isNull);
      expect(bone.offsetX, 40);
      expect(bone.offsetY, 60);
      expect(bone.restAngle, 0);
      expect(bone.length, 100);
    });

    test('boneBetween sur un parent animé : ancrage au repos exact', () {
      final rig = SkeletonRig();
      final parent = RigBone(name: 'P', offsetX: 0, offsetY: 0, length: 100);
      rig.addBone(parent);
      rig.upsertKeyframe(parent.id, 0, 0, easing: EasingKind.linear);
      rig.upsertKeyframe(
        parent.id,
        1000,
        math.pi / 2,
        easing: EasingKind.linear,
      );
      // À t = 500 : parent à 45° — ancrage de l'os 2 au poignet courant.
      final t = 500;
      final frame = SkeletonPose.evaluate(rig, t).frameOf(parent.id)!;
      final child = boneBetween(
        frame.tip,
        frame.tip + const Offset(50, 0),
        name: 'Os 2',
        parentId: parent.id,
        parentFrame: frame,
      );
      rig.addBone(child);
      final pose = SkeletonPose.evaluate(rig, t);
      // Le poignet courant (à 45°) : (70.7, 70.7).
      expect(
        pose.frameOf(child.id)!.joint,
        closeToOffset(Offset(100 * math.sqrt2 / 2, 100 * math.sqrt2 / 2)),
      );
      // Au repos (t = 0), l'ancrage reste au poignet de repos (100, 0).
      final rest = SkeletonPose.evaluate(rig, 0);
      expect(
        rest.frameOf(child.id)!.joint,
        closeToOffset(const Offset(100, 0)),
      );
    });
  });

  group('reparentage sans saut (v0.9.3)', () {
    test('reparentBone → racine : l\'os reste ancré sur place', () {
      final rig = SkeletonRig();
      final parent = RigBone(
        name: 'Os 1',
        offsetX: 100,
        offsetY: 100,
        length: 100,
      );
      final child = RigBone(
        name: 'Os 2',
        parentId: parent.id,
        offsetX: 100,
        offsetY: 0,
        restAngle: 0,
        length: 50,
      );
      rig.addBone(parent);
      rig.addBone(child);
      final pose = SkeletonPose.evaluate(rig, 0);

      rig.reparentBone(child, null, pose);
      expect(child.parentId, isNull);
      // Repos monde préservé : joint (200,100), angle 0 — os visible,
      // ancré sur place (v0.9.2 le faisait sauter → invisible).
      final after = SkeletonPose.evaluate(rig, 0);
      final frame = after.frameOf(child.id)!;
      expect(frame.jointRest, closeToOffset(const Offset(200, 100)));
      expect(frame.worldAngleRest, 0);

      // Bouger l'os 1 n'impacte plus l'os 2.
      rig.translateBoneRest(parent, after, const Offset(30, 0));
      final after2 = SkeletonPose.evaluate(rig, 0);
      expect(
        after2.frameOf(child.id)!.jointRest,
        closeToOffset(const Offset(200, 100)),
      );
    });

    test('reparentBone vers un autre os : géométrie de repos préservée', () {
      final rig = SkeletonRig();
      final a = RigBone(name: 'A', offsetX: 0, offsetY: 0, length: 100);
      final b = RigBone(
        name: 'B',
        offsetX: 0,
        offsetY: 300,
        restAngle: math.pi,
        length: 100,
      );
      final child = RigBone(
        name: 'C',
        parentId: a.id,
        offsetX: 100,
        offsetY: 0,
        restAngle: 0,
        length: 40,
      );
      rig.addBone(a);
      rig.addBone(b);
      rig.addBone(child);
      final pose = SkeletonPose.evaluate(rig, 0);
      expect(
        pose.frameOf(child.id)!.jointRest,
        closeToOffset(const Offset(100, 0)),
      );

      rig.reparentBone(child, b.id, pose);
      final after = SkeletonPose.evaluate(rig, 0);
      final frame = after.frameOf(child.id)!;
      expect(frame.jointRest, closeToOffset(const Offset(100, 0)));
      expect(frame.worldAngleRest, 0);
      // Désormais l'os suit B, plus A.
      rig.translateBoneRest(b, after, const Offset(0, 50));
      final after2 = SkeletonPose.evaluate(rig, 0);
      expect(
        after2.frameOf(child.id)!.jointRest,
        closeToOffset(const Offset(100, 50)),
      );
    });
  });

  group('liaison au niveau couche (v0.9.6)', () {
    test('bindLayer remplace, unbindLayer purge, forme entière séparée', () {
      final rig = SkeletonRig();
      final a = RigBone(name: 'A');
      final b = RigBone(name: 'B');
      rig.addBone(a);
      rig.addBone(b);

      rig.bindLayer('s1', 'l1', a.id);
      expect(rig.bindingForLayer('s1', 'l1')?.boneId, a.id);
      expect(rig.bindingForLayer('s1', 'l2'), isNull);
      expect(rig.bindingForShape('s1'), isNull); // liaisons indépendantes

      // Re-lier la même couche : remplacement, pas de doublon.
      rig.bindLayer('s1', 'l1', b.id);
      expect(rig.bindings.length, 1);
      expect(rig.bindingForLayer('s1', 'l1')?.boneId, b.id);

      rig.unbindLayer('s1', 'l1');
      expect(rig.bindings, isEmpty);
    });

    test(
      'round-trip JSON de la liaison de couche (back-compat sans layerId)',
      () {
        final rig = SkeletonRig();
        rig.bindShape('s1', 'b1');
        rig.bindLayer('s2', 'l2', 'b2');
        final restored = SkeletonRig.fromJson(
          (rig.toJson() as Map).cast<String, Object?>(),
        );
        expect(restored.bindingForShape('s1')?.layerId, isNull);
        expect(restored.bindingForLayer('s2', 'l2')?.boneId, 'b2');
      },
    );

    test('duplicateBindings emporte forme et couches (ids remappés)', () {
      final rig = SkeletonRig();
      final a = RigBone(name: 'A');
      rig.addBone(a);
      rig.bindShape('s1', a.id);
      rig.bindLayer('s1', 'old-l1', a.id);
      rig.duplicateBindings('s1', 's1-clone', {'old-l1': 'new-l1'});
      expect(rig.bindingForShape('s1-clone')?.boneId, a.id);
      expect(rig.bindingForLayer('s1-clone', 'new-l1')?.boneId, a.id);
      expect(rig.bindingForLayer('s1-clone', 'old-l1'), isNull);
    });

    test('carryBoundPieces emporte la couche liée (repère forme conservé)', () {
      final project = AnimationProject.blank(type: ProjectType.skeleton);
      final rig = SkeletonRig();
      project.skeleton = rig;
      final bone = RigBone(name: 'B', offsetX: 0, offsetY: 0, length: 80);
      rig.addBone(bone);
      // Forme à (100,100) sans rotation ; couche ancrée à (50,0) → ancrage
      // monde de repos (150,100).
      final shape = VectorShape(name: 'P', x: 100, y: 100);
      shape.layers.add(
        ShapeLayer(name: 'L', kind: ShapeKind.rect, x: 50, y: 0),
      );
      project.shapes.add(shape);
      rig.bindLayer(shape.id, shape.layers.first.id, bone.id);

      final before = SkeletonPose.evaluate(rig, 0);
      bone.restAngle = math.pi / 2; // pose : l'os tourne de 90°
      final after = SkeletonPose.evaluate(rig, 0);
      carryBoundPieces(project, rig, before, after, 0);

      // L'ancrage monde (150,100) tourne de 90° autour du joint (0,0) →
      // (−100,150) ; en repère forme (origine (100,100), rotation nulle) :
      // (−200,50). Rotation de la couche +90°, pose de la forme intacte.
      expect(shape.layers.first.x, closeTo(-200, 1e-6));
      expect(shape.layers.first.y, closeTo(50, 1e-6));
      expect(shape.layers.first.rotation, closeTo(math.pi / 2, 1e-6));
      expect(shape.x, 100);
      expect(shape.y, 100);
    });
  });

  group('IK 2 os (v0.10)', () {
    test('solveTwoBoneIk : chaîne symétrique atteint la cible', () {
      // L1 = L2 = 50, cible (60,0) : alpha = acos(0,6) ≈ 0,9273, coude
      // symétrique de part et d'autre de la direction cible.
      final (pa, ca) = solveTwoBoneIk(
        joint: Offset.zero,
        length1: 50,
        length2: 50,
        target: const Offset(60, 0),
        bend: 1,
      );
      expect(pa, closeTo(0.9273, 1e-3));
      expect(ca, closeTo(-0.9273, 1e-3));
      // Le bout de la chaîne tombe sur la cible.
      final elbow = Offset(50 * math.cos(pa), 50 * math.sin(pa));
      final tip = elbow + Offset(50 * math.cos(ca), 50 * math.sin(ca));
      expect(tip, closeToOffset(const Offset(60, 0), 1e-3));
      // bend −1 : miroir (angles opposés).
      final (pa2, ca2) = solveTwoBoneIk(
        joint: Offset.zero,
        length1: 50,
        length2: 50,
        target: const Offset(60, 0),
        bend: -1,
      );
      expect(pa2, closeTo(-pa, 1e-9));
      expect(ca2, closeTo(-ca, 1e-9));
    });

    test('solveTwoBoneIk : cible hors de portée = chaîne tendue', () {
      final (pa, ca) = solveTwoBoneIk(
        joint: Offset.zero,
        length1: 50,
        length2: 50,
        target: const Offset(1000, 0),
        bend: 1,
      );
      // d est borné à L1+L2−ε : la chaîne est QUASI tendue (résidu d'arrondi
      // d'acos ≈ 0,014 rad), pas parfaitement droite.
      expect(pa, closeTo(0, 0.05));
      expect(ca, closeTo(0, 0.05));
    });

    test('onlyChildOf : enfant unique, multiple, aucun', () {
      final rig = SkeletonRig();
      final parent = RigBone(name: 'P');
      final a = RigBone(name: 'A', parentId: parent.id);
      final b = RigBone(name: 'B', parentId: parent.id);
      rig.addBone(parent);
      rig.addBone(a);
      expect(rig.onlyChildOf(parent.id)?.id, a.id);
      rig.addBone(b);
      expect(rig.onlyChildOf(parent.id), isNull); // deux enfants : pas d'IK
      rig.removeBone(b.id);
      expect(rig.onlyChildOf(parent.id)?.id, a.id);
      expect(rig.onlyChildOf(a.id), isNull);
    });
  });

  group('keyframes d\'os étendues (v0.10)', () {
    test('samplers opacité/étirement/écrasement : interp + tenue + neutre', () {
      final rig = SkeletonRig();
      final bone = RigBone(name: 'B', length: 10);
      rig.addBone(bone);
      // Sans piste : valeurs neutres.
      expect(rig.opacityAt(bone.id, 500), 1);
      expect(rig.stretchAt(bone.id, 500), 1);
      expect(rig.squashAt(bone.id, 500), 1);
      rig.upsertKeyframe(bone.id, 1000, 0, opacity: 0.0, stretch: 0.5);
      rig.upsertKeyframe(bone.id, 2000, 0, opacity: 1.0, stretch: 2.0);
      expect(rig.opacityAt(bone.id, 500), 0.0); // tenue avant
      expect(rig.opacityAt(bone.id, 2500), 1.0); // tenue après
      expect(rig.opacityAt(bone.id, 1500), closeTo(0.5, 1e-9));
      expect(rig.stretchAt(bone.id, 1500), closeTo(1.25, 1e-9));
      expect(rig.squashAt(bone.id, 1500), 1); // jamais écrite
    });

    test('upsertKeyframe fusionne : l\'angle n\'écrase pas l\'opacité', () {
      final rig = SkeletonRig();
      rig.upsertKeyframe('b', 1000, 0.5, opacity: 0.4, stretch: 1.5);
      // Écriture d'angle à la même keyframe : opacité conservée.
      rig.upsertKeyframe('b', 1000, 1.0);
      var key = rig.trackOf('b')!.first;
      expect(key.angleDelta, 1.0);
      expect(key.opacity, 0.4);
      expect(key.stretch, 1.5);
      // Écriture d'opacité : angle conservé, easing conservé.
      rig.setKeyframeEasing('b', 1000, EasingKind.linear);
      rig.upsertKeyframe('b', 1000, 1.0, opacity: 0.7);
      key = rig.trackOf('b')!.first;
      expect(key.angleDelta, 1.0);
      expect(key.opacity, 0.7);
      expect(key.easing, EasingKind.linear);
    });

    test(
      'FK : le stretch/écrasement de l\'os déforme et entraîne la chaîne',
      () {
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
          restAngle: 0,
          length: 50,
        );
        rig.addBone(root);
        rig.addBone(child);
        // Stretch le long de la racine (2×), écrasement perpendiculaire 0,5.
        rig.upsertKeyframe(root.id, 1000, 0, stretch: 2, squash: 0.5);

        final pose = SkeletonPose.evaluate(rig, 1000);
        final rootFrame = pose.frameOf(root.id)!;
        final childFrame = pose.frameOf(child.id)!;
        // L'os s'étire : tip = (100,100) + 200·(+X).
        expect(rootFrame.tip, closeToOffset(const Offset(300, 100)));
        // L'articulation de l'enfant suit le stretch du parent : offset
        // (100,0) → (200,0) dans le repère du parent.
        expect(childFrame.joint, closeToOffset(const Offset(300, 100)));
        // L'enfant garde SA géométrie : 50 vers +X.
        expect(childFrame.tip, closeToOffset(const Offset(350, 100)));
        // mapPoint : le point de repos (200,100) (bout au repos) suit
        // l'étirement → (300,100).
        expect(
          rootFrame.mapPoint(const Offset(200, 100)),
          closeToOffset(const Offset(300, 100)),
        );
      },
    );

    test('z : pièce portée (forme entière), couche, min des couches', () {
      final rig = SkeletonRig();
      final a = RigBone(name: 'A', z: 3);
      final b = RigBone(name: 'B', z: -2);
      rig.addBone(a);
      rig.addBone(b);
      expect(rig.zForShape('s1'), 0); // non liée
      // Liaison de FORME ENTIERE : z de l'os porteur.
      rig.bindShape('s2', a.id);
      expect(rig.zForShape('s2'), 3);
      // Liaison de COUCHES seulement : MIN du z des os porteurs.
      rig.bindLayer('s1', 'L1', b.id);
      rig.bindLayer('s1', 'L2', a.id);
      expect(rig.zOfLayer('s1', 'L1'), -2);
      expect(rig.zOfLayer('s1', 'L2'), 3);
      expect(rig.zForShape('s1'), -2);
    });

    test(
      'roundtrip JSON : z/ik/bend d\'os, opacity/stretch/squash de keyframe',
      () {
        final rig = SkeletonRig();
        final bone = RigBone(
          name: 'Bras',
          z: -4,
          ikEnabled: true,
          bendSign: -1,
        );
        rig.addBone(bone);
        rig.upsertKeyframe(
          bone.id,
          800,
          0.3,
          opacity: 0.25,
          stretch: 1.75,
          squash: 0.6,
        );
        final restored = SkeletonRig.fromJson(rig.toJson());
        final restoredBone = restored.bones.first;
        expect(restoredBone.z, -4);
        expect(restoredBone.ikEnabled, isTrue);
        expect(restoredBone.bendSign, -1);
        final key = restored.trackOf(restoredBone.id)!.first;
        expect(key.timeMs, 800);
        expect(key.angleDelta, 0.3);
        expect(key.opacity, 0.25);
        expect(key.stretch, 1.75);
        expect(key.squash, 0.6);
        // Os par défaut : rien n'est écrit (JSON compact).
        final plain = RigBone(name: 'P').toJson();
        expect(plain.containsKey('z'), isFalse);
        expect(plain.containsKey('ikEnabled'), isFalse);
      },
    );
  });

  group('translation d\'os + chaînes IK (v0.15)', () {
    test('translationAt échantillonne la piste (tenue + interpolation)', () {
      final rig = SkeletonRig();
      final bone = RigBone(name: 'B', length: 10);
      rig.addBone(bone);
      expect(rig.translationAt(bone.id, 0), Offset.zero);
      rig.upsertKeyframe(bone.id, 0, 0, tx: 10, ty: 0);
      rig.upsertKeyframe(
        bone.id,
        1000,
        0,
        easing: EasingKind.linear,
        tx: 30,
        ty: 20,
      );
      expect(rig.translationAt(bone.id, -5), const Offset(10, 0));
      expect(rig.translationAt(bone.id, 500), const Offset(20, 10));
      expect(rig.translationAt(bone.id, 5000), const Offset(30, 20));
    });

    test('FK : la translation bouge le joint animé, PAS la pose de repos', () {
      final rig = SkeletonRig();
      final root = RigBone(name: 'R', offsetX: 100, offsetY: 100, length: 100);
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
      // La racine glisse de +30 en X au temps 1000 (tenue avant la 1re
      // pose, comme l'angle).
      rig.upsertKeyframe(root.id, 1000, 0, tx: 30, ty: 0);

      final rest = SkeletonPose.evaluate(rig, 0);
      final animated = SkeletonPose.evaluate(rig, 1000);
      // La POSE DE REPOS (jointRest) est intacte — c'est elle qui garantit
      // l'identité au repos du rig maître.
      expect(rest.frameOf(root.id)!.jointRest, const Offset(100, 100));
      expect(rest.frameOf(child.id)!.jointRest, const Offset(200, 100));
      // Animé : le joint glisse et l'enfant suit rigidement.
      expect(animated.frameOf(root.id)!.joint, const Offset(130, 100));
      expect(animated.frameOf(child.id)!.joint, const Offset(230, 100));
      // L'angle monde ne change pas (translation ≠ rotation).
      expect(
        animated.frameOf(root.id)!.worldAngle,
        rest.frameOf(root.id)!.worldAngle,
      );
    });

    test('translation d\'un enfant : exprimée dans le repère du parent', () {
      final rig = SkeletonRig();
      final root = RigBone(
        name: 'R',
        offsetX: 100,
        offsetY: 100,
        restAngle: -math.pi / 2,
        length: 100,
      );
      final child = RigBone(
        name: 'C',
        parentId: root.id,
        offsetX: 100,
        offsetY: 0,
        length: 50,
      );
      rig.addBone(root);
      rig.addBone(child);
      // Le parent pointe vers le HAUT (−90°) : une translation de l'enfant
      // de (30, 0) dans son repère de repos glisse le LONG du parent →
      // (0, −30) monde.
      rig.upsertKeyframe(child.id, 500, 0, tx: 30, ty: 0);
      final animated = SkeletonPose.evaluate(rig, 500);
      final joint = animated.frameOf(child.id)!.joint;
      expect(joint.dx, closeTo(100, 1e-6));
      expect(joint.dy, closeTo(-30, 1e-6));
      final tip = animated.frameOf(child.id)!.tip;
      expect(tip.dx, closeTo(100, 1e-6));
      expect(tip.dy, closeTo(-80, 1e-6));
    });

    test('ikChain suit les enfants uniques et s\'arrête aux branches', () {
      final rig = SkeletonRig();
      final a = RigBone(name: 'A', length: 40);
      final b = RigBone(name: 'B', parentId: a.id, offsetX: 40, length: 30);
      final c = RigBone(name: 'C', parentId: b.id, offsetX: 30, length: 20);
      final branch1 = RigBone(
        name: 'D1',
        parentId: c.id,
        offsetX: 20,
        length: 5,
      );
      final branch2 = RigBone(
        name: 'D2',
        parentId: c.id,
        offsetX: 20,
        length: 5,
      );
      for (final bone in [a, b, c, branch1, branch2]) {
        rig.addBone(bone);
      }
      // A a un seul enfant (B)… mais la chaîne D1/D2 part de C : l'IK de A
      // s'arrête à C (2 enfants → fin de chaîne, effecteur = C).
      expect(rig.ikChain(a.id).map((b) => b.name), ['A', 'B', 'C']);
      expect(rig.ikEffectorOf(a.id)!.name, 'C');
      // Une chaîne linéaire jusqu'au bout.
      expect(rig.ikChain(b.id).map((b) => b.name), ['B', 'C']);
      expect(rig.ikEffectorOf(b.id)!.name, 'C');
      // Os absent → chaîne vide.
      expect(rig.ikChain('inconnu'), isEmpty);
    });

    test('solveChainIk (CCD) atteint la cible sur 3 os', () {
      final rootJoint = const Offset(100, 100);
      final lengths = <double>[80, 60, 40];
      final angles = solveChainIk(
        rootJoint: rootJoint,
        lengths: lengths,
        angles: const <double>[0, 0, 0],
        target: const Offset(160, 190),
      );
      // L'extrémité de la chaîne tombe sur la cible (portée = 180 > distance).
      var tip = rootJoint;
      for (var i = 0; i < lengths.length; i++) {
        tip += rotateVector(Offset(lengths[i], 0), angles[i]);
      }
      expect((tip - const Offset(160, 190)).distance, lessThan(1.0));
      // Cible hors de portée : la chaîne se tend au maximum vers elle.
      final stretched = solveChainIk(
        rootJoint: rootJoint,
        lengths: lengths,
        angles: const <double>[0, 0, 0],
        target: const Offset(100, 1000),
      );
      var stretchedTip = rootJoint;
      for (var i = 0; i < lengths.length; i++) {
        stretchedTip += rotateVector(Offset(lengths[i], 0), stretched[i]);
      }
      expect((stretchedTip - rootJoint).distance, closeTo(180, 2.0));
    });

    test('BoneKeyframe : tx/ty survivent au JSON (et rien quand nuls)', () {
      final rig = SkeletonRig();
      final bone = RigBone(name: 'B', length: 10);
      rig.addBone(bone);
      rig.upsertKeyframe(bone.id, 500, 0.3, tx: 12, ty: -5);
      final restored = SkeletonRig.fromJson(rig.toJson());
      final key = restored.trackOf(bone.id)!.first;
      expect(key.tx, 12);
      expect(key.ty, -5);
      // Une keyframe sans translation n'écrit rien (JSON compact).
      final plain = BoneKeyframe(timeMs: 100).toJson();
      expect(plain.containsKey('tx'), isFalse);
      expect(plain.containsKey('ty'), isFalse);
    });
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
