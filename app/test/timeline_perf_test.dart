import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_anim_studio/engine/timeline_zoom.dart';
import 'package:vector_anim_studio/models/animation.dart';
import 'package:vector_anim_studio/ui/timeline_view.dart';

/// Garde-fou de performance de la timeline.
///
/// Le défilement reconstruit la timeline à chaque frame : le coût d'une frame
/// est proportionnel au nombre de WIDGETS construits, pas au nombre de
/// keyframes ni au nombre de pièces du projet. Ces tests vérifient donc la
/// structure, pas des durées (une mesure en millisecondes dans le harnais de
/// test, en debug et JIT, est trop bruitée pour servir de garde-fou).
AnimationProject _project({int shapes = 0, int keyframes = 0}) {
  final project = AnimationProject.blank();
  for (var i = 0; i < shapes; i++) {
    final shape = VectorShape(
      name: 'Pièce $i',
      startMs: i * 100,
      endMs: i * 100 + 3000,
    );
    shape.layers.add(ShapeLayer(name: 'L', kind: ShapeKind.rect));
    for (var k = 0; k < keyframes; k++) {
      final t = shape.startMs + (k * 3000 ~/ keyframes);
      shape.upsertKeyframe(t, shape.poseAt(t));
    }
    project.shapes.add(shape);
  }
  return project;
}

Widget _host(AnimationProject project, TimelineZoomState zoom) {
  return MaterialApp(
    home: Scaffold(
      body: TimelineView(
        project: project,
        timeMs: 0,
        zoom: zoom,
        selectedShapeId: null,
        onSelect: (_) {},
        onRangeChanged: (_, _, _) {},
        onMoveChanged: (_, _) {},
        onMoveEnd: (_) {},
        onSeek: (_) {},
        onDeleteKeyframe: (_, _) {},
        onZoomChanged: () {},
        onGestureStart: (_) {},
      ),
    ),
  );
}

int _widgetCount(WidgetTester tester) => tester.allWidgets.length;

void main() {
  testWidgets('le nombre de widgets ne dépend pas du nombre de keyframes', (
    tester,
  ) async {
    final few = _project(shapes: 10, keyframes: 2);
    final many = _project(shapes: 10, keyframes: 40);

    await tester.pumpWidget(
      _host(few, TimelineZoomState(durationOf: () => few.durationMs)),
    );
    final fewCount = _widgetCount(tester);

    await tester.pumpWidget(
      _host(many, TimelineZoomState(durationOf: () => many.durationMs)),
    );
    final manyCount = _widgetCount(tester);

    debugPrint(
      'PERF widgets : 2 keyframes/pièce = $fewCount, '
      '40 keyframes/pièce = $manyCount',
    );

    // 10 pièces × 38 keyframes de plus = 380 keyframes supplémentaires. Si
    // chacune construisait un widget, l'écart dépasserait 1000 widgets.
    expect(
      manyCount - fewCount,
      lessThan(50),
      reason:
          'les keyframes sont peintes, pas construites : le nombre de widgets '
          'ne doit pas suivre leur nombre',
    );
  });

  testWidgets('les segments hors de la vue ne sont pas construits', (
    tester,
  ) async {
    // 40 pièces qui se chevauchent : 40 lignes, toutes dans la vue au départ.
    final project = _project(shapes: 40);
    final zoom = TimelineZoomState(durationOf: () => project.durationMs);
    await tester.pumpWidget(_host(project, zoom));
    final allVisible = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .where((paint) => paint.painter is TimelineKeyframePainter)
        .length;

    // Zoom maximal sur le début du projet : la plupart des segments sortent
    // du cadre et ne doivent plus être construits.
    zoom.zoomAt(8, 0);
    await tester.pumpWidget(_host(project, zoom));
    final zoomed = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .where((paint) => paint.painter is TimelineKeyframePainter)
        .length;

    debugPrint('PERF segments construits : $allVisible → $zoomed après zoom');

    expect(allVisible, greaterThan(0));
    expect(
      zoomed,
      lessThan(allVisible),
      reason: 'le culling doit retirer les segments hors de la vue',
    );
  });
}
