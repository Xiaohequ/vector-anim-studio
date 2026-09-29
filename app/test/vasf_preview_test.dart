import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_anim_studio/engine/scene_painter.dart';
import 'package:vector_anim_studio/engine/simple_animation_format.dart';
import 'package:vector_anim_studio/models/animation.dart';

/// Aperçu headless OFFICIEL — rend un JSON vasf avec le VRAI moteur
/// (ScenePainter) et écrit une planche PNG + les frames pleine résolution.
///
/// À la demande : sans variable d'environnement (CI, flutter test normal),
/// ce test est un no-op. Usage depuis l'hôte :
///
///   cp tmp/petit_prince_planete.json vector_anim_studio/tmp/preview_input.json
///   VASF_PREVIEW_INPUT=/work/tmp/preview_input.json \
///   scripts/flutter_docker.sh test test/vasf_preview_test.dart
///
/// Les chemins sont des chemins CONTENEUR (/work = racine du projet
/// vector_anim_studio) — le JSON doit être copié sous ce dossier avant.
/// Variables : VASF_PREVIEW_INPUT (requis), VASF_PREVIEW_OUT (défaut
/// ../tmp/vasf_preview), VASF_PREVIEW_TIMES («0,2.67,8.17» en secondes,
/// défaut 5 instants équirépartis), VASF_PREVIEW_SCALE (défaut 0.28).
/// Sortie : planche.png + frame_t*.png pleine résolution. Si l'import
/// échoue, le test plante avec la liste française des erreurs — même
/// diagnostic que l'appli.
void main() {
  testWidgets('aperçu vasf : planche PNG du vrai moteur (à la demande)', (
    tester,
  ) async {
    final input = Platform.environment['VASF_PREVIEW_INPUT'] ?? '';
    if (input.isEmpty) {
      // Non demandé (CI) : no-op volontaire.
      return;
    }
    final outDir =
        Platform.environment['VASF_PREVIEW_OUT'] ?? '../tmp/vasf_preview';
    final scale =
        double.tryParse(Platform.environment['VASF_PREVIEW_SCALE'] ?? '') ??
        0.28;
    final timesRaw = Platform.environment['VASF_PREVIEW_TIMES'] ?? '';

    final text = File(input).readAsStringSync();
    final json = (jsonDecode(text) as Map).cast<String, Object?>();
    final project = SimpleAnimationFormat.fromJson(
      json,
      fallbackName: 'Aperçu vasf',
    );

    final durationMs = project.durationMs;
    final times = <int>[];
    if (timesRaw.trim().isNotEmpty) {
      for (final part in timesRaw.split(',')) {
        final seconds = double.tryParse(part.trim()) ?? 0;
        times.add((seconds * 1000).round());
      }
    } else if (durationMs <= 0) {
      times.add(0);
    } else {
      times.addAll([
        0,
        (durationMs * 0.25).round(),
        (durationMs * 0.5).round(),
        (durationMs * 0.75).round(),
        math.max(0, durationMs - 1),
      ]);
    }
    final instants = <int>[];
    for (final t in times) {
      final clamped = t < 0 ? 0 : (t > durationMs ? durationMs : t);
      if (!instants.contains(clamped)) instants.add(clamped);
    }
    instants.sort();
    Directory(outDir).createSync(recursive: true);

    final w = project.width.round();
    final h = project.height.round();
    final frames = <ui.Image>[];
    for (final timeMs in instants) {
      final image = _frame(project, timeMs);
      final bytes = await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.png),
      );
      final name = 'frame_t${(timeMs / 1000).toStringAsFixed(2)}';
      File('$outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      frames.add(image);
    }

    // Planche côte à côte (échelle réduite), sans texte (police de test).
    final cellW = (w * scale).round();
    final cellH = (h * scale).round();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Offset.zero &
          ui.Size(cellW.toDouble() * frames.length, cellH.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.medium;
    for (var i = 0; i < frames.length; i++) {
      canvas.save();
      canvas.translate((i * cellW).toDouble(), 0);
      canvas.scale(scale);
      canvas.drawImage(frames[i], ui.Offset.zero, paint);
      canvas.restore();
    }
    final sheet = recorder.endRecording().toImageSync(
      cellW * frames.length,
      cellH,
    );
    final sheetBytes = await tester.runAsync(
      () => sheet.toByteData(format: ui.ImageByteFormat.png),
    );
    File(
      '$outDir/planche.png',
    ).writeAsBytesSync(sheetBytes!.buffer.asUint8List());
    for (final image in frames) {
      image.dispose();
    }
    sheet.dispose();
    stderr.writeln(
      'Aperçu écrit : $outDir/planche.png '
      '+ ${instants.length} frames '
      '(${[for (final t in instants) (t / 1000).toStringAsFixed(2)]})',
    );
  });
}

ui.Image _frame(AnimationProject project, int timeMs) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  ScenePainter(
    project: project,
    timeMs: timeMs,
  ).paint(canvas, ui.Size(project.width.toDouble(), project.height.toDouble()));
  return recorder.endRecording().toImageSync(
    project.width.round(),
    project.height.round(),
  );
}
