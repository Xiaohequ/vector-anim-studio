import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_anim_studio/engine/scene_painter.dart';
import 'package:vector_anim_studio/models/animation.dart';

/// v0.39.0 — transformation STATIQUE d'un groupe d'éléments : décalage,
/// rotation et échelle d'axe autour du centre visuel du groupe. Sonde pixel :
/// on mesure le centroïde du contenu rendu avant/après la transformation.

/// Projet 720×1280 (rendu 360×640, échelle 0,5) avec un groupe de deux
/// carrés symétriques autour de (360, 640) : leur centre visuel est le centre
/// du canvas, ce qui rend les mesures lisibles.
AnimationProject _groupProject({bool grouped = true}) {
  final project = AnimationProject.blank(name: 'Groupes');
  project.width = 720;
  project.height = 1280;
  final group = ShapeGroup(name: 'Paire');
  if (grouped) project.groups.add(group);
  for (final dx in <double>[-120, 120]) {
    final shape = VectorShape(
      name: 'Carre $dx',
      x: 360 + dx,
      y: 640,
      groupId: grouped ? group.id : null,
    );
    shape.layers.add(
      ShapeLayer(
        name: 'Rect',
        kind: ShapeKind.rect,
        width: 120,
        height: 120,
        colorValue: 0xFFFF5C5C,
      ),
    );
    project.shapes.add(shape);
  }
  return project;
}

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
  expect(count, greaterThan(400), reason: 'les carrés sont rendus');
  return (x: sumX / count, y: sumY / count, count: count);
}

void main() {
  test('groupCenter = moyenne des positions de repos des fils', () {
    final project = _groupProject();
    final center = project.groupCenter(project.groups.single.id);
    expect(center, isNotNull);
    expect(center!.dx, closeTo(360, 1e-9));
    expect(center.dy, closeTo(640, 1e-9));
  });

  test('groupCenter est null pour un groupe sans fils', () {
    final project = AnimationProject.blank(name: 'Vide');
    final group = ShapeGroup(name: 'Orphelin');
    project.groups.add(group);
    expect(project.groupCenter(group.id), isNull);
  });

  testWidgets('décalage du groupe déplace ses formes', (tester) async {
    final project = _groupProject();
    final before = _centroid(await _render(tester, project, 0), 360, 640);
    // +100 unités scène = +50 px au rendu (échelle 0,5). Amplitude modérée :
    // un décalage plus grand pousserait le carré droit hors du canvas et le
    // rognage fausserait le centroïde mesuré.
    project.groups.single.offsetX = 100;
    final after = _centroid(await _render(tester, project, 0), 360, 640);
    expect(after.x - before.x, closeTo(50, 2), reason: 'décalage X appliqué');
    expect(after.y, closeTo(before.y, 2), reason: 'Y inchangé');
  });

  testWidgets('rotation du groupe tourne autour de son centre', (tester) async {
    final project = _groupProject();
    final before = _centroid(await _render(tester, project, 0), 360, 640);
    // 90° : les deux carrés, alignés horizontalement, passent à la verticale.
    project.groups.single.rotation = math.pi / 2;
    final after = _centroid(await _render(tester, project, 0), 360, 640);
    // Le centre visuel ne bouge pas (rotation autour de lui).
    expect(after.x, closeTo(before.x, 2), reason: 'centre X stable');
    expect(after.y, closeTo(before.y, 2), reason: 'centre Y stable');
    // La boîte englobante devient verticale : hauteur > largeur.
    final box = _bbox(await _render(tester, project, 0), 360, 640);
    expect(box.height, greaterThan(box.width), reason: 'paire verticale');
  });

  testWidgets('échelle du groupe agrandit autour du centre', (tester) async {
    final project = _groupProject();
    final before = _bbox(await _render(tester, project, 0), 360, 640);
    project.groups.single.scaleX = 2;
    final after = _bbox(await _render(tester, project, 0), 360, 640);
    expect(
      after.width,
      greaterThan(before.width * 1.5),
      reason: 'largeur doublée environ',
    );
    expect(after.height, closeTo(before.height, 2), reason: 'hauteur intacte');
  });

  testWidgets('groupe neutre : rendu identique à une forme non groupée', (
    tester,
  ) async {
    final grouped = _groupProject();
    final free = _groupProject(grouped: false);
    final a = _centroid(await _render(tester, grouped, 0), 360, 640);
    final b = _centroid(await _render(tester, free, 0), 360, 640);
    expect(a.x, closeTo(b.x, 0.5));
    expect(a.y, closeTo(b.y, 0.5));
    expect(a.count, b.count);
  });

  testWidgets('groupe masqué : aucune forme rendue', (tester) async {
    final project = _groupProject();
    project.groups.single.visible = false;
    final pixels = await _render(tester, project, 0);
    var count = 0;
    for (var i = 0; i < pixels.length; i += 4) {
      final r = pixels[i];
      final g = pixels[i + 1];
      final b = pixels[i + 2];
      if ((r - 0xFF).abs() < 30 && (g - 0x5C).abs() < 30 && b < 120) count++;
    }
    expect(count, 0, reason: 'groupe masqué → rien de rendu');
  });
}

({double width, double height}) _bbox(Uint8List pixels, int w, int h) {
  var minX = w.toDouble();
  var maxX = 0.0;
  var minY = h.toDouble();
  var maxY = 0.0;
  var count = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      final r = pixels[i];
      final g = pixels[i + 1];
      final b = pixels[i + 2];
      if ((r - 0xFF).abs() < 30 && (g - 0x5C).abs() < 30 && b < 120) {
        count++;
        if (x < minX) minX = x.toDouble();
        if (x > maxX) maxX = x.toDouble();
        if (y < minY) minY = y.toDouble();
        if (y > maxY) maxY = y.toDouble();
      }
    }
  }
  expect(count, greaterThan(400), reason: 'contenu rendu');
  return (width: maxX - minX, height: maxY - minY);
}
