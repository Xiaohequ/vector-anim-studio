import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import '../models/animation.dart';

/// Mapping entre les coordonnées scène (repère du projet, ex. 360×640) et les
/// coordonnées canvas (repère du widget, pixels logiques). La scène est
/// inscrite dans le canvas avec un facteur unique et centrée — le même calcul
/// que `ScenePainter.paint`, partagé avec la sélection, les poignées et les
/// gestes.
class SceneGeometry {
  const SceneGeometry({
    required this.scale,
    required this.dx,
    required this.dy,
  });

  /// Facteur unique scène → canvas.
  final double scale;

  /// Décalage horizontal (centrage du cadre).
  final double dx;

  /// Décalage vertical (centrage du cadre).
  final double dy;

  /// Inscrit la scène dans [canvasSize] (fit + centrage).
  static SceneGeometry fitFor(AnimationProject project, Size canvasSize) {
    final safeW = math.max(1.0, project.width);
    final safeH = math.max(1.0, project.height);
    final s = math.min(canvasSize.width / safeW, canvasSize.height / safeH);
    return SceneGeometry(
      scale: s,
      dx: (canvasSize.width - safeW * s) / 2,
      dy: (canvasSize.height - safeH * s) / 2,
    );
  }

  Offset sceneToCanvas(Offset scene) =>
      Offset(scene.dx * scale + dx, scene.dy * scale + dy);

  Offset canvasToScene(Offset canvas) =>
      Offset((canvas.dx - dx) / scale, (canvas.dy - dy) / scale);
}

/// Géométrie de la sélection en coordonnées canvas (écran) : rectangle pivoté,
/// poignée de rotation, bouton propriétés et zones de toucher.
///
/// Toutes les méthodes prennent le rect local de la forme (avant
/// transformation, cf. `ScenePainter.shapeBounds`) et la pose effective à
/// l'instant courant. Les distances (poignées, marges de toucher) sont
/// exprimées en pixels écran pour rester constantes quelles que soient les
/// échelles de la forme.
class SelectionGeometry {
  SelectionGeometry._();

  /// Distance (px écran) entre le haut du rectangle et la poignée de rotation.
  static const double handleDistance = 30;

  /// Rayon (px écran) de la poignée de rotation.
  static const double handleRadius = 9;

  /// Décalage (px écran) du bouton propriétés hors du coin bas-gauche.
  static const double buttonOffset = 26;

  /// Tolérance de toucher (px écran) autour de la poignée.
  static const double touchSlop = 26;

  /// Marge de toucher (px écran) autour du corps de la forme.
  static const double shapeTouchMargin = 10;

  /// Pose effective (position, rotation, échelle) de la forme à l'instant donné.
  static ({Offset position, double rotation, double scale}) pose(
    VectorShape shape,
    int timeMs,
  ) => (
        position: Offset(
          shape.valueAt(AnimatableProperty.x, timeMs),
          shape.valueAt(AnimatableProperty.y, timeMs),
        ),
        rotation: shape.valueAt(AnimatableProperty.rotation, timeMs),
        scale: shape.valueAt(AnimatableProperty.scale, timeMs),
      );

  /// Projette un point du repère local de la forme vers le canvas.
  static Offset localToCanvas(
    Offset local,
    VectorShape shape,
    int timeMs,
    SceneGeometry geo,
  ) {
    final p = pose(shape, timeMs);
    final s = math.max(0.0001, p.scale.abs());
    final sx = local.dx * s;
    final sy = local.dy * s;
    final cosR = math.cos(p.rotation);
    final sinR = math.sin(p.rotation);
    return geo.sceneToCanvas(Offset(
      p.position.dx + sx * cosR - sy * sinR,
      p.position.dy + sx * sinR + sy * cosR,
    ));
  }

  /// Les 4 coins du rectangle de sélection, en canvas (HG, HD, BD, BG).
  static List<Offset> cornersCanvas(
    Rect localBounds,
    VectorShape shape,
    int timeMs,
    SceneGeometry geo,
  ) => <Offset>[
        localToCanvas(localBounds.topLeft, shape, timeMs, geo),
        localToCanvas(localBounds.topRight, shape, timeMs, geo),
        localToCanvas(localBounds.bottomRight, shape, timeMs, geo),
        localToCanvas(localBounds.bottomLeft, shape, timeMs, geo),
      ];

  /// Centre de la forme (son origine x, y) en canvas.
  static Offset centerCanvas(
    VectorShape shape,
    int timeMs,
    SceneGeometry geo,
  ) => geo.sceneToCanvas(Offset(
        shape.valueAt(AnimatableProperty.x, timeMs),
        shape.valueAt(AnimatableProperty.y, timeMs),
      ));

  /// Milieu du haut du rectangle de sélection, en canvas.
  static Offset topCenterCanvas(
    Rect localBounds,
    VectorShape shape,
    int timeMs,
    SceneGeometry geo,
  ) => localToCanvas(
        Offset(localBounds.center.dx, localBounds.top),
        shape,
        timeMs,
        geo,
      );

  /// Position du centre de la poignée de rotation, en canvas : à
  /// [handleDistance] au-dessus du haut du rectangle, le long de son axe.
  static Offset rotationHandleCanvas(
    Rect localBounds,
    VectorShape shape,
    int timeMs,
    SceneGeometry geo,
  ) {
    final topCenter = topCenterCanvas(localBounds, shape, timeMs, geo);
    final center = centerCanvas(shape, timeMs, geo);
    final up = topCenter - center;
    final len = up.distance;
    if (len < 0.0001) return topCenter - const Offset(0, handleDistance);
    return topCenter + (up / len) * handleDistance;
  }

  /// Position du centre du bouton propriétés : coin bas-gauche du rectangle
  /// décalé en diagonale externe, en canvas.
  static Offset propertiesButtonCanvas(
    Rect localBounds,
    VectorShape shape,
    int timeMs,
    SceneGeometry geo,
  ) {
    final bottomLeft = cornersCanvas(localBounds, shape, timeMs, geo)[3];
    final center = centerCanvas(shape, timeMs, geo);
    final outward = bottomLeft - center;
    final len = outward.distance;
    final step = len < 0.0001
        ? const Offset(-buttonOffset, buttonOffset)
        : (outward / len) * buttonOffset;
    return bottomLeft + step;
  }

  /// Le point canvas touche-t-il la poignée de rotation ?
  static bool hitRotationHandle(Offset point, Offset handleCenter) =>
      (point - handleCenter).distance <= touchSlop;

  /// Le point canvas touche-t-il la forme ? Rect local pivoté/zoomé avec une
  /// marge de toucher constante en pixels écran.
  static bool hitShape(
    Rect localBounds,
    VectorShape shape,
    int timeMs,
    SceneGeometry geo,
    Offset canvasPoint,
  ) {
    final p = pose(shape, timeMs);
    final s = math.max(0.0001, p.scale.abs());
    final scene = geo.canvasToScene(canvasPoint);
    final relX = scene.dx - p.position.dx;
    final relY = scene.dy - p.position.dy;
    final cosR = math.cos(-p.rotation);
    final sinR = math.sin(-p.rotation);
    final local = Offset(
      (relX * cosR - relY * sinR) / s,
      (relX * sinR + relY * cosR) / s,
    );
    return localBounds.inflate(shapeTouchMargin / s).contains(local);
  }
}
