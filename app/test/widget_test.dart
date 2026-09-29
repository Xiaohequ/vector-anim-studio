import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vector_anim_studio/data/project_repository.dart';
import 'package:vector_anim_studio/engine/scene_painter.dart';
import 'package:vector_anim_studio/engine/selection_geometry.dart';
import 'package:vector_anim_studio/main.dart';
import 'package:vector_anim_studio/models/animation.dart';
import 'package:vector_anim_studio/models/skeleton.dart';
import 'package:vector_anim_studio/ui/shape_properties_sheet.dart';
import 'package:vector_anim_studio/ui/studio_screen.dart';
import 'package:vector_anim_studio/ui/timeline_view.dart';

/// Dépôt en mémoire pour les tests de widgets.
///
/// `sqflite_common_ffi` ne progresse pas dans la zone fake-async de
/// `testWidgets` (même avec `databaseFactoryFfiNoIsolate` et `runAsync`) : la
/// requête reste en vol, l'écran reste sur son `CircularProgressIndicator` et
/// `pumpAndSettle` expire. La couche SQLite est donc couverte séparément par
/// `test/repository_test.dart` (tests `test()` classiques, async réelles).
class _MemoryRepository extends ProjectRepository {
  _MemoryRepository()
    : super(factory: databaseFactoryFfiNoIsolate, databasePath: ':memory:');

  final Map<String, AnimationProject> _projects = <String, AnimationProject>{};

  @override
  Future<List<ProjectSummary>> listSummaries() async => <ProjectSummary>[
    for (final project in _projects.values)
      ProjectSummary(
        id: project.id,
        name: project.name,
        width: project.width,
        height: project.height,
        durationMs: project.durationMs,
        fps: project.fps,
        shapeCount: project.shapes.length,
        updatedAt: project.updatedAt,
      ),
  ];

  @override
  Future<int> countProjects() async => _projects.length;

  @override
  Future<AnimationProject> load(String id) async => _projects[id]!;

  @override
  Future<void> save(AnimationProject project, {bool touch = true}) async {
    _projects[project.id] = project;
  }

  @override
  Future<void> delete(String id) async {
    _projects.remove(id);
  }

  @override
  Future<void> rename(String id, String name) async {
    _projects[id]?.name = name;
  }

  @override
  Future<void> close() async {}
}

void main() {
  late _MemoryRepository repository;

  setUp(() => repository = _MemoryRepository());

  testWidgets(
    'l’écran principal affiche l’état vide et le bouton nouveau projet',
    (tester) async {
      await tester.pumpWidget(VectorAnimStudioApp(repository: repository));
      await tester.pumpAndSettle();

      expect(find.text('Vector Anim Studio'), findsOneWidget);
      // Bouton de l'état vide + bouton flottant.
      expect(find.text('Nouveau projet'), findsNWidgets(2));
      expect(find.text('Aucun projet pour l’instant'), findsOneWidget);
    },
  );

  testWidgets('la création d’un projet l’ajoute à la liste', (tester) async {
    await tester.pumpWidget(VectorAnimStudioApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Nouveau projet'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Mon film');
    await tester.tap(find.widgetWithText(FilledButton, 'Créer'));
    await tester.pumpAndSettle();

    // L'écran studio prend le relais : le nom du projet est dans l'AppBar.
    expect(find.text('Mon film'), findsWidgets);
    expect(await repository.countProjects(), 1);

    // Retour à l'écran principal : le projet apparaît dans la liste.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Mon film'), findsOneWidget);
    expect(find.text('Aucun projet pour l’instant'), findsNothing);
  });

  /// Ouvre l'écran studio avec un projet seedé dans le dépôt mémoire.
  Future<void> pumpStudio(
    WidgetTester tester,
    _MemoryRepository repository,
    AnimationProject project,
  ) async {
    await repository.save(project);
    await tester.pumpWidget(
      MaterialApp(
        home: StudioScreen(projectId: project.id, repository: repository),
      ),
    );
    await tester.pumpAndSettle();
  }

  AnimationProject seededProject({bool withShape = true}) {
    final project = AnimationProject.blank(name: 'Film');
    if (withShape) {
      final shape = VectorShape(name: 'Bloc');
      shape.layers.add(ShapeLayer(name: 'L', kind: ShapeKind.rect));
      // Keyframe : sans elle la forme statique n'a pas de barre timeline
      // (v0.18) et le nom n'est visible nulle part.
      shape.upsertKeyframe(1000, shape.poseAt(1000));
      project.shapes.add(shape);
    }
    return project;
  }

  testWidgets('undo annule la suppression d’une forme', (tester) async {
    final repository = _MemoryRepository();
    final project = seededProject();
    await pumpStudio(tester, repository, project);

    IconButton undoButton() => tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.undo).last,
    );

    // Aucune annulation disponible au départ.
    expect(undoButton().onPressed, isNull);

    // Supprimer la forme via le menu Formes.
    await tester.tap(find.byTooltip('Formes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    expect(project.shapes, isEmpty);
    expect(undoButton().onPressed, isNotNull);

    // Annuler : la forme revient sur la timeline et la pile est vide.
    await tester.tap(find.byIcon(Icons.undo).last);
    await tester.pumpAndSettle();
    expect(undoButton().onPressed, isNull);
    expect(find.text('Bloc'), findsOneWidget);
  });

  testWidgets('undo annule l’ajout d’une forme', (tester) async {
    final repository = _MemoryRepository();
    final project = seededProject(withShape: false);
    await pumpStudio(tester, repository, project);

    IconButton undoButton() => tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.undo).last,
    );

    // Ajouter une forme : menu Formes ▸ Ajouter une forme… puis Enregistrer.
    await tester.tap(find.byTooltip('Formes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter une forme…'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Enregistrer'));
    await tester.pumpAndSettle();
    // Forme statique sans keyframe : pas de barre timeline (v0.18) — on
    // vérifie l'état du projet, pas le texte de la barre.
    expect(project.shapes.single.name, 'Forme 1');
    expect(undoButton().onPressed, isNotNull);

    // Annuler : l'état restauré (snapshot d'avant l'ajout) est re-sauvé.
    await tester.tap(find.byIcon(Icons.undo).last);
    await tester.pumpAndSettle();
    expect(undoButton().onPressed, isNull);
    expect((await repository.load(project.id)).shapes, isEmpty);
  });

  testWidgets('le dialogue de création propose vectorielle ou squelette', (
    tester,
  ) async {
    await tester.pumpWidget(VectorAnimStudioApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Nouveau projet'));
    await tester.pumpAndSettle();
    expect(find.text('Vectorielle'), findsOneWidget);
    expect(find.text('Squelette'), findsOneWidget);

    // Créer un projet squelette : le studio s'ouvre en mode squelette.
    await tester.tap(find.text('Squelette'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Rat rig');
    await tester.tap(find.widgetWithText(FilledButton, 'Créer'));
    await tester.pumpAndSettle();

    expect(find.text('Rat rig'), findsWidgets);
    expect(find.byTooltip('Squelettes'), findsOneWidget);
    expect(find.byTooltip('Animations'), findsNothing);
  });

  testWidgets('le ◆ du playbar anime l’os sélectionné (projet squelette)', (
    tester,
  ) async {
    final project = AnimationProject.blank(
      name: 'Rat',
      type: ProjectType.skeleton,
    );
    final piece = VectorShape(name: 'Bloc');
    piece.layers.add(ShapeLayer(name: 'L', kind: ShapeKind.rect));
    project.shapes.add(piece);
    final rig = SkeletonRig(name: 'Rig');
    final bone = RigBone(name: 'Queue', offsetX: 180, offsetY: 320, length: 50);
    rig.addBone(bone);
    rig.bindShape(piece.id, bone.id);
    project.skeleton = rig;

    await pumpStudio(tester, repository, project);

    // Sélectionner l'os via le menu Squelettes.
    await tester.tap(find.byTooltip('Squelettes'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Queue').last);
    await tester.pumpAndSettle();

    // ◆ au curseur (0 s) : la piste de l'os reçoit sa première keyframe.
    await tester.tap(
      find.byTooltip('Ajouter une keyframe d’angle à l’os au curseur'),
    );
    await tester.pumpAndSettle();
    expect(project.skeleton!.hasKeyframes(bone.id), isTrue);
    expect(project.skeleton!.trackOf(bone.id)!.single.timeMs, 0);

    // Second appui au même endroit : la keyframe est retirée.
    await tester.tap(find.byTooltip('Retirer la keyframe au curseur'));
    await tester.pumpAndSettle();
    expect(project.skeleton!.hasKeyframes(bone.id), isFalse);
  });

  testWidgets(
    'le ◆ du playbar anime la PIÈCE sélectionnée (projet squelette)',
    (tester) async {
      // Bugfix v0.16.1 : avec une pièce sélectionnée, le ◆ no-opait (il
      // visait un os) — aucune pose de pièce n'était créable au doigt.
      final project = AnimationProject.blank(
        name: 'Rat',
        type: ProjectType.skeleton,
      );
      final piece = VectorShape(name: 'Bloc');
      piece.layers.add(ShapeLayer(name: 'L', kind: ShapeKind.rect));
      project.shapes.add(piece);
      final rig = SkeletonRig(name: 'Rig');
      final bone = RigBone(
        name: 'Queue',
        offsetX: 180,
        offsetY: 320,
        length: 50,
      );
      rig.addBone(bone);
      rig.bindShape(piece.id, bone.id);
      project.skeleton = rig;

      await pumpStudio(tester, repository, project);

      // Sélectionner la pièce via le menu Formes (sélection exclusive).
      await tester.tap(find.byTooltip('Formes'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Bloc').last);
      await tester.pumpAndSettle();

      // Le ◆ cible la pièce : tooltip de pose, pas celui d'os.
      expect(find.byTooltip('Ajouter une keyframe au curseur'), findsOneWidget);
      expect(
        find.byTooltip('Ajouter une keyframe d’angle à l’os au curseur'),
        findsNothing,
      );

      // ◆ au curseur (0 s) : la pièce reçoit une pose complète ; la piste
      // de l'os reste vide.
      await tester.tap(find.byTooltip('Ajouter une keyframe au curseur'));
      await tester.pumpAndSettle();
      expect(piece.keyframes.length, 1);
      expect(piece.keyframes.single.timeMs, 0);
      expect(rig.hasKeyframes(bone.id), isFalse);

      // Second appui au même endroit : la pose est retirée.
      await tester.tap(find.byTooltip('Retirer la keyframe au curseur'));
      await tester.pumpAndSettle();
      expect(piece.keyframes, isEmpty);
    },
  );

  testWidgets(
    'la sheet ⚙ d’une pièce propose le ◆ de pose et l’interpolation',
    (tester) async {
      final project = AnimationProject.blank(
        name: 'Rat',
        type: ProjectType.skeleton,
      );
      final piece = VectorShape(name: 'Bloc');
      piece.layers.add(ShapeLayer(name: 'L', kind: ShapeKind.rect));
      project.shapes.add(piece);
      final rig = SkeletonRig(name: 'Rig');
      final bone = RigBone(
        name: 'Queue',
        offsetX: 180,
        offsetY: 320,
        length: 50,
      );
      rig.addBone(bone);
      rig.bindShape(piece.id, bone.id);
      project.skeleton = rig;

      await pumpStudio(tester, repository, project);

      await tester.tap(find.byTooltip('Formes'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Bloc').last);
      await tester.pumpAndSettle();

      // Sheet ⚙ de la pièce : le ◆ de pose (masqué avant le bugfix) est
      // affiché dans l'en-tête ; la note signale l'absence de keyframe.
      await tester.tap(find.byTooltip('Propriétés de la forme'));
      await tester.pumpAndSettle();
      expect(find.textContaining('aucune keyframe'), findsOneWidget);

      // Le losange de la sheet crée la pose (playbar masquée derrière la
      // feuille : 2 widgets portent le tooltip, la feuille est la dernière).
      final sheetDiamond = find.byTooltip('Ajouter une keyframe au curseur');
      expect(sheetDiamond, findsNWidgets(2));
      await tester.tap(sheetDiamond.last);
      await tester.pumpAndSettle();
      expect(piece.keyframes.length, 1);
      expect(piece.keyframes.single.timeMs, 0);
      expect(rig.hasKeyframes(bone.id), isFalse);
      expect(find.textContaining('aucune keyframe'), findsNothing);

      // Ligne Interpolation : plus bas dans la feuille (ListView paresseuse
      // qui ne construit pas ce qui dépasse la fenêtre de test) — défiler
      // jusqu'à elle.
      await tester.scrollUntilVisible(
        find.text('Interpolation'),
        120,
        scrollable: find
            .descendant(
              of: find.byType(ShapePropertiesSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Interpolation'), findsOneWidget);
    },
  );

  testWidgets(
    'l’éditeur de pièce démarre au playhead du studio (poses pas à 0 s)',
    (tester) async {
      // Bugfix v0.16.3 : scrubber le studio à 2 s puis ouvrir l'éditeur —
      // le curseur de l'éditeur retombait à 0 s et TOUTES les
      // poses de morph étaient écrites à 0 (« Pose à 0,00 s » au snack).
      final project = AnimationProject.blank(
        name: 'Rat',
        type: ProjectType.skeleton,
      );
      final piece = VectorShape(name: 'Chemin');
      piece.layers.add(
        ShapeLayer(
          name: 'Ch',
          kind: ShapeKind.path,
          width: 120,
          height: 120,
          points: const <Offset>[
            Offset(0, 0),
            Offset(120, 0),
            Offset(120, 120),
            Offset(0, 120),
          ],
        ),
      );
      project.shapes.add(piece);
      final rig = SkeletonRig(name: 'Rig');
      final bone = RigBone(
        name: 'Queue',
        offsetX: 180,
        offsetY: 320,
        length: 50,
      );
      rig.addBone(bone);
      rig.bindShape(piece.id, bone.id);
      project.skeleton = rig;

      await pumpStudio(tester, repository, project);

      // Sélectionner la pièce, ◆ pose à 0 s.
      await tester.tap(find.byTooltip('Formes'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Chemin').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Ajouter une keyframe au curseur'));
      await tester.pumpAndSettle();
      expect(piece.keyframes, hasLength(1));

      // Scrubber le studio à 2000 ms : le fond SOUS les lignes du timeline
      // (le centre vertical tombe sur la barre de pièce → onSelect).
      final timelineRect = tester.getRect(find.byType(TimelineView));
      await tester.tapAt(
        timelineRect.bottomLeft + Offset(timelineRect.width / 2, -2),
      );
      await tester.pumpAndSettle();

      // Ouvrir la sheet ⚙ puis l'éditeur (bouton Couches).
      await tester.tap(find.byTooltip('Propriétés de la forme'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Couches'));
      await tester.pumpAndSettle();

      // Le curseur de l'éditeur est à 2,00 s (label à droite du slider).
      expect(find.text('2.00 s'), findsOneWidget);

      // Glisser une poignée de point (preview de l'ÉDITEUR = dernier
      // ScenePainter de l'arbre, le studio est derrière la route).
      final canvasFinder = find
          .byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is ScenePainter,
          )
          .last;
      final size = tester.getSize(canvasFinder);
      final geo = SceneGeometry.fitFor(project, size);
      final layer = piece.layers.first;
      final cloud = piece.pointsAtLayer(layer.id, layer.points, 2000);
      final handles = SelectionGeometry.pointHandlePositions(
        cloud,
        layer,
        SelectionGeometry.layerPose(piece, layer, 2000),
        geo,
      );
      expect(handles, hasLength(4));
      debugPrint(
        'DBG canvasRect=${tester.getRect(canvasFinder)} '
        'topLeft=${tester.getTopLeft(canvasFinder)} handles=$handles',
      );
      final gesture = await tester.startGesture(
        tester.getTopLeft(canvasFinder) + handles[1],
      );
      await gesture.moveBy(const Offset(40, -30));
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // Enregistrer (✓) puis vérifier : la pose est écrite À 2000 ms.
      // ATTENTION : _editShape REMPLACE l'objet pièce par le brouillon
      // (project.shapes[index] = edited) — relire project.shapes.first.
      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();
      final savedPiece = project.shapes.first;
      debugPrint(
        'DBG saved: kf=${savedPiece.keyframes.map((k) => k.timeMs).toList()} '
        'layerXY=(${savedPiece.layers.first.x}, ${savedPiece.layers.first.y})',
      );
      expect(savedPiece.keyframes.map((k) => k.timeMs), <int>[0, 2000]);
      final entry = savedPiece.keyframes
          .firstWhere((k) => k.timeMs == 2000)
          .layerPoints[layer.id];
      expect(entry, isNotNull);
      expect(entry![1], isNot(equals(const Offset(120, 0))));
      // La pose 0 (créée avant l'éditeur) est intacte : le morph existe.
      expect(
        savedPiece.keyframes.first.layerPoints[layer.id],
        isNull, // pose 0 sans nuage → morph base → nuage(2000)
      );
    },
  );

  testWidgets('glisser le bouton ✥ déplace l’os (pas de mode armé)', (
    tester,
  ) async {
    final repository = _MemoryRepository();
    final project = AnimationProject.blank(
      name: 'Rat',
      type: ProjectType.skeleton,
    );
    final rig = SkeletonRig();
    final bone = RigBone(name: 'Queue', offsetX: 180, offsetY: 320, length: 50);
    rig.addBone(bone);
    project.skeleton = rig;

    await pumpStudio(tester, repository, project);

    // Sélectionner l'os via le menu Squelettes.
    await tester.tap(find.byTooltip('Squelettes'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Queue').last);
    await tester.pumpAndSettle();

    // Glisser LE BOUTON ✥ : l'ancrage de l'os suit le doigt (v0.9.4
    // armait un mode — choix utilisateur : plus de mode, le bouton
    // lui-même est la poignée).
    await tester.drag(
      find.byTooltip('Glisser pour déplacer l’os'),
      const Offset(100, 0),
    );
    await tester.pumpAndSettle();
    expect(bone.offsetX, greaterThan(180));
    expect(bone.offsetY, 320);

    // Pas de mode collant : un tap sur le bouton ne change rien.
    final afterFirst = bone.offsetX;
    await tester.tap(find.byTooltip('Glisser pour déplacer l’os'));
    await tester.pumpAndSettle();
    expect(bone.offsetX, afterFirst);
  });

  /// Rig IK : épaule (180,320)→(280,320), avant-bras (280,320)→(280,420)
  /// (plié à 90°) ; IK activé sur l'ÉPAULE (os parent), effecteur =
  /// extrémité de l'enfant. Pose initiale JAMAIS tendue à fond (L1+L2 =
  /// 200 > distance joint→effecteur 141) : les cibles de test restent
  /// atteignables.
  AnimationProject ikProject() {
    final project = AnimationProject.blank(
      name: 'Rat',
      type: ProjectType.skeleton,
    );
    final rig = SkeletonRig();
    final parent = RigBone(
      name: 'Bras',
      offsetX: 180,
      offsetY: 320,
      length: 100,
      ikEnabled: true,
    );
    final child = RigBone(
      name: 'Avant-bras',
      parentId: parent.id,
      offsetX: 100,
      offsetY: 0,
      restAngle: math.pi / 2,
      length: 100,
    );
    rig.addBone(parent);
    rig.addBone(child);
    project.skeleton = rig;
    return project;
  }

  /// Point GLOBAL du canvas + géométrie scène↔canvas réelle de l'app.
  (Offset topLeft, SceneGeometry geo) canvasHarness(
    WidgetTester tester,
    AnimationProject project,
  ) {
    final paint = tester.widget<CustomPaint>(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is ScenePainter,
      ),
    );
    final box = tester.renderObject<RenderBox>(find.byWidget(paint));
    return (
      box.localToGlobal(Offset.zero),
      SceneGeometry.fitFor(project, box.size),
    );
  }

  /// Glisser depuis [from] (global) de [sceneDelta] px scène : un premier
  /// déplacement ÉCRAN de 22 px vainc la slop du recognizer (18 px) tout en
  /// gardant le foyer de onScaleStart DANS la zone de saisie IK (26 px) —
  /// le recognizer ne démarle qu'après un déplacement, avec le foyer déjà
  /// déplacé. Un second déplacement recale ensuite le foyer SUR la cible.
  Future<void> dragSceneDelta(
    WidgetTester tester,
    Offset from,
    Offset sceneDelta,
    double scale,
  ) async {
    const big = Offset(22.0, 0.0);
    final grip = await tester.startGesture(from);
    await tester.pump();
    await grip.moveBy(big);
    await tester.pump();
    await grip.moveBy(-big + sceneDelta * scale);
    await tester.pump();
    await grip.up();
    await tester.pumpAndSettle();
  }

  testWidgets(
    'IK : glisser l’effecteur résout la chaîne (enfant sélectionné)',
    (tester) async {
      final repository = _MemoryRepository();
      final project = ikProject();
      await pumpStudio(tester, repository, project);
      final (topLeft, geo) = canvasHarness(tester, project);
      final rig = project.skeleton!;
      final child = rig.bones.last;

      // Tap sur l'effecteur : l'ENFANT se sélectionne (le comportement
      // naturel — v0.10.0 exigeait le parent sélectionné, le glisser était
      // mort depuis cette sélection).
      final effecteur = topLeft + geo.sceneToCanvas(const Offset(280, 420));
      await tester.tapAt(effecteur);
      await tester.pumpAndSettle();

      // Glisser l'effecteur de 60 px scène vers le haut.
      await dragSceneDelta(tester, effecteur, const Offset(0, -60), geo.scale);

      final pose = SkeletonPose.evaluate(rig, 0);
      final tip = pose.frameOf(child.id)!.tip;
      expect(tip.dx, moreOrLessEquals(280, epsilon: 1e-3));
      expect(tip.dy, moreOrLessEquals(360, epsilon: 1e-3));
      // Le coude a bougé : la chaîne a plié (et pas juste glissé).
      expect(pose.frameOf(rig.bones.first.id)!.tip.dy, isNot(320.0));
    },
  );

  testWidgets('IK : le losange vert est une poignée même SANS sélection', (
    tester,
  ) async {
    final repository = _MemoryRepository();
    final project = ikProject();
    await pumpStudio(tester, repository, project);
    final (topLeft, geo) = canvasHarness(tester, project);
    final rig = project.skeleton!;
    final child = rig.bones.last;

    final effecteur = topLeft + geo.sceneToCanvas(const Offset(280, 420));
    await dragSceneDelta(tester, effecteur, const Offset(60, 0), geo.scale);

    // Cible (340, 420) : d = 188,7 < 200 — le bout de l'enfant atterrit
    // SUR la cible.
    final pose = SkeletonPose.evaluate(rig, 0);
    final tip = pose.frameOf(child.id)!.tip;
    expect(tip.dx, moreOrLessEquals(340, epsilon: 1e-3));
    expect(tip.dy, moreOrLessEquals(420, epsilon: 1e-3));
  });

  testWidgets('IK : marche aussi avec l’os parent sélectionné', (tester) async {
    final repository = _MemoryRepository();
    final project = ikProject();
    await pumpStudio(tester, repository, project);
    final (topLeft, geo) = canvasHarness(tester, project);
    final rig = project.skeleton!;
    final child = rig.bones.last;

    // Tap au MILIEU de l'épaule → parent sélectionné.
    await tester.tapAt(topLeft + geo.sceneToCanvas(const Offset(230, 320)));
    await tester.pumpAndSettle();

    final effecteur = topLeft + geo.sceneToCanvas(const Offset(280, 420));
    await dragSceneDelta(tester, effecteur, const Offset(-30, 40), geo.scale);

    final pose = SkeletonPose.evaluate(rig, 0);
    final tip = pose.frameOf(child.id)!.tip;
    expect(tip.dx, moreOrLessEquals(250, epsilon: 1e-3));
    expect(tip.dy, moreOrLessEquals(460, epsilon: 1e-3));
  });

  testWidgets('un projet squelette affiche une barre d’os sur la timeline', (
    tester,
  ) async {
    final project = AnimationProject.blank(
      name: 'Rat',
      type: ProjectType.skeleton,
    );
    final rig = SkeletonRig();
    final bone = RigBone(name: 'Queue');
    rig.addBone(bone);
    rig.upsertKeyframe(bone.id, 500, 0.2);
    rig.upsertKeyframe(bone.id, 1500, 0.4);
    project.skeleton = rig;

    await pumpStudio(tester, repository, project);

    expect(find.textContaining('\u{1F9B4} Queue'), findsOneWidget);
    // Les barres de formes n'existent pas en mode squelette.
    expect(find.textContaining('\u{1F3AC}'), findsNothing);
  });

  testWidgets('une instance de projet squelette s’anime dans un vectoriel', (
    tester,
  ) async {
    final repository = _MemoryRepository();
    // Sous-projet squelette animé : keyframes d'os 0 → 1 s.
    final skeleton = AnimationProject.blank(
      name: 'Rat',
      type: ProjectType.skeleton,
    );
    final rig = SkeletonRig();
    final bone = RigBone(name: 'Queue', offsetX: 180, offsetY: 320, length: 60);
    rig.addBone(bone);
    rig.upsertKeyframe(bone.id, 0, 0, easing: EasingKind.linear);
    rig.upsertKeyframe(bone.id, 1000, 0.8, easing: EasingKind.linear);
    skeleton.skeleton = rig;
    await repository.save(skeleton);

    // Projet hôte vectoriel : le personnage riggé devient une instance.
    final host = AnimationProject.blank(name: 'Scène');
    host.shapes.add(
      VectorShape(
        name: 'Rat',
        embeddedProjectId: skeleton.id,
        embeddedWidth: skeleton.width,
        embeddedHeight: skeleton.height
      ),
    );

    await pumpStudio(tester, repository, host);
    expect(find.textContaining('\u{1F3AC} Rat'), findsOneWidget);

    // Lecture : le rig du sous-projet est échantillonné à son temps de
    // boucle, sans planter (rendu à chaque frame).
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pumpAndSettle();
  });

  testWidgets('importer un fichier JSON vasf crée et ouvre un nouveau projet', (
    tester,
  ) async {
    final repository = _MemoryRepository();
    await pumpStudio(tester, repository, seededProject());

    // Faux sélecteur : un fichier « demo.json » en mémoire.
    final original = FilePickerPlatform.instance;
    addTearDown(() => FilePickerPlatform.instance = original);
    FilePickerPlatform.instance = _FakePickerPlatform(
      Uint8List.fromList(
        utf8.encode(
          '{"version": 1, "name": "Importé", "shapes": ['
          '{"name": "B", "type": "circle", "end": 1}]}',
        ),
      ),
    );

    // Menu Export ▸ Importer un fichier JSON…
    await tester.tap(find.byTooltip('Export'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Importer un fichier JSON…'));
    await tester.pumpAndSettle();

    // Le nouveau projet est ouvert (titre AppBar) et enregistré.
    expect(find.text('Importé'), findsOneWidget);
    final summaries = await repository.listSummaries();
    expect(summaries.map((s) => s.name), contains('Importé'));
    // Le canvas vasf par défaut : 720×1280.
    final imported = summaries.lastWhere((s) => s.name == 'Importé');
    expect(imported.width, 720);
    expect(imported.height, 1280);
  });

  testWidgets(
    'fichier JSON invalide : les erreurs s’affichent dans un dialogue',
    (tester) async {
      final repository = _MemoryRepository();
      await pumpStudio(tester, repository, seededProject());

      final original = FilePickerPlatform.instance;
      addTearDown(() => FilePickerPlatform.instance = original);
      FilePickerPlatform.instance = _FakePickerPlatform(
        Uint8List.fromList(utf8.encode('{"version": 9, "shapes": []}')),
      );

      await tester.tap(find.byTooltip('Export'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Importer un fichier JSON…'));
      await tester.pumpAndSettle();

      // Les problèmes sont listés (version + shapes vides)…
      expect(find.text('Import impossible'), findsOneWidget);
      expect(find.textContaining('version'), findsWidgets);
      expect(find.textContaining('au moins une forme'), findsOneWidget);
      // …dans un dialogue fermable.
      expect(find.text('Fermer'), findsOneWidget);
      // Le dépôt reste inchangé.
      final summaries = await repository.listSummaries();
      expect(summaries.map((s) => s.name), isNot(contains('Importé')));
    },
  );
}

/// Faux fichier choisi dans le sélecteur : contenu EN MÉMOIRE (aucune I/O
/// réelle — dart:io ne progresse pas dans la zone fake-async de testWidgets).
base class _FakePickedFile extends PlatformFile {
  _FakePickedFile(this._name, this._bytes);

  final String _name;
  final Uint8List _bytes;

  @override
  String get name => _name;

  @override
  Uri get uri => Uri.file('/memory/$_name');

  @override
  XFile get xFile => XFile.fromData(_bytes);

  @override
  int? lengthSync() => _bytes.length;

  @override
  Future<int?> length() async => _bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => _bytes;

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(_bytes);
}

/// Faux sélecteur de fichiers : renvoie un seul « demo.json ».
class _FakePickerPlatform extends FilePickerPlatform {
  _FakePickerPlatform(this._bytes);

  final Uint8List _bytes;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => <PlatformFile>[_FakePickedFile('demo.json', _bytes)];
}
