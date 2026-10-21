import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_anim_studio/engine/scene_painter.dart';
import 'package:vector_anim_studio/engine/simple_animation_format.dart';
import 'package:vector_anim_studio/models/animation.dart';

/// Régression v0.13.1 : le VRAI fichier d'exemple vasf-2 G2 doit importer le
/// pivot de la porte (bord gauche) ET le rendu doit tourner autour de ce
/// bord — mesuré par centroid du masque bleu (bug v0.13.0 : un pivot placé
/// dans layers[] était ignoré en silence et la porte tournait au centre).
void main() {
  testWidgets('exemple G2 : pivot de la porte au bord gauche (rendu mesuré)', (
    tester,
  ) async {
    final raw = File('test/fixtures/vasf-2-g2-example.json').readAsStringSync();
    final project = SimpleAnimationFormat.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
      fallbackName: 'exemple',
    );
    expect(project.type, ProjectType.skeleton);
    final porte = project.shapes.firstWhere((s) => s.name == 'Porte');
    expect(porte.pivotDx, -120);
    expect(porte.pivotDy, 0);

    // Rendu à t=1,7 s (rotation 68° atteinte) sur un canvas 360×640
    // (scène 720×1280 → échelle 0,5, aucun décalage de centrage).
    late ui.Image image;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      ScenePainter(
        project: project,
        timeMs: 1700,
      ).paint(canvas, const ui.Size(360, 640));
      image = await recorder.endRecording().toImage(360, 640);
    });
    final data = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    expect(data, isNotNull);
    final pixels = data!.buffer.asUint8List();

    // Masque bleu de la porte (#5B8DEF) + centroid.
    var count = 0;
    var sumX = 0.0;
    var sumY = 0.0;
    for (var y = 0; y < 640; y++) {
      for (var x = 0; x < 360; x++) {
        final i = (y * 360 + x) * 4;
        if ((pixels[i] - 0x5B).abs() < 30 &&
            (pixels[i + 1] - 0x8D).abs() < 30 &&
            (pixels[i + 2] - 0xEF).abs() < 30) {
          count++;
          sumX += x;
          sumY += y;
        }
      }
    }
    expect(count, greaterThan(1000), reason: 'la porte bleue est rendue');
    // Prédiction pivot bord gauche : gond scène (440, 860), centroid
    // scène ≈ (484.9, 971.3) → canvas ≈ (242.5, 485.7). Une rotation
    // autour du CENTRE (pivot perdu) donnerait ≈ (280, 430).
    final cx = sumX / count;
    final cy = sumY / count;
    expect(cx, closeTo(242.5, 20), reason: 'centroid x bleu = $cx');
    expect(cy, closeTo(485.7, 20), reason: 'centroid y bleu = $cy');
    expect(
      math.sqrt(math.pow(cx - 280, 2) + math.pow(cy - 430, 2)),
      greaterThan(30),
      reason: 'la porte ne tourne PAS autour du centre',
    );
  });
}
