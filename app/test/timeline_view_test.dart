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

Widget _host(AnimationProject project, TimelineZoomState zoom, _Rec rec) {
  return MaterialApp(
    home: Scaffold(
      body: TimelineView(
        project: project,
        timeMs: 0,
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
        onDeleteKeyframe: (_, _) {},
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
  tester.renderObject<RenderStack>(find.byType(Stack).first).visitChildren((
    child,
  ) {
    final width = (child.parentData as StackParentData?)?.width;
    if (width != null) widths.add(width);
  });
  return widths;
}

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

    expect(find.text('Groupe tête'), findsOneWidget);
    expect(find.text('Œil'), findsNothing);
    expect(find.text('Bouche'), findsNothing);
    await tester.tap(find.byTooltip('Déplier le groupe'));
    await tester.pumpWidget(_host(project, zoom, rec));

    expect(find.text('Œil'), findsOneWidget);
    expect(find.text('Bouche'), findsOneWidget);
    expect(find.text('Fond'), findsOneWidget);
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

    // Deux losanges (keyframes de l’os), jamais celui du groupe (1000 ms).
    final boneDiamonds = find.byWidgetPredicate(
      (widget) =>
          widget is Container && widget.color == const Color(0xFFF2C94C),
    );
    expect(boneDiamonds, findsNWidgets(2));
    expect(
      tester.widget<Container>(boneDiamonds.at(0)).color,
      const Color(0xFFF2C94C),
    );

    await tester.tap(find.text('Groupe importé'));
    await tester.pump();
    expect(rec.selectedBone, bone.id);
    expect(rec.selectedShape, isNull);

    expect(group.keyframes, hasLength(1));
  });
}
