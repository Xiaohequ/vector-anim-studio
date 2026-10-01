import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_anim_studio/engine/scene_painter.dart';
import 'package:vector_anim_studio/models/animation.dart';
import 'package:vector_anim_studio/ui/bone_editor_screen.dart';

/// v0.20 — éditeur d'os : la SEULE forme sélectionnée, centrée et ancrée au
/// milieu de l'écran ; dessin en 2 taps (① articulation ② extrémité),
/// déplacement de l'os SANS déplacer la forme, conversion en coordonnées
/// projet à la validation.

AnimationProject _project() {
  final project = AnimationProject.blank(
    name: 'Film',
    type: ProjectType.skeleton,
  );
  project.width = 720;
  project.height = 1280;
  final shape = VectorShape(name: 'Bloc', x: 360, y: 640);
  shape.layers.add(
    ShapeLayer(name: 'L', kind: ShapeKind.rect, width: 400, height: 300),
  );
  project.shapes.add(shape);
  return project;
}

/// Lance l'éditeur depuis un bouton et renvoie le résultat par [onResult].
class _Launcher extends StatelessWidget {
  const _Launcher({
    required this.project,
    required this.shape,
    required this.onResult,
  });

  final AnimationProject project;
  final VectorShape shape;
  final void Function(BoneEditorResult result) onResult;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: const Key('open'),
          onPressed: () async {
            final result = await Navigator.of(context).push<BoneEditorResult>(
              MaterialPageRoute(
                builder: (context) =>
                    BoneEditorScreen(project: project, shape: shape),
              ),
            );
            if (result != null) onResult(result);
          },
          child: const Text('open'),
        ),
      ),
    );
  }
}

void main() {
  Finder canvas() => find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is ScenePainter,
  );

  /// Ouvre l'éditeur et renvoie le centre du canvas (= centre de la forme,
  /// l'éditeur recentrant la pièce au milieu de l'écran).
  Future<Offset> openEditor(
    WidgetTester tester,
    AnimationProject project,
    void Function(BoneEditorResult result) onResult,
  ) async {
    final shape = project.shapes.single;
    await tester.pumpWidget(
      MaterialApp(
        home: _Launcher(project: project, shape: shape, onResult: onResult),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Os de « Bloc »'), findsOneWidget);
    return tester.getCenter(canvas());
  }

  testWidgets('dessin en 2 taps → 1 os, articulation au centre de la forme', (
    tester,
  ) async {
    final project = _project();
    BoneEditorResult? captured;
    final center = await openEditor(
      tester,
      project,
      (result) => captured = result,
    );

    await tester.tapAt(center);
    await tester.pump();
    await tester.tapAt(center + const Offset(70, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Enregistrer l’os'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.bones, hasLength(1));
    final bone = captured!.bones.single;
    // Repère projet : le centre de l'écran = centre de la forme (360, 640).
    expect(bone.offsetX, closeTo(360, 2));
    expect(bone.offsetY, closeTo(640, 2));
    expect(bone.length, greaterThan(0));
    expect(captured!.carrierBoneId, bone.id);
    expect(captured!.replacedIds, isEmpty);
  });

  testWidgets('chaîne : tap sur le poignet → os 2 attaché à l’os 1', (
    tester,
  ) async {
    final project = _project();
    BoneEditorResult? captured;
    final center = await openEditor(
      tester,
      project,
      (result) => captured = result,
    );

    // Os 1 : articulation au centre, extrémité à droite.
    await tester.tapAt(center);
    await tester.pump();
    await tester.tapAt(center + const Offset(70, 0));
    await tester.pumpAndSettle();

    // Os 2 : on repart DU POIGNET de l'os 1 (aimantation) → chaîne.
    await tester.tapAt(center + const Offset(70, 0));
    await tester.pump();
    await tester.tapAt(center + const Offset(70, 60));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Enregistrer l’os'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.bones, hasLength(2));
    expect(captured!.bones[1].parentId, captured!.bones[0].id);
    // Porteur = la racine (os 1).
    expect(captured!.carrierBoneId, captured!.bones[0].id);
    // L'os 2 démarre pile sur le POIGNET de l'os 1 — offsets d'enfant
    // exprimés dans le repère du parent (longueur le long de l'os 1).
    expect(captured!.bones[1].offsetX, closeTo(captured!.bones[0].length, 2));
    expect(captured!.bones[1].offsetY, closeTo(0, 2));
  });

  testWidgets('glisser un os le déplace SANS déplacer la forme', (
    tester,
  ) async {
    final project = _project();
    final shape = project.shapes.single;
    BoneEditorResult? captured;
    final center = await openEditor(
      tester,
      project,
      (result) => captured = result,
    );

    await tester.tapAt(center);
    await tester.pump();
    await tester.tapAt(center + const Offset(70, 0));
    await tester.pumpAndSettle();

    // Glisser au MILIEU du segment : l'os bouge (delta scène via geo).
    // 1ᵉʳ move = slop du recognizer (le foyer de onScaleStart est déjà
    // déplacé) → les moves suivants sont ceux qui déplacent réellement.
    final grip = center + const Offset(35, 0);
    final gesture = await tester.startGesture(grip);
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(50, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(5, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Enregistrer l’os'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    final bone = captured!.bones.single;
    expect(
      bone.offsetX,
      greaterThan(360),
      reason: 'l’os a suivi le doigt (repère projet)',
    );
    expect(bone.offsetY, closeTo(640, 2), reason: 'déplacement horizontal');
    // La FORME n'a jamais bougé (ancre au milieu de l'écran = copie locale).
    expect(shape.x, 360);
    expect(shape.y, 640);
    expect(shape.keyframes, isEmpty);
  });

  testWidgets('sans os dessiné, l’enregistrement est désactivé', (
    tester,
  ) async {
    final project = _project();
    BoneEditorResult? captured;
    await openEditor(tester, project, (result) => captured = result);
    // Piège harnais : `find.byTooltip` renvoie le RawTooltip, pas
    // l'IconButton → viser l'icône (cf. find.widgetWithIcon).
    final save = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.check),
    );
    expect(save.onPressed, isNull);
    expect(captured, isNull);
  });

  testWidgets('aucun sélecteur de forme dans l’éditeur d’os', (tester) async {
    final project = _project();
    await openEditor(tester, project, (result) {});
    final paint = tester.widget<CustomPaint>(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is ScenePainter,
      ),
    );
    final painter = paint.painter! as ScenePainter;
    expect(
      painter.selectedShapeId,
      isNull,
      reason: 'pas de pièce sélectionnée',
    );
    expect(painter.showFrame, isFalse, reason: 'pas de cadre de sélection');
  });

  testWidgets('pivot : glisser l’EXTRÉMITÉ tourne l’os, l’articulation fixe', (
    tester,
  ) async {
    final project = _project();
    final shape = project.shapes.single;
    BoneEditorResult? captured;
    final center = await openEditor(
      tester,
      project,
      (result) => captured = result,
    );

    // Os horizontal : articulation au centre, extrémité à droite.
    await tester.tapAt(center);
    await tester.pump();
    await tester.tapAt(center + const Offset(70, 0));
    await tester.pumpAndSettle();

    // Glisser l'EXTRÉMITÉ vers le bas (le 1ᵉʳ move avale la slop).
    final tip = center + const Offset(70, 0);
    final gesture = await tester.startGesture(tip);
    await tester.pump();
    await gesture.moveBy(const Offset(0, 45));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Enregistrer l’os'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    final bone = captured!.bones.single;
    expect(
      bone.restAngle,
      greaterThan(0.1),
      reason: 'l’os a pivote autour de son articulation (y vers le bas)',
    );
    expect(bone.offsetX, closeTo(360, 2), reason: 'articulation fixe (x)');
    expect(bone.offsetY, closeTo(640, 2), reason: 'articulation fixe (y)');
    // La forme n'a pas bougé (ancre au milieu de l'écran).
    expect(shape.x, 360);
    expect(shape.y, 640);
  });
}
