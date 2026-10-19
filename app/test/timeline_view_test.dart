import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_anim_studio/engine/timeline_zoom.dart';
import 'package:vector_anim_studio/models/animation.dart';
import 'package:vector_anim_studio/models/skeleton.dart';
import 'package:vector_anim_studio/ui/timeline_view.dart';

/// Enregistreurs de callbacks pour les tests de la timeline.
class _Rec {
  int? seeked;
  final List<(String, int)> moved = <(String, int)>[];
  String? ended;
  String? selectedShape;
  String? selectedBone;
  String? selectedGroup;
  final List<int> deletedKeyframes = <int>[];
  final List<(String, int)> groupMoves = <(String, int)>[];
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

Widget _host(
  AnimationProject project,
  TimelineZoomState zoom,
  _Rec rec, {
  int timeMs = 0,
}) {
  return MaterialApp(
    home: Scaffold(
      body: TimelineView(
        project: project,
        timeMs: timeMs,
        zoom: zoom,
        selectedShapeId: null,
        skeletonRig: project.skeleton,
        onSelect: (shape) => rec.selectedShape = shape.id,
        onSelectBone: (bone) => rec.selectedBone = bone.id,
        onDeleteBoneKeyframe: (bone, time) {
          project.skeleton?.removeKeyframeAt(bone.id, time);
        },
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
        onDeleteKeyframe: (_, time) => rec.deletedKeyframes.add(time),
        onZoomChanged: () {},
        onGestureStart: (shape) {},
        onSelectGroup: (group) => rec.selectedGroup = group.id,
        onToggleGroupCollapsed: (group) => group.collapsed = !group.collapsed,
        onToggleGroupVisibility: (group) => group.visible = !group.visible,
        onGroupGestureStart: (group) {},
        onGroupMoveChanged: (group, delta) {
          rec.groupMoves.add((group.id, delta));
          for (final shape in project.shapes) {
            if (shape.groupId == group.id) shape.shiftBy(delta);
          }
        },
        onGroupMoveEnd: (group) => rec.ended = group.id,
      ),
    ),
  );
}

/// Largeur de mise en page des enfants positionnés du Stack de la timeline
/// (les barres y sont posées avec une width explicite).
List<double> _barWidths(WidgetTester tester) {
  final widths = <double>[];
  // Le Stack des lignes vit sous le SingleChildScrollView : le Stack racine
  // porte la règle collante et la tête de lecture.
  final lanesStack = find
      .descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Stack),
      )
      .first;
  tester.renderObject<RenderStack>(lanesStack).visitChildren((child) {
    final width = (child.parentData as StackParentData?)?.width;
    if (width != null) widths.add(width);
  });
  return widths;
}

/// Libellés des segments : les pièces sont peintes par [TimelineBarPainter],
/// les groupes restent des widgets `Text`.
List<String> _labels(WidgetTester tester) => <String>[
  ...tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((paint) => paint.painter)
      .whereType<TimelineBarPainter>()
      .map((painter) => painter.label),
  ...tester.widgetList<Text>(find.byType(Text)).map((text) => text.data ?? ''),
];

void main() {
  testWidgets('groupe replié affiche sa ligne et la déplie avec ses fils', (
    tester,
  ) async {
    final project = AnimationProject.blank(name: 'G');
    final group = ShapeGroup(name: 'Groupe tête', collapsed: true);
    project.groups.add(group);
    project.shapes.addAll(<VectorShape>[
      VectorShape(name: 'Œil', startMs: 0, endMs: 1000, groupId: group.id),
      VectorShape(name: 'Bouche', startMs: 500, endMs: 1500, groupId: group.id),
      VectorShape(name: 'Fond', startMs: 0, endMs: 4000),
    ]);
    final rec = _Rec();
    final zoom = TimelineZoomState(durationOf: () => 4000);
    await tester.pumpWidget(_host(project, zoom, rec));

    // Les noms sont PEINTS par le painter des barres, plus des widgets Text :
    // on lit les libellés dans les painters.
    expect(_labels(tester), contains('Groupe tête'));
    expect(_labels(tester), isNot(contains('Œil')));
    expect(_labels(tester), isNot(contains('Bouche')));
    await tester.tap(find.byTooltip('Déplier le groupe'));
    await tester.pumpWidget(_host(project, zoom, rec));

    expect(_labels(tester), contains('Œil'));
    expect(_labels(tester), contains('Bouche'));
    expect(_labels(tester), contains('Fond'));
    expect(find.byTooltip('Replier le groupe'), findsOneWidget);
  });

  testWidgets('visibilité groupe et sélection sont interactives', (
    tester,
  ) async {
    final project = AnimationProject.blank(name: 'G');
    final group = ShapeGroup(name: 'Groupe tête', collapsed: true);
    project.groups.add(group);
    project.shapes.add(
      VectorShape(name: 'Œil', startMs: 0, endMs: 1000, groupId: group.id),
    );
    project.shapes.add(VectorShape(name: 'Fond', startMs: 0, endMs: 4000));
    final rec = _Rec();
    final zoom = TimelineZoomState(durationOf: () => 4000);
    await tester.pumpWidget(_host(project, zoom, rec));

    await tester.tap(find.text('Groupe tête'));
    expect(rec.selectedGroup, group.id);
    await tester.tap(find.byTooltip('Masquer le groupe'));
    expect(group.visible, isFalse);
    await tester.pumpWidget(_host(project, zoom, rec));
    expect(find.byTooltip('Afficher le groupe'), findsOneWidget);
  });

  testWidgets('glisser la ligne groupe décale tous ses fils', (tester) async {
    final project = AnimationProject.blank(name: 'G');
    final group = ShapeGroup(name: 'Groupe tête', collapsed: true);
    project.groups.add(group);
    final a = VectorShape(
      name: 'A',
      startMs: 500,
      endMs: 1500,
      groupId: group.id,
    );
    final b = VectorShape(
      name: 'B',
      startMs: 1000,
      endMs: 2000,
      groupId: group.id,
    );
    project.shapes.addAll(<VectorShape>[a, b]);
    final carrier = VectorShape(name: 'Fond', startMs: 0, endMs: 4000);
    project.shapes.add(carrier);
    final rec = _Rec();
    await tester.pumpWidget(
      _host(project, TimelineZoomState(durationOf: () => 4000), rec),
    );

    final gesture = await tester.startGesture(const Offset(150, 27));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(200, 0));
    await tester.pump();

    expect(a.startMs, 1500);
    expect(a.endMs, 2500);
    expect(b.startMs, 2000);
    expect(b.endMs, 3000);
    expect(rec.groupMoves, isNotEmpty);
    expect(rec.groupMoves.fold<int>(0, (sum, move) => sum + move.$2), 1000);

    await gesture.up();
    await tester.pump();
    expect(rec.ended, group.id);
  });

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

    // Zoom ×4 (vue 1000 ms, centré sur 2000 ms) : le segment 0–4000 ms
    // mesurerait 3200 px. Il est DÉCOUPÉ à la vue (marge d'une demi-largeur
    // d'écran de chaque côté) : aucune barre construite ne dépasse 2 × la
    // largeur de l'écran, même quand le segment est immense.
    final zoom = TimelineZoomState(durationOf: () => 4000)..zoomAt(4, 0.5);
    await tester.pumpWidget(_host(project, zoom, rec));
    expect(zoom.viewMs, 1000);
    final widths = _barWidths(tester);
    expect(widths, isNotEmpty);
    expect(
      widths.every((w) => w <= 1600),
      isTrue,
      reason: 'les barres sont découpées à la vue : $widths',
    );
  });

  testWidgets(
    'la sélection des keyframes suit une tolérance de 10 px au zoom',
    (tester) async {
      final project = _project();
      final rec = _Rec();
      final zoom = TimelineZoomState(durationOf: () => 4000);
      // Le segment 0–1000 ms occupe 200 px à la vue 4000 ms : la keyframe de
      // 500 ms est à x = 100. Les lignes commencent SOUS la règle (20 px).
      const barCenterY =
          TimelineView.rulerHeight + 3 + (TimelineView.laneHeight - 8) / 2;

      for (final expectedViewMs in <int>[4000, 2000, 1000]) {
        expect(zoom.viewMs, expectedViewMs);
        final msPerPixel = zoom.msPerPixel(800);
        final insideTolerance = 500 + (9 * msPerPixel).round();
        final outsideTolerance = 500 + (11 * msPerPixel).round();
        // Position de la keyframe de 500 ms à CE zoom.
        final keyX = zoom.xFor(500, 800);

        // À 9 px de la keyframe, le tap la supprime (tolérance de 10 px).
        await tester.pumpWidget(
          _host(project, zoom, rec, timeMs: insideTolerance),
        );
        await tester.tapAt(Offset(keyX + 9, barCenterY));
        expect(rec.deletedKeyframes, contains(500));
        rec.deletedKeyframes.clear();

        // Juste au-delà de 10 px temporels, le tap rejoint la keyframe sans la
        // supprimer : la tolérance est bien convertie selon le zoom courant.
        await tester.pumpWidget(
          _host(project, zoom, rec, timeMs: outsideTolerance),
        );
        await tester.tapAt(Offset(keyX, barCenterY));
        expect(rec.deletedKeyframes, isEmpty);
        expect(rec.seeked, 500);
        rec.seeked = null;

        // 11 px à droite de la keyframe : plus aucune cible, le tap
        // sélectionne le segment au lieu de bouger la tête de lecture.
        await tester.tapAt(Offset(keyX + 11, barCenterY));
        expect(rec.seeked, isNull);

        if (expectedViewMs != 1000) {
          zoom.zoomAt(2, 0);
        }
      }
    },
  );

  testWidgets('la règle déplace la tête de lecture, le fond fait défiler', (
    tester,
  ) async {
    final project = _project();
    final rec = _Rec();
    // Vue 1000 ms centrée sur 2000 ms : il reste de la place pour défiler.
    final zoom = TimelineZoomState(durationOf: () => 4000)..zoomAt(4, 0.5);
    await tester.pumpWidget(_host(project, zoom, rec));

    // La règle (bande haute) est la SEULE zone de seek.
    await tester.tapAt(const Offset(400, 10));
    expect(rec.seeked, 2000);

    // Un glisser horizontal sur les lignes fait défiler la vue, sans seek.
    rec.seeked = null;
    final before = zoom.offsetMs;
    await tester.dragFrom(const Offset(600, 40), const Offset(-200, 0));
    await tester.pump();
    expect(rec.seeked, isNull);
    expect(zoom.offsetMs, greaterThan(before));
  });

  testWidgets('un glisser vertical défile les lignes, sans toucher au temps', (
    tester,
  ) async {
    // Beaucoup de lignes : la zone défilante a de la matière à faire défiler.
    final project = AnimationProject.blank();
    for (var i = 0; i < 20; i++) {
      final shape = VectorShape(name: 'P$i', startMs: 0, endMs: 1000);
      shape.layers.add(ShapeLayer(name: 'L', kind: ShapeKind.rect));
      project.shapes.add(shape);
    }
    final rec = _Rec();
    final zoom = TimelineZoomState(durationOf: () => 4000)..zoomAt(4, 0.5);
    await tester.pumpWidget(_host(project, zoom, rec));

    final beforeOffset = zoom.offsetMs;
    final scrollable = find.byType(SingleChildScrollView);
    final beforeScroll = tester
        .state<ScrollableState>(
          find.descendant(of: scrollable, matching: find.byType(Scrollable)),
        )
        .position
        .pixels;

    // Glisser vers le haut : les lignes montent, le temps ne bouge pas.
    await tester.dragFrom(const Offset(400, 200), const Offset(0, -120));
    await tester.pump();

    final afterScroll = tester
        .state<ScrollableState>(
          find.descendant(of: scrollable, matching: find.byType(Scrollable)),
        )
        .position
        .pixels;
    expect(afterScroll, greaterThan(beforeScroll));
    expect(zoom.offsetMs, beforeOffset);
    expect(rec.seeked, isNull);
  });

  testWidgets('un glisser horizontal ne fait pas défiler les lignes', (
    tester,
  ) async {
    final project = AnimationProject.blank();
    for (var i = 0; i < 20; i++) {
      final shape = VectorShape(name: 'P$i', startMs: 0, endMs: 1000);
      shape.layers.add(ShapeLayer(name: 'L', kind: ShapeKind.rect));
      project.shapes.add(shape);
    }
    final rec = _Rec();
    final zoom = TimelineZoomState(durationOf: () => 4000)..zoomAt(4, 0.5);
    await tester.pumpWidget(_host(project, zoom, rec));

    final scrollable = find.byType(SingleChildScrollView);
    final beforeScroll = tester
        .state<ScrollableState>(
          find.descendant(of: scrollable, matching: find.byType(Scrollable)),
        )
        .position
        .pixels;
    final beforeOffset = zoom.offsetMs;

    // Glisser franchement horizontal : la timeline défile, les lignes non.
    await tester.dragFrom(const Offset(600, 200), const Offset(-200, 0));
    await tester.pump();

    final afterScroll = tester
        .state<ScrollableState>(
          find.descendant(of: scrollable, matching: find.byType(Scrollable)),
        )
        .position
        .pixels;
    expect(afterScroll, beforeScroll);
    expect(zoom.offsetMs, greaterThan(beforeOffset));
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

  testWidgets(
    'le glisser sur une barre fait défiler, sans scrub ni déplacement',
    (tester) async {
      final project = _project();
      final shape = project.shapes.first;
      final rec = _Rec();
      // Vue 1000 ms centrée sur 2000 ms : la vue peut défiler.
      final zoom = TimelineZoomState(durationOf: () => 4000)..zoomAt(4, 0.5);
      await tester.pumpWidget(_host(project, zoom, rec));

      final before = zoom.offsetMs;
      // Glisser au milieu de la barre (x = 100) : défilement, pas de scrub.
      await tester.dragFrom(const Offset(100, 27), const Offset(-120, 0));
      await tester.pump();

      expect(rec.seeked, isNull);
      expect(zoom.offsetMs, greaterThan(before));
      expect(rec.moved, isEmpty);
      expect(rec.ended, isNull);
      expect(shape.startMs, 0);
    },
  );

  testWidgets('groupe squelette lié : segment = keyframes et sélection de l’os', (
    tester,
  ) async {
    final project = AnimationProject.blank(type: ProjectType.skeleton);
    final group = VectorShape(
      name: 'Groupe importé',
      embeddedProjectId: 'source',
      embeddedWidth: 360,
      embeddedHeight: 640,
      embeddedIsSkeleton: true,
      startMs: 0,
      endMs: 2000,
    );
    // Cette pose propre au groupe ne doit plus être représentée sur son segment.
    group.upsertKeyframe(1000, group.poseAt(1000));
    project.shapes.add(group);
    final rig = SkeletonRig();
    final bone = RigBone(name: 'Os groupe');
    rig.addBone(bone);
    rig.bindShape(group.id, bone.id);
    rig.tracks[bone.id] = <BoneKeyframe>[
      BoneKeyframe(timeMs: 500),
      BoneKeyframe(timeMs: 1500),
    ];
    project.skeleton = rig;
    final rec = _Rec();
    await tester.pumpWidget(
      _host(project, TimelineZoomState(durationOf: () => 4000), rec),
    );

    // Les keyframes de l’os sont celles du segment : taper à 500 ms et à
    // 1500 ms rejoint ces temps, alors qu’un tap à 1000 ms (la pose propre au
    // groupe) ne trouve aucune keyframe et sélectionne le segment.
    // Vue 4000 ms sur 800 px → 5 ms/px ; le segment 0–2000 ms fait 400 px.
    const barCenterY =
        TimelineView.rulerHeight + 3 + (TimelineView.laneHeight - 8) / 2;
    rec.seeked = null;
    await tester.tapAt(const Offset(100, barCenterY)); // 500 ms
    expect(rec.seeked, 500);
    rec.seeked = null;
    await tester.tapAt(const Offset(300, barCenterY)); // 1500 ms
    expect(rec.seeked, 1500);
    rec.seeked = null;
    rec.selectedBone = null;
    await tester.tapAt(const Offset(200, barCenterY)); // 1000 ms : pas de pose
    expect(rec.seeked, isNull);
    expect(rec.selectedBone, bone.id);

    // Le nom est peint : on tape le segment lui-même (au centre de la barre).
    rec.selectedBone = null;
    await tester.tapAt(const Offset(200, barCenterY));
    await tester.pump();
    expect(rec.selectedBone, bone.id);
    expect(rec.selectedShape, isNull);

    expect(group.keyframes, hasLength(1));
  });
}
