import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_anim_studio/engine/binding_retarget.dart';
import 'package:vector_anim_studio/engine/selection_geometry.dart';
import 'package:vector_anim_studio/models/animation.dart';
import 'package:vector_anim_studio/models/skeleton.dart';

/// Projet squelette de test : racine animée (−90° → −74° → −90° → −106°)
/// + un os enfant sans keyframe. Les tests y ajoutent leurs pièces.
AnimationProject _project() {
  final rig = SkeletonRig();
  final root = RigBone(
    name: 'Racine',
    offsetX: 200,
    offsetY: 850,
    restAngle: -math.pi / 2,
    length: 40,
  );
  rig.bones.add(root);
  rig.bones.add(
    RigBone(
      name: 'Bras',
      parentId: root.id,
      offsetX: 40,
      offsetY: 0,
      length: 60,
    ),
  );
  rig.tracks[root.id] = <BoneKeyframe>[
    BoneKeyframe(timeMs: 0),
    BoneKeyframe(timeMs: 600, angleDelta: math.pi / 12),
    BoneKeyframe(timeMs: 1200),
    BoneKeyframe(timeMs: 1800, angleDelta: -math.pi / 12),
    BoneKeyframe(timeMs: 2400),
  ];
  // L'enfant a un delta PROPRE (−30° à 600 ms) : sans lui, il suivrait la
  // racine avec le même delta et le reciblage racine→enfant serait un
  // no-op mathématique (aucune pose à corriger).
  final child = rig.bones.last;
  rig.tracks[child.id] = <BoneKeyframe>[
    BoneKeyframe(timeMs: 0),
    BoneKeyframe(timeMs: 600, angleDelta: -math.pi / 6),
    BoneKeyframe(timeMs: 2400),
  ];
  return AnimationProject(
    name: 'Test reciblage',
    type: ProjectType.skeleton,
    skeleton: rig,
    width: 720,
    height: 1280,
    fps: 25,
  );
}

({Offset origin, double rotation}) _worldOf(
  AnimationProject project,
  VectorShape shape,
  int timeMs,
) {
  final rig = project.skeleton!;
  final pose = SkeletonPose.evaluate(rig, timeMs);
  final frame = pose.frameOf(rig.bindingForShape(shape.id)!.boneId)!;
  final sp = SelectionGeometry.shapePose(shape, timeMs);
  return (
    origin: frame.mapPoint(sp.origin),
    rotation: sp.rotation + frame.worldDelta,
  );
}

Offset _layerOriginOf(VectorShape shape, ShapeLayer layer, int timeMs) {
  final sp = SelectionGeometry.shapePose(shape, timeMs);
  final lx = (layer.x - sp.pivotDx) * sp.sx;
  final ly = (layer.y - sp.pivotDy) * sp.sy;
  final c = math.cos(sp.rotation);
  final s = math.sin(sp.rotation);
  return Offset(
    sp.origin.dx + sp.sx * sp.pivotDx + lx * c - ly * s,
    sp.origin.dy + sp.sy * sp.pivotDy + lx * s + ly * c,
  );
}

void main() {
  test(
    'reciblage : la pièce suit le nouvel os sans saut (poses complètes)',
    () {
      final project = _project();
      final rig = project.skeleton!;
      final shape = VectorShape(name: 'Pièce', x: 200, y: 700);
      shape.layers.add(
        ShapeLayer(name: 'Corps', kind: ShapeKind.rect, width: 70, height: 70),
      );
      project.shapes.add(shape);
      rig.bindShape(shape.id, rig.bones.first.id);
      // Keyframes de pose sur la pièce À TOUS les temps de la piste (poses
      // partielles) : sinon la zone avant la 1re keyframe est « portée »
      // depuis kf600 et le monde y est par définition non préservable.
      shape.keyframes.add(ShapeKeyframe(timeMs: 0));
      shape.keyframes.add(
        ShapeKeyframe(
          timeMs: 600,
          values: <AnimatableProperty, double>{
            AnimatableProperty.rotation: math.pi / 6,
          },
        ),
      );
      shape.keyframes.add(ShapeKeyframe(timeMs: 1200));
      shape.keyframes.add(ShapeKeyframe(timeMs: 1800));
      shape.keyframes.add(ShapeKeyframe(timeMs: 2400));

      final before = <int, ({Offset origin, double rotation})>{
        for (final t in const [0, 600, 1200, 1800, 2400])
          t: _worldOf(project, shape, t),
      };

      final child = rig.bones.last;
      BindingRetarget.retargetShape(rig, shape, child.id, 600);

      // Position/rotation MONDE identiques à chaque pose.
      for (final entry in before.entries) {
        final after = _worldOf(project, shape, entry.key);
        expect(
          (after.origin - entry.value.origin).distance,
          lessThan(0.01),
          reason: 'temps ${entry.key}',
        );
        var d = (after.rotation - entry.value.rotation) % (2 * math.pi);
        if (d > math.pi) d -= 2 * math.pi;
        if (d < -math.pi) d += 2 * math.pi;
        expect(d.abs(), lessThan(0.001), reason: 'temps ${entry.key}');
      }
      // La pose de base a bien été réécrite (le gond a suivi).
      expect(shape.x == 200 && shape.y == 700, isFalse);
    },
  );

  test('reciblage au milieu d un segment : pose interpolée préservée', () {
    final project = _project();
    final rig = project.skeleton!;
    final shape = VectorShape(name: 'Pièce', x: 200, y: 700);
    shape.layers.add(
      ShapeLayer(name: 'Corps', kind: ShapeKind.rect, width: 70, height: 70),
    );
    project.shapes.add(shape);
    rig.bindShape(shape.id, rig.bones.first.id);

    final before = _worldOf(project, shape, 300);
    BindingRetarget.retargetShape(rig, shape, rig.bones.last.id, 300);
    final after = _worldOf(project, shape, 300);
    expect((after.origin - before.origin).distance, lessThan(0.01));
  });

  test('reciblage sans keyframe : os au repos, la pièce ne bouge pas', () {
    final project = _project();
    final rig = project.skeleton!;
    final root = rig.bones.first;
    final child = rig.bones.last;
    rig.tracks.remove(root.id);
    final shape = VectorShape(name: 'Pièce', x: 200, y: 700);
    shape.layers.add(
      ShapeLayer(name: 'Corps', kind: ShapeKind.rect, width: 70, height: 70),
    );
    project.shapes.add(shape);
    rig.bindShape(shape.id, root.id);

    BindingRetarget.retargetShape(rig, shape, child.id, 0);

    // Identité au repos : la pose de base est conservée.
    expect(shape.x, closeTo(200, 0.001));
    expect(shape.y, closeTo(700, 0.001));
    expect(rig.bindingForShape(shape.id)!.boneId, child.id);
  });

  test('pièce non liée : liaison simple, poses intactes', () {
    final project = _project();
    final rig = project.skeleton!;
    final shape = VectorShape(name: 'Pièce', x: 200, y: 700);
    shape.layers.add(
      ShapeLayer(name: 'Corps', kind: ShapeKind.rect, width: 70, height: 70),
    );
    project.shapes.add(shape);

    BindingRetarget.retargetShape(rig, shape, rig.bones.last.id, 600);

    expect(shape.x, 200);
    expect(shape.y, 700);
    expect(rig.isBound(shape.id), isTrue);
  });

  test('reciblage d une couche : la lampe reste en place au curseur', () {
    final project = _project();
    final rig = project.skeleton!;
    final shape = VectorShape(name: 'Lampadaire', x: 200, y: 860);
    shape.layers.add(
      ShapeLayer(
        name: 'Poteau',
        kind: ShapeKind.rect,
        width: 36,
        height: 200,
        y: 90,
      ),
    );
    final lampe = ShapeLayer(
      name: 'Lampe',
      kind: ShapeKind.circle,
      width: 74,
      height: 74,
      y: -30,
    );
    shape.layers.add(lampe);
    project.shapes.add(shape);
    rig.bindLayer(shape.id, lampe.id, rig.bones.first.id);

    final poseBefore = SkeletonPose.evaluate(rig, 600);
    final before = poseBefore
        .frameOf(rig.bones.first.id)!
        .mapPoint(_layerOriginOf(shape, lampe, 600));

    BindingRetarget.retargetLayer(rig, shape, lampe, rig.bones.last.id, 600);

    final poseAfter = SkeletonPose.evaluate(rig, 600);
    final after = poseAfter
        .frameOf(rig.bones.last.id)!
        .mapPoint(_layerOriginOf(shape, lampe, 600));
    expect((after - before).distance, lessThan(0.01));
    // La rotation locale est recalée du delta d'angle entre les deux os
    // (racine +15°, bras −30° → correction de +45°).
    final fAfter = poseAfter.frameOf(rig.bones.last.id)!;
    final fRoot = poseBefore.frameOf(rig.bones.first.id)!;
    expect(
      lampe.rotation - (fRoot.worldDelta - fAfter.worldDelta),
      closeTo(0, 0.001),
    );
  });
}
