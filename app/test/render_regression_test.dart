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
  String? selectedBoneId,
  Map<String, AnimationProject> embeddedProjects = const {},
}) async {
  late ui.Image image;
  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    ScenePainter(
      project: project,
      timeMs: timeMs,
      selectedBoneId: selectedBoneId,
      embeddedProjects: embeddedProjects,
    ).paint(canvas, ui.Size(w.toDouble(), h.toDouble()));
    image = await recorder.endRecording().toImage(w, h);
  });
  final data = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  expect(data, isNotNull);
  return data!.buffer.asUint8List();
}

int _countMatching(Uint8List pixels, bool Function(int r, int g, int b) match) {
  var count = 0;
  for (var i = 0; i < pixels.length; i += 4) {
    if (match(pixels[i], pixels[i + 1], pixels[i + 2])) count++;
  }
  return count;
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
  testWidgets(
    'groupe squelette lié : déplacer un os enfant entraîne le groupe entier',
    (tester) async {
      final sourceRig = _rig();
      final source = _project(rig: sourceRig);
      final sourcePiece = VectorShape(name: 'Corps', x: 200, y: 700);
      sourcePiece.layers.add(
        ShapeLayer(
          name: 'Corps rouge',
          kind: ShapeKind.rect,
          width: 90,
          height: 90,
          colorValue: 0xFFFF5C5C,
        ),
      );
      source.shapes.add(sourcePiece);
      sourceRig.bindShape(sourcePiece.id, sourceRig.bones.first.id);

      final hostRig = SkeletonRig();
      final root = RigBone(name: 'Porteur', offsetX: 360, offsetY: 640, length: 100);
      final child = RigBone(
        name: 'Os ajouté',
        parentId: root.id,
        offsetX: 100,
        offsetY: 0,
        length: 80,
      );
      hostRig.bones.addAll(<RigBone>[root, child]);
      hostRig.tracks[child.id] = <BoneKeyframe>[
        BoneKeyframe(timeMs: 0),
        BoneKeyframe(timeMs: 1000, tx: 35),
      ];
      final host = _project(rig: hostRig);
      final group = VectorShape(
        name: 'Groupe',
        embeddedProjectId: source.id,
        embeddedWidth: source.width,
        embeddedHeight: source.height,
        embeddedIsSkeleton: true,
        x: 360,
        y: 640,
        startMs: 0,
        endMs: 2000,
      );
      host.shapes.add(group);
      hostRig.bindShape(group.id, root.id);

      Future<({double x, double y, int count})> centroidAt(
        int timeMs,
        String? selectedBoneId,
      ) async => _centroid(
        await _render(
          tester,
          host,
          timeMs,
          selectedBoneId: selectedBoneId,
          embeddedProjects: <String, AnimationProject>{source.id: source},
        ),
        360,
        640,
        (r, g, b) =>
            (r - 0xFF).abs() < 30 &&
            (g - 0x5C).abs() < 30 &&
            (b - 0x5C).abs() < 30,
      );

      final defaultCarrier = await centroidAt(1000, null);
      final animatedChild = await centroidAt(1000, child.id);
      expect((animatedChild.x - defaultCarrier.x).abs(), greaterThan(8));
      expect((animatedChild.y - defaultCarrier.y).abs(), lessThan(3));
    },
  );

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

  testWidgets(
    'projet squelette : la pièce respecte le rectangle de la timeline',
    (tester) async {
      final rig = SkeletonRig();
      final bone = RigBone(
        name: 'Porteur',
        offsetX: 200,
        offsetY: 850,
        restAngle: -math.pi / 2,
        length: 40,
      );
      rig.addBone(bone);
      // Cette keyframe dépasse volontairement la fin du segment de la pièce.
      rig.upsertKeyframe(bone.id, 2000, math.pi / 8);

      final project = _project(rig: rig);
      final shape = VectorShape(
        name: 'Pièce temporaire',
        x: 200,
        y: 700,
        startMs: 0,
        endMs: 1000,
      );
      shape.layers.add(
        ShapeLayer(
          name: 'Corps',
          kind: ShapeKind.rect,
          width: 120,
          height: 120,
          colorValue: 0xFFFF5C5C,
        ),
      );
      project.shapes.add(shape);
      rig.bindShape(shape.id, bone.id);

      bool red(int r, int g, int b) =>
          (r - 0xFF).abs() < 30 &&
          (g - 0x5C).abs() < 30 &&
          (b - 0x5C).abs() < 30;
      final inside = await _render(tester, project, 500);
      final outside = await _render(tester, project, 1500);

      expect(
        _countMatching(inside, red),
        greaterThan(400),
        reason: 'la pièce est visible quand le playhead est sur le segment',
      );
      expect(
        _countMatching(outside, red),
        0,
        reason:
            'une keyframe d’os après la fin ne doit pas prolonger la visibilité',
      );
    },
  );

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

  testWidgets('couleur animée : interpolation mesurée entre deux poses', (
    tester,
  ) async {
    final project = AnimationProject.blank(name: 'Ciel');
    final shape = VectorShape(name: 'Aplat', x: 360, y: 640);
    shape.layers.add(
      ShapeLayer(
        name: 'Ciel',
        kind: ShapeKind.rect,
        width: 720,
        height: 1280,
        colorValue: 0xFF5B8DEF,
      ),
    );
    project.shapes.add(shape);
    // Pose à t=0 sans couleur (retombe sur la base bleue), pose rouge à 2 s.
    shape.upsertKeyframe(0, shape.poseAt(0), easing: EasingKind.linear);
    shape.upsertKeyframe(
      2000,
      shape.poseAt(2000),
      easing: EasingKind.linear,
      layerColors: {shape.layers.first.id: 0xFFFF5C5C},
    );
    project.fps = 25;

    // À mi-course (linéaire) : couleur mélangée ≈ (0xAD, 0x74, 0xA5).
    final pixels = await _render(tester, project, 1000);
    int countWhere(bool Function(int r, int g, int b) match) {
      var count = 0;
      for (var i = 0; i < pixels.length; i += 4) {
        if (match(pixels[i], pixels[i + 1], pixels[i + 2])) count++;
      }
      return count;
    }

    final blendCount = countWhere(
      (r, g, b) =>
          (r - 0xAD).abs() < 30 &&
          (g - 0x74).abs() < 30 &&
          (b - 0xA5).abs() < 30,
    );
    final blueCount = countWhere(
      (r, g, b) =>
          (r - 0x5B).abs() < 25 &&
          (g - 0x8D).abs() < 25 &&
          (b - 0xEF).abs() < 25,
    );
    expect(
      blendCount,
      greaterThan(400),
      reason: 'la couleur mélangée est rendue',
    );
    expect(blueCount, 0, reason: 'le bleu pur a bien disparu à mi-course');
  });

  testWidgets('morph de points : le path suit les poses (centroid mesuré)', (
    tester,
  ) async {
    // Grand cadre : le nuage glisse de +200 unités SANS sortir du cadre
    // (échelle de vue 1 : rendu 800×400 d'un projet 800×400).
    final project = AnimationProject(width: 800, height: 400, fps: 25);
    final shape = VectorShape(name: 'Flamme', x: 200, y: 200);
    final layer = ShapeLayer(
      name: 'Langue',
      kind: ShapeKind.path,
      width: 200,
      height: 200,
      colorValue: 0xFFFF5C5C,
    );
    layer.points.addAll(const <Offset>[
      Offset(60, 60),
      Offset(140, 60),
      Offset(100, 160),
    ]);
    shape.layers.add(layer);
    project.shapes.add(shape);
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
          Offset(260, 60),
          Offset(340, 60),
          Offset(300, 160),
        ],
      },
    );
    project.fps = 25;

    final start = _centroid(
      await _render(tester, project, 0, w: 800, h: 400),
      800,
      400,
      (r, g, b) =>
          (r - 0xFF).abs() < 30 &&
          (g - 0x5C).abs() < 30 &&
          (b - 0x5C).abs() < 30,
    );
    final end = _centroid(
      await _render(tester, project, 2000, w: 800, h: 400),
      800,
      400,
      (r, g, b) =>
          (r - 0xFF).abs() < 30 &&
          (g - 0x5C).abs() < 30 &&
          (b - 0x5C).abs() < 30,
    );
    // Le nuage a glissé de +200 unités stockées → +200 px écran (échelle 1).
    expect(end.x - start.x, closeTo(200, 8), reason: 'le morph a été appliqué');
    // Garde anti-faux-positif : à mi-course, le centroid est à mi-chemin.
    final mid = _centroid(
      await _render(tester, project, 1000, w: 800, h: 400),
      800,
      400,
      (r, g, b) =>
          (r - 0xFF).abs() < 30 &&
          (g - 0x5C).abs() < 30 &&
          (b - 0x5C).abs() < 30,
    );
    expect(mid.x - start.x, closeTo(100, 8));
  });
}
