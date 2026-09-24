import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_anim_studio/engine/animation_presets.dart';
import 'package:vector_anim_studio/models/animation.dart';

void main() {
  group('poses de keyframe', () {
    test('interpole toutes les propriétés entre deux poses', () {
      final shape = VectorShape(name: 'A', x: 0, y: 10, opacity: 1);
      shape.upsertKeyframe(0, shape.poseAt(0), easing: EasingKind.linear);
      shape.upsertKeyframe(
        1000,
        <AnimatableProperty, double>{
          ...shape.poseAt(0),
          AnimatableProperty.x: 100,
          AnimatableProperty.y: 60,
          AnimatableProperty.opacity: 0,
        },
        easing: EasingKind.linear,
      );

      expect(shape.valueAt(AnimatableProperty.x, 0), 0);
      expect(shape.valueAt(AnimatableProperty.x, 500), closeTo(50, 0.001));
      expect(shape.valueAt(AnimatableProperty.y, 500), closeTo(35, 0.001));
      expect(shape.valueAt(AnimatableProperty.opacity, 500), closeTo(0.5, 0.001));
      expect(shape.valueAt(AnimatableProperty.x, 2000), 100);
    });

    test('easeInOut part et arrive en douceur', () {
      final shape = VectorShape(name: 'B', opacity: 0);
      shape.upsertKeyframe(0, shape.poseAt(0), easing: EasingKind.linear);
      shape.upsertKeyframe(
        1000,
        <AnimatableProperty, double>{
          ...shape.poseAt(0),
          AnimatableProperty.opacity: 1,
        },
      );
      expect(shape.valueAt(AnimatableProperty.opacity, 250), lessThan(0.25));
      expect(shape.valueAt(AnimatableProperty.opacity, 750), greaterThan(0.75));
    });

    test('remplace la pose au même temps', () {
      final shape = VectorShape(name: 'C');
      shape.upsertKeyframe(0, shape.poseAt(0));
      shape.upsertKeyframe(
        0,
        <AnimatableProperty, double>{
          ...shape.poseAt(0),
          AnimatableProperty.scale: 2,
        },
      );
      expect(shape.keyframes.length, 1);
      expect(shape.keyframes.first.values[AnimatableProperty.scale], 2);
    });
  });

  group('VectorShape', () {
    test('valueAt retombe sur la valeur de base sans keyframe', () {
      final shape = VectorShape(name: 'A', x: 42);
      expect(shape.valueAt(AnimatableProperty.x, 500), 42);
      expect(shape.isAnimated(AnimatableProperty.x), isFalse);
    });

    test('addKeyframeAt capture toutes les propriétés', () {
      final shape = VectorShape(name: 'B', y: 7, opacity: 0.5);
      shape.addKeyframeAt(100);
      expect(shape.keyframes.single.timeMs, 100);
      expect(shape.keyframes.single.values[AnimatableProperty.y], 7);
      expect(shape.keyframes.single.values[AnimatableProperty.opacity], 0.5);
      expect(shape.isAnimated(AnimatableProperty.y), isFalse);
    });

    test('applyValue écrit la base sans keyframe, la pose ensuite', () {
      final shape = VectorShape(name: 'C', opacity: 1);
      shape.applyValue(AnimatableProperty.opacity, 0.3, 500, autoKey: true);
      expect(shape.opacity, 0.3);
      expect(shape.keyframes, isEmpty);

      shape.addKeyframeAt(0);
      shape.applyValue(AnimatableProperty.x, 999, 500, autoKey: true);
      expect(shape.keyframes.length, 2);
      expect(shape.keyframes.last.timeMs, 500);
      expect(shape.keyframes.last.values[AnimatableProperty.x], 999);
    });

    test('applyValue snappe sur la pose à proximité', () {
      final shape = VectorShape(name: 'D');
      shape.addKeyframeAt(0);
      shape.applyValue(
        AnimatableProperty.y,
        50,
        60,
        autoKey: true,
        toleranceMs: 80,
      );
      expect(shape.keyframes.length, 1);
      expect(shape.keyframes.first.timeMs, 0);
      expect(shape.keyframes.first.values[AnimatableProperty.y], 50);
    });

    test('une forme n’est visible que dans sa fenêtre d’affichage', () {
      final shape = VectorShape(name: 'Fenêtre', startMs: 500, endMs: 1500);
      expect(shape.isVisibleAt(400), isFalse);
      expect(shape.isVisibleAt(500), isTrue);
      expect(shape.isVisibleAt(1000), isTrue);
      expect(shape.isVisibleAt(1600), isFalse);

      shape.visible = false;
      expect(shape.isVisibleAt(1000), isFalse);
    });

    test('copy détache les couches et les keyframes', () {
      final shape = VectorShape(
        name: 'Originale',
        layers: <ShapeLayer>[ShapeLayer(name: 'Rect', kind: ShapeKind.rect)],
      );
      shape.addKeyframeAt(0);
      final clone = shape.copy();

      clone.layers.first.width = 999;
      clone.keyframes.first.values[AnimatableProperty.x] = 999;

      expect(shape.layers.first.width, isNot(999));
      expect(shape.keyframes.first.values[AnimatableProperty.x], isNot(999));
    });
  });

  group('AnimationProject', () {
    test('survit à un aller-retour JSON', () {
      final project = AnimationProject.demo();
      final restored = AnimationProject.fromJson(
        jsonDecode(jsonEncode(project.toJson())) as Map<String, dynamic>,
      );

      expect(restored.shapes.length, project.shapes.length);
      expect(restored.durationMs, project.durationMs);
      expect(restored.shapes.first.layers.length, 1);
      expect(restored.shapes.first.keyframes.length, 3);
      expect(
        restored.shapes.first.valueAt(
          AnimatableProperty.rotation,
          restored.durationMs,
        ),
        closeTo(2 * math.pi, 0.01),
      );
    });

    test('visibleShapesAt filtre sur la fenêtre d’affichage', () {
      final project = AnimationProject.demo();
      expect(project.visibleShapesAt(0).length, 1);
      expect(project.visibleShapesAt(1000).length, 2);
    });

    test('moveShape réordonne les calques', () {
      final project = AnimationProject.demo();
      final first = project.shapes.first;
      project.moveShape(0, 1);
      expect(project.shapes.last.id, first.id);
    });

    test('blank applique le format choisi', () {
      final project = AnimationProject.blank(
        name: 'Test',
        format: ProjectFormat.landscape,
        durationMs: 2500,
        fps: 24,
      );
      expect(project.width, 640);
      expect(project.height, 360);
      expect(project.durationMs, 2500);
      expect(project.fps, 24);
      expect(project.shapes, isEmpty);
    });
  });

  group('presets d’animation', () {
    test('apparition crée une pose d’opacité 0 → 1', () {
      final shape = VectorShape(name: 'A', startMs: 1000, endMs: 3000);
      applyPreset(shape, AnimationPreset.apparition);
      expect(shape.isAnimated(AnimatableProperty.opacity), isTrue);
      expect(shape.keyframes.first.values[AnimatableProperty.opacity], 0);
      expect(shape.keyframes.last.values[AnimatableProperty.opacity], 1);
      expect(shape.keyframes.first.timeMs, 1000);
    });

    test('pulsation passe par un maximum au milieu', () {
      final shape = VectorShape(name: 'P', startMs: 0, endMs: 2000);
      applyPreset(shape, AnimationPreset.pulsation);
      expect(shape.valueAt(AnimatableProperty.scale, 1000), closeTo(1.25, 0.001));
      expect(shape.valueAt(AnimatableProperty.scale, 0), closeTo(1, 0.001));
    });

    test('clearAnimations vide les keyframes', () {
      final shape = VectorShape(name: 'C');
      applyPreset(shape, AnimationPreset.rotation);
      clearAnimations(shape);
      expect(shape.keyframes, isEmpty);
    });
  });

  group('formes basiques étendues', () {
    const newKinds = <ShapeKind>[
      ShapeKind.triangle,
      ShapeKind.star,
      ShapeKind.hexagon,
      ShapeKind.cross,
      ShapeKind.heart,
      ShapeKind.arrow,
    ];

    test('chaque nouveau type a un label non vide', () {
      for (final kind in newKinds) {
        expect(shapeKindLabel(kind), isNotEmpty);
      }
    });

    test('aller-retour JSON conserve le type et les dimensions', () {
      for (final kind in newKinds) {
        final layer = ShapeLayer(name: 'L', kind: kind, width: 80, height: 60);
        final back = ShapeLayer.fromJson(layer.toJson());
        expect(back.kind, kind);
        expect(back.width, 80);
        expect(back.height, 60);
      }
    });

    test('copy de couche : nouvel id, contenu identique, points copiés', () {
      final layer = ShapeLayer(
        name: 'Étoile',
        kind: ShapeKind.star,
        x: 12,
        y: -4,
        colorValue: 0xFFFF5C5C,
        filled: false,
        strokeWidth: 6,
        points: const <Offset>[Offset(1, 2), Offset(3, 4)],
      );
      final clone = layer.copy(id: generateId('layer'), name: 'Étoile (copie)');
      expect(clone.id, isNot(layer.id));
      expect(clone.name, 'Étoile (copie)');
      expect(clone.kind, ShapeKind.star);
      expect(clone.x, 12);
      expect(clone.y, -4);
      expect(clone.colorValue, 0xFFFF5C5C);
      expect(clone.filled, isFalse);
      expect(clone.strokeWidth, 6);
      expect(clone.points, layer.points);
      expect(identical(clone.points, layer.points), isFalse);
    });
  });

  group('instance d\'animation', () {
    test('aller-retour JSON conserve le projet imbriqué', () {
      final shape = VectorShape(
        name: 'Instance',
        embeddedProjectId: 'src-1',
        embeddedWidth: 360,
        embeddedHeight: 640,
      );
      final back = VectorShape.fromJson(shape.toJson());
      expect(back.isInstance, isTrue);
      expect(back.embeddedProjectId, 'src-1');
      expect(back.embeddedWidth, 360);
      expect(back.embeddedHeight, 640);
    });

    test('copy conserve l\'instance', () {
      final shape = VectorShape(
        name: 'Instance',
        embeddedProjectId: 'src-1',
        embeddedWidth: 360,
        embeddedHeight: 640,
      );
      final clone = shape.copy();
      expect(clone.isInstance, isTrue);
      expect(clone.embeddedProjectId, 'src-1');
      expect(clone.embeddedWidth, 360);
    });

    test('une forme classique n\'est pas une instance', () {
      expect(VectorShape(name: 'F').isInstance, isFalse);
    });

    test('instanceTimeMs boucle sur la durée source', () {
      // Avant la fenêtre : 0.
      expect(instanceTimeMs(400, 500, 1000), 0);
      // Début de fenêtre : 0.
      expect(instanceTimeMs(500, 500, 1000), 0);
      // Milieu : temps écoulé.
      expect(instanceTimeMs(1900, 500, 1000), 400);
      // Boucle : à début + durée exacte on repart de 0.
      expect(instanceTimeMs(1500, 500, 1000), 0);
      expect(instanceTimeMs(2600, 500, 1000), 100);
      // Durée source nulle : figée à 0.
      expect(instanceTimeMs(1500, 500, 0), 0);
    });
  });

  group('duplication de forme', () {
    test('duplicated clone couches et keyframes avec de nouveaux ids', () {
      final shape = VectorShape(
        name: 'Carré',
        x: 10,
        y: 20,
        startMs: 500,
        endMs: 2500,
      );
      shape.layers.add(ShapeLayer(name: 'Rect', kind: ShapeKind.rect));
      shape.layers.add(ShapeLayer(name: 'Cercle', kind: ShapeKind.circle));
      shape.upsertKeyframe(500, shape.poseAt(500), easing: EasingKind.linear);
      shape.upsertKeyframe(
        2500,
        <AnimatableProperty, double>{
          ...shape.poseAt(500),
          AnimatableProperty.rotation: 1.5,
        },
        easing: EasingKind.easeOut,
      );

      final clone = shape.duplicated();

      expect(clone.id, isNot(shape.id));
      expect(clone.name, 'Carré (copie)');
      expect(clone.startMs, 500);
      expect(clone.endMs, 2500);
      for (var i = 0; i < shape.layers.length; i++) {
        expect(clone.layers[i].id, isNot(shape.layers[i].id));
        expect(clone.layers[i].name, shape.layers[i].name);
        expect(clone.layers[i].kind, shape.layers[i].kind);
      }
      expect(clone.keyframes.length, 2);
      expect(clone.keyframes[0].timeMs, 500);
      expect(clone.keyframes[0].easing, EasingKind.linear);
      expect(clone.keyframes[1].timeMs, 2500);
      expect(clone.keyframes[1].values[AnimatableProperty.rotation], 1.5);
      expect(clone.keyframes[1].easing, EasingKind.easeOut);
      // L'original reste intact.
      expect(shape.keyframes.length, 2);
    });

    test('duplicated conserve une instance d\'animation', () {
      final shape = VectorShape(
        name: 'Instance',
        embeddedProjectId: 'src-1',
        embeddedWidth: 360,
        embeddedHeight: 640,
      );
      final clone = shape.duplicated();
      expect(clone.isInstance, isTrue);
      expect(clone.embeddedProjectId, 'src-1');
      expect(clone.id, isNot(shape.id));
    });
  });

  group('déplacement de segment', () {
    test('shiftBy décale fenêtre et keyframes, durée inchangée', () {
      final shape = VectorShape(name: 'A', startMs: 1000, endMs: 3000);
      shape.upsertKeyframe(1000, shape.poseAt(1000), easing: EasingKind.linear);
      shape.upsertKeyframe(
        2000,
        shape.poseAt(1000),
        easing: EasingKind.easeInOut,
      );
      shape.upsertKeyframe(3000, shape.poseAt(1000), easing: EasingKind.easeOut);

      shape.shiftBy(500);
      expect(shape.startMs, 1500);
      expect(shape.endMs, 3500);
      expect(shape.durationMs, 2000);
      expect(
        [for (final key in shape.keyframes) key.timeMs],
        <int>[1500, 2500, 3500],
      );
      expect(
        [for (final key in shape.keyframes) key.easing],
        <EasingKind>[
          EasingKind.linear,
          EasingKind.easeInOut,
          EasingKind.easeOut,
        ],
      );

      shape.shiftBy(-1200);
      expect(shape.startMs, 300);
      expect(shape.endMs, 2300);
      expect(
        [for (final key in shape.keyframes) key.timeMs],
        <int>[300, 1300, 2300],
      );
    });

    test('shiftBy décalage nul ne change rien', () {
      final shape = VectorShape(name: 'A', startMs: 100, endMs: 500);
      shape.upsertKeyframe(300, shape.poseAt(300));
      shape.shiftBy(0);
      expect(shape.startMs, 100);
      expect(shape.endMs, 500);
      expect(shape.keyframes.single.timeMs, 300);
    });

    test('shiftBy rabote les keyframes passées sous zéro', () {
      final shape = VectorShape(name: 'A', startMs: 0, endMs: 1000);
      shape.upsertKeyframe(500, shape.poseAt(500));
      shape.keyframes.add(ShapeKeyframe(timeMs: -400)); // hors fenêtre
      shape.shiftBy(-200);
      expect([for (final key in shape.keyframes) key.timeMs], contains(0));
      expect(shape.keyframes.length, 2);
    });
  });
}
