import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vector_anim_studio/data/project_repository.dart';
import 'package:vector_anim_studio/engine/rig_overlay_painter.dart';
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
        type: project.type,
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

      expect(find.text('Keyform Studio'), findsOneWidget);
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

  testWidgets('la barre du bas regroupe éléments, animation et os', (
    tester,
  ) async {
    final project = seededProject();
    await pumpStudio(tester, repository, project);

    expect(find.text('Éléments'), findsOneWidget);
    expect(find.text('Animation'), findsOneWidget);
    expect(find.text('Os'), findsOneWidget);
    expect(find.byTooltip('Export'), findsOneWidget);
    expect(find.text('Formes'), findsNothing);

    await tester.tap(find.text('Éléments'));
    await tester.pumpAndSettle();
    expect(find.text('Ajouter une forme…'), findsOneWidget);
    expect(find.text('DANS LE PROJET · 1 ÉLÉMENTS'), findsOneWidget);
    expect(find.text('Bloc'), findsWidgets);
    await tester.tap(find.text('Bloc').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Animation'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ANIMATIONS RAPIDES'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Os'));
    await tester.pumpAndSettle();
    expect(find.text('Créer et lier un os'), findsOneWidget);
    expect(find.text('Aucun os créé'), findsOneWidget);
  });

  /// Point GLOBAL du canvas + géométrie scène↔canvas réelle de l'app.
  /// Déclaré en tête : les tests d'os (tap sur l'os) l'utilisent avant les
  /// tests IK qui suivent.
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

  testWidgets(
    'preview reste à sa taille quand on sélectionne une forme aux couches cachées',
    (tester) async {
      final repository = _MemoryRepository();
      final project = AnimationProject.blank(
        name: 'Rig',
        type: ProjectType.skeleton,
      );
      final visible = VectorShape(name: 'Visible');
      visible.layers.add(ShapeLayer(name: 'Corps', kind: ShapeKind.rect));
      final hidden = VectorShape(name: 'Masquée');
      hidden.layers.add(
        ShapeLayer(name: 'Unique', kind: ShapeKind.rect, visible: false),
      );
      project.shapes.addAll(<VectorShape>[visible, hidden]);
      final rig = SkeletonRig();
      final bone = RigBone(name: 'Os');
      rig.addBone(bone);
      rig.bindShape(hidden.id, bone.id);
      project.skeleton = rig;
      await pumpStudio(tester, repository, project);

      final before = tester
          .renderObject<RenderBox>(
            find.byWidgetPredicate(
              (w) => w is CustomPaint && w.painter is ScenePainter,
            ),
          )
          .size;
      await tester.tap(find.text('Éléments').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Masquée').last);
      await tester.pumpAndSettle();

      final after = tester
          .renderObject<RenderBox>(
            find.byWidgetPredicate(
              (w) => w is CustomPaint && w.painter is ScenePainter,
            ),
          )
          .size;
      expect(after.width, closeTo(before.width, 0.01));
      expect(after.height, closeTo(before.height, 0.01));
    },
  );

  testWidgets('undo annule la suppression d’une forme', (tester) async {
    final repository = _MemoryRepository();
    final project = seededProject();
    await pumpStudio(tester, repository, project);

    IconButton undoButton() => tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.undo).last,
    );

    // Aucune annulation disponible au départ.
    expect(undoButton().onPressed, isNull);

    // Supprimer la forme via le panneau Éléments.
    await tester.tap(find.text('Éléments'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Supprimer').last);
    await tester.tap(find.text('Supprimer').last);
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

    // Ajouter une forme : panneau Éléments ▸ Ajouter une forme… puis Enregistrer.
    await tester.tap(find.text('Éléments'));
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

  testWidgets('création unifiée : pas de choix de type', (tester) async {
    await tester.pumpWidget(VectorAnimStudioApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Nouveau projet'));
    await tester.pumpAndSettle();
    expect(find.text('Vectorielle'), findsNothing);
    expect(find.text('Squelette'), findsNothing);
    expect(find.text('Type d’animation'), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'Projet mixte');
    await tester.tap(find.widgetWithText(FilledButton, 'Créer'));
    await tester.pumpAndSettle();

    final project = await repository.load(repository._projects.keys.single);
    expect(project.type, ProjectType.vector, reason: 'ancien champ conservé');
    expect(project.usesRigWorkflow, isFalse, reason: 'le rig reste optionnel');
    expect(find.text('Projet mixte'), findsWidgets);
    expect(find.textContaining(' fps'), findsNothing);
    expect(find.textContaining(' / '), findsNothing);
  });

  testWidgets('un ancien projet vectoriel expose les outils de rig', (
    tester,
  ) async {
    final project = seededProject();
    await pumpStudio(tester, repository, project);

    await tester.tap(find.byTooltip('Propriétés de la forme'));
    await tester.pumpAndSettle();
    expect(find.text('Ajouter un os…'), findsOneWidget);
    await tester.tap(find.text('Ajouter un os…'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Os de « Bloc »'), findsOneWidget);
  });

  testWidgets('le ◆ du playbar anime l’os en projet vectoriel', (tester) async {
    final project = AnimationProject.blank(
      name: 'Rat',
      type: ProjectType.vector,
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

    // Le type historique reste vectoriel ; le rig est néanmoins actif.
    final (topLeft, geo) = canvasHarness(tester, project);
    await tester.tapAt(topLeft + geo.sceneToCanvas(const Offset(180, 320)));
    await tester.pumpAndSettle();
    expect(
      find.byTooltip('Glisser pour déplacer l’os'),
      findsOneWidget,
      reason: 'le tap sur l’os doit le sélectionner',
    );

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
      final piece = VectorShape(name: 'Bloc', startMs: 0, endMs: 2000);
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

      // Sélectionner la pièce via le panneau Éléments (sélection exclusive).
      await tester.tap(find.text('Éléments'));
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
      final piece = VectorShape(name: 'Bloc', startMs: 0, endMs: 2000);
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

      await tester.tap(find.text('Éléments'));
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
      // le curseur de l'éditeur retombait à startMs (0 s) et TOUTES les
      // poses de morph étaient écrites à 0 (« Pose à 0,00 s » au snack).
      final project = AnimationProject.blank(
        name: 'Rat',
        type: ProjectType.skeleton,
      );
      final piece = VectorShape(name: 'Chemin', startMs: 0, endMs: 4000);
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
      await tester.tap(find.text('Éléments'));
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

    // Sélectionner l'os en TAPANT dessus (le menu Squelette n'existe plus :
    // la sélection d'os passe par le canvas ou la sélection de segment).
    final (topLeft, geo) = canvasHarness(tester, project);
    await tester.tapAt(topLeft + geo.sceneToCanvas(const Offset(180, 320)));
    await tester.pumpAndSettle();
    expect(
      find.byTooltip('Glisser pour déplacer l’os'),
      findsOneWidget,
      reason: 'le tap sur l’os doit le sélectionner',
    );

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

  testWidgets(
    'segment lié : keyframes de l’os, couleur, clic = os sélectionné',
    (tester) async {
      final repository = _MemoryRepository();
      final project = AnimationProject.blank(
        name: 'Rat',
        type: ProjectType.skeleton,
      );
      project.width = 720;
      project.height = 1280;
      final shape = VectorShape(name: 'Bloc', startMs: 0, endMs: 2000);
      shape.layers.add(ShapeLayer(name: 'L', kind: ShapeKind.rect));
      // Keyframes de la FORME : sur un segment lié, elles ne s'affichent PLUS
      // (choix utilisateur v0.21.0) — seules celles de l'os comptent.
      shape.setKeyframes(<ShapeKeyframe>[ShapeKeyframe(timeMs: 250)]);
      project.shapes.add(shape);

      final rig = SkeletonRig();
      final bone = RigBone(name: 'Queue');
      rig.addBone(bone);
      rig.bindShape(shape.id, bone.id);
      rig.upsertKeyframe(bone.id, 500, 0.2);
      rig.upsertKeyframe(bone.id, 1500, 0.4);
      project.skeleton = rig;

      await pumpStudio(tester, repository, project);

      // ① Plus de piste d'os séparée (🦴) : une seule ligne, celle de la pièce.
      expect(find.textContaining('\u{1F9B4}'), findsNothing);
      expect(find.text('Bloc'), findsOneWidget);

      // ② Losanges = keyframes de l'OS (2), pas celles de la forme (1 à 250).
      final diamonds = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.color == const Color(0xFFF2C94C) &&
            w.constraints == const BoxConstraints.tightFor(width: 7, height: 7),
      );
      expect(diamonds, findsNWidgets(2));

      // ③ Couleur propre au segment lié (vert os, alpha de remplissage 0.30).
      final bars = tester
          .widgetList<Container>(find.byType(Container))
          .where(
            (c) =>
                c.decoration is BoxDecoration &&
                (c.decoration! as BoxDecoration).color ==
                    const Color(0xFF3ECF8E).withValues(alpha: 0.30),
          )
          .toList();
      expect(bars, hasLength(1), reason: 'un segment lié coloré en vert os');

      // ④ Clic sur le segment → l'OS est sélectionné (sélection exclusive).
      await tester.tap(find.text('Bloc'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Propriétés de l’os'), findsOneWidget);
      expect(find.byTooltip('Propriétés de la forme'), findsNothing);
    },
  );

  testWidgets(
    'un projet squelette s’insère comme groupe dans un projet squelette',
    (tester) async {
      final repository = _MemoryRepository();
      final source = AnimationProject.blank(
        name: 'Personnage source',
        type: ProjectType.skeleton,
      );
      source.shapes.add(
        VectorShape(
          name: 'Corps',
          x: 180,
          y: 320,
          startMs: 0,
          endMs: 2000,
          layers: <ShapeLayer>[
            ShapeLayer(
              name: 'L',
              kind: ShapeKind.rect,
              width: 120,
              height: 160,
            ),
          ],
        ),
      );
      source.skeleton = SkeletonRig(
        bones: <RigBone>[
          RigBone(name: 'Torso', offsetX: 180, offsetY: 320, length: 80),
        ],
      );
      await repository.save(source);
      final host = AnimationProject.blank(
        name: 'Scène squelette',
        type: ProjectType.skeleton,
      );
      await pumpStudio(tester, repository, host);

      await tester.tap(find.text('Éléments'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Insérer une animation…').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Personnage source'));
      await tester.pumpAndSettle();

      final group = host.shapes.single;
      expect(group.isInstance, isTrue);
      expect(group.embeddedIsSkeleton, isTrue);
      expect(group.embeddedProjectId, source.id);
      expect(find.textContaining('Personnage source'), findsOneWidget);
      expect(find.textContaining('🦴'), findsNothing);

      // Le groupe a des transformations et ses propres keyframes, et peut être
      // pris en charge par le rig hôte sans perdre sa manipulation de groupe.
      await tester.tap(find.byTooltip('Propriétés de la forme'));
      await tester.pumpAndSettle();
      expect(find.text('Miroir H'), findsOneWidget);
      expect(find.text('Miroir V'), findsOneWidget);
      await tester.tap(find.text('Miroir H'));
      await tester.pumpAndSettle();
      expect(group.flipH, isTrue);
      await tester.tapAt(const Offset(8, 8)); // ferme la feuille de propriétés
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Ajouter une keyframe au curseur'));
      await tester.pumpAndSettle();
      expect(group.keyframes, hasLength(1));
    },
  );

  testWidgets(
    'la re-sélection du groupe restaure les os ajoutés dans le preview',
    (tester) async {
      final repository = _MemoryRepository();
      final host = AnimationProject.blank(
        name: 'Hôte',
        type: ProjectType.skeleton,
      );
      final group = VectorShape(
        name: 'Groupe squelette',
        embeddedProjectId: 'source-id',
        embeddedWidth: 360,
        embeddedHeight: 640,
        embeddedIsSkeleton: true,
        startMs: 0,
        endMs: 4000,
      );
      final other = VectorShape(name: 'Autre élément', startMs: 0, endMs: 4000);
      other.layers.add(ShapeLayer(name: 'L', kind: ShapeKind.rect));
      host.shapes.addAll(<VectorShape>[group, other]);

      final rig = SkeletonRig();
      final root = RigBone(
        name: 'Os groupe',
        offsetX: 180,
        offsetY: 260,
        length: 80,
      );
      final child = RigBone(
        name: 'Os ajouté',
        parentId: root.id,
        offsetX: 80,
        offsetY: 0,
        length: 70,
      );
      rig.bones.addAll(<RigBone>[root, child]);
      rig.bindShape(group.id, root.id);
      host.skeleton = rig;
      await repository.save(host);

      await pumpStudio(tester, repository, host);
      await tester.tap(find.text('Éléments'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Autre élément').last);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Propriétés de l’os'), findsNothing);

      await tester.tap(find.text('Éléments'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Groupe squelette').last);
      await tester.pumpAndSettle();

      final overlay = tester.widget<CustomPaint>(
        find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter is RigOverlayPainter,
        ),
      );
      final painter = overlay.painter! as RigOverlayPainter;
      expect(painter.visibleBoneIds, containsAll(<String>{root.id, child.id}));
      expect(find.byTooltip('Propriétés de la forme'), findsOneWidget);

      final (topLeft, geo) = canvasHarness(tester, host);
      await tester.tapAt(topLeft + geo.sceneToCanvas(const Offset(220, 260)));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Propriétés de l’os'), findsOneWidget);
    },
  );

  testWidgets('importer un VASF squelette dans le studio ajoute une instance', (
    tester,
  ) async {
    final repository = _MemoryRepository();
    final host = AnimationProject.blank(
      name: 'Hôte rig',
      type: ProjectType.skeleton,
    );
    await pumpStudio(tester, repository, host);

    final original = FilePickerPlatform.instance;
    addTearDown(() => FilePickerPlatform.instance = original);
    FilePickerPlatform.instance = _FakePickerPlatform(
      Uint8List.fromList(
        utf8.encode(
          '{"version":1,"name":"VASF importé",'
          '"canvas":{"width":360,"height":640,"fps":25},'
          '"shapes":[{"name":"Torso","type":"rect",'
          '"width":90,"height":140,"x":180,"y":320,"end":2}],'
          '"skeleton":{"name":"Rig","bones":['
          '{"name":"Root","joint":[180,320],"angle":-90,"length":80}]}}',
        ),
      ),
    );

    await tester.tap(find.text('Éléments'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Importer un VASF comme groupe…'));
    await tester.pumpAndSettle();

    expect(host.shapes, hasLength(1));
    expect(host.shapes.single.embeddedIsSkeleton, isTrue);
    final savedSource = await repository.load(
      host.shapes.single.embeddedProjectId!,
    );
    expect(savedSource.name, 'VASF importé');
    expect(savedSource.isSkeleton, isTrue);
    expect(find.textContaining('VASF importé'), findsOneWidget);
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
        embeddedIsSkeleton: true,
        startMs: 0,
        endMs: 2000,
      ),
    );

    await pumpStudio(tester, repository, host);
    expect(find.textContaining('Rat'), findsOneWidget);

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
    await repository.save(seededProject());
    await tester.pumpWidget(VectorAnimStudioApp(repository: repository));
    await tester.pumpAndSettle();

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

    // L'action d'import est maintenant sur l'écran liste des projets.
    await tester.tap(find.byTooltip('Importer un fichier JSON'));
    await tester.pumpAndSettle();

    // Le nouveau projet est ouvert (titre AppBar) et enregistré.
    expect(find.text('Importé'), findsOneWidget);
    final summaries = await repository.listSummaries();
    expect(summaries.map((s) => s.name), contains('Importé'));
    // Le canvas vasf par défaut : 720×1280.
    final imported = summaries.lastWhere((s) => s.name == 'Importé');
    expect(imported.width, 720);
    expect(imported.height, 1280);
    expect(summaries, hasLength(2)); // le projet d'origine n'a pas été écrasé.
    expect(find.text('Importer un fichier JSON…'), findsNothing);
  });

  testWidgets(
    'fichier JSON invalide : les erreurs s’affichent dans un dialogue',
    (tester) async {
      final repository = _MemoryRepository();
      await repository.save(seededProject());
      await tester.pumpWidget(VectorAnimStudioApp(repository: repository));
      await tester.pumpAndSettle();

      final original = FilePickerPlatform.instance;
      addTearDown(() => FilePickerPlatform.instance = original);
      FilePickerPlatform.instance = _FakePickerPlatform(
        Uint8List.fromList(utf8.encode('{"version": 9, "shapes": []}')),
      );

      await tester.tap(find.byTooltip('Importer un fichier JSON'));
      await tester.pumpAndSettle();

      // Les problèmes sont listés (version + shapes vides)…
      expect(find.text('Import impossible'), findsOneWidget);
      expect(find.textContaining('version'), findsWidgets);
      expect(find.textContaining('au moins une forme'), findsOneWidget);
      // …dans un dialogue fermable.
      expect(find.text('Fermer'), findsOneWidget);
      // Le dépôt reste inchangé (seul le projet préexistant est conservé).
      final summaries = await repository.listSummaries();
      expect(summaries, hasLength(1));
      expect(summaries.single.name, 'Film');
    },
  );

  // ------------------------------------- v0.19.1 : forme portée par un os

  /// Pièce squelette 720×1280 au CENTRE du canvas ; [bind] la lie à l'os.
  /// La pièce est VOLONTAIREMENT grande (400×300) : le canvas du studio est
  /// limité en hauteur (~366 px → échelle 0,29), une petite pièce ne
  /// laisserait pas le pointeur rester dedans pendant la slop du geste.
  AnimationProject lockedPiece({required bool bind}) {
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
    final rig = SkeletonRig();
    // Os LOIN de la pièce (sc. y 150→230 vs pièce à y 640) : le tap de test
    // sur la pièce ne doit pas être absorbé par l'os (segmentTouchSlop 13 px,
    // tipTouchSlop 26 px) — sinon c'est l'OS qui se sélectionne.
    final bone = RigBone(name: 'Tronc', offsetX: 360, offsetY: 150, length: 80);
    rig.addBone(bone);
    if (bind) rig.bindShape(shape.id, bone.id);
    project.skeleton = rig;
    return project;
  }

  /// Sélectionne la pièce via le panneau Éléments (le TAP au canvas est ignoré
  /// pour une pièce liée — v0.19.1) et vérifie que le bouton ⚙ apparaît.
  Future<void> selectPieceViaMenu(WidgetTester tester) async {
    await tester.tap(find.text('Éléments'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Bloc').last);
    await tester.pumpAndSettle();
    // Sélection confirmée : le bouton ⚙ n'existe que pour une forme
    // sélectionnée (sinon, la suite ne prouve rien).
    expect(
      find.byTooltip('Propriétés de la forme'),
      findsOneWidget,
      reason: 'la pièce doit être sélectionnée avant le geste',
    );
  }

  /// Sélectionne la pièce puis la glisse de [dx] px écran (deux moves :
  /// le recognizer Scale ne démarre qu'après ~18 px de slop).
  Future<void> dragSelectedPiece(
    WidgetTester tester,
    Offset from,
    double dx,
  ) async {
    await selectPieceViaMenu(tester);

    final gesture = await tester.startGesture(from);
    await tester.pump();
    await gesture.moveBy(Offset(dx, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(6, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets(
    'forme liée à un os : le glisser ne la déplace pas (avertissement)',
    (tester) async {
      final repository = _MemoryRepository();
      // Fenêtre HAUTE : la preview du studio est clampée à ~200 px en 800×600
      // (échelle 0,159) — même une pièce de 400 px ne laisserait pas le
      // pointeur rester dedans pendant la slop du geste (18 px).
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final project = lockedPiece(bind: true);
      await pumpStudio(tester, repository, project);
      final (topLeft, geo) = canvasHarness(tester, project);
      final center = topLeft + geo.sceneToCanvas(const Offset(360, 640));

      await dragSelectedPiece(tester, center, 30);

      expect(
        project.shapes.first.x,
        360,
        reason: 'la pièce portée par un os ne bouge pas au doigt',
      );
      expect(project.shapes.first.y, 640);
      expect(find.textContaining('transformations bloquées'), findsOneWidget);
      expect(project.shapes.first.keyframes, isEmpty);
    },
  );

  testWidgets('pièce liée : le tap au canvas ne la sélectionne pas', (
    tester,
  ) async {
    final repository = _MemoryRepository();
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final project = lockedPiece(bind: true);
    await pumpStudio(tester, repository, project);
    final (topLeft, geo) = canvasHarness(tester, project);
    final center = topLeft + geo.sceneToCanvas(const Offset(360, 640));

    // Piège : _load() AUTO-SÉLECTIONNE la dernière forme au chargement —
    // il faut d'abord désélectionner (sélection exclusive : un tap sur l'OS
    // désélectionne la pièce).
    final bonePoint = topLeft + geo.sceneToCanvas(const Offset(360, 190));
    await tester.tapAt(bonePoint);
    await tester.pumpAndSettle();
    expect(
      find.byTooltip('Propriétés de la forme'),
      findsNothing,
      reason: 'le tap sur l’os doit désélectionner la pièce',
    );

    // Tap sur la pièce : toujours pas sélectionnée + message explicatif.
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Propriétés de la forme'), findsNothing);
    expect(find.textContaining('non sélectionnable'), findsOneWidget);

    // Le SnackBar pèse en bas et recouvre la barre d'outils : le laisser se
    // fermer (4 s) avant d'utiliser le menu, sinon le tap tombe dessus.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // Passerelle : le panneau Éléments la choisit quand même (sheet + Délier).
    await selectPieceViaMenu(tester);
  });

  testWidgets('pièce liée sélectionnée : pincement et rotation bloqués', (
    tester,
  ) async {
    final repository = _MemoryRepository();
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final project = lockedPiece(bind: true);
    await pumpStudio(tester, repository, project);
    final (topLeft, geo) = canvasHarness(tester, project);
    final center = topLeft + geo.sceneToCanvas(const Offset(360, 640));
    await selectPieceViaMenu(tester);

    // Pincement 2 pointeurs : sans verrou, le bras scale s'applique sans
    // aucun hit test → l'échelle bougerait. Ici : rien.
    final left = await tester.startGesture(center - const Offset(60, 0));
    final right = await tester.startGesture(center + const Offset(60, 0));
    await left.moveBy(const Offset(-40, 0));
    await right.moveBy(const Offset(40, 0));
    await tester.pump();
    await left.up();
    await right.up();
    await tester.pumpAndSettle();
    expect(project.shapes.first.scale, 1.0);

    // Rotation via la POIGNÉE (position calculée comme l'appli : pose
    // rig-aware + bounds de la pièce) : la pièce ne pivote pas.
    final shape = project.shapes.first;
    final rig = project.skeleton!;
    final frame = SkeletonPose.evaluate(
      rig,
      0,
    ).frameOf(rig.boneIdForShape(shape.id));
    final pose = SelectionGeometry.shapePoseWithRig(shape, 0, frame);
    final bounds = ScenePainter.shapeBounds(shape, 0)!;
    final handle =
        topLeft + SelectionGeometry.rotationHandle(bounds, pose, geo);
    final grip = await tester.startGesture(handle);
    await grip.moveBy(const Offset(40, 0));
    await tester.pump();
    await grip.up();
    await tester.pumpAndSettle();
    expect(shape.rotation, 0.0);
    expect(shape.scale, 1.0);
    expect(find.textContaining('transformations bloquées'), findsOneWidget);
  });

  testWidgets('forme NON liée : le glisser la déplace (témoin)', (
    tester,
  ) async {
    final repository = _MemoryRepository();
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final project = lockedPiece(bind: false);
    await pumpStudio(tester, repository, project);
    final (topLeft, geo) = canvasHarness(tester, project);
    final center = topLeft + geo.sceneToCanvas(const Offset(360, 640));

    await dragSelectedPiece(tester, center, 30);

    expect(
      project.shapes.first.x,
      greaterThan(360),
      reason: 'une pièce libre se déplace normalement',
    );
    expect(find.textContaining('est liée à'), findsNothing);
  });

  // ------------------------------------------- v0.20 : parcours os/forme

  testWidgets('sheet ⚙ : « Ajouter un os… » prévient des keyframes effacées', (
    tester,
  ) async {
    final repository = _MemoryRepository();
    final project = AnimationProject.blank(
      name: 'Film',
      type: ProjectType.skeleton,
    );
    project.width = 720;
    project.height = 1280;
    final shape = VectorShape(name: 'Bloc', x: 360, y: 640);
    shape.layers.add(
      ShapeLayer(name: 'L', kind: ShapeKind.rect, width: 300, height: 200),
    );
    project.shapes.add(shape);
    // 2 keyframes de TRANSFORM (seront effacées) + morph sur la 2ᵉ.
    final pose = shape.poseAt(0);
    shape.setKeyframes(<ShapeKeyframe>[
      ShapeKeyframe(
        timeMs: 0,
        values: Map<AnimatableProperty, double>.from(pose),
      ),
      ShapeKeyframe(
        timeMs: 800,
        values: <AnimatableProperty, double>{
          ...pose,
          AnimatableProperty.x: 500,
        },
        layerPoints: <String, List<Offset>>{
          shape.layers.first.id: const <Offset>[Offset(0, 0), Offset(30, 10)],
        },
      ),
    ]);
    project.skeleton = SkeletonRig(name: 'Squelette');

    await pumpStudio(tester, repository, project);
    // La pièce est auto-sélectionnée au chargement → bouton ⚙ visible.
    await tester.tap(find.byTooltip('Propriétés de la forme'));
    await tester.pumpAndSettle();
    expect(find.text('Ajouter un os…'), findsOneWidget);

    await tester.tap(find.text('Ajouter un os…'));
    await tester.pumpAndSettle();
    // Confirmation AVANT l'effacement (2 transformations keyframées).
    expect(find.text('Lier la pièce à un os ?'), findsOneWidget);
    expect(find.textContaining('2 transformation'), findsOneWidget);
    expect(find.textContaining('conservées'), findsOneWidget);

    // Annuler : ni éditeur, ni effacement.
    await tester.tap(find.widgetWithText(TextButton, 'Annuler'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Os de « Bloc »'), findsNothing);
    expect(shape.keyframes, hasLength(2));
    expect(project.skeleton!.bones, isEmpty);
  });

  testWidgets('sheet ⚙ : « Supprimer l’os » efface os, keyframes et lien', (
    tester,
  ) async {
    final repository = _MemoryRepository();
    final project = AnimationProject.blank(
      name: 'Film',
      type: ProjectType.skeleton,
    );
    project.width = 720;
    project.height = 1280;
    final shape = VectorShape(name: 'Bloc', x: 360, y: 640);
    shape.layers.add(
      ShapeLayer(name: 'L', kind: ShapeKind.rect, width: 300, height: 200),
    );
    project.shapes.add(shape);
    final rig = SkeletonRig(name: 'Squelette');
    final root = RigBone(name: 'Tronc', offsetX: 360, offsetY: 500, length: 90);
    final child = RigBone(
      name: 'Bras',
      parentId: root.id,
      offsetX: 90,
      offsetY: 0,
      length: 70,
    );
    rig.addBone(root);
    rig.addBone(child);
    rig.bindShape(shape.id, root.id);
    rig.tracks[root.id] = <BoneKeyframe>[
      BoneKeyframe(timeMs: 0),
      BoneKeyframe(timeMs: 1000),
    ];
    rig.tracks[child.id] = <BoneKeyframe>[BoneKeyframe(timeMs: 500)];
    project.skeleton = rig;

    await pumpStudio(tester, repository, project);
    await tester.tap(find.byTooltip('Propriétés de la forme'));
    await tester.pumpAndSettle();
    expect(find.text('Os « Tronc »'), findsOneWidget);
    expect(find.text('Supprimer l’os'), findsOneWidget);

    await tester.tap(find.text('Supprimer l’os'));
    await tester.pumpAndSettle();
    // Confirmation : chaîne + total des keyframes annoncés.
    expect(find.text('Supprimer l’os ?'), findsOneWidget);
    expect(find.textContaining('2 os'), findsOneWidget);
    expect(find.textContaining('3 keyframes'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
    await tester.pumpAndSettle();
    expect(project.skeleton!.bones, isEmpty);
    expect(project.skeleton!.bindings, isEmpty);
    expect(project.skeleton!.tracks, isEmpty);
    expect(project.skeleton!.isAttached(shape.id), isFalse);
  });

  testWidgets('miroir H de la chaîne os apparaît dans la sheet et s’annule', (
    tester,
  ) async {
    final repository = _MemoryRepository();
    final project = AnimationProject.blank(
      name: 'Film',
      type: ProjectType.skeleton,
    );
    project.width = 720;
    project.height = 1280;
    final shape = VectorShape(name: 'Bloc', x: 360, y: 640);
    shape.layers.add(ShapeLayer(name: 'L', kind: ShapeKind.rect));
    shape.upsertKeyframe(0, shape.poseAt(0));
    shape.upsertKeyframe(1000, <AnimatableProperty, double>{
      ...shape.poseAt(0),
      AnimatableProperty.x: 420,
      AnimatableProperty.rotation: 0.6,
    });
    project.shapes.add(shape);
    final rig = SkeletonRig();
    final root = RigBone(
      id: 'root',
      name: 'Racine',
      offsetX: 350,
      offsetY: 500,
      restAngle: 0.2,
      length: 240,
    );
    final child = RigBone(
      id: 'child',
      name: 'Enfant',
      parentId: root.id,
      offsetX: 240,
      offsetY: 0,
      restAngle: 0.4,
      length: 60,
    );
    rig.bones.addAll(<RigBone>[root, child]);
    rig.bindShape(shape.id, root.id);
    rig.tracks[root.id] = <BoneKeyframe>[
      BoneKeyframe(timeMs: 0, angleDelta: 0.1),
      BoneKeyframe(timeMs: 1000, angleDelta: 0.5),
    ];
    rig.tracks[child.id] = <BoneKeyframe>[
      BoneKeyframe(timeMs: 0, angleDelta: -0.2),
      BoneKeyframe(timeMs: 1000, angleDelta: 0.3),
    ];
    project.skeleton = rig;
    await pumpStudio(tester, repository, project);
    final rootBefore = root.toJson();
    final childBefore = child.toJson();
    final tracksBefore = rig.toJson()['tracks'];
    final shapeBefore = shape.toJson();

    final (topLeft, geo) = canvasHarness(tester, project);
    await tester.tapAt(topLeft + geo.sceneToCanvas(const Offset(360, 502)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Propriétés de l’os'));
    await tester.pumpAndSettle();
    expect(find.text('Miroir H'), findsOneWidget);
    expect(find.text('Miroir V'), findsOneWidget);

    final pieceFrame = SkeletonPose.evaluate(rig, 0).frameOf(root.id)!;
    final pivot = SelectionGeometry.shapePoseWithRig(
      shape,
      0,
      pieceFrame,
    ).origin;
    await tester.tap(find.text('Miroir H'));
    await tester.pumpAndSettle();
    final mirroredRoot = root.toJson();
    final mirroredChild = child.toJson();
    final mirroredTracks = rig.toJson()['tracks'];
    final mirroredShape = shape.toJson();
    expect(root.offsetX, closeTo(2 * pivot.dx - 350, 1e-6));
    expect(child.restAngle, closeTo(-0.4, 1e-6));
    expect(rig.tracks[root.id]![1].angleDelta, closeTo(-0.5, 1e-6));
    expect(rig.tracks[child.id]![1].angleDelta, closeTo(-0.3, 1e-6));
    expect(
      shape.keyframes[1].values[AnimatableProperty.x],
      closeTo(2 * pivot.dx - 420, 1e-6),
    );
    expect(
      shape.keyframes[1].values[AnimatableProperty.rotation],
      closeTo(-0.6, 1e-6),
    );

    // Le projet restauré est une copie JSON ; vérifier par identifiants et
    // comparer à la sauvegarde capturée après l'action pour contrôler qu'Undo
    // a bien changé l'état.
    // Fermer la bottom sheet avant d'appuyer sur Undo dans la playbar.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.undo).last);
    await tester.pumpAndSettle();
    final restored = await repository.load(project.id);
    expect(restored.skeleton!.boneById(root.id)!.toJson(), rootBefore);
    expect(restored.skeleton!.boneById(root.id)!.toJson(), isNot(mirroredRoot));
    expect(restored.skeleton!.boneById(child.id)!.toJson(), childBefore);
    expect(
      restored.skeleton!.boneById(child.id)!.toJson(),
      isNot(mirroredChild),
    );
    expect(restored.skeleton!.toJson()['tracks'], tracksBefore);
    expect(restored.skeleton!.toJson()['tracks'], isNot(mirroredTracks));
    expect(restored.shapeById(shape.id)!.toJson(), shapeBefore);
    expect(restored.shapeById(shape.id)!.toJson(), isNot(mirroredShape));
  });

  testWidgets('bugfix v0.20.1 : « Ajouter un os… » visible SANS rig', (
    tester,
  ) async {
    final repository = _MemoryRepository();
    final project = AnimationProject.blank(
      name: 'Film',
      type: ProjectType.skeleton,
    );
    project.width = 720;
    project.height = 1280;
    final shape = VectorShape(name: 'Bloc', x: 360, y: 640);
    shape.layers.add(
      ShapeLayer(name: 'L', kind: ShapeKind.rect, width: 300, height: 200),
    );
    project.shapes.add(shape);
    project.skeleton = null; // projet squelette NEUF : pas encore de rig

    await pumpStudio(tester, repository, project);
    expect(project.skeleton, isNull);

    // La pièce est auto-sélectionnée au chargement → sheet ⚙.
    await tester.tap(find.byTooltip('Propriétés de la forme'));
    await tester.pumpAndSettle();
    expect(
      find.text('Ajouter un os…'),
      findsOneWidget,
      reason: 'le bouton ne doit pas dépendre de l’existence du rig',
    );
    expect(find.text('Aucun os'), findsOneWidget);

    // Le flux ouvre directement l'éditeur (aucune keyframe → pas de
    // dialogue de confirmation) et le rig naît à la VALIDATION (✓).
    await tester.tap(find.text('Ajouter un os…'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Os de « Bloc »'), findsOneWidget);
    expect(project.skeleton, isNull);
  });

  testWidgets('sheet os : « Ouvrir l’éditeur d’os… » ouvre l’éditeur', (
    tester,
  ) async {
    final repository = _MemoryRepository();
    final project = AnimationProject.blank(
      name: 'Film',
      type: ProjectType.skeleton,
    );
    project.width = 720;
    project.height = 1280;
    final shape = VectorShape(name: 'Bloc', x: 360, y: 640);
    shape.layers.add(
      ShapeLayer(name: 'L', kind: ShapeKind.rect, width: 300, height: 200),
    );
    project.shapes.add(shape);
    final rig = SkeletonRig(name: 'Squelette');
    final root = RigBone(name: 'Tronc', offsetX: 360, offsetY: 500, length: 90);
    rig.addBone(root);
    rig.bindShape(shape.id, root.id);
    project.skeleton = rig;

    await pumpStudio(tester, repository, project);

    // Sélectionner l'os en tapant dessus (segment AU-DESSUS de la pièce :
    // y 500 vs pièce de 540 à 740 — pas d'ambiguïté).
    final (topLeft, geo) = canvasHarness(tester, project);
    await tester.tapAt(topLeft + geo.sceneToCanvas(const Offset(400, 500)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Propriétés de l’os'), findsOneWidget);

    // Feuille des propriétés de l'OS → bouton vers l'éditeur (v0.20.2).
    await tester.tap(find.byTooltip('Propriétés de l’os'));
    await tester.pumpAndSettle();
    expect(find.text('Ouvrir l’éditeur d’os…'), findsOneWidget);

    await tester.tap(find.text('Ouvrir l’éditeur d’os…'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Os de « Bloc »'), findsOneWidget);
    expect(find.textContaining('EXTRÉMITÉ'), findsOneWidget);
  });

  testWidgets(
    'un os lié à une forme masquée disparaît du preview et du keyframe',
    (tester) async {
      final repository = _MemoryRepository();
      final project = AnimationProject.blank(
        name: 'Rat',
        type: ProjectType.skeleton,
      );
      final piece = VectorShape(name: 'Bloc', startMs: 0, endMs: 1000);
      piece.layers.add(ShapeLayer(name: 'L', kind: ShapeKind.rect));
      project.shapes.add(piece);
      final rig = SkeletonRig();
      final bone = RigBone(
        name: 'Os lié',
        offsetX: 180,
        offsetY: 320,
        length: 50,
      );
      rig.addBone(bone);
      rig.bindShape(piece.id, bone.id);
      project.skeleton = rig;
      await pumpStudio(tester, repository, project);

      final (topLeft, geo) = canvasHarness(tester, project);
      await tester.tapAt(topLeft + geo.sceneToCanvas(const Offset(180, 320)));
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('Ajouter une keyframe d’angle à l’os au curseur'),
        findsOneWidget,
      );

      final timeline = tester.getRect(find.byType(TimelineView));
      await tester.tapAt(
        timeline.bottomLeft + Offset(timeline.width * 0.9, -2),
      );
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('Keyframe d’os indisponible hors du segment'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.diamond_outlined),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'sélectionner une autre forme dans la timeline désélectionne l’os',
    (tester) async {
      final repository = _MemoryRepository();
      final project = AnimationProject.blank(
        name: 'Rat',
        type: ProjectType.skeleton,
      );
      final linked = VectorShape(name: 'Liée', startMs: 0, endMs: 2000);
      linked.layers.add(ShapeLayer(name: 'Corps', kind: ShapeKind.rect));
      final free = VectorShape(name: 'Libre', startMs: 0, endMs: 2000);
      free.layers.add(ShapeLayer(name: 'Décor', kind: ShapeKind.circle));
      project.shapes.addAll(<VectorShape>[linked, free]);

      final rig = SkeletonRig();
      final bone = RigBone(name: 'Os lié');
      rig.addBone(bone);
      rig.bindShape(linked.id, bone.id);
      project.skeleton = rig;

      await pumpStudio(tester, repository, project);

      // Le segment lié sélectionne l'os, comme en v0.21.0.
      await tester.tap(find.text('Liée'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Propriétés de l’os'), findsOneWidget);
      expect(find.byTooltip('Propriétés de la forme'), findsNothing);

      // Une autre forme sélectionnée dans la timeline doit effacer la
      // sélection d'os et sélectionner la forme correspondante.
      await tester.tap(find.text('Libre'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Propriétés de l’os'), findsNothing);
      expect(find.byTooltip('Propriétés de la forme'), findsOneWidget);
    },
  );

  testWidgets('MP4 propose les résolutions et le GIF garde seulement le fps', (
    tester,
  ) async {
    final project = seededProject();
    await pumpStudio(tester, repository, project);

    await tester.tap(find.byTooltip('Export'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vidéo MP4 (H.264)'));
    await tester.pumpAndSettle();

    expect(find.text('Résolution vidéo'), findsOneWidget);
    expect(find.text('480p'), findsOneWidget);
    expect(find.text('720p'), findsOneWidget);
    expect(find.text('1080p'), findsOneWidget);
    expect(
      find.text('406×720 px · proportions du projet conservées'),
      findsOneWidget,
    );
    expect(find.text('30 fps'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Export'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GIF animé'));
    await tester.pumpAndSettle();
    expect(find.text('Résolution vidéo'), findsNothing);
    expect(find.text('12 fps'), findsOneWidget);
  });

  testWidgets(
    'messages Studio apparaissent en haut et disparaissent après 5 s',
    (tester) async {
      final project = lockedPiece(bind: true);
      await pumpStudio(tester, repository, project);
      final (topLeft, geo) = canvasHarness(tester, project);
      final bonePoint = topLeft + geo.sceneToCanvas(const Offset(360, 190));
      await tester.tapAt(bonePoint);
      await tester.pumpAndSettle();
      final center = topLeft + geo.sceneToCanvas(const Offset(360, 640));
      await tester.tapAt(center);
      await tester.pumpAndSettle();

      final message = find.byKey(const ValueKey<String>('keyform-top-message'));
      expect(message, findsOneWidget);
      expect(find.textContaining('non sélectionnable'), findsOneWidget);
      final banner = tester.getTopLeft(message);
      final scaffoldTop = tester.getTopLeft(find.byType(Scaffold).first);
      expect(banner.dy, greaterThanOrEqualTo(scaffoldTop.dy));
      expect(banner.dy, greaterThan(50));
      expect(banner.dy, lessThan(150));
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('keyform-top-message')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'lier un groupe squelette supprime toutes ses keyframes propres',
    (tester) async {
      final repository = _MemoryRepository();
      final host = AnimationProject.blank(
        name: 'Hôte',
        type: ProjectType.skeleton,
      );
      final group = VectorShape(
        name: 'Groupe importé',
        embeddedProjectId: 'source-id',
        embeddedWidth: 360,
        embeddedHeight: 640,
        embeddedIsSkeleton: true,
        startMs: 0,
        endMs: 4000,
      );
      group.upsertKeyframe(0, group.poseAt(0));
      group.upsertKeyframe(2000, <AnimatableProperty, double>{
        ...group.poseAt(2000),
        AnimatableProperty.x: 420,
      });
      host.shapes.add(group);
      host.skeleton = SkeletonRig(name: 'Hôte');

      await pumpStudio(tester, repository, host);
      await tester.tap(find.byTooltip('Propriétés de la forme'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajouter un os…'));
      await tester.pumpAndSettle();
      expect(find.text('Lier le groupe à un os ?'), findsOneWidget);
      expect(find.textContaining('2 keyframe(s) de groupe'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Ouvrir l’éditeur'));
      await tester.pumpAndSettle();

      final canvas = find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is ScenePainter,
      );
      final center = tester.getCenter(canvas);
      await tester.tapAt(center);
      await tester.pump();
      await tester.tapAt(center + const Offset(70, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Enregistrer l’os'));
      await tester.pumpAndSettle();

      expect(group.keyframes, isEmpty);
      expect(host.skeleton!.carrierBoneId(group.id), isNotNull);
      expect(find.byTooltip('Propriétés de l’os'), findsOneWidget);
    },
  );

  testWidgets('zoom du Studio est indépendant et plein écran désélectionne', (
    tester,
  ) async {
    final project = seededProject();
    await pumpStudio(tester, repository, project);

    final painterFinder = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is ScenePainter,
    );
    var painter =
        tester.widget<CustomPaint>(painterFinder).painter! as ScenePainter;
    expect(painter.previewZoom, 1);
    expect(painter.selectedShapeId, project.shapes.single.id);

    await tester.tap(find.byTooltip('Zoom avant du preview'));
    await tester.pump();
    painter =
        tester.widget<CustomPaint>(painterFinder).painter! as ScenePainter;
    expect(painter.previewZoom, closeTo(1.2, 0.0001));

    await tester.tap(find.byTooltip('Déplacer la vue'));
    await tester.pump();
    expect(
      find.byTooltip('Désactiver le déplacement de la vue'),
      findsOneWidget,
    );
    await tester.drag(find.byType(GestureDetector).first, const Offset(36, 24));
    await tester.pump();
    painter =
        tester.widget<CustomPaint>(painterFinder).painter! as ScenePainter;
    expect(painter.previewPan.dx, greaterThan(0));
    expect(painter.previewPan.dy, greaterThan(0));

    await tester.tap(find.byTooltip('Ajuster le preview'));
    await tester.pump();
    painter =
        tester.widget<CustomPaint>(painterFinder).painter! as ScenePainter;
    expect(painter.previewZoom, 1);
    expect(painter.previewPan, Offset.zero);

    await tester.tap(find.byTooltip('Plein écran'));
    await tester.pumpAndSettle();
    painter =
        tester.widget<CustomPaint>(painterFinder).painter! as ScenePainter;
    expect(painter.selectedShapeId, isNull);
    expect(find.byTooltip('Quitter le plein écran'), findsOneWidget);
    expect(find.byTooltip('Exporter'), findsNothing);

    await tester.tap(find.byTooltip('Quitter le plein écran'));
    await tester.pumpAndSettle();
    expect(find.text('Film'), findsOneWidget);
  });
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
