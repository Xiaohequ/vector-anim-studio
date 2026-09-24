import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vector_anim_studio/data/project_repository.dart';
import 'package:vector_anim_studio/models/animation.dart';
import 'package:vector_anim_studio/models/skeleton.dart';

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
    );
    project.fps = 24;
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
    final pose = shape.poseAt(0);
    shape.setKeyframes(<ShapeKeyframe>[
      ShapeKeyframe(
        timeMs: 200,
        easing: EasingKind.easeOut,
        values: <AnimatableProperty, double>{
          ...pose,
          AnimatableProperty.opacity: 0,
        },
      ),
      ShapeKeyframe(
        timeMs: 1200,
        easing: EasingKind.linear,
        values: <AnimatableProperty, double>{
          ...pose,
          AnimatableProperty.opacity: 1,
        },
      ),
    ]);
    project.shapes.add(shape);

    await repository.save(project);
    final summaries = await repository.listSummaries();
    expect(summaries.length, 1);
    expect(summaries.first.name, 'Test enregistrement');
    expect(summaries.first.shapeCount, 1);

    final loaded = await repository.load(project.id);
    expect(loaded.name, project.name);
    // Durée dérivée : fin du dernier segment (2400 ms).
    expect(loaded.durationMs, 2400);
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

    expect(loadedShape.keyframes.length, 2);
    expect(loadedShape.keyframes.first.timeMs, 200);
    expect(loadedShape.keyframes.first.easing, EasingKind.easeOut);
    expect(loadedShape.valueAt(AnimatableProperty.opacity, 1200), 1);
    expect(
      loadedShape.valueAt(AnimatableProperty.opacity, 700),
      closeTo(0.5, 0.01),
    );
  });

  test(
    'une seconde sauvegarde remplace les formes sans les dupliquer',
    () async {
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
    },
  );

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
    expect(
      copy.shapes.first.layers.first.id,
      isNot(project.shapes.first.layers.first.id),
    );
    expect((await repository.listSummaries()).length, 2);

    await repository.rename(project.id, 'Renommé');
    expect(
      (await repository.listSummaries()).map((s) => s.name),
      contains('Renommé'),
    );

    await repository.delete(project.id);
    expect(await repository.listSummaries(), hasLength(1));
  });

  test('une instance d\'animation conserve sa référence imbriquée', () async {
    final project = AnimationProject.blank(name: 'Hôte');
    project.shapes.add(
      VectorShape(
        name: 'Instance',
        embeddedProjectId: 'source-123',
        embeddedWidth: 1080,
        embeddedHeight: 1920,
      ),
    );
    await repository.save(project);

    final loaded = await repository.load(project.id);
    final instance = loaded.shapes.single;
    expect(instance.isInstance, isTrue);
    expect(instance.embeddedProjectId, 'source-123');
    expect(instance.embeddedWidth, 1080);
    expect(instance.embeddedHeight, 1920);
  });

  test('un projet squelette persiste son rig (os, pistes, liaisons)', () async {
    final project = AnimationProject.blank(
      name: 'Rig rat',
      type: ProjectType.skeleton,
    );
    final piece = VectorShape(
      name: 'Corps',
      x: 150,
      y: 250,
      startMs: 0,
      endMs: 1000,
    );
    piece.layers.add(ShapeLayer(name: 'L', kind: ShapeKind.rect));
    project.shapes.add(piece);

    final rig = SkeletonRig(name: 'Rig test');
    final bone = RigBone(
      name: 'Torse',
      offsetX: 150,
      offsetY: 280,
      restAngle: 0,
      length: 60,
    );
    rig.addBone(bone);
    rig.bindShape(piece.id, bone.id);
    rig.upsertKeyframe(bone.id, 0, 0, easing: EasingKind.linear);
    rig.upsertKeyframe(bone.id, 1400, 0.9, easing: EasingKind.easeOut);
    project.skeleton = rig;

    await repository.save(project);
    final summaries = await repository.listSummaries();
    expect(summaries.single.type, ProjectType.skeleton);

    final loaded = await repository.load(project.id);
    expect(loaded.type, ProjectType.skeleton);
    // Plancher éditable de 4 s : les keyframes (1,4 s) sont en dessous.
    expect(loaded.durationMs, 4000);
    final loadedRig = loaded.skeleton!;
    expect(loadedRig.name, 'Rig test');
    expect(loadedRig.bones.single.name, 'Torse');
    expect(loadedRig.bones.single.length, 60);
    expect(loadedRig.boneIdForShape(piece.id), bone.id);
    expect(loadedRig.trackOf(bone.id)![1].angleDelta, closeTo(0.9, 1e-9));

    // La duplication emporte le rig avec un id de projet différent.
    final copy = await repository.duplicate(project.id);
    expect(copy.type, ProjectType.skeleton);
    expect(copy.skeleton!.name, 'Rig test');
    expect(copy.skeleton!.bones.single.id, bone.id);
    expect(copy.id, isNot(project.id));
  });

  test('les projets vectoriels créés avant la v4 restent vectoriels', () async {
    final project = AnimationProject.blank(name: 'Ancien');
    await repository.save(project);
    final loaded = await repository.load(project.id);
    expect(loaded.type, ProjectType.vector);
    expect(loaded.isSkeleton, isFalse);
  });
}
