import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vector_anim_studio/data/project_repository.dart';
import 'package:vector_anim_studio/main.dart';
import 'package:vector_anim_studio/models/animation.dart';
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
      : super(
          factory: databaseFactoryFfiNoIsolate,
          databasePath: ':memory:',
        );

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

  testWidgets('l’écran principal affiche l’état vide et le bouton nouveau projet', (
    tester,
  ) async {
    await tester.pumpWidget(VectorAnimStudioApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.text('Vector Anim Studio'), findsOneWidget);
    // Bouton de l'état vide + bouton flottant.
    expect(find.text('Nouveau projet'), findsNWidgets(2));
    expect(find.text('Aucun projet pour l’instant'), findsOneWidget);
  });

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
        find.widgetWithIcon(IconButton, Icons.undo).last);

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
        find.widgetWithIcon(IconButton, Icons.undo).last);

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
}
