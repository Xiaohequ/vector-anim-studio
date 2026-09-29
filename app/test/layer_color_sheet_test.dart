import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_anim_studio/engine/timeline_controller.dart';
import 'package:vector_anim_studio/models/animation.dart';
import 'package:vector_anim_studio/ui/palette.dart';
import 'package:vector_anim_studio/ui/shape_properties_sheet.dart';

/// v0.15 : lignes « Couleurs des couches » dans la sheet de propriétés —
/// palette + losange d'auto-key (pose/retire l'entrée de couleur au curseur).
void main() {
  Future<
    ({VectorShape shape, List<(String, int)> colors, List<String> toggles})
  >
  pumpSheet(WidgetTester tester, {bool withKeyframes = false}) async {
    final project = AnimationProject.blank(name: 'Film');
    final shape = VectorShape(name: 'Fleur');
    shape.layers.add(ShapeLayer(name: 'Pétale', kind: ShapeKind.rect));
    shape.layers.add(ShapeLayer(name: 'Cœur', kind: ShapeKind.circle));
    project.shapes.add(shape);
    if (withKeyframes) {
      shape.upsertKeyframe(0, shape.poseAt(0));
      shape.upsertKeyframe(2000, shape.poseAt(2000));
    }
    final colors = <(String, int)>[];
    final toggles = <String>[];
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
            onLayerColorChanged: (layer, color) =>
                colors.add((layer.name, color)),
            onToggleLayerColor: (layer) => toggles.add(layer.name),
          ),
        ),
      ),
    );
    return (shape: shape, colors: colors, toggles: toggles);
  }

  testWidgets('les couches ont chacune leur ligne couleur', (tester) async {
    await pumpSheet(tester);
    await tester.scrollUntilVisible(
      find.text('Couleurs des couches'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Couleurs des couches'), findsOneWidget);
    expect(find.text('Pétale'), findsOneWidget);
    expect(find.text('Cœur'), findsOneWidget);
  });

  testWidgets('un choix de palette appelle onLayerColorChanged', (
    tester,
  ) async {
    final state = await pumpSheet(tester);
    // Ligne « Cœur » : la première pastille = première couleur de la palette.
    final heartRow = find.widgetWithText(Row, 'Cœur').first;
    final swatch = find
        .descendant(of: heartRow, matching: find.byType(GestureDetector))
        .first;
    await tester.scrollUntilVisible(
      find.text('Cœur'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(swatch);
    await tester.pumpAndSettle();
    expect(state.colors, hasLength(1));
    expect(state.colors.single.$1, 'Cœur');
    expect(state.colors.single.$2, kColorPalette.first);
    expect(state.colors.where((c) => c.$1 == 'Pétale'), isEmpty);
  });

  testWidgets('le losange de couleur appelle onToggleLayerColor', (
    tester,
  ) async {
    final state = await pumpSheet(tester, withKeyframes: true);
    await tester.scrollUntilVisible(
      find.text('Pétale'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    // Le losange de la ligne « Pétale » : dans la Row de cette couche (les
    // indicateurs des sliders montent aussi des losanges — viser la ligne).
    final row = find.widgetWithText(Row, 'Pétale').first;
    final diamond = find
        .descendant(of: row, matching: find.byIcon(Icons.diamond_outlined))
        .first;
    await tester.tap(diamond, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(state.toggles, ['Pétale']);
  });
}
