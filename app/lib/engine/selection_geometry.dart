import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import '../models/animation.dart';
import '../models/skeleton.dart';

/// Pose d'un objet en coordonnées scène : origine (centre de rotation et
/// d'échelle), rotation (radians), échelle. Sert autant pour une forme que
/// pour une couche (via composition, cf. `layerPose`).
class Pose2D {
  const Pose2D({
    required this.origin,
    required this.rotation,
    required this.scale,
  });

  final Offset origin;
  final double rotation;
  final double scale;
}

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
/// poignée de rotation, bouton propriétés et zones de toucher — à partir d'une
/// [Pose2D] et du rect local de l'objet.
///
/// Les distances (poignées, marges de toucher) sont exprimées en pixels écran
/// pour rester constantes quelles que soient les échelles de l'objet.
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

  /// Marge de toucher (px écran) autour du corps de l'objet.
  static const double shapeTouchMargin = 10;

  // ------------------------------------------------------------- poses

  /// Pose d'une forme à l'instant donné (valeurs interpolées).
  static Pose2D shapePose(VectorShape shape, int timeMs) => Pose2D(
    origin: Offset(
      shape.valueAt(AnimatableProperty.x, timeMs),
      shape.valueAt(AnimatableProperty.y, timeMs),
    ),
    rotation: shape.valueAt(AnimatableProperty.rotation, timeMs),
    scale: shape.valueAt(AnimatableProperty.scale, timeMs),
  );

  /// Pose d'une forme liée à un os : composition `os(t) ∘ os(repos)⁻¹ ∘ pose`.
  /// Le mouvement de l'os (rigide) emporte l'origine de la forme (elle orbite
  /// l'articulation) et s'ajoute à sa rotation ; l'échelle passe inchangée.
  /// Sans os (ou hors rig), équivalent à [shapePose].
  static Pose2D shapePoseWithRig(
    VectorShape shape,
    int timeMs,
    BoneFrame? frame,
  ) {
    if (frame == null) return shapePose(shape, timeMs);
    final origin = Offset(
      shape.valueAt(AnimatableProperty.x, timeMs),
      shape.valueAt(AnimatableProperty.y, timeMs),
    );
    return Pose2D(
      origin: frame.mapPoint(origin),
      rotation:
          shape.valueAt(AnimatableProperty.rotation, timeMs) + frame.worldDelta,
      scale: shape.valueAt(AnimatableProperty.scale, timeMs),
    );
  }

  /// Pose d'une couche : composition de la transforme de la forme ∘ couche.
  /// L'origine de la couche (son centre, positionné par layer.x/y dans le
  /// repère de la forme) est transformée par la pose de la forme ; rotations
  /// s'additionnent, échelles se multiplient.
  static Pose2D layerPose(VectorShape shape, ShapeLayer layer, int timeMs) {
    final sp = shapePose(shape, timeMs);
    final cosR = math.cos(sp.rotation);
    final sinR = math.sin(sp.rotation);
    final lx = layer.x * sp.scale;
    final ly = layer.y * sp.scale;
    return Pose2D(
      origin: Offset(
        sp.origin.dx + lx * cosR - ly * sinR,
        sp.origin.dy + lx * sinR + ly * cosR,
      ),
      rotation: sp.rotation + layer.rotation,
      scale: sp.scale * layer.scale,
    );
  }

  // ---------------------------------------------------------- géométrie

  /// Projette un point du repère local de l'objet vers le canvas.
  static Offset localToCanvas(Offset local, Pose2D pose, SceneGeometry geo) {
    final s = math.max(0.0001, pose.scale.abs());
    final sx = local.dx * s;
    final sy = local.dy * s;
    final cosR = math.cos(pose.rotation);
    final sinR = math.sin(pose.rotation);
    return geo.sceneToCanvas(
      Offset(
        pose.origin.dx + sx * cosR - sy * sinR,
        pose.origin.dy + sx * sinR + sy * cosR,
      ),
    );
  }

  /// Les 4 coins du rectangle de sélection, en canvas (HG, HD, BD, BG).
  static List<Offset> corners(
    Rect localBounds,
    Pose2D pose,
    SceneGeometry geo,
  ) => <Offset>[
    localToCanvas(localBounds.topLeft, pose, geo),
    localToCanvas(localBounds.topRight, pose, geo),
    localToCanvas(localBounds.bottomRight, pose, geo),
    localToCanvas(localBounds.bottomLeft, pose, geo),
  ];

  /// Centre de l'objet (son origine) en canvas.
  static Offset center(Pose2D pose, SceneGeometry geo) =>
      geo.sceneToCanvas(pose.origin);

  /// Milieu du haut du rectangle de sélection, en canvas.
  static Offset topCenter(Rect localBounds, Pose2D pose, SceneGeometry geo) =>
      localToCanvas(Offset(localBounds.center.dx, localBounds.top), pose, geo);

  /// Position du centre de la poignée de rotation, en canvas : à
  /// [handleDistance] au-dessus du haut du rectangle, le long de son axe.
  static Offset rotationHandle(
    Rect localBounds,
    Pose2D pose,
    SceneGeometry geo,
  ) {
    final top = topCenter(localBounds, pose, geo);
    final c = center(pose, geo);
    final up = top - c;
    final len = up.distance;
    if (len < 0.0001) return top - const Offset(0, handleDistance);
    return top + (up / len) * handleDistance;
  }

  /// Position du centre du bouton propriétés : coin bas-gauche du rectangle
  /// décalé en diagonale externe, en canvas.
  static Offset propertiesButton(
    Rect localBounds,
    Pose2D pose,
    SceneGeometry geo,
  ) {
    final bottomLeft = corners(localBounds, pose, geo)[3];
    final c = center(pose, geo);
    final outward = bottomLeft - c;
    final len = outward.distance;
    final step = len < 0.0001
        ? const Offset(-buttonOffset, buttonOffset)
        : (outward / len) * buttonOffset;
    return bottomLeft + step;
  }

  // ---------------------------------------------------------- hit tests

  /// Le point canvas touche-t-il la poignée de rotation ?
  static bool hitRotationHandle(Offset point, Offset handleCenter) =>
      (point - handleCenter).distance <= touchSlop;

  /// Le point canvas touche-t-il l'objet ? Rect local pivoté/zoomé avec une
  /// marge de toucher constante en pixels écran.
  static bool hit(
    Rect localBounds,
    Pose2D pose,
    SceneGeometry geo,
    Offset canvasPoint,
  ) {
    final s = math.max(0.0001, pose.scale.abs());
    final scene = geo.canvasToScene(canvasPoint);
    final relX = scene.dx - pose.origin.dx;
    final relY = scene.dy - pose.origin.dy;
    final cosR = math.cos(-pose.rotation);
    final sinR = math.sin(-pose.rotation);
    final local = Offset(
      (relX * cosR - relY * sinR) / s,
      (relX * sinR + relY * cosR) / s,
    );
    return localBounds.inflate(shapeTouchMargin / s).contains(local);
  }
}
