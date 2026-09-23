import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vector_anim_studio/data/project_repository.dart';
import 'package:vector_anim_studio/models/animation.dart';

void main() {
  late Directory tmp;
  late ProjectRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('vector_anim_studio_test');
    repository = ProjectRepository(
      factory: databaseFactoryFfi,
      databasePath: p.join(tmp.path, 'test.db'),
    );
  });

  tearDown(() async {
    await repository.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('la base démarre vide', () async {
    expect(await repository.listSummaries(), isEmpty);
    expect(await repository.countProjects(), 0);
  });

  test('un projet se sauvegarde et se recharge à l’identique', () async {
    final project = AnimationProject.blank(
      name: 'Test enregistrement',
      format: ProjectFormat.portrait,
      durationMs: 3000,
      fps: 24,
    );
    final shape = VectorShape(
      name: 'Étoile',
      x: 120,
      y: 200,
      startMs: 200,
      endMs: 2400,
      layers: <ShapeLayer>[
        ShapeLayer(
          name: 'Chemin',
          kind: ShapeKind.path,
          points: const <Offset>[Offset(0, 0), Offset(40, 12), Offset(12, 30)],
          colorValue: 0xFFF2C94C,
        ),
        ShapeLayer(name: 'Cercle', kind: ShapeKind.circle, filled: false),
      ],
    );
    shape.tracks[AnimatableProperty.opacity] = AnimTrack(
      AnimatableProperty.opacity,
    )
      ..setKey(200, 0, easing: EasingKind.easeOut)
      ..setKey(1200, 1, easing: EasingKind.linear);
    project.shapes.add(shape);

    await repository.save(project);
    final summaries = await repository.listSummaries();
    expect(summaries.length, 1);
    expect(summaries.first.name, 'Test enregistrement');
    expect(summaries.first.shapeCount, 1);

    final loaded = await repository.load(project.id);
    expect(loaded.name, project.name);
    expect(loaded.durationMs, 3000);
    expect(loaded.fps, 24);
    expect(loaded.shapes.length, 1);

    final loadedShape = loaded.shapes.first;
    expect(loadedShape.name, 'Étoile');
    expect(loadedShape.startMs, 200);
    expect(loadedShape.endMs, 2400);
    expect(loadedShape.layers.length, 2);
    expect(loadedShape.layers.first.kind, ShapeKind.path);
    expect(loadedShape.layers.first.points.length, 3);
    expect(loadedShape.layers.first.points.first, const Offset(0, 0));
    expect(loadedShape.layers[1].filled, isFalse);

    final track = loadedShape.tracks[AnimatableProperty.opacity]!;
    expect(track.keys.length, 2);
    expect(track.keys.first.timeMs, 200);
    expect(track.keys.first.easing, EasingKind.easeOut);
    expect(track.sample(1200, 0), 1);
  });

  test('une seconde sauvegarde remplace les formes sans les dupliquer', () async {
    final project = AnimationProject.blank(name: 'Remplacement');
    project.shapes.add(
      VectorShape(
        name: 'Forme',
        layers: <ShapeLayer>[ShapeLayer(name: 'Rect', kind: ShapeKind.rect)],
      ),
    );
    await repository.save(project);
    project.shapes.first.name = 'Forme renommée';
    await repository.save(project);

    final loaded = await repository.load(project.id);
    expect(loaded.shapes.length, 1);
    expect(loaded.shapes.first.name, 'Forme renommée');
  });

  test('suppression et duplication', () async {
    final project = AnimationProject.blank(name: 'Source');
    project.shapes.add(
      VectorShape(
        name: 'Forme',
        layers: <ShapeLayer>[ShapeLayer(name: 'Rect', kind: ShapeKind.rect)],
      ),
    );
    await repository.save(project);

    final copy = await repository.duplicate(project.id);
    expect(copy.name, 'Source (copie)');
    expect(copy.shapes.first.id, isNot(project.shapes.first.id));
    expect(copy.shapes.first.layers.first.id, isNot(project.shapes.first.layers.first.id));
    expect((await repository.listSummaries()).length, 2);

    await repository.rename(project.id, 'Renommé');
    expect(
      (await repository.listSummaries()).map((s) => s.name),
      contains('Renommé'),
    );

    await repository.delete(project.id);
    expect(await repository.listSummaries(), hasLength(1));
  });
}
