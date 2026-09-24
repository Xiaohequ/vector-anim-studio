import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_anim_studio/engine/timeline_zoom.dart';
import 'package:vector_anim_studio/models/animation.dart';
import 'package:vector_anim_studio/ui/timeline_view.dart';

/// Enregistreurs de callbacks pour les tests de la timeline.
class _Rec {
  int? seeked;
  final List<(String, int)> moved = <(String, int)>[];
  String? ended;
}

AnimationProject _project() {
  final project = AnimationProject.blank();
  final shape = VectorShape(name: 'A', startMs: 0, endMs: 1000);
  shape.layers.add(ShapeLayer(name: 'L', kind: ShapeKind.rect));
  shape.upsertKeyframe(500, shape.poseAt(500));
  project.shapes.add(shape);
  // Porteur de la durée dérivée du projet : fin du dernier segment (4 s).
  final carrier = VectorShape(name: 'Fond', startMs: 0, endMs: 4000);
  carrier.layers.add(ShapeLayer(name: 'Base', kind: ShapeKind.rect));
  project.shapes.add(carrier);
  return project;
}

Widget _host(AnimationProject project, TimelineZoomState zoom, _Rec rec) {
  return MaterialApp(
    home: Scaffold(
      body: TimelineView(
        project: project,
        timeMs: 0,
        zoom: zoom,
        selectedShapeId: null,
        onSelect: (_) {},
        onRangeChanged: (shape, start, end) {
          shape.startMs = start;
          shape.endMs = end;
        },
        onMoveChanged: (shape, target) {
          rec.moved.add((shape.id, target));
          shape.shiftBy(target - shape.startMs);
        },
        onMoveEnd: (shape) => rec.ended = shape.id,
        onSeek: (t) => rec.seeked = t,
        onDeleteKeyframe: (_, _) {},
        onZoomChanged: () {},
        onGestureStart: (shape) {},
      ),
    ),
  );
}

/// Largeur de mise en page des enfants positionnés du Stack de la timeline
/// (les barres y sont posées avec une width explicite).
List<double> _barWidths(WidgetTester tester) {
  final widths = <double>[];
  tester.renderObject<RenderStack>(find.byType(Stack).first).visitChildren((
    child,
  ) {
    final width = (child.parentData as StackParentData?)?.width;
    if (width != null) widths.add(width);
  });
  return widths;
}

void main() {
  testWidgets('la largeur des barres = durée × pixels/ms (pas le contraire)', (
    tester,
  ) async {
    final project = _project();
    final rec = _Rec();
    await tester.pumpWidget(
      _host(project, TimelineZoomState(durationOf: () => 4000), rec),
    );

    // Vue 4000 ms sur 800 px : segment 0–1000 ms → 200 px (le bug v0.6.0
    // donnait durée × ms/px = 5000 px, une barre qui couvre tout l'écran).
    expect(_barWidths(tester), contains(200.0));

    // Zoom ×4 (vue 1000 ms) : le même segment occupe toute la largeur.
    final zoom = TimelineZoomState(durationOf: () => 4000)..zoomAt(4, 0.5);
    await tester.pumpWidget(_host(project, zoom, rec));
    expect(zoom.viewMs, 1000);
    expect(_barWidths(tester), contains(800.0));
  });

  testWidgets('un tap sur le fond déplace la tête de lecture', (tester) async {
    final project = _project();
    final rec = _Rec();
    await tester.pumpWidget(
      _host(project, TimelineZoomState(durationOf: () => 4000), rec),
    );

    // Hors de la barre (x > 200) : le tap tombe sur le fond → scrub.
    await tester.tapAt(const Offset(400, 30));
    expect(rec.seeked, 2000);
  });

  testWidgets('appui long + glisser déplace le segment, keyframes suivent', (
    tester,
  ) async {
    final project = _project();
    final shape = project.shapes.first;
    final rec = _Rec();
    await tester.pumpWidget(
      _host(project, TimelineZoomState(durationOf: () => 4000), rec),
    );

    // Appui long sur la barre (x < 200) puis glisser de 200 px :
    // ms/px = 4000/800 = 5 → décalage de 1000 ms.
    final gesture = await tester.startGesture(const Offset(100, 27));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(200, 0));
    await tester.pump();

    expect(rec.moved, contains((shape.id, 1000)));
    expect(shape.startMs, 1000);
    expect(shape.endMs, 2000);
    expect(shape.durationMs, 1000);
    expect(shape.keyframes.single.timeMs, 1500);

    await gesture.up();
    await tester.pump();
    expect(rec.ended, shape.id);
  });

  testWidgets('le pincement à deux doigts zoome la vue', (tester) async {
    final project = _project();
    final rec = _Rec();
    final zoom = TimelineZoomState(durationOf: () => 4000);
    await tester.pumpWidget(_host(project, zoom, rec));

    final g1 = await tester.startGesture(const Offset(100, 27));
    final g2 = await tester.startGesture(const Offset(300, 27));
    await tester.pump();
    // Écartement : 200 → 300 px → zoom ×1,5 → vue ≈ 2667 ms.
    await g1.moveBy(const Offset(-50, 0));
    await g2.moveBy(const Offset(50, 0));
    await tester.pump();

    expect(zoom.viewMs, lessThan(4000));
    expect(zoom.viewMs, closeTo(2667, 2));

    await g1.up();
    await g2.up();
    await tester.pump();
  });

  testWidgets('le glisser sur une barre scrub aussi la tête de lecture', (
    tester,
  ) async {
    final project = _project();
    final shape = project.shapes.first;
    final rec = _Rec();
    await tester.pumpWidget(
      _host(project, TimelineZoomState(durationOf: () => 4000), rec),
    );

    // Glisser au milieu de la barre (x = 100) : scrub, pas de déplacement.
    await tester.dragFrom(const Offset(100, 27), const Offset(120, 0));
    await tester.pump();

    expect(rec.seeked, isNotNull);
    expect(rec.seeked!, closeTo(1100, 20)); // ~220 px × 5 ms/px
    expect(rec.moved, isEmpty);
    expect(rec.ended, isNull);
    expect(shape.startMs, 0);
  });
}
