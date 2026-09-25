import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vector_anim_studio/data/project_repository.dart';
import 'package:vector_anim_studio/engine/scene_painter.dart';
import 'package:vector_anim_studio/engine/selection_geometry.dart';
import 'package:vector_anim_studio/main.dart';
import 'package:vector_anim_studio/models/animation.dart';
import 'package:vector_anim_studio/models/skeleton.dart';
import 'package:vector_anim_studio/ui/studio_screen.dart';

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
      final shape = VectorShape(name: 'Bloc', startMs: 0, endMs: 2000);
      shape.layers.add(ShapeLayer(name: 'L', kind: ShapeKind.rect));
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
    await pumpStudio(tester, repository, seededProject(withShape: false));

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
    expect(find.text('Forme 1'), findsOneWidget);
    expect(undoButton().onPressed, isNotNull);

    // Annuler : la forme disparaît de la timeline.
    await tester.tap(find.byIcon(Icons.undo).last);
    await tester.pumpAndSettle();
    expect(undoButton().onPressed, isNull);
    expect(find.text('Forme 1'), findsNothing);
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
    final piece = VectorShape(name: 'Bloc', startMs: 0, endMs: 2000);
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
        embeddedHeight: skeleton.height,
        startMs: 0,
        endMs: 2000,
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
}
