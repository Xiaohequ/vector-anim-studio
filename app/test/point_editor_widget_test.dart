import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_anim_studio/engine/scene_painter.dart';
import 'package:vector_anim_studio/engine/selection_geometry.dart';
import 'package:vector_anim_studio/models/animation.dart';
import 'package:vector_anim_studio/ui/shape_editor_screen.dart';

/// Hôte de test : pousse l'éditeur de forme puis capture le brouillon
/// renvoyé à l'enregistrement (le Navigator ne peut pas fermer la route
/// racine — l'éditeur doit être poussé, pas être `home`).
class _Host extends StatefulWidget {
  const _Host({required this.project, this.shape, this.onSaved});

  final AnimationProject project;
  final VectorShape? shape;
  final ValueChanged<VectorShape?>? onSaved;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context)
          .push<VectorShape>(
            MaterialPageRoute<VectorShape>(
              builder: (_) => ShapeEditorScreen(
                project: widget.project,
                shape: widget.shape,
              ),
            ),
          )
          .then((value) => widget.onSaved?.call(value));
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox());
}

AnimationProject _project() => AnimationProject(
  name: 'P',
  width: 360,
  height: 640,
  fps: 25,
  backgroundValue: 0xFF14161C,
);

VectorShape _pathShape({required bool withKeyframes}) {
  final shape = VectorShape(name: 'S', x: 180, y: 320);
  shape.layers.add(
    ShapeLayer(
      name: 'L',
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
  if (withKeyframes) {
    shape.upsertKeyframe(0, shape.poseAt(0), easing: EasingKind.linear);
    shape.upsertKeyframe(4000, shape.poseAt(4000), easing: EasingKind.linear);
  }
  return shape;
}

/// Positions écran des poignées — le MÊME calcul que le painter (taille
/// réelle du preview mesurée dans l'arbre de test, projet de même format).
List<Offset> _handlePositions(
  WidgetTester tester,
  AnimationProject project,
  VectorShape shape,
) {
  final size = tester.getSize(_previewCanvas());
  final geo = SceneGeometry.fitFor(project, size);
  final layer = shape.layers.first;
  final cloud = shape.pointsAtLayer(layer.id, layer.points, 0);
  return SelectionGeometry.pointHandlePositions(
    cloud,
    layer,
    SelectionGeometry.layerPose(shape, layer, 0),
    geo,
  );
}

/// Preview-local → coordonnées GLOBALES de surface (tester.startGesture et
/// tapAt travaillent en global ; les DELTAS restent identiques par
/// translation).
Offset _global(WidgetTester tester, Offset local) =>
    tester.getTopLeft(_previewCanvas()) + local;

/// Le CustomPaint du preview (le SEUL ScenePainter de l'arbre) — son cadre
/// EST le repère canvas des poignées. `find.byType(Listener).first` ne
/// convient pas : le premier Listener de l'arbre est un interne Material
/// (plein écran), pas le preview.
Finder _previewCanvas() => find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is ScenePainter,
);

void main() {
  testWidgets('glisser une poignée auto-key le nuage sur la pose au curseur', (
    tester,
  ) async {
    final project = _project();
    final shape = _pathShape(withKeyframes: true);
    final layer = shape.layers.first;
    final base = List<Offset>.from(layer.points);
    VectorShape? saved;

    await tester.pumpWidget(
      MaterialApp(
        home: _Host(
          project: project,
          shape: shape,
          onSaved: (value) => saved = value,
        ),
      ),
    );
    await tester.pumpAndSettle(); // route de l'éditeur poussée et posée
    final handles = _handlePositions(tester, project, shape);
    expect(handles, hasLength(4));

    // Reconnaissance du geste : le premier déplacement (~50 px) déclenche
    // onScaleStart avec le foyer DÉJÀ déplacé (piège connu) — le hit des
    // poignées se fait sur la position brute du doigt.
    final gesture = await tester.startGesture(_global(tester, handles[1]));
    await gesture.moveBy(const Offset(40, -30));
    await gesture.moveBy(const Offset(10, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    // Delta local exact = différence des conversions des deux foyers.
    final previewSize = tester.getSize(_previewCanvas());
    final geo = SceneGeometry.fitFor(project, previewSize);
    final pose = SelectionGeometry.layerPose(shape, layer, 0);
    final delta =
        SelectionGeometry.canvasToLocal(
          handles[1] + const Offset(50, -30),
          pose,
          geo,
        ) -
        SelectionGeometry.canvasToLocal(
          handles[1] + const Offset(40, -30),
          pose,
          geo,
        );

    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    final entry = saved!.keyframes.first.layerPoints[saved!.layers.first.id]!;
    expect(entry, hasLength(4));
    expect(entry[1].dx, closeTo(base[1].dx + delta.dx, 0.001));
    expect(entry[1].dy, closeTo(base[1].dy + delta.dy, 0.001));
    // La base n'a pas bougé (la forme est animée → auto-key).
    expect(saved!.layers.first.points[1], base[1]);
    // Pas de keyframe supplémentaire (le curseur est sur la pose 0).
    expect(saved!.keyframes, hasLength(2));
  });

  testWidgets('sans keyframe : le glisser écrit la base (géométrie)', (
    tester,
  ) async {
    final project = _project();
    final shape = _pathShape(withKeyframes: false);
    final base = List<Offset>.from(shape.layers.first.points);
    VectorShape? saved;

    await tester.pumpWidget(
      MaterialApp(
        home: _Host(
          project: project,
          shape: shape,
          onSaved: (value) => saved = value,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final handles = _handlePositions(tester, project, shape);

    final gesture = await tester.startGesture(_global(tester, handles[3]));
    await gesture.moveBy(const Offset(40, 0));
    await gesture.moveBy(const Offset(30, 40));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final scale = SceneGeometry.fitFor(
      project,
      tester.getSize(_previewCanvas()),
    ).scale;
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    final points = saved!.layers.first.points;
    expect(points, hasLength(4));
    // Le point 3 a bougé en local ; les autres sont intacts.
    expect(points[0], base[0]);
    expect(points[1], base[1]);
    expect(points[2], base[2]);
    expect(points[3], isNot(base[3]));
    expect(points[3].dx, closeTo(base[3].dx + 30 / scale, 0.001));
    expect(points[3].dy, closeTo(base[3].dy + 40 / scale, 0.001));
  });

  testWidgets('appui long sur une poignée supprime le point', (tester) async {
    final project = _project();
    final shape = _pathShape(withKeyframes: true);
    // La pose 0 porte le nuage de base : la suppression s'aligne partout.
    shape.keyframes.first.layerPoints[shape.layers.first.id] =
        List<Offset>.from(shape.layers.first.points);
    VectorShape? saved;

    await tester.pumpWidget(
      MaterialApp(
        home: _Host(
          project: project,
          shape: shape,
          onSaved: (value) => saved = value,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final handles = _handlePositions(tester, project, shape);

    final gesture = await tester.startGesture(_global(tester, handles[2]));
    await tester.pump(const Duration(milliseconds: 700)); // kLongPressTimeout
    await gesture.up();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!.layers.first.points, hasLength(3));
    expect(
      saved!.keyframes.first.layerPoints[saved!.layers.first.id],
      hasLength(3),
    );
  });

  testWidgets('mode ✚ : toucher un segment ajoute un point partout', (
    tester,
  ) async {
    final project = _project();
    final shape = _pathShape(withKeyframes: true);
    shape.keyframes.first.layerPoints[shape.layers.first.id] =
        List<Offset>.from(shape.layers.first.points);
    VectorShape? saved;

    await tester.pumpWidget(
      MaterialApp(
        home: _Host(
          project: project,
          shape: shape,
          onSaved: (value) => saved = value,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final handles = _handlePositions(tester, project, shape);

    await tester.tap(
      find.byTooltip('Ajouter un point — touche un segment du chemin'),
    );
    await tester.pump();
    // Milieu du segment (0 → 1) : distance ~0.
    final midGlobal =
        tester.getTopLeft(_previewCanvas()) +
        Offset(
          (handles[0].dx + handles[1].dx) / 2,
          (handles[0].dy + handles[1].dy) / 2 + 4,
        );
    await tester.tapAt(midGlobal);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!.layers.first.points, hasLength(5));
    // Le point inséré est à l'index 1 (après le départ du segment 0→1).
    expect(
      saved!.keyframes.first.layerPoints[saved!.layers.first.id],
      hasLength(5),
    );
  });

  testWidgets('légende des points visible pour une couche Chemin', (
    tester,
  ) async {
    final project = _project();
    final shape = _pathShape(withKeyframes: false);
    await tester.pumpWidget(
      MaterialApp(
        home: _Host(project: project, shape: shape),
      ),
    );
    await tester.pumpAndSettle();
    // Vectoriel sans keyframe : l'aide dit que l'on dessine la base.
    expect(find.textContaining('tu dessines la base'), findsOneWidget);
  });

  testWidgets(
    'pièce squelette sans keyframe : le 1ᵉʳ glisser crée la pose (base intacte)',
    (tester) async {
      // Bugfix v0.16.2 : en projet squelette, le premier glisser de point
      // CRÉE la première pose au lieu d'éditer la base en silence.
      final project = AnimationProject(
        name: 'Rig',
        type: ProjectType.skeleton,
        width: 360,
        height: 640,
      );
      final shape = _pathShape(withKeyframes: false);
      final layer = shape.layers.first;
      final base = List<Offset>.from(layer.points);
      VectorShape? saved;

      await tester.pumpWidget(
        MaterialApp(
          home: _Host(
            project: project,
            shape: shape,
            onSaved: (v) => saved = v,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final handles = _handlePositions(tester, project, shape);

      final gesture = await tester.startGesture(_global(tester, handles[1]));
      await gesture.moveBy(const Offset(40, -30));
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      // La première pose a été CRÉÉE au curseur (0 s).
      expect(saved!.keyframes, hasLength(1));
      final entry = saved!.keyframes.single.layerPoints[saved!.layers.first.id];
      expect(entry, isNotNull);
      expect(entry, hasLength(4));
      expect(entry![1], isNot(equals(base[1])));
      // La base n'a PAS bougé (l'écriture est allée dans la pose).
      expect(saved!.layers.first.points[1], base[1]);
    },
  );

  testWidgets('le ◆ de l’éditeur crée une keyframe au curseur', (tester) async {
    final project = _project();
    final shape = _pathShape(withKeyframes: false);
    VectorShape? saved;

    await tester.pumpWidget(
      MaterialApp(
        home: _Host(project: project, shape: shape, onSaved: (v) => saved = v),
      ),
    );
    await tester.pumpAndSettle();

    // ◆ au curseur (0 s) : la pose est créée dans le brouillon.
    await tester.tap(find.byTooltip('Ajouter une keyframe au curseur'));
    await tester.pumpAndSettle();
    // Le losange devient plein (tooltip inversé).
    expect(find.byTooltip('Retirer la keyframe au curseur'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!.keyframes.map((k) => k.timeMs), <int>[0]);
  });

  testWidgets('le ◆ de l’éditeur retire la keyframe au curseur', (
    tester,
  ) async {
    final project = _project();
    final shape = _pathShape(withKeyframes: false);
    shape.addKeyframeAt(0);
    VectorShape? saved;

    await tester.pumpWidget(
      MaterialApp(
        home: _Host(project: project, shape: shape, onSaved: (v) => saved = v),
      ),
    );
    await tester.pumpAndSettle();

    // Le curseur démarre sur la pose (0 s) : tooltip « Retirer ».
    await tester.tap(find.byTooltip('Retirer la keyframe au curseur'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!.keyframes, isEmpty);
  });
}
