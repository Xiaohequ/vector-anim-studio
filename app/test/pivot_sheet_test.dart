import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_anim_studio/engine/timeline_controller.dart';
import 'package:vector_anim_studio/models/animation.dart';
import 'package:vector_anim_studio/ui/shape_properties_sheet.dart';

/// v0.13.1 : les sliders Pivot X/Y doivent être visibles aussi pour les
/// pièces d'un projet SQUELETTE (l'exemple vasf-2 G2 en est un — en v0.13.0
/// le garde `!skeletonPiece` les cachait, le pivot était introuvable).
void main() {
  VectorShape shapeIn(AnimationProject project) {
    final shape = VectorShape(name: 'Porte');
    shape.layers.add(ShapeLayer(name: 'Panneau', kind: ShapeKind.rect));
    project.shapes.add(shape);
    return shape;
  }

  Future<void> pumpSheet(
    WidgetTester tester, {
    required bool skeletonPiece,
    required void Function(double dx, double dy) onPivotChanged,
    double pivotDx = 0,
  }) async {
    final project = AnimationProject.blank(
      name: 'Film',
      type: skeletonPiece ? ProjectType.skeleton : ProjectType.vector,
    );
    final shape = shapeIn(project);
    shape.pivotDx = pivotDx;
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
            onPivotChanged: onPivotChanged,
            skeletonPiece: skeletonPiece,
          ),
        ),
      ),
    );
  }

  testWidgets('projet SQUELETTE : les sliders Pivot X/Y sont affichés', (
    tester,
  ) async {
    final captured = <(double, double)>[];
    await pumpSheet(
      tester,
      skeletonPiece: true,
      onPivotChanged: (dx, dy) => captured.add((dx, dy)),
      pivotDx: -120, // valeur importée de l'exemple G2 (porte)
    );
    // Les lignes pivot sont sous le pli de la sheet → défiler jusqu'à elles.
    await tester.scrollUntilVisible(
      find.text('Pivot Y'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Pivot de rotation (offset depuis le centre)'),
      findsOneWidget,
    );
    expect(find.text('Pivot X'), findsOneWidget);
    expect(find.text('Pivot Y'), findsOneWidget);
    // La valeur importée (-120) est affichée sur la ligne Pivot X.
    expect(find.text('-120'), findsOneWidget);

    // Glisser le DERNIER slider (Pivot Y) : le callback reçoit (dx=-120, dy>0).
    await tester.drag(find.byType(Slider).last, const Offset(40, 0));
    await tester.pumpAndSettle();
    expect(captured, isNotEmpty);
    expect(captured.last.$1, -120);
    expect(captured.last.$2, greaterThan(10));
  });

  testWidgets('projet VECTORIEL : les sliders Pivot X/Y restent affichés', (
    tester,
  ) async {
    await pumpSheet(tester, skeletonPiece: false, onPivotChanged: (dx, dy) {});
    await tester.scrollUntilVisible(
      find.text('Pivot X'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Pivot de rotation (offset depuis le centre)'),
      findsOneWidget,
    );
    expect(find.text('Pivot X'), findsOneWidget);
    expect(find.text('Pivot Y'), findsOneWidget);
  });
}
