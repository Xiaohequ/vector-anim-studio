import 'package:flutter_test/flutter_test.dart';
import 'package:vector_anim_studio/engine/selection_geometry.dart';
import 'package:vector_anim_studio/engine/simple_animation_format.dart';
import 'package:vector_anim_studio/models/animation.dart';

VectorShape _pathShape({List<Offset>? points}) {
  final shape = VectorShape(name: 'A', startMs: 0, endMs: 4000);
  shape.layers.add(
    ShapeLayer(
      name: 'L',
      kind: ShapeKind.path,
      width: 100,
      height: 100,
      points:
          points ??
          const <Offset>[
            Offset(0, 0),
            Offset(100, 0),
            Offset(100, 100),
            Offset(0, 100),
          ],
    ),
  );
  return shape;
}

void main() {
  group('éditeur de points (v0.16)', () {
    test('sans keyframe : le nuage est écrit dans la base', () {
      final shape = _pathShape();
      final layer = shape.layers.first;
      final cloud = List<Offset>.from(layer.points);
      cloud[1] = const Offset(120, -20);
      shape.applyLayerPoints(layer, cloud, 1000, autoKey: true);
      expect(shape.keyframes, isEmpty);
      expect(layer.points[1], const Offset(120, -20));
      // Les autres points sont intacts.
      expect(layer.points[0], const Offset(0, 0));
      expect(layer.points[2], const Offset(100, 100));
    });

    test('auto-key : un glisser crée une pose au curseur semée du nuage', () {
      final shape = _pathShape();
      final layer = shape.layers.first;
      // Base posée d'abord (pas de keyframe).
      final base = List<Offset>.from(layer.points);
      base[0] = const Offset(-40, -40);
      shape.applyLayerPoints(layer, base, 0, autoKey: true);
      // Une pose existe (créée par le ◆ du studio) : le glisser auto-keye.
      shape.upsertKeyframe(0, shape.poseAt(0), easing: EasingKind.linear);
      // Déplace le point 2 de +30,+10 au curseur 2000.
      // (pointsAtLayer peut renvoyer la liste de base VIVANTE — toujours
      // copier avant de muter, comme le fait l'éditeur.)
      final cloud = List<Offset>.from(
        shape.pointsAtLayer(layer.id, layer.points, 2000),
      );
      cloud[2] = cloud[2] + const Offset(30, 10);
      shape.applyLayerPoints(layer, cloud, 2000, autoKey: true);
      expect(shape.keyframes, hasLength(2));
      final key = shape.keyframes.last;
      expect(key.timeMs, 2000);
      expect(key.layerPoints[layer.id]![2], const Offset(130, 110));
      // Les points non déplacés sont semés du nuage échantillonné (base).
      expect(key.layerPoints[layer.id]![0], const Offset(-40, -40));
      // La base n'a pas bougé (auto-key, la forme a désormais des keyframes).
      expect(layer.points[2], const Offset(100, 100));
      // La pose numérique est capturée (complète).
      expect(key.values, hasLength(AnimatableProperty.values.length));
    });

    test('semer est visuellement neutre : continuité de l\'interpolation', () {
      final shape = _pathShape();
      final layer = shape.layers.first;
      shape.upsertKeyframe(
        0,
        shape.poseAt(0),
        easing: EasingKind.linear,
        layerPoints: {layer.id: List<Offset>.from(layer.points)},
      );
      shape.upsertKeyframe(
        2000,
        shape.poseAt(2000),
        easing: EasingKind.linear,
        layerPoints: {
          layer.id: const <Offset>[
            Offset(200, 0),
            Offset(300, 0),
            Offset(300, 100),
            Offset(200, 100),
          ],
        },
      );
      // À mi-course, le rendu glisse de +100 en X.
      final mid = shape.pointsAtLayer(layer.id, const [], 1000);
      expect(mid[0], const Offset(100, 0));
      // Éditer le point 1 au CURSEUR 1000 (pas une pose existante) : le nuage
      // semé = le rendu à la cible ; le point 0 reste à sa place rendue.
      final cloud = List<Offset>.from(
        shape.pointsAtLayer(layer.id, const [], 1000),
      );
      cloud[1] = cloud[1] + const Offset(0, -50);
      shape.applyLayerPoints(layer, cloud, 1000, autoKey: true);
      final newKey = shape.keyframes[1];
      expect(newKey.timeMs, 1000);
      expect(newKey.layerPoints[layer.id]![0], const Offset(100, 0));
      expect(newKey.layerPoints[layer.id]![1], const Offset(200, -50));
      // Les poses encadrantes sont inchangées.
      expect(
        shape.keyframes[0].layerPoints[layer.id]![1],
        const Offset(100, 0),
      );
      expect(
        shape.keyframes[2].layerPoints[layer.id]![1],
        const Offset(300, 0),
      );
    });

    test('tolérance : le glisser écrit dans la keyframe proche', () {
      final shape = _pathShape();
      final layer = shape.layers.first;
      shape.upsertKeyframe(0, shape.poseAt(0));
      shape.upsertKeyframe(2000, shape.poseAt(2000));
      final cloud = List<Offset>.from(
        shape.pointsAtLayer(layer.id, layer.points, 2050),
      );
      cloud[0] = cloud[0] + const Offset(5, 5);
      // Tolérance ~80 ms pour 4000 ms : 2050 snappe à 2000.
      shape.applyLayerPoints(
        layer,
        cloud,
        2050,
        autoKey: true,
        toleranceMs: keyframeSnapToleranceMs(shape.durationMs),
      );
      expect(shape.keyframes, hasLength(2));
      expect(shape.keyframes[1].timeMs, 2000);
      expect(
        shape.keyframes[1].layerPoints[layer.id]![0].dx,
        closeTo(5, 0.01),
      );
    });

    test('éditer une pose existante préserve easings et couleurs', () {
      final shape = _pathShape();
      final layer = shape.layers.first;
      shape.upsertKeyframe(
        0,
        shape.poseAt(0),
        easing: EasingKind.linear,
        layerColors: {layer.id: 0xFFFF5C5C},
      );
      shape.upsertKeyframe(
        2000,
        shape.poseAt(2000),
        easing: EasingKind.easeOut,
      );
      final cloud = List<Offset>.from(layer.points);
      cloud[3] = const Offset(-30, 130);
      shape.applyLayerPoints(layer, cloud, 2000, autoKey: true);
      final key = shape.keyframes[1];
      expect(key.easing, EasingKind.easeOut);
      expect(shape.keyframes[0].layerColors[layer.id], 0xFFFF5C5C);
      expect(key.layerPoints[layer.id]![3], const Offset(-30, 130));
      // La couleur de la pose éditée est restée absente (non portée).
      expect(key.layerColors[layer.id], isNull);
    });

    test('insertLayerPoint aligne la base et tous les nuages', () {
      final shape = _pathShape();
      final layer = shape.layers.first;
      shape.upsertKeyframe(
        0,
        shape.poseAt(0),
        layerPoints: {
          layer.id: const <Offset>[
            Offset(-10, -10),
            Offset(110, -10),
            Offset(110, 110),
            Offset(-10, 110),
          ],
        },
      );
      shape.upsertKeyframe(
        2000,
        shape.poseAt(2000),
        layerPoints: {
          layer.id: const <Offset>[
            Offset(0, 0),
            Offset(100, 0),
            Offset(100, 100),
            Offset(0, 100),
          ],
        },
      );
      shape.insertLayerPoint(layer, 2, const Offset(50, -5));
      expect(layer.points, hasLength(5));
      expect(layer.points[2], const Offset(50, -5));
      final key0 = shape.keyframes[0];
      final key1 = shape.keyframes[1];
      expect(key0.layerPoints[layer.id], hasLength(5));
      expect(key0.layerPoints[layer.id]![2], const Offset(50, -5));
      expect(key1.layerPoints[layer.id]![2], const Offset(50, -5));
      // La correspondance positionnelle est préservée.
      expect(key0.layerPoints[layer.id]![3], const Offset(110, 110));
      expect(key1.layerPoints[layer.id]![3], const Offset(100, 100));
    });

    test('insertLayerPoint : un nuage plus court reçoit le point en fin', () {
      final shape = _pathShape();
      final layer = shape.layers.first;
      shape.upsertKeyframe(
        0,
        shape.poseAt(0),
        layerPoints: {
          layer.id: const <Offset>[Offset(1, 1), Offset(2, 2)],
        },
      );
      shape.insertLayerPoint(layer, 2, const Offset(50, -5));
      final entry = shape.keyframes.first.layerPoints[layer.id]!;
      expect(entry, hasLength(3));
      expect(entry[2], const Offset(50, -5));
    });

    test('removeLayerPoint aligne la base et les nuages', () {
      final shape = _pathShape();
      final layer = shape.layers.first;
      shape.upsertKeyframe(
        0,
        shape.poseAt(0),
        layerPoints: {layer.id: List<Offset>.from(layer.points)},
      );
      shape.removeLayerPoint(layer, 1);
      expect(layer.points, hasLength(3));
      final entry = shape.keyframes.first.layerPoints[layer.id]!;
      expect(entry, hasLength(3));
      expect(entry[1], const Offset(100, 100));
    });

    test('removeLayerPoint ignore un nuage plus court que l\'index', () {
      final shape = _pathShape();
      final layer = shape.layers.first;
      shape.upsertKeyframe(
        0,
        shape.poseAt(0),
        layerPoints: {
          layer.id: const <Offset>[Offset(1, 1)],
        },
      );
      shape.removeLayerPoint(layer, 2);
      // Nuage laissé tel quel, base réduite.
      expect(shape.keyframes.first.layerPoints[layer.id]!, hasLength(1));
      expect(layer.points, hasLength(3));
    });

    test(
      'canvasToLocal : aller-retour exact sous rotation + échelle d\'axe',
      () {
        const geo = SceneGeometry(scale: 0.5, dx: 40, dy: 12);
        final pose = Pose2D(
          origin: const Offset(180, 320),
          rotation: 0.7,
          scale: 1.3,
          scaleX: 0.8,
          scaleY: 1.4,
          pivotDx: 20,
          pivotDy: -10,
        );
        final local = const Offset(33, -21);
        final canvas = SelectionGeometry.localToCanvas(local, pose, geo);
        final back = SelectionGeometry.canvasToLocal(canvas, pose, geo);
        expect(back.dx, closeTo(local.dx, 0.0001));
        expect(back.dy, closeTo(local.dy, 0.0001));
        // Deltas : la différence des conversions donne le delta local exact.
        final canvasB = SelectionGeometry.localToCanvas(
          local + const Offset(10, 4),
          pose,
          geo,
        );
        final delta =
            SelectionGeometry.canvasToLocal(canvasB, pose, geo) -
            SelectionGeometry.canvasToLocal(canvas, pose, geo);
        expect(delta.dx, closeTo(10, 0.0001));
        expect(delta.dy, closeTo(4, 0.0001));
      },
    );

    test('vasf : un nuage édité in-app est exporté en version 3', () {
      final shape = _pathShape();
      final layer = shape.layers.first;
      shape.upsertKeyframe(
        0,
        shape.poseAt(0),
        easing: EasingKind.linear,
        layerPoints: {
          layer.id: const <Offset>[
            Offset(-10, 0),
            Offset(110, 0),
            Offset(110, 100),
            Offset(-10, 100),
          ],
        },
      );
      final json = SimpleAnimationFormat.toJson(
        AnimationProject(name: 'P', shapes: <VectorShape>[shape]),
      );
      expect(json['version'], 3);
      final keys =
          (json['shapes'] as List<Object?>).first as Map<String, Object?>;
      final kf =
          ((keys['keyframes'] as List<Object?>).first as Map<String, Object?>);
      // Repère json : autour du centre de la bbox de base (50, 50) —
      // stocké − (50, 50) + (50, 50) = stocké ici (bbox 100×100 centrée).
      expect(kf['points'], <Object?>[
        <Object?>[-10, 0],
        <Object?>[110, 0],
        <Object?>[110, 100],
        <Object?>[-10, 100],
      ]);
    });

    test('nearestClosedSegment trouve le segment de fermeture', () {
      final positions = const <Offset>[
        Offset(0, 0),
        Offset(100, 0),
        Offset(100, 100),
        Offset(0, 100),
      ];
      final (segment, distance) = SelectionGeometry.nearestClosedSegment(
        positions,
        const Offset(-8, 50),
      );
      expect(segment, 3); // segment de fermeture (3 → 0)
      expect(distance, closeTo(8, 0.01));
      final (segment2, distance2) = SelectionGeometry.nearestClosedSegment(
        positions,
        const Offset(50, 8),
      );
      expect(segment2, 0); // segment (0 → 1)
      expect(distance2, closeTo(8, 0.01));
    });

    test('hitPointIndex renvoie le plus proche dans la tolérance', () {
      final handles = const <Offset>[Offset(0, 0), Offset(50, 0)];
      expect(
        SelectionGeometry.hitPointIndex(handles, const Offset(46, 0), 10),
        1,
      );
      expect(
        SelectionGeometry.hitPointIndex(handles, const Offset(4, 0), 10),
        0,
      );
      expect(
        SelectionGeometry.hitPointIndex(handles, const Offset(24, 0), 10),
        -1,
      );
    });

    test('insertLayerPoint : index borné', () {
      final shape = _pathShape();
      final layer = shape.layers.first;
      shape.insertLayerPoint(layer, 99, const Offset(7, 7));
      expect(layer.points.last, const Offset(7, 7));
      expect(layer.points, hasLength(5));
    });

    test('pointsAtLayer : le carry traverse les poses sans nuage', () {
      final shape = _pathShape();
      final layer = shape.layers.first;
      final seed = List<Offset>.from(layer.points);
      seed[0] = const Offset(-5, -5);
      shape.applyLayerPoints(layer, seed, 1000, autoKey: true);
      // Sans keyframe (base écrite), le fallback est utilisé tel quel :
      // passer la base → carry amont à 0.
      expect(shape.pointsAtLayer(layer.id, layer.points, 0), layer.points);
      final at3000 = shape.pointsAtLayer(layer.id, layer.points, 3000);
      expect(at3000[0], const Offset(-5, -5));
    });
  });
}
