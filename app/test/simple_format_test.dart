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

  group('vasf-2', () {
    test('versions 1/2/3 acceptées, version 4 rejetée (v0.15)', () {
      final imported = SimpleAnimationFormat.fromJson(<String, Object?>{
        'version': 2,
        'shapes': <Object?>[
          <String, Object?>{'name': 'Bloc', 'type': 'rect', 'end': 1},
        ],
      });
      expect(imported.shapes, hasLength(1));
      // v0.15 : la version 3 (couleur animée, morph, translation d'os) est
      // acceptée — même sans champ v3.
      final v3 = SimpleAnimationFormat.fromJson(<String, Object?>{
        'version': 3,
        'shapes': <Object?>[
          <String, Object?>{'name': 'Bloc', 'type': 'rect', 'end': 1},
        ],
      });
      expect(v3.shapes, hasLength(1));
      expect(
        () => SimpleAnimationFormat.fromJson(<String, Object?>{
          'version': 4,
          'shapes': <Object?>[
            <String, Object?>{'name': 'Bloc', 'type': 'rect'},
          ],
        }),
        throwsA(isA<SimpleFormatException>()),
      );
      try {
        SimpleAnimationFormat.fromJson(<String, Object?>{
          'version': 4,
          'shapes': <Object?>[
            <String, Object?>{'name': 'Bloc', 'type': 'rect'},
          ],
        });
        fail('SimpleFormatException attendu');
      } on SimpleFormatException catch (error) {
        expect(error.toString(), contains('version : 1, 2 ou 3 attendu'));
      }
    });

    test('palette : les alias sont résolus partout', () {
      final imported = SimpleAnimationFormat.fromJson(<String, Object?>{
        'version': 2,
        'theme': <String, Object?>{'peau': '#FFE3C2', 'rouge': '#FF5C5C'},
        'canvas': <String, Object?>{'background': '\$rouge'},
        'shapes': <Object?>[
          <String, Object?>{
            'name': 'Tête',
            'type': 'circle',
            'color': '\$peau',
            'end': 1,
          },
        ],
      });
      expect(imported.backgroundValue, 0xFFFF5C5C);
      expect(imported.shapes.first.layers.first.colorValue, 0xFFFFE3C2);
    });

    test('alias inconnu : erreur collectée avec chemin', () {
      try {
        SimpleAnimationFormat.fromJson(<String, Object?>{
          'version': 2,
          'shapes': <Object?>[
            <String, Object?>{
              'name': 'Tête',
              'type': 'circle',
              'color': '\$ombre',
              'end': 1,
            },
          ],
        });
        fail('SimpleFormatException attendu');
      } on SimpleFormatException catch (error) {
        expect(
          error.toString(),
          contains('shapes[0].color : alias « ombre » inconnu'),
        );
      }
    });

    test('layers[] : une forme multi-couches est importée en une forme', () {
      final imported = SimpleAnimationFormat.fromJson(<String, Object?>{
        'version': 2,
        'shapes': <Object?>[
          <String, Object?>{
            'name': 'Visage',
            'x': 300,
            'y': 400,
            'end': 2,
            'layers': <Object?>[
              <String, Object?>{
                'name': 'Peau',
                'type': 'circle',
                'color': '#FFE3C2',
                'width': 160,
                'height': 160,
              },
              <String, Object?>{
                'name': 'Œil',
                'type': 'circle',
                'color': '#14161C',
                'width': 24,
                'height': 24,
                'x': -30,
                'y': -20,
              },
            ],
          },
        ],
      });
      expect(imported.shapes, hasLength(1));
      final shape = imported.shapes.first;
      expect(shape.name, 'Visage');
      expect(shape.x, 300);
      expect(shape.y, 400);
      expect(shape.layers, hasLength(2));
      expect(shape.layers[0].name, 'Peau');
      expect(shape.layers[0].kind, ShapeKind.circle);
      expect(shape.layers[0].colorValue, 0xFFFFE3C2);
      expect(shape.layers[0].width, 160);
      expect(shape.layers[0].x, 0);
      expect(shape.layers[1].name, 'Œil');
      expect(shape.layers[1].colorValue, 0xFF14161C);
      expect(shape.layers[1].width, 24);
      expect(shape.layers[1].x, -30);
      expect(shape.layers[1].y, -20);
    });

    test('layers[] : points de path par couche (bbox + recentrage)', () {
      final imported = SimpleAnimationFormat.fromJson(<String, Object?>{
        'version': 2,
        'shapes': <Object?>[
          <String, Object?>{
            'name': 'Bouche',
            'end': 1,
            'layers': <Object?>[
              <String, Object?>{
                'name': 'Trait',
                'type': 'path',
                'points': <Object?>[
                  <Object?>[0, 0],
                  <Object?>[80, 0],
                  <Object?>[80, 30],
                ],
              },
            ],
          },
        ],
      });
      final layer = imported.shapes.first.layers.first;
      expect(layer.width, 80);
      expect(layer.height, 30);
      expect(layer.points[0], const Offset(0, 0));
      expect(layer.points[1], const Offset(80, 0));
      expect(layer.points[2], const Offset(80, 30));
    });

    test('round-trip multi-couches : export → import → identique', () {
      final original = AnimationProject.blank(name: 'Perso');
      final shape = VectorShape(name: 'Visage', startMs: 0, endMs: 2000);
      shape.x = 300;
      shape.y = 400;
      shape.layers.add(
        ShapeLayer(
          name: 'Peau',
          kind: ShapeKind.circle,
          width: 160,
          height: 160,
        )..colorValue = 0xFFFFE3C2,
      );
      final eye =
          ShapeLayer(name: 'Œil', kind: ShapeKind.circle, width: 24, height: 24)
            ..colorValue = 0xFF14161C
            ..x = -30
            ..y = -20;
      shape.layers.add(eye);
      shape.upsertKeyframe(1000, <AnimatableProperty, double>{
        AnimatableProperty.x: 320,
        AnimatableProperty.y: 410,
        AnimatableProperty.rotation: 0,
        AnimatableProperty.scale: 1,
        AnimatableProperty.opacity: 1,
        AnimatableProperty.strokeWidth: 1,
      });
      original.shapes.add(shape);

      final json = SimpleAnimationFormat.toJson(original);
      expect(json['version'], 2); // multi-couches → vasf-2
      final imported = SimpleAnimationFormat.fromJson(json);
      final shape2 = imported.shapes.first;
      expect(shape2.name, 'Visage');
      expect(shape2.x, 300);
      expect(shape2.layers, hasLength(2));
      expect(shape2.layers[0].colorValue, 0xFFFFE3C2);
      expect(shape2.layers[1].x, -30);
      expect(shape2.layers[1].y, -20);
      expect(shape2.keyframes, hasLength(1));
      expect(shape2.keyframes.first.timeMs, 1000);
      expect(shape2.keyframes.first.valueOf(AnimatableProperty.x), 320);

      // Une forme à couche unique reste exportée à plat (vasf-1).
      final single = AnimationProject.blank(name: 'Plat');
      final flat = VectorShape(name: 'Bloc', startMs: 0, endMs: 1000);
      flat.layers.add(ShapeLayer(name: 'Couche', kind: ShapeKind.rect));
      single.shapes.add(flat);
      expect(SimpleAnimationFormat.toJson(single)['version'], 1);
    });

    test('cycle : le motif de keyframes est dupliqué (raccord propre)', () {
      final imported = SimpleAnimationFormat.fromJson(<String, Object?>{
        'version': 2,
        'shapes': <Object?>[
          <String, Object?>{
            'name': 'Marcheur',
            'type': 'rect',
            'cycle': <String, Object?>{'repeat': 2},
            'keyframes': <Object?>[
              <String, Object?>{'t': 0, 'x': 0, 'y': 100, 'easing': 'linear'},
              <String, Object?>{'t': 1, 'x': 40, 'y': 100, 'easing': 'linear'},
              <String, Object?>{'t': 2, 'x': 0, 'y': 100, 'easing': 'linear'},
            ],
          },
        ],
      });
      final shape = imported.shapes.first;
      // Période 2 s, 2 répétitions : 0,1,2 puis 3,4 puis 5,6 (raccord sauté).
      expect(shape.keyframes.map((k) => k.timeMs).toList(), <int>[
        0,
        1000,
        2000,
        3000,
        4000,
        5000,
        6000,
      ]);
      expect(shape.keyframes[3].valueOf(AnimatableProperty.x), 40);
      expect(shape.keyframes[5].valueOf(AnimatableProperty.x), 40);
      expect(shape.endMs, 6000);
    });

    test('cycle sans keyframes : ignoré ; repeat invalide : erreur', () {
      final imported = SimpleAnimationFormat.fromJson(<String, Object?>{
        'version': 2,
        'shapes': <Object?>[
          <String, Object?>{
            'name': 'Statique',
            'type': 'rect',
            'end': 1,
            'cycle': <String, Object?>{'repeat': 3},
          },
        ],
      });
      expect(imported.shapes.first.keyframes, isEmpty);
      try {
        SimpleAnimationFormat.fromJson(<String, Object?>{
          'version': 2,
          'shapes': <Object?>[
            <String, Object?>{
              'name': 'Bloc',
              'type': 'rect',
              'end': 1,
              'cycle': <String, Object?>{'repeat': 0},
            },
          ],
        });
        fail('SimpleFormatException attendu');
      } on SimpleFormatException catch (error) {
        expect(
          error.toString(),
          contains('shapes[0].cycle.repeat : entier ≥ 1 attendu'),
        );
      }
    });

    test('ref : la définition fournit la géométrie, la forme surcharge', () {
      final imported = SimpleAnimationFormat.fromJson(<String, Object?>{
        'version': 2,
        'defs': <String, Object?>{
          'oeil': <String, Object?>{
            'type': 'circle',
            'color': '#14161C',
            'width': 24,
            'height': 24,
          },
        },
        'shapes': <Object?>[
          <String, Object?>{
            'name': 'Œil gauche',
            'ref': 'oeil',
            'x': 100,
            'y': 100,
            'end': 1,
          },
          <String, Object?>{
            'name': 'Œil droit',
            'ref': 'oeil',
            'x': 160,
            'y': 100,
            'end': 1,
            'color': '#FF5C5C',
          },
        ],
      });
      final left = imported.shapes[0].layers.first;
      expect(left.kind, ShapeKind.circle);
      expect(left.colorValue, 0xFF14161C);
      expect(left.width, 24);
      final right = imported.shapes[1].layers.first;
      expect(right.colorValue, 0xFFFF5C5C); // surchargé
      expect(right.width, 24); // hérité
      try {
        SimpleAnimationFormat.fromJson(<String, Object?>{
          'version': 2,
          'shapes': <Object?>[
            <String, Object?>{'name': 'X', 'ref': 'inconnue', 'type': 'rect'},
          ],
        });
        fail('SimpleFormatException attendu');
      } on SimpleFormatException catch (error) {
        expect(
          error.toString(),
          contains('shapes[0].ref : définition « inconnue » inconnue'),
        );
      }
    });

    test('cycle de squelette : tous les os sont répétés', () {
      final imported = SimpleAnimationFormat.fromJson(<String, Object?>{
        'version': 2,
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
            },
          ],
          'cycle': <String, Object?>{'repeat': 1},
          'keyframes': <Object?>[
            <String, Object?>{'bone': 'Bras', 't': 0, 'angle': 0},
            <String, Object?>{'bone': 'Bras', 't': 1, 'angle': 30},
            <String, Object?>{'bone': 'Avant-bras', 't': 0, 'angle': 90},
            <String, Object?>{'bone': 'Avant-bras', 't': 1, 'angle': 60},
          ],
        },
      });
      final rig = imported.skeleton!;
      final root = rig.bones[0];
      final child = rig.bones[1];
      // Période 1 s : raccord à t=1 sauté, copie à t=2 pour chaque os.
      expect(rig.tracks[root.id], hasLength(3));
      expect(rig.tracks[child.id], hasLength(3));
      expect(rig.angleDeltaAt(root.id, 2000), closeTo(math.pi / 6, 1e-9));
      // Copie de la keyframe t=1 : angle monde 60° − repos 90° = −30°.
      expect(rig.angleDeltaAt(child.id, 2000), closeTo(-math.pi / 6, 1e-9));
    });

    test('scaleX/scaleY : bases + keyframes, round trip', () {
      final imported = SimpleAnimationFormat.fromJson(<String, Object?>{
        'version': 2,
        'shapes': <Object?>[
          <String, Object?>{
            'name': 'Gel',
            'type': 'circle',
            'end': 1,
            'scale': 2,
            'scaleX': 0.5,
            'keyframes': <Object?>[
              <String, Object?>{'t': 0, 'scaleY': 1.5},
            ],
          },
        ],
      });
      final shape = imported.shapes.first;
      expect(shape.scale, 2);
      expect(shape.scaleX, 0.5); // facteur d'axe (base)
      expect(shape.scaleY, 1); // base
      expect(
        shape.keyframes[0].valueOf(AnimatableProperty.scaleY),
        1.5, // keyframe ≠ base
      );
      // valueAt renvoie le FACTEUR brut (la composition scale × facteur
      // se fait au rendu, dans le painter).
      expect(shape.valueAt(AnimatableProperty.scaleX, 0), closeTo(0.5, 1e-9));
      final json = SimpleAnimationFormat.toJson(imported);
      expect(json['version'], 2);
      final round = SimpleAnimationFormat.fromJson(json);
      final shape2 = round.shapes.first;
      expect(shape2.scale, 2);
      expect(shape2.scaleX, 0.5);
      expect(shape2.keyframes[0].valueOf(AnimatableProperty.scaleY), 1.5);
    });

    test('pivot : exporté/importé, version 2', () {
      final original = AnimationProject.blank(name: 'Porte');
      final shape = VectorShape(name: 'Porte', startMs: 0, endMs: 1000);
      shape.pivotDx = 30;
      shape.pivotDy = -20;
      shape.layers.add(ShapeLayer(name: 'Couche', kind: ShapeKind.rect));
      original.shapes.add(shape);
      final json = SimpleAnimationFormat.toJson(original);
      expect(json['version'], 2);
      final imported = SimpleAnimationFormat.fromJson(json);
      expect(imported.shapes.first.pivotDx, 30);
      expect(imported.shapes.first.pivotDy, -20);
    });

    test('pivot dans layers[] : refusé (sinon rotation autour du centre '
        'en silence, bug v0.13.0)', () {
      try {
        SimpleAnimationFormat.fromJson(<String, Object?>{
          'version': 2,
          'shapes': <Object?>[
            <String, Object?>{
              'name': 'Porte',
              'layers': <Object?>[
                <String, Object?>{
                  'name': 'Panneau',
                  'type': 'rect',
                  'width': 240,
                  'height': 420,
                  'pivot': <Object?>[-120, 0],
                },
              ],
            },
          ],
        });
        fail('SimpleFormatException attendu');
      } on SimpleFormatException catch (error) {
        expect(error.toString(), contains('shapes[0].layers[0].pivot'));
        expect(error.toString(), contains('au niveau de la FORME'));
      }
    });

    test('cubic-bezier : parse CSS, interpolation, round trip', () {
      final imported = SimpleAnimationFormat.fromJson(<String, Object?>{
        'version': 2,
        'shapes': <Object?>[
          <String, Object?>{
            'name': 'Bloc',
            'type': 'rect',
            'end': 1,
            'keyframes': <Object?>[
              <String, Object?>{'t': 0, 'x': 0, 'easing': 'linear'},
              <String, Object?>{
                't': 1,
                'x': 100,
                'easing': 'cubic-bezier(0.25, 0.1, 0.25, 1)',
              },
            ],
          },
        ],
      });
      final shape = imported.shapes.first;
      expect(shape.keyframes[1].easing, EasingKind.customBezier);
      expect(shape.keyframes[1].bezier, <double>[0.25, 0.1, 0.25, 1]);
      // Bézier par défaut (≈ easeInOut) : à mi-course, x ≈ 80,3.
      expect(shape.valueAt(AnimatableProperty.x, 500), closeTo(80.3, 0.5));
      // Round trip : la chaîne CSS ressort identique.
      final json = SimpleAnimationFormat.toJson(imported);
      final keys =
          (json['shapes'] as List<Object?>).first as Map<String, Object?>;
      final exported =
          (keys['keyframes'] as List<Object?>)[1] as Map<String, Object?>;
      expect(exported['easing'], 'cubic-bezier(0.25, 0.1, 0.25, 1)');
      final round = SimpleAnimationFormat.fromJson(json);
      expect(round.shapes.first.keyframes[1].bezier, <double>[
        0.25,
        0.1,
        0.25,
        1,
      ]);
    });

    test('cubic-bezier invalide : erreur collectée', () {
      try {
        SimpleAnimationFormat.fromJson(<String, Object?>{
          'version': 2,
          'shapes': <Object?>[
            <String, Object?>{
              'name': 'Bloc',
              'type': 'rect',
              'end': 1,
              'keyframes': <Object?>[
                <String, Object?>{
                  't': 0,
                  'x': 0,
                  'easing': 'cubic-bezier(2, 0, 0.25, 1)',
                },
              ],
            },
          ],
        });
        fail('SimpleFormatException attendu');
      } on SimpleFormatException catch (error) {
        expect(
          error.toString(),
          contains('cubic-bezier — x1 et x2 dans [0, 1] attendus'),
        );
      }
    });

    test('keyframe d\'os cubic-bezier : sampler + round trip', () {
      final imported = SimpleAnimationFormat.fromJson(<String, Object?>{
        'version': 2,
        'shapes': <Object?>[
          <String, Object?>{'name': 'Bloc', 'type': 'rect', 'end': 2},
        ],
        'skeleton': <String, Object?>{
          'bones': <Object?>[
            <String, Object?>{
              'name': 'Bras',
              'joint': <Object?>[100, 320],
              'angle': 0,
              'length': 100,
            },
          ],
          'keyframes': <Object?>[
            <String, Object?>{'bone': 'Bras', 't': 0, 'angle': 0},
            <String, Object?>{
              'bone': 'Bras',
              't': 1,
              'angle': 30,
              'easing':
                  'cubic-bezier(0.3333333333, 0.3333333333, 0.6666666667, 0.6666666667)',
            },
          ],
        },
      });
      final rig = imported.skeleton!;
      final bone = rig.bones.first;
      final track = rig.tracks[bone.id]!;
      expect(track[1].easing, EasingKind.customBezier);
      expect(track[1].bezier!.length, 4);
      // Bézier identité : 15° à mi-course.
      expect(rig.angleDeltaAt(bone.id, 500), closeTo(math.pi / 12, 1e-6));
      // Round trip.
      final json = SimpleAnimationFormat.toJson(imported);
      final skeleton = json['skeleton'] as Map<String, Object?>;
      final exported =
          (skeleton['keyframes'] as List<Object?>)[1] as Map<String, Object?>;
      expect(
        exported['easing'],
        'cubic-bezier(0.3333, 0.3333, 0.6667, 0.6667)',
      );
      final round = SimpleAnimationFormat.fromJson(json);
      expect(
        round.skeleton!.angleDeltaAt(round.skeleton!.bones.first.id, 500),
        closeTo(math.pi / 12, 1e-6),
      );
    });

    test('bind de couche : « Forme/Couche » importé et exporté', () {
      final imported = SimpleAnimationFormat.fromJson(<String, Object?>{
        'version': 2,
        'shapes': <Object?>[
          <String, Object?>{
            'name': 'Visage',
            'end': 2,
            'layers': <Object?>[
              <String, Object?>{
                'name': 'Œil',
                'type': 'circle',
                'width': 24,
                'height': 24,
              },
            ],
          },
        ],
        'skeleton': <String, Object?>{
          'bones': <Object?>[
            <String, Object?>{
              'name': 'OeilG',
              'joint': <Object?>[100, 100],
              'angle': 0,
              'length': 40,
            },
          ],
          'bind': <String, Object?>{'Visage/Œil': 'OeilG'},
        },
      });
      final rig = imported.skeleton!;
      final shape = imported.shapes.first;
      final layer = shape.layers.first;
      // La couche est liée ; la FORME ne l'est pas (liaison de couche
      // ne capture pas la forme entière).
      expect(rig.bindingForLayer(shape.id, layer.id), isNotNull);
      expect(
        rig.bindingForLayer(shape.id, layer.id)!.boneId,
        rig.bones.first.id,
      );
      expect(rig.boneIdForShape(shape.id), isNull);
      // Round trip : la liaison de couche est exportée « Forme/Couche ».
      final json = SimpleAnimationFormat.toJson(imported);
      expect(json['version'], 2);
      final skeleton = json['skeleton'] as Map<String, Object?>;
      expect((skeleton['bind'] as Map<String, Object?>)['Visage/Œil'], 'OeilG');
      final round = SimpleAnimationFormat.fromJson(json);
      expect(
        round.skeleton!.bindingForLayer(
          round.shapes.first.id,
          round.shapes.first.layers.first.id,
        ),
        isNotNull,
      );
    });

    test('courbes cubic-bezier : valeurs de référence', () {
      // Identité exacte : cubic-bezier(1/3, 1/3, 2/3, 2/3) = linéaire
      // (x(u) = u[(1-u) + u]² = u).
      expect(
        applyBezierEasing(1 / 3, 1 / 3, 2 / 3, 2 / 3, 0.3),
        closeTo(0.3, 1e-9),
      );
      // Extrémités.
      expect(applyBezierEasing(0.25, 0.1, 0.25, 1, 0), 0);
      expect(applyBezierEasing(0.25, 0.1, 0.25, 1, 1), 1);
      // Par défaut (proche easeInOut) : à mi-course, ≈ 0,803.
      expect(applyBezierEasing(0.25, 0.1, 0.25, 1, 0.5), closeTo(0.803, 0.005));
      // easingProgress : bezier de la keyframe, défaut si null.
      expect(
        easingProgress(EasingKind.customBezier, null, 0.5),
        closeTo(0.803, 0.005),
      );
      expect(easingProgress(EasingKind.easeIn, null, 0.5), closeTo(0.25, 1e-9));
    });
  });

  group('vasf-3 (v0.15 : couleur animée, morph, translation d\'os)', () {
    test(
      'couleur animée à plat : « color » par keyframe, carry, round trip',
      () {
        final imported = SimpleAnimationFormat.fromJson(<String, Object?>{
          'version': 3,
          'shapes': <Object?>[
            <String, Object?>{
              'name': 'Ciel',
              'type': 'rect',
              'width': 720,
              'height': 1280,
              'end': 4,
              'color': '#0000FF',
              'keyframes': <Object?>[
                <String, Object?>{'t': 0, 'color': '#0000FF'},
                <String, Object?>{
                  't': 2,
                  'easing': 'linear',
                  'color': '#FF0000',
                },
                <String, Object?>{
                  't': 3,
                }, // sans couleur : le rouge porté tient
              ],
            },
          ],
        });
        final shape = imported.shapes.first;
        final layer = shape.layers.first;
        expect(shape.layerColorAnimated(layer.id), isTrue);
        expect(shape.colorAtLayer(layer.id, 0, 0), 0xFF0000FF);
        expect(
          shape.colorAtLayer(layer.id, 1000, 0),
          lerpArgb(0xFF0000FF, 0xFFFF0000, 0.5),
        );
        expect(shape.colorAtLayer(layer.id, 3500, 0), 0xFFFF0000);
        // Round trip : version 3 + couleurs émises (sparse numériques sinon).
        final exported = SimpleAnimationFormat.toJson(imported);
        expect(exported['version'], 3);
        final keys =
            ((exported['shapes'] as List<Object?>).first
                    as Map<String, Object?>)['keyframes']!
                as List<Object?>;
        expect((keys[0] as Map<String, Object?>)['color'], '#0000FF');
        expect((keys[1] as Map<String, Object?>)['color'], '#FF0000');
        expect((keys[2] as Map<String, Object?>)['color'], '#FF0000');
      },
    );

    test('morph de points à plat : « points » par keyframe, lerp mesuré', () {
      final imported = SimpleAnimationFormat.fromJson(<String, Object?>{
        'version': 3,
        'shapes': <Object?>[
          <String, Object?>{
            'name': 'Flamme',
            'type': 'path',
            'end': 3,
            'points': <Object?>[
              <Object?>[0, 0],
              <Object?>[100, 0],
              <Object?>[100, 100],
            ],
            'keyframes': <Object?>[
              <String, Object?>{
                't': 0,
                'points': <Object?>[
                  <Object?>[0, 0],
                  <Object?>[100, 0],
                  <Object?>[100, 100],
                ],
              },
              <String, Object?>{
                't': 2,
                'easing': 'linear',
                'points': <Object?>[
                  <Object?>[200, 0],
                  <Object?>[300, 0],
                  <Object?>[300, 100],
                ],
              },
            ],
          },
        ],
      });
      final shape = imported.shapes.first;
      final layer = shape.layers.first;
      expect(shape.layerPointsAnimated(layer.id), isTrue);
      // La base : bbox 100×100, points recentrés (json − (50,50) + (50,50)).
      expect(layer.width, closeTo(100, 0.001));
      expect(layer.height, closeTo(100, 0.001));
      final base = shape.pointsAtLayer(layer.id, const [], 0);
      expect(base, const <Offset>[
        Offset(0, 0),
        Offset(100, 0),
        Offset(100, 100),
      ]);
      // À mi-course : chaque point a glissé de +100 en X (repère cohérent).
      final mid = shape.pointsAtLayer(layer.id, const [], 1000);
      expect(mid, const <Offset>[
        Offset(100, 0),
        Offset(200, 0),
        Offset(200, 100),
      ]);
      // Round trip : l'export émet les points de morph dans le repère de base.
      final exported = SimpleAnimationFormat.toJson(imported);
      expect(exported['version'], 3);
      final keys =
          ((exported['shapes'] as List<Object?>).first
                  as Map<String, Object?>)['keyframes']!
              as List<Object?>;
      final kf2 = keys[1] as Map<String, Object?>;
      final points = (kf2['points'] as List<Object?>)
          .map(
            (p) => <double>[(p as List<Object?>)[0] as double, p[1] as double],
          )
          .toList();
      expect(points[0][0], closeTo(200, 0.01));
      expect(points[1][0], closeTo(300, 0.01));
      expect(points[2][1], closeTo(100, 0.01));
    });

    test('couleurs + morph par couche (layers[]), round trip', () {
      final imported = SimpleAnimationFormat.fromJson(<String, Object?>{
        'version': 3,
        'shapes': <Object?>[
          <String, Object?>{
            'name': 'Feu',
            'layers': <Object?>[
              <String, Object?>{'name': 'Braise', 'type': 'rect'},
              <String, Object?>{
                'name': 'Langue',
                'type': 'path',
                'points': <Object?>[
                  <Object?>[0, 0],
                  <Object?>[50, 0],
                  <Object?>[25, 60],
                ],
              },
            ],
            'end': 3,
            'keyframes': <Object?>[
              <String, Object?>{
                't': 0,
                'colors': <String, Object?>{'Langue': '#FF5C5C'},
                'layerPoints': <String, Object?>{
                  'Langue': <Object?>[
                    <Object?>[0, 0],
                    <Object?>[50, 0],
                    <Object?>[25, 60],
                  ],
                },
              },
              <String, Object?>{
                't': 2,
                'easing': 'linear',
                'colors': <String, Object?>{'Langue': '#F2C94C'},
                'layerPoints': <String, Object?>{
                  'Langue': <Object?>[
                    <Object?>[30, 10],
                    <Object?>[80, 10],
                    <Object?>[55, 70],
                  ],
                },
              },
            ],
          },
        ],
      });
      final shape = imported.shapes.first;
      final langue = shape.layers.where((l) => l.name == 'Langue').firstOrNull!;
      expect(shape.layerColorAnimated(langue.id), isTrue);
      // Base : bbox 50×60 → centre (25,30), stocké = json − (25,30) + (25,30).
      final mid = shape.pointsAtLayer(langue.id, const [], 1000);
      expect(mid.length, 3);
      expect(mid[0].dx, closeTo(15, 0.01));
      expect(mid[0].dy, closeTo(5, 0.01));
      // Couleur interpolée (linéaire à mi-course).
      expect(
        shape.colorAtLayer(langue.id, 1000, 0),
        lerpArgb(0xFFFF5C5C, 0xFFF2C94C, 0.5),
      );
      // Round trip : maps par NOM de couche.
      final exported = SimpleAnimationFormat.toJson(imported);
      expect(exported['version'], 3);
      final keys =
          ((exported['shapes'] as List<Object?>).first
                  as Map<String, Object?>)['keyframes']!
              as List<Object?>;
      final kf0 = keys[0] as Map<String, Object?>;
      expect(((kf0['colors'] as Map<String, Object?>)['Langue']), '#FF5C5C');
      final kf2 = keys[1] as Map<String, Object?>;
      expect(
        ((kf2['layerPoints'] as Map<String, Object?>)['Langue'] as List).length,
        3,
      );
      // Les poses numériques sont restées complètes (pas de perte).
      expect(kf2.containsKey('x'), isFalse); // inchangé → omis (sparse)
      expect((kf2['colors'] as Map)['Langue'], '#F2C94C');
    });

    test('erreurs : color/colors et points/layerPoints hors contexte', () {
      Map<String, Object?> shapeJson(Map<String, Object?> kf) =>
          <String, Object?>{
            'name': 'A',
            'layers': <Object?>[
              <String, Object?>{'name': 'L', 'type': 'rect'},
            ],
            'end': 1,
            'keyframes': <Object?>[kf],
          };
      // `color` (scalaire) sur une forme en layers[] → refus explicite.
      try {
        SimpleAnimationFormat.fromJson(<String, Object?>{
          'version': 3,
          'shapes': <Object?>[
            shapeJson(<String, Object?>{'t': 0, 'color': '#FF0000'}),
          ],
        });
        fail('SimpleFormatException attendu');
      } on SimpleFormatException catch (error) {
        expect(
          error.toString(),
          contains('keyframes[0].color : réservé aux formes à UNE couche'),
        );
      }
      // `colors` (map) sur une forme à plat → refus explicite.
      try {
        SimpleAnimationFormat.fromJson(<String, Object?>{
          'version': 3,
          'shapes': <Object?>[
            <String, Object?>{
              'name': 'B',
              'type': 'rect',
              'end': 1,
              'keyframes': <Object?>[
                <String, Object?>{
                  't': 0,
                  'colors': <String, Object?>{'L': '#FF0000'},
                },
              ],
            },
          ],
        });
        fail('SimpleFormatException attendu');
      } on SimpleFormatException catch (error) {
        expect(
          error.toString(),
          contains('keyframes[0].colors : réservé aux formes en layers[]'),
        );
      }
      // Couche inconnue dans `colors` → erreur avec chemin.
      try {
        SimpleAnimationFormat.fromJson(<String, Object?>{
          'version': 3,
          'shapes': <Object?>[
            shapeJson(<String, Object?>{
              't': 0,
              'colors': <String, Object?>{'Inconnue': '#FF0000'},
            }),
          ],
        });
        fail('SimpleFormatException attendu');
      } on SimpleFormatException catch (error) {
        expect(
          error.toString(),
          contains('keyframes[0].colors.Inconnue : couche inconnue'),
        );
      }
    });

    test(
      'translation d\'os : « move » monde → interne → monde (round trip)',
      () {
        final imported = SimpleAnimationFormat.fromJson(<String, Object?>{
          'version': 3,
          'shapes': <Object?>[
            <String, Object?>{
              'name': 'Pièce',
              'type': 'rect',
              'end': 2,
              'x': 100,
              'y': 100,
            },
          ],
          'skeleton': <String, Object?>{
            'name': 'Bras',
            'bones': <Object?>[
              <String, Object?>{
                'name': 'Épaule',
                'joint': <Object?>[100, 100],
                'angle': -90,
                'length': 80,
                'ik': true,
              },
              <String, Object?>{
                'name': 'Coude',
                'parent': 'Épaule',
                'joint': <Object?>[100, 20],
                'angle': -90,
                'length': 60,
              },
              <String, Object?>{
                'name': 'Poignet',
                'parent': 'Coude',
                'joint': <Object?>[100, -40],
                'angle': -90,
                'length': 40,
              },
            ],
            'bind': <String, Object?>{'Pièce': 'Épaule'},
            'keyframes': <Object?>[
              <String, Object?>{
                'bone': 'Poignet',
                't': 1,
                'angle': -90,
                'move': <Object?>[0, -20],
              },
            ],
          },
        });
        expect(imported.isSkeleton, isTrue);
        final rig = imported.skeleton!;
        final poignet = rig.bones
            .where((b) => b.name == 'Poignet')
            .firstOrNull!;
        // Stockage dans le repère de repos du parent : (0,−20) monde avec
        // parent à −90° → (20, 0) local (ε du cos(π/2) toléré).
        final stored = rig.translationAt(poignet.id, 1000);
        expect(stored.dx, closeTo(20, 1e-9));
        expect(stored.dy, closeTo(0, 1e-9));
        // FK : le poignet glisse de 20 unités le long du bras (vers le haut).
        final animated = SkeletonPose.evaluate(rig, 1000);
        final joint = animated.frameOf(poignet.id)!.joint;
        expect(joint.dx, closeTo(100, 1e-6));
        expect(joint.dy, closeTo(-60, 1e-6));
        // L'angle du poignet est inchangé (move ≠ angle).
        expect(
          animated.frameOf(poignet.id)!.worldAngle,
          closeTo(-math.pi / 2, 1e-6),
        );
        // Round trip : l'export ré-émet le delta en MONDE.
        final exported = SimpleAnimationFormat.toJson(imported);
        expect(exported['version'], 3);
        final keys =
            ((exported['skeleton'] as Map<String, Object?>)['keyframes']!
                as List<Object?>);
        final move =
            (keys.single as Map<String, Object?>)['move'] as List<Object?>;
        expect((move[0] as num).toDouble(), closeTo(0, 1e-6));
        expect((move[1] as num).toDouble(), closeTo(-20, 1e-6));
      },
    );
  });

  group('v0.17 — import strict + cycles par os', () {
    Map<String, Object?> rigJson({
      required List<Object?> bones,
      List<Object?>? skeletonKeys,
      Object? skeletonCycle,
      Object? bind,
    }) => {
      'version': 2,
      'name': 'Test',
      'canvas': {
        'width': 720,
        'height': 1280,
        'fps': 25,
        'background': '#0E1230',
      },
      'shapes': [
        {
          'name': 'Planete',
          'type': 'circle',
          'color': '#E3B466',
          'width': 1080,
          'height': 1080,
          'x': 360,
          'y': 1680,
          'end': 12,
        },
      ],
      'skeleton': {
        'name': 'Rig',
        'bones': bones,
        'keyframes': ?skeletonKeys,
        'cycle': ?skeletonCycle,
        'bind': ?bind,
      },
    };

    Map<String, Object?> boneJson({
      required String name,
      List<double> joint = const [360, 1680],
      double angle = 0,
      Object? keyframes,
      Object? cycle,
      Object? bogus,
    }) => {
      'name': name,
      'joint': joint,
      'angle': angle,
      'length': 540,
      'keyframes': ?keyframes,
      'cycle': ?cycle,
      'bogus': ?bogus,
    };

    test('keyframes embarquées dans l os : acceptées et fusionnées', () {
      final project = SimpleAnimationFormat.fromJson(
        rigJson(
          bones: [
            boneJson(
              name: 'Planete',
              keyframes: [
                {'t': 0, 'angle': 0, 'easing': 'linear'},
                {'t': 12, 'angle': -360, 'easing': 'linear'},
              ],
            ),
          ],
        ),
      );
      final rig = project.skeleton!;
      final track = rig.tracks[rig.bones.first.id]!;
      expect(track.length, 2);
      expect(track.last.timeMs, 12000);
      // Angle MONDE −360° avec repos 0° → delta −2π.
      expect(track.last.angleDelta, closeTo(-2 * math.pi, 1e-6));
      expect(track.last.easing, EasingKind.linear);
    });

    test('champ inconnu sur une forme : refusé avec le chemin', () {
      expect(
        () => SimpleAnimationFormat.fromJson({
          'version': 1,
          'shapes': [
            {
              'name': 'A',
              'type': 'rect',
              'color': '#FF0000',
              'colo': '#00FF00',
            },
          ],
        }),
        throwsA(
          predicate(
            (e) =>
                e is SimpleFormatException &&
                e.problems.any(
                  (p) => p.contains('shapes[0]') && p.contains('colo'),
                ),
          ),
        ),
      );
    });

    test('champ inconnu sur un os : refusé avec le chemin', () {
      expect(
        () => SimpleAnimationFormat.fromJson(
          rigJson(bones: [boneJson(name: 'Planete', bogus: 1)]),
        ),
        throwsA(
          predicate(
            (e) =>
                e is SimpleFormatException &&
                e.problems.any(
                  (p) => p.contains('skeleton.bones[0]') && p.contains('bogus'),
                ),
          ),
        ),
      );
    });

    test('raccourci « bone » sur une forme : la liaison est créée', () {
      final project = SimpleAnimationFormat.fromJson({
        'version': 2,
        'canvas': {
          'width': 720,
          'height': 1280,
          'fps': 25,
          'background': '#0E1230',
        },
        'shapes': [
          {
            'name': 'Planete',
            'type': 'circle',
            'color': '#E3B466',
            'width': 1080,
            'height': 1080,
            'x': 360,
            'y': 1680,
            'end': 12,
            'bone': 'Planete',
          },
        ],
        'skeleton': {
          'name': 'Rig',
          'bones': [boneJson(name: 'Planete')],
        },
      });
      final rig = project.skeleton!;
      expect(rig.bindings, hasLength(1));
      expect(rig.bindings.first.shapeId, project.shapes.first.id);
      expect(rig.bindings.first.boneId, rig.bones.first.id);
      expect(rig.bindings.first.layerId, isNull);
    });

    test('« bone » + « bind » en désaccord : erreur explicite', () {
      expect(
        () => SimpleAnimationFormat.fromJson(
          rigJson(
              bones: [
                boneJson(name: 'OsA'),
                boneJson(name: 'OsB', joint: [10, 10]),
              ],
              bind: {'Planete': 'OsA'},
            )
            ..['shapes'] = [
              {
                'name': 'Planete',
                'type': 'circle',
                'color': '#E3B466',
                'width': 1080,
                'height': 1080,
                'x': 360,
                'y': 1680,
                'end': 12,
                'bone': 'OsB',
              },
            ],
        ),
        throwsA(
          predicate(
            (e) =>
                e is SimpleFormatException &&
                e.problems.any((p) => p.contains('déjà liée à un autre os')),
          ),
        ),
      );
    });

    test('« bone » sans squelette : erreur claire', () {
      expect(
        () => SimpleAnimationFormat.fromJson({
          'version': 1,
          'shapes': [
            {'name': 'A', 'type': 'rect', 'color': '#FF0000', 'bone': 'X'},
          ],
        }),
        throwsA(
          predicate(
            (e) =>
                e is SimpleFormatException &&
                e.problems.any((p) => p.contains('exige une section')),
          ),
        ),
      );
    });

    test(
      'cycle par os : chaque os répète SON motif (périodes différentes)',
      () {
        final walkKeys = [
          {'t': 0, 'angle': 68},
          {'t': 0.3, 'angle': 89},
          {'t': 0.6, 'angle': 112},
          {'t': 0.9, 'angle': 86},
          {'t': 1.2, 'angle': 68},
        ];
        final project = SimpleAnimationFormat.fromJson(
          rigJson(
            bones: [
              boneJson(
                name: 'Marche',
                joint: [348, 869],
                angle: 90,
                keyframes: walkKeys,
                cycle: {'repeat': 9},
              ),
              boneJson(
                name: 'Lent',
                joint: [500, 500],
                keyframes: [
                  {'t': 0, 'angle': 0, 'easing': 'linear'},
                  {'t': 12, 'angle': -360, 'easing': 'linear'},
                ],
              ),
            ],
          ),
        );
        final rig = project.skeleton!;
        final marche = rig.bones.firstWhere((b) => b.name == 'Marche');
        final lent = rig.bones.firstWhere((b) => b.name == 'Lent');
        // 5 keys du motif + 9 répétitions × 4 (raccord sauté) = 41.
        expect(rig.tracks[marche.id]!, hasLength(41));
        expect(rig.tracks[marche.id]!.last.timeMs, 12000);
        expect(
          rig.tracks[marche.id]!.last.angleDelta,
          closeTo((68 - 90) * math.pi / 180, 1e-6),
        );
        // L os sans cycle propre garde ses 2 keyframes : la marche et la
        // rotation lente coexistent sur des périodes DIFFÉRENTES.
        expect(rig.tracks[lent.id]!, hasLength(2));
        expect(rig.tracks[lent.id]!.last.timeMs, 12000);
      },
    );

    test('cycle par os + cycle global : le global épargne les os à cycle', () {
      final project = SimpleAnimationFormat.fromJson(
        rigJson(
          bones: [
            boneJson(
              name: 'A',
              keyframes: [
                {'t': 0, 'angle': 0},
                {'t': 1, 'angle': 10},
              ],
              cycle: {'repeat': 2},
            ),
            boneJson(
              name: 'B',
              joint: [500, 500],
              keyframes: [
                {'t': 0, 'angle': 0},
                {'t': 2, 'angle': 10},
              ],
            ),
          ],
          skeletonCycle: {'repeat': 1},
        ),
      );
      final rig = project.skeleton!;
      final a = rig.bones.firstWhere((b) => b.name == 'A');
      final b = rig.bones.firstWhere((b) => b.name == 'B');
      // A (cycle propre, période 1 s) : 0, 1, 2, 3 — le global ne le
      // recycle pas.
      final trackA = rig.tracks[a.id]!;
      expect(trackA.map((k) => k.timeMs).toSet(), {0, 1000, 2000, 3000});
      // B (sans cycle propre) : le global (période du sous-ensemble = 2 s)
      // ajoute la rep à 4 s (la rep à 2 s tombe sur la keyframe posée).
      final trackB = rig.tracks[b.id]!;
      expect(trackB.map((k) => k.timeMs).toSet(), {0, 2000, 4000});
    });
  });
}
