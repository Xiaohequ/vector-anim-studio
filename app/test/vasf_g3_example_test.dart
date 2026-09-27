import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_anim_studio/engine/scene_painter.dart';
import 'package:vector_anim_studio/engine/simple_animation_format.dart';
import 'package:vector_anim_studio/models/animation.dart';
import 'package:vector_anim_studio/models/skeleton.dart';

/// Régression v0.15 : le VRAI fichier d'exemple vasf-3 doit importer (1) la
/// couleur animée du ciel, (2) le morph de la flamme, (3) la chaîne 3 os avec
/// l'angle monde de chaque niveau honoré (bug v0.11 : le bookkeeping
/// `somme(parent) + angle` posait fausse le 3e niveau) et (4) la translation
/// d'os `move`.
void main() {
  testWidgets('exemple G3 : couleur, morph, chaîne 3 os, move (rendu mesuré)', (
    tester,
  ) async {
    final raw = File('../docs/vasf-3-example.json').readAsStringSync();
    final project = SimpleAnimationFormat.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
      fallbackName: 'exemple',
    );
    expect(project.type, ProjectType.skeleton);
    expect(project.shapes, hasLength(6));

    // ① Couleur animée du ciel : à t=1 s, entre #1B2A4A (t=0) et #7A3B2E
    // (t=2) en linéaire → (74.5, 50.5, 60).
    final ciel = project.shapes.firstWhere((s) => s.name == 'Ciel');
    final cielLayer = ciel.layers.first;
    expect(ciel.layerColorAnimated(cielLayer.id), isTrue);
    expect(
      ciel.colorAtLayer(cielLayer.id, 1000, 0),
      lerpArgb(0xFF1B2A4A, 0xFF7A3B2E, 0.5),
    );

    // ② Morph de la flamme : la langue glisse entre deux nuages de points.
    final flamme = project.shapes.firstWhere((s) => s.name == 'Flamme');
    final langue = flamme.layers.firstWhere((l) => l.name == 'Langue');
    expect(flamme.layerPointsAnimated(langue.id), isTrue);
    final mid = flamme.pointsAtLayer(langue.id, const [], 300);
    expect(mid[2].dy, lessThan(langue.points[2].dy), reason: 'la pointe monte');

    // ③ Chaîne 3 os : les joints/angles MONDE déclarés sont honorés au repos
    // (le bug v0.11 donnait poignet.jointRest = (559.7, 740.5) au lieu de
    // (620, 775)).
    final rig = project.skeleton!;
    expect(rig.bones, hasLength(3));
    final poignet = rig.bones.last;
    final restPose = SkeletonPose.evaluate(rig, 0);
    final frame = restPose.frameOf(poignet.id)!;
    expect(frame.jointRest.dx, closeTo(620, 1e-6));
    expect(frame.jointRest.dy, closeTo(775, 1e-6));
    expect(frame.worldAngleRest, closeTo(-math.pi / 3, 1e-6));

    // ④ Translation d'os : la chaîne suit RIGIDEMENT la translation de la
    // racine — on neutralise le move dans une copie du rig : la seule
    // différence de position = le move monde [0, −12] (les angles animés
    // étant identiques des deux côtés).
    final epaule = rig.bones.first;
    final at1 = SkeletonPose.evaluate(rig, 1000);
    expect(at1.frameOf(epaule.id)!.joint.dx, closeTo(560, 1e-6));
    expect(at1.frameOf(epaule.id)!.joint.dy, closeTo(888, 1e-6));
    final sansMove = SkeletonRig.fromJson(rig.toJson());
    for (final key in sansMove.trackOf(epaule.id)!) {
      key.tx = 0;
      key.ty = 0;
    }
    final avec = SkeletonPose.evaluate(rig, 1000).frameOf(poignet.id)!.joint;
    final sans = SkeletonPose.evaluate(
      sansMove,
      1000,
    ).frameOf(poignet.id)!.joint;
    expect((avec - sans).dx, closeTo(0, 1e-6));
    expect((avec - sans).dy, closeTo(-12, 1e-6));

    // Rendu t=1 s : le ciel est à mi-fondu (masque ≈ (74, 50, 60)) — le
    // bleu nuit pur doit avoir disparu.
    late ui.Image image;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      ScenePainter(
        project: project,
        timeMs: 1000,
      ).paint(canvas, const ui.Size(360, 640));
      image = await recorder.endRecording().toImage(360, 640);
    });
    final data = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    expect(data, isNotNull);
    final pixels = data!.buffer.asUint8List();
    var blend = 0;
    var nuit = 0;
    for (var i = 0; i < pixels.length; i += 4) {
      final r = pixels[i];
      final g = pixels[i + 1];
      final b = pixels[i + 2];
      if ((r - 74).abs() < 25 && (g - 50).abs() < 25 && (b - 60).abs() < 25) {
        blend++;
      } else if ((r - 27).abs() < 12 &&
          (g - 42).abs() < 12 &&
          (b - 74).abs() < 12) {
        nuit++;
      }
    }
    expect(blend, greaterThan(400), reason: 'le ciel fondu est rendu');
    expect(nuit, 0, reason: 'le bleu nuit pur a disparu à mi-course');
  });
}
