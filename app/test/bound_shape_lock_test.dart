import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_anim_studio/engine/timeline_controller.dart';
import 'package:vector_anim_studio/models/animation.dart';
import 'package:vector_anim_studio/models/skeleton.dart';
import 'package:vector_anim_studio/ui/shape_properties_sheet.dart';

/// v0.19.1 — une forme PORTÉE par un os ne se déplace plus : seul l'os la
/// transporte, ou une dissociation (Squelettes ▸ Délier la pièce).
///
/// Trois faces : le modèle (détection de l'os porteur), la sheet ⚙
/// (sliders de translation/rotation/échelle verrouillés + avertissement)
/// et le geste canvas (couvert par `widget_test.dart` — blocage des gestes
/// + pièce non sélectionnable au doigt + témoin non lié).

/// Projet squelette 720×1280 avec une seule pièce ; [bind] lie la forme
/// entière à l'os, [bindLayer] lie sa première couche à la place.
({AnimationProject project, VectorShape shape, RigBone bone, SkeletonRig rig})
pieceProject({bool bind = false, bool bindLayer = false}) {
  final project = AnimationProject.blank(
    name: 'Film',
    type: ProjectType.skeleton,
  );
  project.width = 720;
  project.height = 1280;
  final shape = VectorShape(name: 'Bloc', x: 360, y: 640);
  shape.layers.add(
    ShapeLayer(name: 'L', kind: ShapeKind.rect, width: 200, height: 120),
  );
  project.shapes.add(shape);
  final rig = SkeletonRig();
  final bone = RigBone(name: 'Tronc', offsetX: 360, offsetY: 460, length: 80);
  rig.addBone(bone);
  if (bind) rig.bindShape(shape.id, bone.id);
  if (bindLayer) rig.bindLayer(shape.id, shape.layers.first.id, bone.id);
  project.skeleton = rig;
  return (project: project, shape: shape, bone: bone, rig: rig);
}

Future<void> pumpSheet(
  WidgetTester tester, {
  required AnimationProject project,
  required VectorShape shape,
  required SkeletonRig? rig,
}) async {
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
          skeletonRig: rig,
          skeletonPiece: rig != null,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('SkeletonRig.carrierBoneId / isAttached', () {
    test('liaison de la forme entière', () {
      final rig = SkeletonRig();
      final bone = RigBone(
        name: 'Tronc',
        offsetX: 100,
        offsetY: 100,
        length: 60,
      );
      rig.addBone(bone);
      expect(rig.isAttached('s1'), isFalse);
      expect(rig.carrierBoneId('s1'), isNull);
      rig.bindShape('s1', bone.id);
      expect(rig.isAttached('s1'), isTrue);
      expect(rig.carrierBoneId('s1'), bone.id);
      expect(rig.isAttached('s2'), isFalse);
      expect(rig.isAttached(null), isFalse);
    });

    test('liaison d’une couche compte aussi (la pièce bouge avec)', () {
      final rig = SkeletonRig();
      final bone = RigBone(
        name: 'Bras',
        offsetX: 100,
        offsetY: 100,
        length: 60,
      );
      rig.addBone(bone);
      rig.bindLayer('s1', 'l1', bone.id);
      expect(rig.isAttached('s1'), isTrue);
      expect(rig.carrierBoneId('s1'), bone.id);
      expect(rig.isAttached('s2'), isFalse);
    });

    test('les deux liaisons coexistent : la forme entière prime', () {
      final rig = SkeletonRig();
      final a = RigBone(name: 'A', offsetX: 0, offsetY: 0, length: 50);
      final b = RigBone(name: 'B', offsetX: 50, offsetY: 0, length: 50);
      rig.addBone(a);
      rig.addBone(b);
      rig.bindShape('s1', a.id);
      rig.bindLayer('s1', 'l1', b.id);
      expect(
        rig.bindings.where((binding) => binding.shapeId == 's1'),
        hasLength(2),
      );
      expect(
        rig.carrierBoneId('s1'),
        a.id,
        reason: 'la liaison de la forme entière prime',
      );
      // Délier la pièce dissocie TOUT (forme + couches) : plus de porteur.
      rig.unbindShape('s1');
      expect(rig.bindings.where((binding) => binding.shapeId == 's1'), isEmpty);
      expect(rig.isAttached('s1'), isFalse);
      expect(rig.carrierBoneId('s1'), isNull);
      // Inversement, lier la forme purge les liaisons de couche antérieures.
      rig.bindLayer('s1', 'l1', b.id);
      rig.bindShape('s1', a.id);
      expect(
        rig.bindings.where((binding) => binding.shapeId == 's1'),
        hasLength(1),
      );
      expect(rig.carrierBoneId('s1'), a.id);
    });
  });

  group('sheet ⚙ — translation verrouillée', () {
    testWidgets('forme liée : sliders X/Y désactivés + avertissement', (
      tester,
    ) async {
      final f = pieceProject(bind: true);
      await pumpSheet(tester, project: f.project, shape: f.shape, rig: f.rig);

      final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
      expect(sliders.length, greaterThanOrEqualTo(5));
      expect(sliders[0].onChanged, isNull, reason: 'X verrouillé');
      expect(sliders[1].onChanged, isNull, reason: 'Y verrouillé');
      expect(sliders[2].onChanged, isNull, reason: 'rotation verrouillée');
      expect(sliders[3].onChanged, isNull, reason: 'échelle verrouillée');
      expect(sliders[4].onChanged, isNull, reason: 'échelle X verrouillée');
      if (sliders.length > 5) {
        expect(sliders[5].onChanged, isNull, reason: 'échelle Y verrouillée');
      }

      expect(find.textContaining('transformations bloquées'), findsOneWidget);
      expect(find.textContaining('Tronc'), findsOneWidget);

      // Les lignes basses sont hors de la vue (ListView paresseux sous la
      // hauteur max) : défiler jusqu'à Opacité pour vérifier qu'elle reste
      // libre — seule la transformation est verrouillée.
      await tester.scrollUntilVisible(
        find.text('Opacité'),
        40,
        scrollable: find.descendant(
          of: find.byType(ShapePropertiesSheet),
          matching: find.byType(Scrollable),
        ),
      );
      final all = tester.widgetList<Slider>(find.byType(Slider)).toList();
      expect(all, isNotEmpty);
      expect(all.last.onChanged, isNotNull, reason: 'opacité libre');
    });

    testWidgets('forme liée par sa COUCHE : même verrou', (tester) async {
      final f = pieceProject(bindLayer: true);
      await pumpSheet(tester, project: f.project, shape: f.shape, rig: f.rig);
      final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
      expect(sliders[0].onChanged, isNull);
      expect(sliders[1].onChanged, isNull);
      expect(sliders[2].onChanged, isNull, reason: 'rotation verrouillée');
      expect(sliders[3].onChanged, isNull, reason: 'échelle verrouillée');
      expect(find.textContaining('transformations bloquées'), findsOneWidget);
    });

    testWidgets('forme non liée : sliders actifs, aucun avertissement', (
      tester,
    ) async {
      final f = pieceProject();
      await pumpSheet(tester, project: f.project, shape: f.shape, rig: f.rig);
      final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
      expect(sliders.length, greaterThanOrEqualTo(4));
      expect(sliders[0].onChanged, isNotNull);
      expect(sliders[1].onChanged, isNotNull);
      expect(sliders[2].onChanged, isNotNull);
      expect(sliders[3].onChanged, isNotNull);
      expect(find.textContaining('transformations bloquées'), findsNothing);
    });

    testWidgets('onPropertyChanged n’est JAMAIS appelé sur X/Y verrouillés', (
      tester,
    ) async {
      final f = pieceProject(bind: true);
      final project = f.project;
      final shape = f.shape;
      final rig = f.rig;
      final calls = <(AnimatableProperty, double)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShapePropertiesSheet(
              project: project,
              shape: shape,
              controller: TimelineController(project),
              onPropertyChanged: (property, value) =>
                  calls.add((property, value)),
              onToggleKeyframe: () async {},
              onKeyframeEasing: (_) async {},
              onEditLayers: () {},
              skeletonRig: rig,
              skeletonPiece: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Un Slider verrouillé n'appelle pas onChanged (onChanged == null) :
      // le modèle ne peut pas bouger même si quelque chose le déclenche.
      for (final slider in tester.widgetList<Slider>(find.byType(Slider))) {
        if (slider.onChanged != null) slider.onChanged!(slider.value + 1);
      }
      expect(calls.map((c) => c.$1), isNot(contains(AnimatableProperty.x)));
      expect(calls.map((c) => c.$1), isNot(contains(AnimatableProperty.y)));
      expect(shape.x, 360);
      expect(shape.y, 640);
    });
  });
}
