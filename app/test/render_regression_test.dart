import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_anim_studio/engine/binding_retarget.dart';
import 'package:vector_anim_studio/engine/scene_painter.dart';
import 'package:vector_anim_studio/engine/selection_geometry.dart';
import 'package:vector_anim_studio/models/animation.dart';
import 'package:vector_anim_studio/models/skeleton.dart';

/// Suite de régression de RENDU — exécutée à chaque CI (flutter test).
///
/// Chaque test rend une scène de référence en headless (PictureRecorder →
/// image RGBA) et tranche par mesure pixel (centroid d'un masque couleur) :
/// c'est la sonde v0.13.1 rendue permanente (option C, demandée). Toute
/// régression du painter (rig non appliqué, pivot perdu, couche détachée)
/// casse un centroid attendu.

/// Rig commun : racine animée (−90° → −74° à 600 ms) + os enfant.
SkeletonRig _rig() {
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
  // Delta propre sur l'enfant (−30°) : sinon le reciblage racine→enfant
  // est un no-op (le gond ne bouge pas) et le test de reciblage perd son
  // objet.
  final child = rig.bones.last;
  rig.tracks[child.id] = <BoneKeyframe>[
    BoneKeyframe(timeMs: 0),
    BoneKeyframe(timeMs: 600, angleDelta: -math.pi / 6),
    BoneKeyframe(timeMs: 2400),
  ];
  return rig;
}

AnimationProject _project({required SkeletonRig rig}) => AnimationProject(
  name: 'Test rendu',
  type: ProjectType.skeleton,
  skeleton: rig,
  width: 720,
  height: 1280,
  fps: 25,
);

Future<Uint8List> _render(
  WidgetTester tester,
  AnimationProject project,
  int timeMs, {
  int w = 360,
  int h = 640,
}) async {
  late ui.Image image;
  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    ScenePainter(
      project: project,
      timeMs: timeMs,
    ).paint(canvas, ui.Size(w.toDouble(), h.toDouble()));
    image = await recorder.endRecording().toImage(w, h);
  });
  final data = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  expect(data, isNotNull);
  return data!.buffer.asUint8List();
}

({double x, double y, int count}) _centroid(
  Uint8List pixels,
  int w,
  int h,
  bool Function(int r, int g, int b) match,
) {
  var count = 0;
  var sumX = 0.0;
  var sumY = 0.0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      if (match(pixels[i], pixels[i + 1], pixels[i + 2])) {
        count++;
        sumX += x;
        sumY += y;
      }
    }
  }
  expect(count, greaterThan(400), reason: 'le masque est rendu');
  return (x: sumX / count, y: sumY / count, count: count);
}

void main() {
  testWidgets('la pièce liée suit l os animé (centroid mesuré)', (
    tester,
  ) async {
    final rig = _rig();
    final project = _project(rig: rig);
    final shape = VectorShape(name: 'Pièce', x: 200, y: 700);
    shape.layers.add(
      ShapeLayer(
        name: 'Corps',
        kind: ShapeKind.rect,
        width: 70,
        height: 70,
        colorValue: 0xFFFF5C5C,
      ),
    );
    project.shapes.add(shape);
    rig.bindShape(shape.id, rig.bones.first.id);

    final pixels = await _render(tester, project, 600);
    final centroid = _centroid(
      pixels,
      360,
      640,
      (r, g, b) =>
          (r - 0xFF).abs() < 30 &&
          (g - 0x5C).abs() < 30 &&
          (b - 0x5C).abs() < 30,
    );
    // Prédiction : pose de la forme emportée par os(t) — gond à 150 u
    // au-dessus de l'articulation (200, 850), pivot nul.
    final frame = SkeletonPose.evaluate(rig, 600).frameOf(rig.bones.first.id)!;
    final predicted = frame.mapPoint(const Offset(200, 700));
    expect(centroid.x, closeTo(predicted.dx / 2, 6), reason: 'centroid x');
    expect(centroid.y, closeTo(predicted.dy / 2, 6), reason: 'centroid y');
    // Garde anti-faux-positif : sans rig appliqué, centroid = (100, 350).
    expect(
      math.sqrt(math.pow(centroid.x - 100, 2) + math.pow(centroid.y - 350, 2)),
      greaterThan(15),
      reason: 'la pièce a bien tourné avec l os',
    );
  });

  testWidgets('la couche liée suit son os (centroid mesuré)', (tester) async {
    final rig = _rig();
    final project = _project(rig: rig);
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
      colorValue: 0xFFF2C94C,
    );
    shape.layers.add(lampe);
    project.shapes.add(shape);
    rig.bindLayer(shape.id, lampe.id, rig.bones.first.id);

    final pixels = await _render(tester, project, 600);
    final centroid = _centroid(
      pixels,
      360,
      640,
      (r, g, b) =>
          (r - 0xF2).abs() < 30 &&
          (g - 0xC9).abs() < 30 &&
          (b - 0x4C).abs() < 30,
    );
    final frame = SkeletonPose.evaluate(rig, 600).frameOf(rig.bones.first.id)!;
    final layerPose = SelectionGeometry.layerPose(shape, lampe, 600);
    final predicted = frame.mapPoint(layerPose.origin);
    expect(centroid.x, closeTo(predicted.dx / 2, 6), reason: 'centroid x');
    expect(centroid.y, closeTo(predicted.dy / 2, 6), reason: 'centroid y');
  });

  testWidgets('reciblage sans saut : rendu identique avant/après', (
    tester,
  ) async {
    final rig = _rig();
    final project = _project(rig: rig);
    final shape = VectorShape(name: 'Pièce', x: 200, y: 700);
    shape.layers.add(
      ShapeLayer(
        name: 'Corps',
        kind: ShapeKind.rect,
        width: 70,
        height: 70,
        colorValue: 0xFFFF5C5C,
      ),
    );
    project.shapes.add(shape);
    rig.bindShape(shape.id, rig.bones.first.id);

    final before = _centroid(
      await _render(tester, project, 600),
      360,
      640,
      (r, g, b) =>
          (r - 0xFF).abs() < 30 &&
          (g - 0x5C).abs() < 30 &&
          (b - 0x5C).abs() < 30,
    );

    BindingRetarget.retargetShape(rig, shape, rig.bones.last.id, 600);
    // Le reciblage a bien déplacé la pose de base (sinon test sans objet).
    expect(shape.x == 200 && shape.y == 700, isFalse);

    final after = _centroid(
      await _render(tester, project, 600),
      360,
      640,
      (r, g, b) =>
          (r - 0xFF).abs() < 30 &&
          (g - 0x5C).abs() < 30 &&
          (b - 0x5C).abs() < 30,
    );
    final distance = math.sqrt(
      math.pow(after.x - before.x, 2) + math.pow(after.y - before.y, 2),
    );
    expect(
      distance,
      lessThan(4),
      reason: 'la pièce n a pas sauté au reciblage',
    );
  });
}
