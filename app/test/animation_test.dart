import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
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
      final shape = VectorShape(id: 'a', name: 'A', kind: ShapeKind.rect, x: 42);
      expect(shape.valueAt(AnimatableProperty.x, 500), 42);
      expect(shape.isAnimated(AnimatableProperty.x), isFalse);
    });

    test('addKeyframeAt capture la valeur courante', () {
      final shape = VectorShape(id: 'b', name: 'B', kind: ShapeKind.circle, y: 7);
      shape.addKeyframeAt(AnimatableProperty.y, 100);
      expect(shape.isAnimated(AnimatableProperty.y), isTrue);
      expect(shape.tracks[AnimatableProperty.y]!.keys.first.timeMs, 100);
      expect(shape.tracks[AnimatableProperty.y]!.keys.first.value, 7);
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
      final rotation =
          restored.shapes.first.tracks[AnimatableProperty.rotation]!;
      expect(rotation.keys.length, 3);
      expect(rotation.sample(restored.durationMs, 0), closeTo(2 * math.pi, 0.01));
    });
  });
}