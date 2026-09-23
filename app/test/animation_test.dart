import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_anim_studio/engine/animation_presets.dart';
import 'package:vector_anim_studio/models/animation.dart';

void main() {
  group('AnimTrack', () {
    test('interpole linéairement entre deux keyframes', () {
      final track = AnimTrack(AnimatableProperty.x)
        ..setKey(0, 0, easing: EasingKind.linear)
        ..setKey(1000, 100, easing: EasingKind.linear);

      expect(track.sample(0, 0), 0);
      expect(track.sample(500, 0), closeTo(50, 0.001));
      expect(track.sample(1000, 0), 100);
      expect(track.sample(2000, 0), 100);
    });

    test('easeInOut part et arrive en douceur', () {
      final track = AnimTrack(AnimatableProperty.opacity)
        ..setKey(0, 0)
        ..setKey(1000, 1);
      expect(track.sample(250, 0), lessThan(0.25));
      expect(track.sample(750, 0), greaterThan(0.75));
    });

    test('remplace une keyframe existante au même temps', () {
      final track = AnimTrack(AnimatableProperty.scale)
        ..setKey(0, 1)
        ..setKey(0, 2);
      expect(track.keys.length, 1);
      expect(track.keys.first.value, 2);
    });
  });

  group('VectorShape', () {
    test('valueAt retombe sur la valeur de base sans piste', () {
      final shape = VectorShape(name: 'A', x: 42);
      expect(shape.valueAt(AnimatableProperty.x, 500), 42);
      expect(shape.isAnimated(AnimatableProperty.x), isFalse);
    });

    test('addKeyframeAt capture la valeur courante', () {
      final shape = VectorShape(name: 'B', y: 7);
      shape.addKeyframeAt(AnimatableProperty.y, 100);
      expect(shape.isAnimated(AnimatableProperty.y), isTrue);
      expect(shape.tracks[AnimatableProperty.y]!.keys.first.timeMs, 100);
      expect(shape.tracks[AnimatableProperty.y]!.keys.first.value, 7);
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

    test('copy détache les couches et les pistes', () {
      final shape = VectorShape(
        name: 'Originale',
        layers: <ShapeLayer>[ShapeLayer(name: 'Rect', kind: ShapeKind.rect)],
      );
      shape.addKeyframeAt(AnimatableProperty.x, 0);
      final clone = shape.copy();

      clone.layers.first.width = 999;
      clone.tracks[AnimatableProperty.x]!.setKey(0, 999);

      expect(shape.layers.first.width, isNot(999));
      expect(shape.tracks[AnimatableProperty.x]!.sample(0, 0), isNot(999));
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
      final rotation =
          restored.shapes.first.tracks[AnimatableProperty.rotation]!;
      expect(rotation.keys.length, 3);
      expect(rotation.sample(restored.durationMs, 0), closeTo(2 * math.pi, 0.01));
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
    test('apparition crée une piste d’opacité 0 → 1', () {
      final shape = VectorShape(name: 'A', startMs: 1000, endMs: 3000);
      applyPreset(shape, AnimationPreset.apparition);
      final track = shape.tracks[AnimatableProperty.opacity]!;
      expect(shape.isAnimated(AnimatableProperty.opacity), isTrue);
      expect(track.keys.first.value, 0);
      expect(track.keys.last.value, 1);
      expect(track.keys.first.timeMs, 1000);
    });

    test('pulsation passe par un maximum au milieu', () {
      final shape = VectorShape(name: 'P', startMs: 0, endMs: 2000);
      applyPreset(shape, AnimationPreset.pulsation);
      expect(shape.valueAt(AnimatableProperty.scale, 1000), closeTo(1.25, 0.001));
      expect(shape.valueAt(AnimatableProperty.scale, 0), closeTo(1, 0.001));
    });

    test('clearAnimations vide les pistes', () {
      final shape = VectorShape(name: 'C');
      applyPreset(shape, AnimationPreset.rotation);
      clearAnimations(shape);
      expect(shape.tracks, isEmpty);
    });
  });
}