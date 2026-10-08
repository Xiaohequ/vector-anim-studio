import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_anim_studio/engine/animation_presets.dart';
import 'package:vector_anim_studio/engine/timeline_layout.dart';
import 'package:vector_anim_studio/engine/undo_stack.dart';
import 'package:vector_anim_studio/engine/export_service.dart';
import 'package:vector_anim_studio/models/animation.dart';
import 'package:vector_anim_studio/models/skeleton.dart';

void main() {
  group('poses de keyframe', () {
    test('interpole toutes les propriétés entre deux poses', () {
      final shape = VectorShape(name: 'A', x: 0, y: 10, opacity: 1);
      shape.upsertKeyframe(0, shape.poseAt(0), easing: EasingKind.linear);
      shape.upsertKeyframe(1000, <AnimatableProperty, double>{
        ...shape.poseAt(0),
        AnimatableProperty.x: 100,
        AnimatableProperty.y: 60,
        AnimatableProperty.opacity: 0,
      }, easing: EasingKind.linear);

      expect(shape.valueAt(AnimatableProperty.x, 0), 0);
      expect(shape.valueAt(AnimatableProperty.x, 500), closeTo(50, 0.001));
      expect(shape.valueAt(AnimatableProperty.y, 500), closeTo(35, 0.001));
      expect(
        shape.valueAt(AnimatableProperty.opacity, 500),
        closeTo(0.5, 0.001),
      );
      expect(shape.valueAt(AnimatableProperty.x, 2000), 100);
    });

    test('easeInOut part et arrive en douceur', () {
      final shape = VectorShape(name: 'B', opacity: 0);
      shape.upsertKeyframe(0, shape.poseAt(0), easing: EasingKind.linear);
      shape.upsertKeyframe(1000, <AnimatableProperty, double>{
        ...shape.poseAt(0),
        AnimatableProperty.opacity: 1,
      });
      expect(shape.valueAt(AnimatableProperty.opacity, 250), lessThan(0.25));
      expect(shape.valueAt(AnimatableProperty.opacity, 750), greaterThan(0.75));
    });

    test('remplace la pose au même temps', () {
      final shape = VectorShape(name: 'C');
      shape.upsertKeyframe(0, shape.poseAt(0));
      shape.upsertKeyframe(0, <AnimatableProperty, double>{
        ...shape.poseAt(0),
        AnimatableProperty.scale: 2,
      });
      expect(shape.keyframes.length, 1);
      expect(shape.keyframes.first.values[AnimatableProperty.scale], 2);
    });
  });

  group('VectorShape', () {
    test('zIndex et les coins arrondis survivent au JSON interne', () {
      final shape = VectorShape(name: 'Styles', zIndex: 4);
      final rect = ShapeLayer(
        name: 'Rect',
        kind: ShapeKind.rect,
        cornerRadius: 17,
        roundTopLeft: false,
        roundBottomRight: false,
      );
      shape.layers.add(rect);
      final copy = VectorShape.fromJson(shape.toJson());
      expect(copy.zIndex, 4);
      expect(copy.layers.single.cornerRadius, 17);
      expect(copy.layers.single.roundTopLeft, isFalse);
      expect(copy.layers.single.roundTopRight, isTrue);
      expect(copy.layers.single.roundBottomRight, isFalse);
      expect(copy.layers.single.roundBottomLeft, isTrue);
      expect(
        ShapeLayer(name: 'Default', kind: ShapeKind.rect).cornerRadius,
        -1,
      );
    });

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

    test('les huit formats Canvas respectent leur ratio et dimensions', () {
      const expectedRatios = <ProjectFormat, double>{
        ProjectFormat.portrait: 9 / 16,
        ProjectFormat.portrait4x5: 4 / 5,
        ProjectFormat.portrait3x4: 3 / 4,
        ProjectFormat.square: 1,
        ProjectFormat.landscape4x3: 4 / 3,
        ProjectFormat.landscape3x2: 3 / 2,
        ProjectFormat.landscape: 16 / 9,
        ProjectFormat.ultrawide21x9: 21 / 9,
      };
      expect(ProjectFormat.values, hasLength(8));
      for (final format in ProjectFormat.values) {
        expect(
          format.width / format.height,
          closeTo(expectedRatios[format]!, 0.001),
          reason: format.ratioLabel,
        );
      }
      expect(ProjectFormatInfo.closestTo(512, 640), ProjectFormat.portrait4x5);
      expect(ProjectFormatInfo.closestTo(100, 0), ProjectFormat.portrait);
    });

    test('blank applique le format choisi, durée et fps non fixés', () {
      final project = AnimationProject.blank(
        name: 'Test',
        format: ProjectFormat.landscape,
      );
      project.fps = 24;
      expect(project.width, 640);
      expect(project.height, 360);
      // Durée dérivée du contenu : projet vide → 0.
      expect(project.durationMs, 0);
      expect(project.fps, 24);
      expect(project.shapes, isEmpty);
    });

    test('la durée du projet suit le contenu de la timeline', () {
      final project = AnimationProject.blank();
      expect(project.durationMs, 0);

      final a = VectorShape(name: 'A', startMs: 0, endMs: 2000);
      project.shapes.add(a);
      expect(project.durationMs, 2000);

      // Une forme posée plus loin étend le projet.
      final b = VectorShape(name: 'B', startMs: 3000, endMs: 5000);
      project.shapes.add(b);
      expect(project.durationMs, 5000);

      // Raccourcir le porteur de la durée raccourcit le projet.
      b.endMs = 3500;
      expect(project.durationMs, 3500);

      // Supprimer la dernière forme le raccourcit encore.
      project.shapes.remove(b);
      expect(project.durationMs, 2000);

      // Un aller-retour JSON conserve la durée dérivée.
      final restored = AnimationProject.fromJson(
        jsonDecode(jsonEncode(project.toJson())) as Map<String, dynamic>,
      );
      expect(restored.durationMs, 2000);
    });

    test('durée squelette : les pièces comptent, plancher 4 s avec rig', () {
      final project = AnimationProject.blank(type: ProjectType.skeleton);
      final piece = VectorShape(name: 'Tête', startMs: 0, endMs: 4000);
      project.shapes.add(piece);
      // Bug v0.9.0 : sans rig, la durée d'un projet squelette valait 0 →
      // playback mort et « 0 s / 0 s » malgré des pièces de 4 s.
      expect(project.durationMs, 4000);

      final rig = SkeletonRig();
      project.skeleton = rig;
      rig.addBone(RigBone(name: 'B'));
      expect(project.durationMs, 4000); // plancher 4 s

      piece.endMs = 6000;
      expect(project.durationMs, 6000); // la pièce porte la durée

      rig.upsertKeyframe('b1', 9000, 1);
      expect(project.durationMs, 9000); // les keyframes dépassent
    });
  });

  group('pile d\'annulation', () {
    test('push copie profondément, pop rejoue en FIFO', () {
      final stack = UndoStack();
      final project = AnimationProject.blank(name: 'P');
      final shape = VectorShape(name: 'A', startMs: 0, endMs: 1000);
      shape.layers.add(ShapeLayer(name: 'L', kind: ShapeKind.rect));
      shape.upsertKeyframe(500, shape.poseAt(500));
      project.shapes.add(shape);

      stack.push(project);

      // Mutation après le snapshot.
      shape.endMs = 3000;
      shape.upsertKeyframe(1000, shape.poseAt(1000));
      shape.layers.add(ShapeLayer(name: 'B', kind: ShapeKind.circle));
      expect(project.durationMs, 3000);
      expect(shape.keyframes.length, 2);
      expect(shape.layers.length, 2);

      // L'annulation rend l'état d'avant mutation.
      final previous = stack.pop()!;
      expect(previous.shapes.single.endMs, 1000);
      expect(previous.durationMs, 1000);
      expect(previous.shapes.single.keyframes.length, 1);
      expect(previous.shapes.single.layers.length, 1);
      expect(stack.canUndo, isFalse);
    });

    test('la pile est limitée aux 20 dernières actions', () {
      final stack = UndoStack();
      final project = AnimationProject.blank(name: 'P');
      for (var i = 0; i < 25; i++) {
        stack.push(project);
      }
      expect(stack.length, 20);
      // Les 5 plus anciens ont été évincés : on pop 20 fois, plus rien après.
      for (var i = 0; i < 20; i++) {
        expect(stack.pop(), isNotNull);
      }
      expect(stack.pop(), isNull);
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
      expect(
        shape.valueAt(AnimatableProperty.scale, 1000),
        closeTo(1.25, 0.001),
      );
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
      expect(back.embeddedIsSkeleton, isFalse);
      expect(back.flipH, isFalse);
      expect(back.flipV, isFalse);
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
      shape.upsertKeyframe(2500, <AnimatableProperty, double>{
        ...shape.poseAt(500),
        AnimatableProperty.rotation: 1.5,
      }, easing: EasingKind.easeOut);

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
      shape.upsertKeyframe(
        3000,
        shape.poseAt(1000),
        easing: EasingKind.easeOut,
      );

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

    test('shiftBy déplace au-delà de la fin : la durée projet s\'étend', () {
      final project = AnimationProject.blank(name: 'P');
      final shape = VectorShape(name: 'A', startMs: 0, endMs: 2000);
      shape.upsertKeyframe(1000, shape.poseAt(1000));
      project.shapes.add(shape);
      expect(project.durationMs, 2000);

      // Déplacer bien au-delà de la fin actuelle : aucun butoir, la durée
      // dérivée suit la fenêtre et les keyframes suivent d'un même delta.
      shape.shiftBy(6000);
      expect(shape.startMs, 6000);
      expect(shape.endMs, 8000);
      expect(shape.keyframes.single.timeMs, 7000);
      expect(project.durationMs, 8000);
    });

    test('allonger la fin d\'une forme au-delà de la fin étend le projet', () {
      final project = AnimationProject.blank(name: 'P');
      final shape = VectorShape(name: 'A', startMs: 0, endMs: 2000);
      shape.layers.add(ShapeLayer(name: 'L', kind: ShapeKind.rect));
      project.shapes.add(shape);

      // La poignée droite de la timeline écrit directement la fenêtre.
      shape.endMs = 5000;
      expect(project.durationMs, 5000);

      // Un trou reste possible : deux formes espacées tiennent sur la même
      // ligne (l'empilement glouton réutilise une ligne après un trou).
      final b = VectorShape(name: 'B', startMs: 6000, endMs: 7000);
      b.layers.add(ShapeLayer(name: 'L', kind: ShapeKind.rect));
      project.shapes.add(b);
      expect(TimelineLayout.packLanes(project.shapes).length, 1);
    });
  });

  group('couleur animée + morph (v0.15)', () {
    ShapeLayer layerOf(VectorShape shape) => shape.layers.first;

    test('colorAtLayer interpole, tient hors plage et retombe sur la base', () {
      final shape = VectorShape(name: 'A', startMs: 0, endMs: 3000);
      shape.layers.add(ShapeLayer(name: 'L', kind: ShapeKind.rect));
      final layer = layerOf(shape);
      shape.upsertKeyframe(
        0,
        shape.poseAt(0),
        layerColors: {layer.id: 0xFF0000FF},
      );
      shape.upsertKeyframe(
        2000,
        shape.poseAt(2000),
        easing: EasingKind.linear,
        layerColors: {layer.id: 0xFFFF0000},
      );
      // Tenue avant/après la plage colorée.
      expect(shape.colorAtLayer(layer.id, -1, 0xFF123456), 0xFF0000FF);
      expect(shape.colorAtLayer(layer.id, 5000, 0xFF123456), 0xFFFF0000);
      // Interpolation à mi-parcours (linéaire).
      expect(
        shape.colorAtLayer(layer.id, 1000, 0xFF123456),
        lerpArgb(0xFF0000FF, 0xFFFF0000, 0.5),
      );
      // Couche sans entrée posée → couleur de base (fallback).
      final other = ShapeLayer(name: 'Autre', kind: ShapeKind.circle);
      shape.layers.add(other);
      expect(shape.colorAtLayer(other.id, 1000, 0xFFABCDEF), 0xFFABCDEF);
      expect(shape.layerColorAnimated(layer.id), isTrue);
      expect(shape.layerColorAnimated(other.id), isFalse);
    });

    test('les poses sans couleur ne coupent pas l\'animation (carry)', () {
      final shape = VectorShape(name: 'A', startMs: 0, endMs: 4000);
      final layer = ShapeLayer(name: 'L', kind: ShapeKind.rect);
      shape.layers.add(layer);
      shape.upsertKeyframe(
        0,
        shape.poseAt(0),
        layerColors: {layer.id: 0xFF0000FF},
      );
      shape.upsertKeyframe(
        2000,
        shape.poseAt(2000),
        easing: EasingKind.linear,
        layerColors: {layer.id: 0xFFFFFFFF},
      );
      // Pose intermédiaire SANS couleur : le blanc porté tient jusqu'ici.
      shape.upsertKeyframe(3000, shape.poseAt(3000), easing: EasingKind.linear);
      expect(shape.colorAtLayer(layer.id, 2500, 0), 0xFFFFFFFF);
      expect(shape.colorAtLayer(layer.id, 3500, 0), 0xFFFFFFFF);
    });

    test('pointsAtLayer lerpe point par point et bourre le nuage court', () {
      final shape = VectorShape(name: 'A', startMs: 0, endMs: 2000);
      final layer = ShapeLayer(
        name: 'L',
        kind: ShapeKind.path,
        points: const <Offset>[Offset(0, 0), Offset(100, 0), Offset(100, 100)],
      );
      shape.layers.add(layer);
      shape.upsertKeyframe(
        0,
        shape.poseAt(0),
        layerPoints: {layer.id: layer.points},
      );
      shape.upsertKeyframe(
        2000,
        shape.poseAt(2000),
        easing: EasingKind.linear,
        layerPoints: {
          layer.id: const <Offset>[Offset(200, 50), Offset(300, 50)],
        },
      );
      final mid = shape.pointsAtLayer(layer.id, const [], 1000);
      expect(mid.length, 3); // bourré avec le dernier point du nuage court
      expect(
        mid[0],
        Offset.lerp(const Offset(0, 0), const Offset(200, 50), 0.5),
      );
      expect(
        mid[1],
        Offset.lerp(const Offset(100, 0), const Offset(300, 50), 0.5),
      );
      expect(
        mid[2],
        Offset.lerp(const Offset(100, 100), const Offset(300, 50), 0.5),
      );
      expect(shape.pointsAtLayer(layer.id, const [], 3000), const <Offset>[
        Offset(200, 50),
        Offset(300, 50),
      ]);
    });

    test('applyLayerColor écrit la base sans keyframe, la pose ensuite', () {
      final shape = VectorShape(name: 'A', startMs: 0, endMs: 2000);
      final layer = ShapeLayer(name: 'L', kind: ShapeKind.rect);
      shape.layers.add(layer);
      shape.applyLayerColor(layer, 0xFF112233, 500, autoKey: true);
      expect(layer.colorValue, 0xFF112233);
      expect(shape.keyframes, isEmpty);

      shape.upsertKeyframe(0, shape.poseAt(0));
      shape.upsertKeyframe(2000, shape.poseAt(2000));
      shape.applyLayerColor(
        layer,
        0xFF445566,
        1000,
        autoKey: true,
        toleranceMs: 0,
      );
      // Une NOUVELLE pose est créée au curseur, avec l'entrée de couleur.
      expect(shape.keyframes.length, 3);
      expect(shape.keyframes[1].timeMs, 1000);
      expect(shape.keyframes[1].layerColors[layer.id], 0xFF445566);
      // Écrire SUR une pose existante fusionne (la pose numérique tient).
      shape.applyLayerColor(
        layer,
        0xFFAABBCC,
        2000,
        autoKey: true,
        toleranceMs: 0,
      );
      expect(shape.keyframes.length, 3);
      expect(shape.keyframes.last.layerColors[layer.id], 0xFFAABBCC);
      expect(shape.keyframes.last.valueOf(AnimatableProperty.x), isNotNull);
    });

    test(
      'upsertKeyframe préserve la bézier d\'une pose existante (bug v0.13)',
      () {
        final shape = VectorShape(name: 'A', startMs: 0, endMs: 2000);
        shape.layers.add(ShapeLayer(name: 'L', kind: ShapeKind.rect));
        shape.upsertKeyframe(0, shape.poseAt(0));
        shape.upsertKeyframe(
          2000,
          shape.poseAt(2000),
          easing: EasingKind.customBezier,
          bezier: const [0.34, 1.56, 0.64, 1.0],
          layerColors: {shape.layers.first.id: 0xFFFF0000},
        );
        // Écriture d'une position sur cette pose : la courbe et la couleur
        // doivent survivre (v0.13 les perdait → overshoot mort).
        shape.applyValue(AnimatableProperty.x, 42, 2000, autoKey: true);
        final pose = shape.keyframes.last;
        expect(pose.timeMs, 2000);
        expect(pose.easing, EasingKind.customBezier);
        expect(pose.bezier, const <double>[0.34, 1.56, 0.64, 1.0]);
        expect(pose.layerColors[shape.layers.first.id], 0xFFFF0000);
        expect(pose.valueOf(AnimatableProperty.x), 42);
      },
    );

    test('aller-retour JSON des cartes couleur/morph', () {
      final shape = VectorShape(name: 'A', startMs: 0, endMs: 2000);
      final layer = ShapeLayer(
        name: 'L',
        kind: ShapeKind.path,
        points: const <Offset>[Offset(0, 0), Offset(40, 0), Offset(40, 40)],
      );
      shape.layers.add(layer);
      shape.upsertKeyframe(
        0,
        shape.poseAt(0),
        layerColors: {layer.id: 0xFFFF5C5C},
        layerPoints: {
          layer.id: const <Offset>[Offset(9, 9), Offset(31, 9), Offset(31, 31)],
        },
      );
      final decoded = VectorShape.fromJson(
        (shape.toJson() as Map).cast<String, Object?>(),
      );
      final key = decoded.keyframes.single;
      expect(key.layerColors[decoded.layers.first.id], 0xFFFF5C5C);
      expect(key.layerPoints[decoded.layers.first.id], const <Offset>[
        Offset(9, 9),
        Offset(31, 9),
        Offset(31, 31),
      ]);
    });
  });

  group('définition vidéo MP4', () {
    test(
      'preset 720p préserve le ratio portrait et le codec reçoit du pair',
      () {
        final project = AnimationProject(width: 720, height: 1280);
        final size = mp4DimensionsForLongEdge(project, 720);
        expect(size.width, 406);
        expect(size.height, 720);
        expect(size.width.isEven, isTrue);
        expect(size.height.isEven, isTrue);
      },
    );

    test('preset 1080p fonctionne en paysage et sur un format carré', () {
      final landscape = mp4DimensionsForLongEdge(
        AnimationProject(width: 1280, height: 720),
        1080,
      );
      expect(landscape, (width: 1080, height: 608));
      final square = mp4DimensionsForLongEdge(
        AnimationProject(width: 800, height: 800),
        480,
      );
      expect(square, (width: 480, height: 480));
    });
  });

  test('la durée inclut les keyframes du rig même en type vectoriel', () {
    final project = AnimationProject.blank(type: ProjectType.vector);
    final rig = SkeletonRig();
    final bone = RigBone(name: 'Bras');
    rig.addBone(bone);
    rig.upsertKeyframe(bone.id, 7000, 0.4);
    project.skeleton = rig;

    expect(project.durationMs, 7000);
  });
}
