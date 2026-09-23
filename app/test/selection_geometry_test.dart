import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_anim_studio/engine/selection_geometry.dart';
import 'package:vector_anim_studio/models/animation.dart';

AnimationProject _project() => AnimationProject(width: 360, height: 640);

/// Forme simple : une couche rectangulaire 110×50 centrée sur l'origine.
VectorShape _shape({
  double rotation = 0,
  double scale = 1,
}) =>
    VectorShape(
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

  group('SelectionGeometry', () {
    test('coins sans rotation', () {
      final geo = SceneGeometry.fitFor(_project(), const Size(360, 640));
      final corners = SelectionGeometry.cornersCanvas(
          _bounds(), _shape(), 0, geo);
      expect(corners[0], const Offset(180 - 61, 320 - 31)); // HG
      expect(corners[1], const Offset(180 + 61, 320 - 31)); // HD
      expect(corners[2], const Offset(180 + 61, 320 + 31)); // BD
      expect(corners[3], const Offset(180 - 61, 320 + 31)); // BG
    });

    test('coins pivotés de 90°', () {
      final geo = SceneGeometry.fitFor(_project(), const Size(360, 640));
      final corners = SelectionGeometry.cornersCanvas(
          _bounds(), _shape(rotation: math.pi / 2), 0, geo);
      // (-61,-31) tourné de 90° → (31,-61) ; (61,-31) → (31,61) ;
      // (61,31) → (-31,61).
      expect(corners[0], const Offset(180 + 31, 320 - 61));
      expect(corners[1], const Offset(180 + 31, 320 + 61));
      expect(corners[2], const Offset(180 - 31, 320 + 61));
    });

    test('poignée de rotation au-dessus du rectangle', () {
      final geo = SceneGeometry.fitFor(_project(), const Size(360, 640));
      final handle = SelectionGeometry.rotationHandleCanvas(
          _bounds(), _shape(), 0, geo);
      expect(handle, const Offset(180, 320 - 31 - 30));
    });

    test('poignée de rotation suit la rotation de la forme', () {
      final geo = SceneGeometry.fitFor(_project(), const Size(360, 640));
      final handle = SelectionGeometry.rotationHandleCanvas(
          _bounds(), _shape(rotation: math.pi), 0, geo);
      // Forme retournée : la poignée passe sous le rectangle.
      expect(handle.dy, greaterThan(320 + 31));
    });

    test('bouton propriétés au coin bas-gauche, en diagonale externe', () {
      final geo = SceneGeometry.fitFor(_project(), const Size(360, 640));
      final button = SelectionGeometry.propertiesButtonCanvas(
          _bounds(), _shape(), 0, geo);
      final bl = const Offset(180 - 61, 320 + 31);
      final outward = (bl - const Offset(180, 320));
      final expected = bl + (outward / outward.distance) * 26;
      expect(button.dx, closeTo(expected.dx, 0.01));
      expect(button.dy, closeTo(expected.dy, 0.01));
    });

    test('hitShape : centre touché, extérieur raté, marge écran constante', () {
      final geo = SceneGeometry.fitFor(_project(), const Size(360, 640));
      final shape = _shape();
      expect(
        SelectionGeometry.hitShape(_bounds(), shape, 0, geo,
            const Offset(180, 320)),
        isTrue,
      );
      // 5 px écran à droite du bord (61) : dans la marge de 10 px.
      expect(
        SelectionGeometry.hitShape(_bounds(), shape, 0, geo,
            const Offset(180 + 66, 320)),
        isTrue,
      );
      // Loin : raté.
      expect(
        SelectionGeometry.hitShape(_bounds(), shape, 0, geo,
            const Offset(180 + 120, 320)),
        isFalse,
      );
    });

    test('hitShape suit la rotation de la forme', () {
      final geo = SceneGeometry.fitFor(_project(), const Size(360, 640));
      final shape = _shape(rotation: math.pi / 2);
      // Le rect 220×62 devient vertical après rotation : point au-dessus → touché.
      expect(
        SelectionGeometry.hitShape(_bounds(), shape, 0, geo,
            const Offset(180, 320 - 50)),
        isTrue,
      );
      // Point à droite (horizontalement large) → raté maintenant.
      expect(
        SelectionGeometry.hitShape(_bounds(), shape, 0, geo,
            const Offset(180 + 50, 320)),
        isFalse,
      );
    });

    test('hitRotationHandle avec tolérance de toucher', () {
      final handle = const Offset(100, 100);
      expect(
        SelectionGeometry.hitRotationHandle(
            const Offset(100 + 25, 100), handle),
        isTrue,
      );
      expect(
        SelectionGeometry.hitRotationHandle(
            const Offset(100 + 40, 100), handle),
        isFalse,
      );
    });
  });
}
