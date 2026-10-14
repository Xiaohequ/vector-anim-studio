import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/animation.dart';
import '../settings/language_settings.dart';

/// Animations prêtes à l'emploi, appliquées à la forme sélectionnée.
enum AnimationPreset {
  apparition,
  disparition,
  deplacement,
  rotation,
  pulsation,
  fondu,
}

extension AnimationPresetInfo on AnimationPreset {
  String get label => switch (this) {
    AnimationPreset.apparition => AppStrings.text('Apparition'),
    AnimationPreset.disparition => AppStrings.text('Disparition'),
    AnimationPreset.deplacement => AppStrings.text('Déplacement'),
    AnimationPreset.rotation => AppStrings.text('Rotation'),
    AnimationPreset.pulsation => AppStrings.text('Pulsation'),
    AnimationPreset.fondu => AppStrings.text('Fondu (aller-retour)'),
  };

  String get description => switch (this) {
    AnimationPreset.apparition => AppStrings.text(
      'Opacité 0 → 1 en entrée de forme',
    ),
    AnimationPreset.disparition => AppStrings.text(
      'Opacité 1 → 0 en fin de forme',
    ),
    AnimationPreset.deplacement => AppStrings.text(
      'Glisse depuis la gauche vers sa place',
    ),
    AnimationPreset.rotation => AppStrings.text(
      'Rotation complète sur la durée affichée',
    ),
    AnimationPreset.pulsation => AppStrings.text('Échelle 1 → 1,25 → 1'),
    AnimationPreset.fondu => AppStrings.text(
      'Opacité 0 → 1 → 0 sur la durée affichée',
    ),
  };

  IconData get icon => switch (this) {
    AnimationPreset.apparition => Icons.blur_on,
    AnimationPreset.disparition => Icons.blur_off,
    AnimationPreset.deplacement => Icons.swap_horiz,
    AnimationPreset.rotation => Icons.rotate_right,
    AnimationPreset.pulsation => Icons.zoom_in,
    AnimationPreset.fondu => Icons.gradient,
  };
}

/// Applique un preset à la forme : les keyframes (poses) existantes sont
/// remplacées par la nouvelle séquence. La pose reprend les valeurs de base de
/// la forme, seule la propriété visée varie.
void applyPreset(VectorShape shape, AnimationPreset preset) {
  final start = shape.startMs;
  final end = math.max(shape.startMs + 1, shape.endMs);
  final span = end - start;

  final base = <AnimatableProperty, double>{
    for (final property in AnimatableProperty.values)
      property: shape.baseOf(property),
  };

  ShapeKeyframe pose(
    int timeMs,
    Map<AnimatableProperty, double> overrides,
    EasingKind easing,
  ) => ShapeKeyframe(
    timeMs: timeMs,
    values: <AnimatableProperty, double>{...base, ...overrides},
    easing: easing,
  );

  switch (preset) {
    case AnimationPreset.apparition:
      final fade = math.min(400, math.max(80, span ~/ 4));
      shape.setKeyframes(<ShapeKeyframe>[
        pose(start, <AnimatableProperty, double>{
          AnimatableProperty.opacity: 0,
        }, EasingKind.linear),
        pose(start + fade, <AnimatableProperty, double>{
          AnimatableProperty.opacity: shape.opacity,
        }, EasingKind.easeOut),
      ]);
    case AnimationPreset.disparition:
      final fade = math.min(400, math.max(80, span ~/ 4));
      shape.setKeyframes(<ShapeKeyframe>[
        pose(end - fade, <AnimatableProperty, double>{
          AnimatableProperty.opacity: shape.opacity,
        }, EasingKind.easeIn),
        pose(end, <AnimatableProperty, double>{
          AnimatableProperty.opacity: 0,
        }, EasingKind.linear),
      ]);
    case AnimationPreset.deplacement:
      final slide = math.min(700, math.max(200, span ~/ 3));
      shape.setKeyframes(<ShapeKeyframe>[
        pose(start, <AnimatableProperty, double>{
          AnimatableProperty.x: shape.x - 140,
        }, EasingKind.easeOut),
        pose(start + slide, <AnimatableProperty, double>{
          AnimatableProperty.x: shape.x,
        }, EasingKind.linear),
      ]);
    case AnimationPreset.rotation:
      shape.setKeyframes(<ShapeKeyframe>[
        pose(start, <AnimatableProperty, double>{
          AnimatableProperty.rotation: shape.rotation,
        }, EasingKind.linear),
        pose(end, <AnimatableProperty, double>{
          AnimatableProperty.rotation: shape.rotation + 2 * math.pi,
        }, EasingKind.linear),
      ]);
    case AnimationPreset.pulsation:
      final mid = start + (span / 2).round();
      shape.setKeyframes(<ShapeKeyframe>[
        pose(start, <AnimatableProperty, double>{
          AnimatableProperty.scale: shape.scale,
        }, EasingKind.easeInOut),
        pose(mid, <AnimatableProperty, double>{
          AnimatableProperty.scale: shape.scale * 1.25,
        }, EasingKind.easeInOut),
        pose(end, <AnimatableProperty, double>{
          AnimatableProperty.scale: shape.scale,
        }, EasingKind.linear),
      ]);
    case AnimationPreset.fondu:
      final mid = start + (span / 2).round();
      shape.setKeyframes(<ShapeKeyframe>[
        pose(start, <AnimatableProperty, double>{
          AnimatableProperty.opacity: 0,
        }, EasingKind.easeOut),
        pose(mid, <AnimatableProperty, double>{
          AnimatableProperty.opacity: shape.opacity,
        }, EasingKind.easeInOut),
        pose(end, <AnimatableProperty, double>{
          AnimatableProperty.opacity: 0,
        }, EasingKind.linear),
      ]);
  }
}

/// Retire toutes les animations d'une forme.
void clearAnimations(VectorShape shape) => shape.keyframes.clear();
