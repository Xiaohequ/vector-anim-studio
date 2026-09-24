import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_anim_studio/engine/selection_geometry.dart';
import 'package:vector_anim_studio/models/animation.dart';

AnimationProject _project() => AnimationProject(width: 360, height: 640);

/// Forme simple : une couche rectangulaire 110×50 centrée sur l'origine.
VectorShape _shape({double rotation = 0, double scale = 1}) => VectorShape(
  name: 'Test',
  x: 180,
  y: 320,
  rotation: rotation,
  scale: scale,
  layers: <ShapeLayer>[
    ShapeLayer(name: 'L', kind: ShapeKind.rect, width: 110, height: 50),
  ],
);

/// Rect local de la forme de test, gonflé de 6 comme la sélection.
Rect _bounds() => Rect.fromLTRB(-61, -31, 61, 31);

void main() {
  group('SceneGeometry', () {
    test('fit exact quand le canvas a le ratio du projet', () {
      final geo = SceneGeometry.fitFor(_project(), const Size(360, 640));
      expect(geo.scale, 1);
      expect(geo.dx, 0);
      expect(geo.dy, 0);
    });

    test('letterbox horizontal : scène centrée', () {
      final geo = SceneGeometry.fitFor(_project(), const Size(720, 640));
      expect(geo.scale, 1);
      expect(geo.dx, 180);
      expect(geo.dy, 0);
    });

    test('aller-retour scène ↔ canvas', () {
      final geo = SceneGeometry.fitFor(_project(), const Size(500, 700));
      final scene = const Offset(123, 456);
      final back = geo.canvasToScene(geo.sceneToCanvas(scene));
      expect(back.dx, closeTo(scene.dx, 0.001));
      expect(back.dy, closeTo(scene.dy, 0.001));
    });
  });

  group('Poses', () {
    test('shapePose lit les valeurs de base', () {
      final pose = SelectionGeometry.shapePose(_shape(), 0);
      expect(pose.origin, const Offset(180, 320));
      expect(pose.rotation, 0);
      expect(pose.scale, 1);
    });

    test('layerPose compose forme ∘ couche (identité)', () {
      final layer = ShapeLayer(
        name: 'L',
        kind: ShapeKind.rect,
        x: 10,
        y: 20,
        width: 110,
        height: 50,
      );
      final pose = SelectionGeometry.layerPose(_shape(), layer, 0);
      expect(pose.origin, const Offset(190, 340));
      expect(pose.rotation, 0);
      expect(pose.scale, 1);
    });

    test('layerPose : rotation et échelle de la forme se composent', () {
      final shape = _shape(rotation: math.pi / 2, scale: 2);
      final layer = ShapeLayer(
        name: 'L',
        kind: ShapeKind.rect,
        x: 10,
        y: 20,
        width: 110,
        height: 50,
        rotation: 0.5,
        scale: 1.5,
      );
      final pose = SelectionGeometry.layerPose(shape, layer, 0);
      // R(90°) × (10, 20) = (-20, 10), fois l'échelle 2 → (-40, 20).
      expect(pose.origin, const Offset(180 - 40, 320 + 20));
      expect(pose.rotation, closeTo(math.pi / 2 + 0.5, 1e-9));
      expect(pose.scale, 3);
    });
  });

  group('SelectionGeometry', () {
    test('coins sans rotation', () {
      final geo = SceneGeometry.fitFor(_project(), const Size(360, 640));
      final corners = SelectionGeometry.corners(
        _bounds(),
        SelectionGeometry.shapePose(_shape(), 0),
        geo,
      );
      expect(corners[0], const Offset(180 - 61, 320 - 31)); // HG
      expect(corners[1], const Offset(180 + 61, 320 - 31)); // HD
      expect(corners[2], const Offset(180 + 61, 320 + 31)); // BD
      expect(corners[3], const Offset(180 - 61, 320 + 31)); // BG
    });

    test('coins pivotés de 90°', () {
      final geo = SceneGeometry.fitFor(_project(), const Size(360, 640));
      final corners = SelectionGeometry.corners(
        _bounds(),
        SelectionGeometry.shapePose(_shape(rotation: math.pi / 2), 0),
        geo,
      );
      // (-61,-31) tourné de 90° → (31,-61) ; (61,-31) → (31,61) ;
      // (61,31) → (-31,61).
      expect(corners[0], const Offset(180 + 31, 320 - 61));
      expect(corners[1], const Offset(180 + 31, 320 + 61));
      expect(corners[2], const Offset(180 - 31, 320 + 61));
    });

    test('poignée de rotation au-dessus du rectangle', () {
      final geo = SceneGeometry.fitFor(_project(), const Size(360, 640));
      final handle = SelectionGeometry.rotationHandle(
        _bounds(),
        SelectionGeometry.shapePose(_shape(), 0),
        geo,
      );
      expect(handle, const Offset(180, 320 - 31 - 30));
    });

    test('poignée de rotation suit la rotation de la forme', () {
      final geo = SceneGeometry.fitFor(_project(), const Size(360, 640));
      final handle = SelectionGeometry.rotationHandle(
        _bounds(),
        SelectionGeometry.shapePose(_shape(rotation: math.pi), 0),
        geo,
      );
      // Forme retournée : la poignée passe sous le rectangle.
      expect(handle.dy, greaterThan(320 + 31));
    });

    test('bouton propriétés au coin bas-gauche, en diagonale externe', () {
      final geo = SceneGeometry.fitFor(_project(), const Size(360, 640));
      final button = SelectionGeometry.propertiesButton(
        _bounds(),
        SelectionGeometry.shapePose(_shape(), 0),
        geo,
      );
      final bl = const Offset(180 - 61, 320 + 31);
      final outward = (bl - const Offset(180, 320));
      final expected = bl + (outward / outward.distance) * 26;
      expect(button.dx, closeTo(expected.dx, 0.01));
      expect(button.dy, closeTo(expected.dy, 0.01));
    });

    test('hit : centre touché, extérieur raté, marge écran constante', () {
      final geo = SceneGeometry.fitFor(_project(), const Size(360, 640));
      final pose = SelectionGeometry.shapePose(_shape(), 0);
      expect(
        SelectionGeometry.hit(_bounds(), pose, geo, const Offset(180, 320)),
        isTrue,
      );
      // 5 px écran à droite du bord (61) : dans la marge de 10 px.
      expect(
        SelectionGeometry.hit(
          _bounds(),
          pose,
          geo,
          const Offset(180 + 66, 320),
        ),
        isTrue,
      );
      // Loin : raté.
      expect(
        SelectionGeometry.hit(
          _bounds(),
          pose,
          geo,
          const Offset(180 + 120, 320),
        ),
        isFalse,
      );
    });

    test('hit suit la rotation de l\'objet', () {
      final geo = SceneGeometry.fitFor(_project(), const Size(360, 640));
      final pose = SelectionGeometry.shapePose(
        _shape(rotation: math.pi / 2),
        0,
      );
      // Le rect 220×62 devient vertical après rotation : point au-dessus → touché.
      expect(
        SelectionGeometry.hit(
          _bounds(),
          pose,
          geo,
          const Offset(180, 320 - 50),
        ),
        isTrue,
      );
      // Point à droite (horizontalement large) → raté maintenant.
      expect(
        SelectionGeometry.hit(
          _bounds(),
          pose,
          geo,
          const Offset(180 + 50, 320),
        ),
        isFalse,
      );
    });

    test('hit sur une couche via la pose composée', () {
      final geo = SceneGeometry.fitFor(_project(), const Size(360, 640));
      final shape = _shape();
      final layer = ShapeLayer(
        name: 'L',
        kind: ShapeKind.rect,
        x: 10,
        y: 20,
        width: 110,
        height: 50,
      );
      final pose = SelectionGeometry.layerPose(shape, layer, 0);
      expect(
        SelectionGeometry.hit(
          Rect.fromLTRB(-55, -55, 55, 55),
          pose,
          geo,
          const Offset(190, 340),
        ),
        isTrue,
      );
      expect(
        SelectionGeometry.hit(
          Rect.fromLTRB(-55, -55, 55, 55),
          pose,
          geo,
          const Offset(100, 250),
        ),
        isFalse,
      );
    });

    test('hitRotationHandle avec tolérance de toucher', () {
      final handle = const Offset(100, 100);
      expect(
        SelectionGeometry.hitRotationHandle(
          const Offset(100 + 25, 100),
          handle,
        ),
        isTrue,
      );
      expect(
        SelectionGeometry.hitRotationHandle(
          const Offset(100 + 40, 100),
          handle,
        ),
        isFalse,
      );
    });
  });
}
