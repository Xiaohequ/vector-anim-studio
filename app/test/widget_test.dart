import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vector_anim_studio/data/project_repository.dart';
import 'package:vector_anim_studio/main.dart';
import 'package:vector_anim_studio/models/animation.dart';

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
}
