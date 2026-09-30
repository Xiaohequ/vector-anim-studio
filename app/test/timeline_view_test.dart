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
  String? selected;
}

AnimationProject _project() {
  final project = AnimationProject.blank();
  final shape = VectorShape(name: 'A');
  shape.layers.add(ShapeLayer(name: 'L', kind: ShapeKind.rect));
  shape.upsertKeyframe(500, shape.poseAt(500));
  project.shapes.add(shape);
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
        onSelect: (shape) => rec.selected = shape.id,
        onMoveChanged: (shape, target) {
          rec.moved.add((shape.id, target));
          shape.shiftBy(target - shape.spanStartMs);
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
List<double> _barWidths(WidgetTester tester) =>
    [for (final (_, width) in _barRects(tester)) width];

/// (offset.dx, largeur) des enfants positionnés du Stack de la timeline.
List<(double, double)> _barRects(WidgetTester tester) {
  final rects = <(double, double)>[];
  tester.renderObject<RenderStack>(find.byType(Stack).first).visitChildren((
    child,
  ) {
    final data = child.parentData as StackParentData?;
    if (data?.width != null) rects.add((data!.offset.dx, data.width!));
  });
  return rects;
}

void main() {
  testWidgets('le segment couvre la durée de rendu, même zoomé (v0.18.2)', (
    tester,
  ) async {
    final project = _project();
    final rec = _Rec();
    // Keyframes 500–1500 ms : sous v0.18.x la barre se repliait sur ce
    // span ; depuis v0.18.2 elle reste la durée de rendu [0, 4 s].
    project.shapes.first.upsertKeyframe(1500, project.shapes.first.poseAt(1500));
    await tester.pumpWidget(
      _host(project, TimelineZoomState(durationOf: () => 4000), rec),
    );

    // Vue 4000 ms sur 800 px : barre 800 px (PAS le span 200 px des
    // keyframes — le repli v0.18.x est corrigé ; le bug v0.6.0 d'unité
    // inversée reste exclu : durée × px/ms, pas ms/px).
    expect(_barWidths(tester), contains(800.0));

    // Zoom ×4 (vue 1000 ms, offset 1500 ms) : le segment couvre encore
    // tout le viewport (le clamp v0.18.0 avec ancre x0 = -1200 px rendait
    // la barre entièrement invisible).
    final zoom = TimelineZoomState(durationOf: () => 4000)..zoomAt(4, 0.5);
    await tester.pumpWidget(_host(project, zoom, rec));
    expect(zoom.viewMs, 1000);
    expect(_barWidths(tester), contains(800.0));
    for (final (dx, w) in _barRects(tester)) {
      if (w < 100) continue; // tête de lecture, barre hors vue…
      expect(dx, greaterThanOrEqualTo(0.0));
    }
  });

  testWidgets('ajouter une keyframe ne rétrécit pas le segment (v0.18.2)', (
    tester,
  ) async {
    final project = AnimationProject.blank();
    final statique = VectorShape(name: 'Statique');
    statique.layers.add(ShapeLayer(name: 'L', kind: ShapeKind.rect));
    project.shapes.add(statique);
    final rec = _Rec();
    final zoom = TimelineZoomState(durationOf: () => 4000);
    await tester.pumpWidget(_host(project, zoom, rec));
    expect(_barWidths(tester), contains(800.0));

    // Keyframe à 500 ms : la barre GARDE sa pleine durée (v0.18.1 la
    // repliait sur le span des keyframes → 24 px à x = 100).
    statique.upsertKeyframe(500, statique.poseAt(500));
    await tester.pumpWidget(_host(project, zoom, rec));
    expect(_barWidths(tester), contains(800.0));
    expect(statique.spanStartMs, 500);
  });

  testWidgets('un tap sur la règle scrubbe ; un tap sur la barre sélectionne', (
    tester,
  ) async {
    final project = _project();
    final rec = _Rec();
    await tester.pumpWidget(
      _host(project, TimelineZoomState(durationOf: () => 4000), rec),
    );

    // La barre pleine durée couvre la ligne : le scrub au tap passe par
    // la RÈGLE (IgnorePointer, v0.18.2).
    await tester.tapAt(const Offset(400, 10));
    expect(rec.seeked, 2000);

    // Un tap sur la barre sélectionne la forme (et ne scrubbe pas).
    await tester.tapAt(const Offset(400, 30));
    expect(rec.selected, project.shapes.first.id);
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

    // Appui long sur la barre pleine durée (x = 112 tombe dessus) puis
    // glisser de 200 px : ms/px = 4000/800 = 5 → cible = origine (500)
    // + 1000 = 1500. La barre reste pleine durée, les keyframes bougent.
    final gesture = await tester.startGesture(const Offset(112, 27));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(200, 0));
    await tester.pump();

    expect(rec.moved, contains((shape.id, 1500)));
    expect(shape.spanStartMs, 1500);
    expect(shape.keyframes.single.timeMs, 1500);

    await gesture.up();
    await tester.pump();
    expect(rec.ended, shape.id);
  });

  testWidgets('une forme sans keyframe a un segment pleine durée (v0.18.1)',
    (tester) async {
    final project = AnimationProject.blank();
    final statique = VectorShape(name: 'Statique');
    statique.layers.add(ShapeLayer(name: 'L', kind: ShapeKind.rect));
    project.shapes.add(statique);
    final rec = _Rec();
    await tester.pumpWidget(
      _host(project, TimelineZoomState(durationOf: () => 4000), rec),
    );

    // Durée de rendu par défaut : [0, 4 s] → barre pleine vue (800 px).
    expect(_barWidths(tester), contains(800.0));

    // Appui long : rien à décaler sans keyframe → aucun callback de move
    // (pas d'undo fantôme), mais le tap sélectionne toujours.
    final g = await tester.startGesture(const Offset(112, 27));
    await tester.pump(const Duration(milliseconds: 600));
    await g.moveBy(const Offset(200, 0));
    await tester.pump();
    await g.up();
    await tester.pump();
    expect(rec.moved, isEmpty);
    expect(rec.ended, isNull);
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

    // Glisser sur la barre pleine durée (ancre x = 0) : scrub en espace
    // vue, pas de déplacement. x final 232 px × 5 ms/px = 1160.
    await tester.dragFrom(const Offset(112, 27), const Offset(120, 0));
    await tester.pump();

    expect(rec.seeked, isNotNull);
    expect(rec.seeked!, closeTo(1160, 20));
    expect(rec.moved, isEmpty);
    expect(rec.ended, isNull);
    expect(shape.spanStartMs, 500);
  });
}
