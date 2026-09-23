import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/animation.dart';

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
        AnimationPreset.apparition => 'Apparition',
        AnimationPreset.disparition => 'Disparition',
        AnimationPreset.deplacement => 'Déplacement',
        AnimationPreset.rotation => 'Rotation',
        AnimationPreset.pulsation => 'Pulsation',
        AnimationPreset.fondu => 'Fondu (aller-retour)',
      };

  String get description => switch (this) {
        AnimationPreset.apparition => 'Opacité 0 → 1 en entrée de forme',
        AnimationPreset.disparition => 'Opacité 1 → 0 en fin de forme',
        AnimationPreset.deplacement => 'Glisse depuis la gauche vers sa place',
        AnimationPreset.rotation => 'Rotation complète sur la durée affichée',
        AnimationPreset.pulsation => 'Échelle 1 → 1,25 → 1',
        AnimationPreset.fondu => 'Opacité 0 → 1 → 0 sur la durée affichée',
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

/// Applique un preset à la forme (pistes créées ou remplacées).
void applyPreset(VectorShape shape, AnimationPreset preset) {
  final start = shape.startMs;
  final end = math.max(shape.startMs + 1, shape.endMs);
  final span = end - start;

  switch (preset) {
    case AnimationPreset.apparition:
      final fade = math.min(400, math.max(80, span ~/ 4));
      _replace(shape, AnimatableProperty.opacity)
        ..setKey(start, 0, easing: EasingKind.linear)
        ..setKey(start + fade, shape.opacity, easing: EasingKind.easeOut);
    case AnimationPreset.disparition:
      final fade = math.min(400, math.max(80, span ~/ 4));
      _replace(shape, AnimatableProperty.opacity)
        ..setKey(end - fade, shape.opacity, easing: EasingKind.easeIn)
        ..setKey(end, 0, easing: EasingKind.linear);
    case AnimationPreset.deplacement:
      final slide = math.min(700, math.max(200, span ~/ 3));
      _replace(shape, AnimatableProperty.x)
        ..setKey(start, shape.x - 140, easing: EasingKind.easeOut)
        ..setKey(start + slide, shape.x, easing: EasingKind.linear);
    case AnimationPreset.rotation:
      _replace(shape, AnimatableProperty.rotation)
        ..setKey(start, shape.rotation, easing: EasingKind.linear)
        ..setKey(end, shape.rotation + 2 * math.pi, easing: EasingKind.linear);
    case AnimationPreset.pulsation:
      final mid = start + (span / 2).round();
      _replace(shape, AnimatableProperty.scale)
        ..setKey(start, shape.scale, easing: EasingKind.easeInOut)
        ..setKey(mid, shape.scale * 1.25, easing: EasingKind.easeInOut)
        ..setKey(end, shape.scale, easing: EasingKind.linear);
    case AnimationPreset.fondu:
      final mid = start + (span / 2).round();
      _replace(shape, AnimatableProperty.opacity)
        ..setKey(start, 0, easing: EasingKind.easeOut)
        ..setKey(mid, shape.opacity, easing: EasingKind.easeInOut)
        ..setKey(end, 0, easing: EasingKind.linear);
  }
}

/// Retire toutes les animations d'une forme.
void clearAnimations(VectorShape shape) => shape.tracks.clear();

AnimTrack _replace(VectorShape shape, AnimatableProperty property) {
  final track = AnimTrack(property);
  shape.tracks[property] = track;
  return track;
}
