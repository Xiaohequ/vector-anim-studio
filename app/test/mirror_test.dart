import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vector_anim_studio/data/project_repository.dart';
import 'package:vector_anim_studio/engine/scene_painter.dart';
import 'package:vector_anim_studio/engine/selection_geometry.dart';
import 'package:vector_anim_studio/engine/simple_animation_format.dart';
import 'package:vector_anim_studio/engine/timeline_controller.dart';
import 'package:vector_anim_studio/models/animation.dart';
import 'package:vector_anim_studio/ui/shape_properties_sheet.dart';

/// v0.19.0 — miroir d'une forme (groupe de couches). Trois faces :
/// le modèle (négations + flags), la persistance (DB + vasf v4) et le rendu
/// (sonde pixel : le contenu dessiné est bien reflété, la forme reste en
/// place, les keyframes ne bougent pas).

/// Projet 720×1280 avec UN groupe décentré : blob en path, contenu à droite
/// et en bas de sa boîte (points stockés dans le repère boîte [0..w]/[0..h],
/// dessinés centrés : contenu = point − (w/2, h/2)).
AnimationProject _blobProject({bool morph = false, bool bottom = false}) {
  final project = AnimationProject.blank(name: 'Film');
  // Projet 720×1280 (rendu à 360×640, échelle 0,5) : la forme au centre.
  project.width = 720;
  project.height = 1280;
  final shape = VectorShape(name: 'Groupe', x: 360, y: 640);
  final layer = ShapeLayer(
    name: 'Blob',
    kind: ShapeKind.path,
    width: 300,
    height: 300,
    colorValue: 0xFFFF5C5C,
    points: bottom
        ? <Offset>[
            // Contenu y ∈ [30, 140] — nettement en bas de la boîte.
            const Offset(60, 280),
            const Offset(120, 290),
            const Offset(100, 180),
            const Offset(55, 230),
          ]
        : <Offset>[
            // Contenu x ∈ [40, 120], y ∈ [−40, 80] — droite de la boîte.
            const Offset(220, 210),
            const Offset(270, 230),
            const Offset(260, 110),
            const Offset(190, 170),
          ],
  );
  shape.layers.add(layer);
  if (morph) {
    // Pose de morph à 1 s : le nuage glisse à droite (+200 en x).
    shape.setKeyframes(<ShapeKeyframe>[
      ShapeKeyframe(
        timeMs: 0,
        layerPoints: <String, List<Offset>>{
          layer.id: List<Offset>.from(layer.points),
        },
      ),
      ShapeKeyframe(
        timeMs: 1000,
        layerPoints: <String, List<Offset>>{
          layer.id: <Offset>[
            const Offset(420, 210),
            const Offset(470, 230),
            const Offset(460, 110),
            const Offset(390, 170),
          ],
        },
      ),
    ]);
  }
  project.shapes.add(shape);
  return project;
}

/// Rend headless avec le VRAI ScenePainter (harnais render_regression).
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

/// Centroid du masque rouge (#FF5C5C sur fond sombre #14161C).
({double x, double y, int count}) _centroid(Uint8List pixels, int w, int h) {
  var count = 0;
  var sumX = 0.0;
  var sumY = 0.0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      final r = pixels[i];
      final g = pixels[i + 1];
      final b = pixels[i + 2];
      if ((r - 0xFF).abs() < 30 && (g - 0x5C).abs() < 30 && b < 120) {
        count++;
        sumX += x;
        sumY += y;
      }
    }
  }
  expect(count, greaterThan(400), reason: 'le blob est rendu');
  return (x: sumX / count, y: sumY / count, count: count);
}

void main() {
  // ------------------------------------------------------------- modèle
  test('miroir H : x et rotation négées, flipH posé — double appel = identité',
      () {
    final shape = VectorShape(name: 'Groupe');
    final layer = ShapeLayer(
      name: 'Flèche',
      kind: ShapeKind.arrow,
      x: 20,
      y: 8,
      rotation: 0.4,
    );
    shape.layers.add(layer);
    shape.mirror(horizontal: true);
    expect(layer.x, -20);
    expect(layer.y, 8);
    expect(layer.rotation, closeTo(-0.4, 1e-9));
    expect(layer.flipH, isTrue);
    expect(layer.flipV, isFalse);
    // Le flip est auto-inverse : deux pressions reviennent à l'original.
    shape.mirror(horizontal: true);
    expect(layer.x, 20);
    expect(layer.rotation, closeTo(0.4, 1e-9));
    expect(layer.flipH, isFalse);
  });

  test('miroir V : y et rotation négées, flipV posé', () {
    final shape = VectorShape(name: 'Groupe');
    final layer = ShapeLayer(
      name: 'Blob',
      kind: ShapeKind.rect,
      x: 6,
      y: 30,
      rotation: 0.7,
    );
    shape.layers.add(layer);
    shape.mirror(horizontal: false); // miroir V = axe horizontal
    expect(layer.y, -30);
    expect(layer.x, 6);
    expect(layer.rotation, closeTo(-0.7, 1e-9));
    expect(layer.flipV, isTrue);
    expect(layer.flipH, isFalse);
  });

  test('miroir : les keyframes de la forme (poses, couleurs, morph) restent '
      'intactes', () {
    final shape = VectorShape(name: 'Groupe', rotation: 0.3);
    shape.layers.add(ShapeLayer(name: 'Blob', kind: ShapeKind.rect));
    final pose = shape.poseAt(0);
    shape.setKeyframes(<ShapeKeyframe>[
      ShapeKeyframe(
        timeMs: 0,
        values: Map<AnimatableProperty, double>.from(pose),
        layerColors: {shape.layers.first.id: 0xFFFF5C5C},
        layerPoints: {
          shape.layers.first.id: const <Offset>[
            Offset(0, 0),
            Offset(30, 10),
          ],
        },
      ),
      ShapeKeyframe(
        timeMs: 500,
        values: {
          ...pose,
          AnimatableProperty.rotation: 1.2,
          AnimatableProperty.x: 300,
        },
      ),
    ]);
    final snapshot = shape.keyframes.map((k) => k.toJson()).toList();
    shape.mirror(horizontal: true);
    shape.mirror(horizontal: false); // miroir V
    expect(shape.keyframes.map((k) => k.toJson()).toList(), snapshot);
  });

  // ------------------------------------------------------- géométrie
  test('poignées de points : le flip reflète le contenu dessiné', () {
    // Espace = pose = données (scale 1, décalages nuls).
    const geo = SceneGeometry(scale: 1, dx: 0, dy: 0);
    final shape = VectorShape(name: 'Forme', x: 0, y: 0);
    final layer = ShapeLayer(
      name: 'P',
      kind: ShapeKind.path,
      width: 100,
      height: 100,
      points: const <Offset>[Offset(80, 50), Offset(120, 50)],
    );
    shape.layers.add(layer);
    final pose = SelectionGeometry.layerPose(shape, layer, 0);
    // Sans flip : contenu = point − (50, 50) → (30, 0) puis (70, 0).
    final plain = SelectionGeometry.pointHandlePositions(
      layer.points,
      layer,
      pose,
      geo,
    );
    expect(plain[0].dx, closeTo(30, 1e-6));
    expect(plain[0].dy, closeTo(0, 1e-6));
    expect(plain[1].dx, closeTo(70, 1e-6));
    // flipH : le contenu se reflète autour de l'origine de la couche.
    layer.flipH = true;
    final flipped = SelectionGeometry.pointHandlePositions(
      layer.points,
      layer,
      pose,
      geo,
    );
    expect(flipped[0].dx, closeTo(-30, 1e-6));
    expect(flipped[0].dy, closeTo(0, 1e-6));
    expect(flipped[1].dx, closeTo(-70, 1e-6));
  });

  // --------------------------------------------------- persistance (DB)
  test('le flip survit à la base (round-trip save/load)', () async {
    sqfliteFfiInit();
    final tmp = Directory.systemTemp.createTempSync('mirror_test_db');
    final repository = ProjectRepository(
      factory: databaseFactoryFfi,
      databasePath: p.join(tmp.path, 't.db'),
    );
    try {
      final project = AnimationProject.blank(name: 'Miroir');
      final shape = VectorShape(name: 'Groupe', x: 100, y: 200);
      final layer = ShapeLayer(
        name: 'Flèche',
        kind: ShapeKind.arrow,
        rotation: 0.5,
      );
      shape.layers.add(layer);
      shape.mirror(horizontal: true);
      shape.mirror(horizontal: false); // miroir V — rotation : deux négations → 0.5
      project.shapes.add(shape);
      await repository.save(project);
      final loaded = await repository.load(project.id);
      final loadedLayer = loaded.shapes.first.layers.first;
      expect(loadedLayer.flipH, isTrue);
      expect(loadedLayer.flipV, isTrue);
      expect(loadedLayer.rotation, closeTo(0.5, 1e-9));
    } finally {
      await repository.close();
      tmp.deleteSync(recursive: true);
    }
  });

  // -------------------------------------------------- persistance (vasf)
  test('vasf : flip à plat exporté en version 4 et réimporté', () {
    final project = AnimationProject.blank(name: 'Vasf flip');
    final shape = VectorShape(name: 'Flèche');
    shape.layers.add(ShapeLayer(name: 'Trait', kind: ShapeKind.arrow));
    shape.mirror(horizontal: true);
    project.shapes.add(shape);
    final json = SimpleAnimationFormat.toJson(project);
    expect(json['version'], SimpleAnimationFormat.version4);
    final flat = (json['shapes'] as List<Object?>).first
        as Map<String, Object?>;
    expect(flat['flipH'], isTrue);
    final imported = SimpleAnimationFormat.fromJson(json);
    expect(imported.shapes.first.layers.first.flipH, isTrue);
    expect(imported.shapes.first.layers.first.flipV, isFalse);
  });

  test('vasf : flip porté par couche en layers[]', () {
    final project = AnimationProject.blank(name: 'Groupe vasf');
    final shape = VectorShape(name: 'Groupe');
    shape.layers.add(ShapeLayer(name: 'A', kind: ShapeKind.arrow)..flipH = true);
    shape.layers.add(ShapeLayer(name: 'B', kind: ShapeKind.rect));
    project.shapes.add(shape);
    final json = SimpleAnimationFormat.toJson(project);
    expect(json['version'], SimpleAnimationFormat.version4);
    final imported = SimpleAnimationFormat.fromJson(json).shapes.first.layers;
    expect(imported[0].flipH, isTrue);
    expect(imported[1].flipH, isFalse);
  });

  test('vasf : version 5 refusée (message à jour)', () {
    try {
      SimpleAnimationFormat.fromJson(<String, Object?>{
        'version': 5,
        'shapes': <Object?>[],
      });
      fail('SimpleFormatException attendu');
    } on SimpleFormatException catch (error) {
      expect(error.toString(), contains('1, 2, 3 ou 4'));
    }
  });

  // ------------------------------------------------------- rendu (pixels)
  testWidgets('sonde : miroir H reflète le blob autour du centre de la forme',
      (tester) async {
    final project = _blobProject();
    final before = _centroid(await _render(tester, project, 0), 360, 640);
    expect(before.x, greaterThan(210), reason: 'blob à droite du centre');
    project.shapes.first.mirror(horizontal: true);
    final after = _centroid(await _render(tester, project, 0), 360, 640);
    expect(after.x, lessThan(150), reason: 'blob passé à gauche');
    // Réflexion exacte autour du centre du canvas (180) — la forme reste
    // en place, seule la géométrie se reflète.
    expect((before.x - 180) + (after.x - 180), closeTo(0, 3));
    expect((before.y - after.y).abs(), lessThan(3));
    expect(after.count, closeTo(before.count, before.count * 0.05));
  });

  testWidgets('sonde : miroir V reflète verticalement, x intact', (
    tester,
  ) async {
    final project = _blobProject(bottom: true);
    final before = _centroid(await _render(tester, project, 0), 360, 640);
    expect(before.y, greaterThan(335), reason: 'blob en bas');
    project.shapes.first.mirror(horizontal: false); // miroir V
    final after = _centroid(await _render(tester, project, 0), 360, 640);
    expect(after.y, lessThan(305), reason: 'blob passé en haut');
    expect((before.y - 320) + (after.y - 320), closeTo(0, 3));
    expect((before.x - after.x).abs(), lessThan(3));
  });

  testWidgets('sonde : le morph passe à travers le flip (nuage reflété)', (
    tester,
  ) async {
    final project = _blobProject(morph: true);
    // À 1 s le nuage de morph est PLUS à droite que la base.
    final before = _centroid(await _render(tester, project, 1000), 360, 640);
    expect(before.x, greaterThan(290), reason: 'nuage morphé à droite');
    project.shapes.first.mirror(horizontal: true);
    final after = _centroid(await _render(tester, project, 1000), 360, 640);
    expect(after.x, lessThan(70), reason: 'nuage morphé reflété à gauche');
    expect((before.x - 180) + (after.x - 180), closeTo(0, 3));
  });

  // ------------------------------------------------------------ UI sheet
  testWidgets('sheet : les boutons Miroir H/V appellent le callback', (
    tester,
  ) async {
    final project = AnimationProject.blank(name: 'Projet');
    final shape = VectorShape(name: 'Groupe');
    shape.layers.add(ShapeLayer(name: 'Flèche', kind: ShapeKind.arrow));
    project.shapes.add(shape);
    final calls = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShapePropertiesSheet(
            project: project,
            shape: shape,
            controller: TimelineController(project),
            onPropertyChanged: (_, _) {},
            onToggleKeyframe: () async {},
            onKeyframeEasing: (_) async {},
            onEditLayers: () {},
            onMirror: (h) => calls.add(h),
          ),
        ),
      ),
    );
    // La ligne miroir est juste sous le titre : visible sans défiler.
    await tester.tap(find.text('Miroir H'));
    await tester.pump();
    await tester.tap(find.text('Miroir V'));
    await tester.pump();
    expect(calls, <bool>[true, false]);
  });
}
