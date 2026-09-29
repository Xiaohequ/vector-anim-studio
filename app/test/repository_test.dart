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
    // v0.13.2 : facteurs d'axe + pivot de rotation doivent survivre à la DB.
    shape.scaleX = 0.8;
    shape.scaleY = 1.2;
    shape.pivotDx = -120;
    shape.pivotDy = 15;
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
      ShapeKeyframe(
        timeMs: 2000,
        easing: EasingKind.customBezier,
        bezier: const <double>[0.34, 1.56, 0.64, 1.0],
        values: <AnimatableProperty, double>{
          ...pose,
          AnimatableProperty.opacity: 1,
          AnimatableProperty.scale: 1.5,
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
    // Durée dérivée : dernière keyframe (2000 ms).
    expect(loaded.durationMs, 2000);
    expect(loaded.fps, 24);
    expect(loaded.shapes.length, 1);

    final loadedShape = loaded.shapes.first;
    expect(loadedShape.name, 'Étoile');
    expect(loadedShape.spanStartMs, 200);
    expect(loadedShape.spanEndMs, 2000);
    expect(loadedShape.layers.length, 2);
    expect(loadedShape.layers.first.kind, ShapeKind.path);
    expect(loadedShape.layers.first.points.length, 3);
    expect(loadedShape.layers.first.points.first, const Offset(0, 0));
    expect(loadedShape.layers[1].filled, isFalse);

    // v0.13.2 : le pivot + les facteurs d'axe ne sont plus perdus en DB
    // (v0.13.0 : la porte tournait autour du centre après rechargement).
    expect(loadedShape.scaleX, 0.8);
    expect(loadedShape.scaleY, 1.2);
    expect(loadedShape.pivotDx, -120);
    expect(loadedShape.pivotDy, 15);

    expect(loadedShape.keyframes.length, 3);
    expect(loadedShape.keyframes.first.timeMs, 200);
    expect(loadedShape.keyframes.first.easing, EasingKind.easeOut);
    // cubic-bezier : les 4 paramètres survivent au round-trip (v0.13.0 les
    // perdait → overshoot mort après rechargement).
    expect(loadedShape.keyframes[2].easing, EasingKind.customBezier);
    expect(loadedShape.keyframes[2].bezier, const <double>[
      0.34,
      1.56,
      0.64,
      1.0,
    ]);
    expect(loadedShape.valueAt(AnimatableProperty.opacity, 1200), 1);
    expect(
      loadedShape.valueAt(AnimatableProperty.opacity, 700),
      closeTo(0.5, 0.01),
    );

    // v0.15 : couleur animée + morph de points doivent survivre à la DB
    // (leçon v0.13.2 : un champ de modèle sans colonne meurt au rechargement).
    shape.keyframes.first.layerColors[shape.layers.first.id] = 0xFFFF0000;
    shape.keyframes[1].layerColors[shape.layers.first.id] = 0xFF00FF00;
    shape.keyframes.first.layerPoints[shape.layers.first.id] = const <Offset>[
      Offset(1, 2),
      Offset(3, 4),
      Offset(5, 6),
    ];
    await repository.save(project);
    final reloaded = await repository.load(project.id);
    final reloadedShape = reloaded.shapes.first;
    expect(
      reloadedShape.keyframes.first.layerColors[reloadedShape.layers.first.id],
      0xFFFF0000,
    );
    expect(
      reloadedShape.keyframes[1].layerColors[reloadedShape.layers.first.id],
      0xFF00FF00,
    );
    expect(
      reloadedShape.keyframes.first.layerPoints[reloadedShape.layers.first.id],
      const <Offset>[Offset(1, 2), Offset(3, 4), Offset(5, 6)],
    );
    // Interpolation couleur reconstruite depuis la DB (easeInOut à mi-course).
    expect(
      reloadedShape.colorAtLayer(
        reloadedShape.layers.first.id,
        700,
        0xFF000000,
      ),
      0xFF808000,
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
      y: 250
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
    // v0.15 : la translation keyframée d'os vit dans le JSON du rig.
    expect(
      loadedRig.translationAt(bone.id, 1400),
      Offset.zero,
      reason: 'repos sans move posé',
    );

    // La duplication emporte le rig avec un id de projet différent.
    final copy = await repository.duplicate(project.id);
    expect(copy.type, ProjectType.skeleton);
    expect(copy.skeleton!.name, 'Rig test');
    expect(copy.skeleton!.bones.single.id, bone.id);
    expect(copy.id, isNot(project.id));
  });

  test('la translation keyframée d os survit à la DB (v0.15)', () async {
    final project = AnimationProject.blank(
      name: 'Rig glissé',
      type: ProjectType.skeleton,
    );
    final rig = SkeletonRig();
    final bone = RigBone(name: 'Slide', offsetX: 100, offsetY: 100, length: 60);
    rig.addBone(bone);
    rig.upsertKeyframe(bone.id, 0, 0, easing: EasingKind.linear);
    rig.upsertKeyframe(
      bone.id,
      1200,
      0.2,
      easing: EasingKind.linear,
      tx: 12,
      ty: -5,
    );
    project.skeleton = rig;

    await repository.save(project);
    final loaded = await repository.load(project.id);
    final loadedRig = loaded.skeleton!;
    expect(loadedRig.translationAt(bone.id, 0), Offset.zero);
    expect(loadedRig.translationAt(bone.id, 1200), const Offset(12, -5));
    // FK reconstruit : le joint glisse, la pose de repos reste en place.
    expect(
      SkeletonPose.evaluate(loadedRig, 1200).frameOf(bone.id)!.joint,
      const Offset(112, 95),
    );
    expect(
      SkeletonPose.evaluate(loadedRig, 0).frameOf(bone.id)!.joint,
      const Offset(100, 100),
    );
  });

  test('les projets vectoriels créés avant la v4 restent vectoriels', () async {
    final project = AnimationProject.blank(name: 'Ancien');
    await repository.save(project);
    final loaded = await repository.load(project.id);
    expect(loaded.type, ProjectType.vector);
    expect(loaded.isSkeleton, isFalse);
  });
}
