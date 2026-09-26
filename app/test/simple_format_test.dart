import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_anim_studio/engine/simple_animation_format.dart';
import 'package:vector_anim_studio/models/animation.dart';
import 'package:vector_anim_studio/models/skeleton.dart';

AnimationProject _vectorProject() {
  final project = AnimationProject.blank(name: 'Film');
  final shape = VectorShape(name: 'Bloc', startMs: 0, endMs: 2000);
  shape.x = 100;
  shape.y = 200;
  shape.rotation = math.pi / 4;
  shape.scale = 2;
  shape.opacity = 0.5;
  shape.layers.add(ShapeLayer(name: 'L', kind: ShapeKind.rect));
  shape.layers.first.colorValue = 0xFFFF5C5C;
  shape.layers.first.width = 120;
  shape.layers.first.height = 80;
  shape.layers.first.filled = false;
  shape.layers.first.strokeWidth = 6;
  shape.upsertKeyframe(500, <AnimatableProperty, double>{
    AnimatableProperty.x: 120,
    AnimatableProperty.y: 100,
    AnimatableProperty.rotation: math.pi,
    AnimatableProperty.scale: 1,
    AnimatableProperty.opacity: 1,
    AnimatableProperty.strokeWidth: 1,
  });
  project.shapes.add(shape);
  return project;
}

void main() {
  group('export vasf-1', () {
    test(
      'les champs canvas et forme sont convertis (secondes, degrés, hex)',
      () {
        final json = SimpleAnimationFormat.toJson(_vectorProject());
        expect(json['version'], 1);
        expect(json['name'], 'Film');
        final canvas = json['canvas'] as Map<String, Object?>;
        expect(canvas['width'], 360);
        expect(canvas['height'], 640);
        expect(canvas['background'], '#14161C');
        final shapes = json['shapes'] as List<Object?>;
        final bloc = shapes.first as Map<String, Object?>;
        expect(bloc['name'], 'Bloc');
        expect(bloc['type'], 'rect');
        expect(bloc['color'], '#FF5C5C');
        expect(bloc['filled'], false);
        expect(bloc['strokeWidth'], 6);
        expect(bloc['width'], 120);
        expect(bloc['height'], 80);
        expect(bloc['x'], 100);
        expect(bloc['y'], 200);
        expect(bloc['rotation'], closeTo(45, 1e-9));
        expect(bloc['scale'], 2);
        expect(bloc['opacity'], 0.5);
        expect(bloc['start'], 0);
        expect(bloc['end'], 2);
      },
    );

    test('export sparse : une propriété inchangée est omise', () {
      final project = AnimationProject.blank(name: 'Film');
      final shape = VectorShape(name: 'Bloc', startMs: 0, endMs: 2000);
      shape.x = 50;
      shape.upsertKeyframe(1000, <AnimatableProperty, double>{
        AnimatableProperty.x: 150,
        AnimatableProperty.y: 200,
        AnimatableProperty.rotation: 0,
        AnimatableProperty.scale: 1,
        AnimatableProperty.opacity: 1,
        AnimatableProperty.strokeWidth: 1,
      });
      shape.upsertKeyframe(2000, <AnimatableProperty, double>{
        AnimatableProperty.x: 150,
        AnimatableProperty.y: 260,
        AnimatableProperty.rotation: 0,
        AnimatableProperty.scale: 1,
        AnimatableProperty.opacity: 1,
        AnimatableProperty.strokeWidth: 1,
      });
      project.shapes.add(shape);
      final keys =
          ((SimpleAnimationFormat.toJson(project)['shapes'] as List<Object?>)
                      .first
                  as Map<String, Object?>)['keyframes']
              as List<Object?>;
      final k0 = keys[0] as Map<String, Object?>;
      final k1 = keys[1] as Map<String, Object?>;
      expect(k0['x'], 150); // ≠ base 50 → présent
      expect(k0['y'], 200); // ≠ base 320 → présent
      expect(k0.containsKey('rotation'), isFalse); // = base 0 → omis
      // x identique à la keyframe précédente → omis (porté).
      expect(k1.containsKey('x'), isFalse);
      expect(k1['y'], 260);
    });

    test('le squelette est exporté en coordonnées monde', () {
      final project = AnimationProject.blank(
        name: 'Rat',
        type: ProjectType.skeleton,
      );
      final rig = SkeletonRig();
      final root = RigBone(
        name: 'Bras',
        offsetX: 100,
        offsetY: 320,
        restAngle: 0,
        length: 100,
      );
      final child = RigBone(
        name: 'Avant-bras',
        parentId: root.id,
        offsetX: 100,
        offsetY: 0,
        restAngle: math.pi / 2, // pointe vers le bas
        length: 80,
        z: 3,
        ikEnabled: true,
        bendSign: -1,
      );
      rig.addBone(root);
      rig.addBone(child);
      rig.upsertKeyframe(root.id, 1000, math.pi / 6); // +30°
      project.skeleton = rig;
      final shape = VectorShape(name: 'Bloc');
      project.shapes.add(shape);
      rig.bindShape(shape.id, root.id);

      final json = SimpleAnimationFormat.toJson(project);
      expect(json['skeleton'], isNotNull);
      final skeleton = json['skeleton'] as Map<String, Object?>;
      final bones = skeleton['bones'] as List<Object?>;
      final bras = bones[0] as Map<String, Object?>;
      final avant = bones[1] as Map<String, Object?>;
      expect(bras['joint'], [100, 320]);
      expect(bras['angle'], 0);
      expect(avant['parent'], 'Bras');
      // Articulation MONDE de l'enfant : (200, 320) + R(0)·(100, 0) → (200,320).
      expect(avant['joint'], [200, 320]);
      expect(avant['angle'], closeTo(90, 1e-9)); // 0 + 90
      expect(avant['length'], 80);
      expect(avant['z'], 3);
      expect(avant['ik'], true);
      expect(avant['bend'], -1);
      final bind = skeleton['bind'] as Map<String, Object?>;
      expect(bind['Bloc'], 'Bras');
      final keyframes = skeleton['keyframes'] as List<Object?>;
      final key = keyframes.first as Map<String, Object?>;
      expect(key['bone'], 'Bras');
      expect(key['t'], 1);
      // Angle MONDE absolu : repos 0 + delta 30°.
      expect(key['angle'], closeTo(30, 1e-9));
    });
  });

  group('import vasf-1', () {
    test('round-trip vectoriel : export → import → même contenu', () {
      final original = _vectorProject();
      final json = SimpleAnimationFormat.toJson(original);
      final imported = SimpleAnimationFormat.fromJson(json);
      expect(imported.name, 'Film');
      expect(imported.width, 360);
      expect(imported.height, 640);
      expect(imported.backgroundValue, 0xFF14161C);
      final shape = imported.shapes.first;
      expect(shape.name, 'Bloc');
      expect(shape.x, 100);
      expect(shape.y, 200);
      expect(shape.rotation, closeTo(math.pi / 4, 1e-9));
      expect(shape.scale, 2);
      expect(shape.opacity, 0.5);
      expect(shape.startMs, 0);
      expect(shape.endMs, 2000);
      final layer = shape.layers.first;
      expect(layer.kind, ShapeKind.rect);
      expect(layer.colorValue, 0xFFFF5C5C);
      expect(layer.filled, false);
      expect(layer.strokeWidth, 6);
      expect(layer.width, 120);
      expect(layer.height, 80);
      // La keyframe interne (pose complète) survit au round-trip.
      expect(shape.keyframes, hasLength(1));
      expect(shape.keyframes.first.timeMs, 500);
      expect(shape.keyframes.first.valueOf(AnimatableProperty.x), 120);
      expect(shape.keyframes.first.valueOf(AnimatableProperty.y), 100);
    });

    test('keyframes partielles : les propriétés absentes sont portées', () {
      final imported = SimpleAnimationFormat.fromJson(<String, Object?>{
        'version': 1,
        'name': 'Test',
        'shapes': <Object?>[
          <String, Object?>{
            'name': 'Bloc',
            'type': 'rect',
            'x': 180,
            'y': 320,
            'end': 2,
            'keyframes': <Object?>[
              <String, Object?>{'t': 0, 'x': 100},
              <String, Object?>{
                't': 2,
                'y': 50,
                'rotation': 90,
                'easing': 'linear',
              },
            ],
          },
        ],
      });
      final shape = imported.shapes.first;
      expect(shape.keyframes, hasLength(2));
      // kf0 : x = 100, le reste = base.
      expect(shape.keyframes[0].valueOf(AnimatableProperty.x), 100);
      expect(shape.keyframes[0].valueOf(AnimatableProperty.y), 320);
      // kf1 : x porté de kf0 (=100), y = 50, rotation = 90°.
      expect(shape.keyframes[1].valueOf(AnimatableProperty.x), 100);
      expect(shape.keyframes[1].valueOf(AnimatableProperty.y), 50);
      expect(
        shape.keyframes[1].valueOf(AnimatableProperty.rotation),
        closeTo(math.pi / 2, 1e-9),
      );
      expect(shape.keyframes[1].easing, EasingKind.linear);
      // Interpolation : à mi-chemin, y = (320+50)/2.
      expect(shape.valueAt(AnimatableProperty.y, 1000), closeTo(185, 1e-9));
    });

    test('défauts : canvas 720×1280/25 fps, couleur, taille, centre', () {
      final imported = SimpleAnimationFormat.fromJson(<String, Object?>{
        'version': 1,
        'shapes': <Object?>[
          <String, Object?>{'name': 'Bloc', 'type': 'circle', 'end': 1},
        ],
      });
      expect(imported.width, 720);
      expect(imported.height, 1280);
      expect(imported.fps, 25);
      expect(imported.backgroundValue, 0xFF14161C);
      final shape = imported.shapes.first;
      expect(shape.x, 360);
      expect(shape.y, 640);
      final layer = shape.layers.first;
      expect(layer.colorValue, 0xFF5B8DEF);
      expect(layer.filled, true);
      expect(layer.strokeWidth, 4);
      expect(layer.width, 110);
      expect(layer.height, 110);
    });

    test('path : bbox et points centrés', () {
      final imported = SimpleAnimationFormat.fromJson(<String, Object?>{
        'version': 1,
        'shapes': <Object?>[
          <String, Object?>{
            'name': 'Nuage',
            'type': 'path',
            'points': <Object?>[
              <Object?>[0, 0],
              <Object?>[100, 0],
              <Object?>[100, 50],
              <Object?>[0, 50],
            ],
            'end': 1,
          },
        ],
      });
      final layer = imported.shapes.first.layers.first;
      expect(layer.width, 100);
      expect(layer.height, 50);
      // Points convertis : le nuage est recentré sur l'origine de la couche.
      expect(layer.points.first, const Offset(0, 0));
      expect(layer.points[1], const Offset(100, 0));
      expect(layer.points[2], const Offset(100, 50));
      expect(layer.points.last, const Offset(0, 50));
      // L'application rend `point − (w/2, h/2)` : les 4 coins rendus sont
      // (−50,−25) (50,−25) (50,25) (−50,25) — nuage centré sur la forme ✓.
      final rendered = layer.points
          .map((p) => Offset(p.dx - layer.width / 2, p.dy - layer.height / 2))
          .toList();
      expect(rendered[0], const Offset(-50, -25));
      expect(rendered[1], const Offset(50, -25));
      expect(rendered[2], const Offset(50, 25));
      expect(rendered[3], const Offset(-50, 25));
    });

    test('squelette : angles monde → internes, keyframes absolues', () {
      final imported = SimpleAnimationFormat.fromJson(<String, Object?>{
        'version': 1,
        'name': 'Rat',
        'shapes': <Object?>[
          <String, Object?>{'name': 'Bloc', 'type': 'rect', 'end': 3},
        ],
        'skeleton': <String, Object?>{
          'bones': <Object?>[
            <String, Object?>{
              'name': 'Bras',
              'joint': <Object?>[100, 320],
              'angle': 0,
              'length': 100,
            },
            <String, Object?>{
              'name': 'Avant-bras',
              'parent': 'Bras',
              'joint': <Object?>[200, 420],
              'angle': 90,
              'length': 80,
              'ik': true,
              'bend': -1,
              'z': 2,
            },
          ],
          'bind': <String, Object?>{'Bloc': 'Bras'},
          'keyframes': <Object?>[
            <String, Object?>{
              'bone': 'Bras',
              't': 1,
              'angle': 30,
              'easing': 'linear',
            },
            <String, Object?>{
              'bone': 'Avant-bras',
              't': 2,
              // Angle monde absolu 30° : repos monde = 90° → delta = −60°.
              'angle': 30,
            },
          ],
        },
      });
      expect(imported.type, ProjectType.skeleton);
      final rig = imported.skeleton!;
      final root = rig.bones[0];
      final child = rig.bones[1];
      expect(root.offsetX, 100);
      expect(root.offsetY, 320);
      expect(root.restAngle, 0);
      // Enfant : joint (200,420) = parentJoint (100,320) + R(0)·(100,100) →
      // offset local (100,100), restAngle = 90° − 0°.
      expect(child.offsetX, closeTo(100, 1e-9));
      expect(child.offsetY, closeTo(100, 1e-9));
      expect(child.restAngle, closeTo(math.pi / 2, 1e-9));
      expect(child.ikEnabled, true);
      expect(child.bendSign, -1);
      expect(child.z, 2);
      // Repos : les frames monde retombent sur les valeurs vasf.
      final pose = SkeletonPose.evaluate(rig, 0);
      expect(pose.frameOf(child.id)!.jointRest, const Offset(200, 420));
      expect(
        pose.frameOf(child.id)!.worldAngleRest,
        closeTo(math.pi / 2, 1e-9),
      );
      // Keyframes : delta = angleMonde − reposMonde.
      expect(rig.angleDeltaAt(root.id, 1000), closeTo(math.pi / 6, 1e-9));
      expect(rig.angleDeltaAt(child.id, 2000), closeTo(-math.pi / 3, 1e-9));
      // La liaison a suivi.
      expect(rig.boneIdForShape(imported.shapes.first.id), root.id);
    });

    test('erreurs collectées avec chemins (français)', () {
      try {
        SimpleAnimationFormat.fromJson(<String, Object?>{
          'version': 9,
          'shapes': <Object?>[
            <String, Object?>{
              'name': 'Bloc',
              'type': 'blob',
              'color': 'rouge',
              'keyframes': <Object?>[
                <String, Object?>{'t': 0.5, 'x': 'abc', 'easing': 'zigzag'},
              ],
            },
          ],
          'skeleton': <String, Object?>{
            'bones': <Object?>[
              <String, Object?>{
                'name': 'B',
                'parent': 'Inconnu',
                'joint': <Object?>[0],
              },
            ],
            'bind': <String, Object?>{'Fantôme': 'B'},
          },
        });
        fail('SimpleFormatException attendu');
      } on SimpleFormatException catch (error) {
        final text = error.toString();
        expect(text, contains('version'));
        expect(text, contains('shapes[0].type'));
        expect(text, contains('shapes[0].color'));
        expect(text, contains('shapes[0].keyframes[0].x'));
        expect(text, contains('easing inconnu'));
        expect(text, contains('skeleton.bones[0].parent'));
        expect(text, contains('skeleton.bind : forme « Fantôme » inconnue'));
      }
    });

    test('noms de formes en double : uniquifiés, la liaison suit', () {
      final imported = SimpleAnimationFormat.fromJson(<String, Object?>{
        'version': 1,
        'shapes': <Object?>[
          <String, Object?>{'name': 'Bloc', 'type': 'rect', 'end': 1},
          <String, Object?>{'name': 'Bloc', 'type': 'circle', 'end': 1},
        ],
        'skeleton': <String, Object?>{
          'bones': <Object?>[
            <String, Object?>{
              'name': 'B1',
              'joint': <Object?>[0, 0],
              'angle': 0,
              'length': 50,
            },
          ],
          'bind': <String, Object?>{'Bloc 2': 'B1'},
        },
      });
      expect(imported.shapes[0].name, 'Bloc');
      expect(imported.shapes[1].name, 'Bloc 2');
      expect(
        imported.skeleton!.boneIdForShape(imported.shapes[1].id),
        imported.skeleton!.bones.first.id,
      );
    });

    test('round-trip squelette complet : export → import → même rendu', () {
      final original = AnimationProject.blank(
        name: 'Rat',
        type: ProjectType.skeleton,
      );
      final rig = SkeletonRig();
      final root = RigBone(
        name: 'Bras',
        offsetX: 100,
        offsetY: 320,
        restAngle: 0,
        length: 100,
      );
      final child = RigBone(
        name: 'Avant-bras',
        parentId: root.id,
        offsetX: 100,
        offsetY: 0,
        restAngle: math.pi / 2,
        length: 80,
      );
      rig.addBone(root);
      rig.addBone(child);
      rig.upsertKeyframe(root.id, 1000, math.pi / 6);
      rig.upsertKeyframe(child.id, 2000, -math.pi / 12);
      original.skeleton = rig;
      final shape = VectorShape(name: 'Bloc');
      original.shapes.add(shape);
      rig.bindShape(shape.id, root.id);

      final json = SimpleAnimationFormat.toJson(original);
      final imported = SimpleAnimationFormat.fromJson(json);
      final rig2 = imported.skeleton!;
      for (final t in const [0, 500, 1000, 1500, 2000]) {
        final a = SkeletonPose.evaluate(rig, t);
        final b = SkeletonPose.evaluate(rig2, t);
        for (final bone in rig.bones) {
          final fa = a.frameOf(bone.id)!;
          final matching = rig2.bones.firstWhere((x) => x.name == bone.name);
          final fb = b.frameOf(matching.id)!;
          expect(fb.joint.dx, closeTo(fa.joint.dx, 1e-6), reason: 't=$t');
          expect(fb.joint.dy, closeTo(fa.joint.dy, 1e-6), reason: 't=$t');
          expect(fb.worldAngle, closeTo(fa.worldAngle, 1e-9), reason: 't=$t');
          expect(fb.tip.dx, closeTo(fa.tip.dx, 1e-6), reason: 't=$t');
          expect(fb.tip.dy, closeTo(fa.tip.dy, 1e-6), reason: 't=$t');
        }
      }
      expect(rig2.boneIdForShape(imported.shapes.first.id), isNotNull);
    });
  });
}
