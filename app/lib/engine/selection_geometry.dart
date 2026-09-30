import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import '../models/animation.dart';
import '../models/skeleton.dart';

/// Pose d'un objet en coordonnées scène : centre non compensé du pivot,
/// rotation, échelle (uniforme × facteurs d'axe, v0.13) et pivot de rotation
/// (offset en unités de forme, v0.13). Sert autant pour une forme que pour
/// une couche (via composition, cf. `layerPose`).
class Pose2D {
  const Pose2D({
    required this.origin,
    required this.rotation,
    required this.scale,
    this.scaleX = 1,
    this.scaleY = 1,
    this.pivotDx = 0,
    this.pivotDy = 0,
  });

  /// Centre de la pose, NON compensé du pivot (= shape.x/y interpolés).
  final Offset origin;
  final double rotation;
  final double scale;

  /// Facteurs d'axe (squash & stretch non uniforme) : effective = scale ×
  /// facteur. Composition couche : exacte quand la rotation de couche est
  /// nulle ou l'échelle de forme uniforme (sinon rect de sélection approché).
  final double scaleX;
  final double scaleY;

  /// Pivot de rotation : offset en unités de forme depuis le centre ; le
  /// gond est ancré à sa position VISUELLE (S·pivot) — il reste collé au
  /// bord visuel sous une échelle non uniforme.
  final double pivotDx;
  final double pivotDy;

  /// Échelle effective par axe (uniforme × facteur).
  double get sx => scale * scaleX;
  double get sy => scale * scaleY;

  /// Origine COMPENSÉE du pivot : world(q) = foldedOrigin + R·S·q
  /// (chaîne de rendu = centre + S·pivot + R·S·(q − pivot)).
  Offset get foldedOrigin {
    if (pivotDx == 0 && pivotDy == 0) return origin;
    final c = math.cos(rotation);
    final s = math.sin(rotation);
    final rpx = sx * pivotDx;
    final rpy = sy * pivotDy;
    return origin +
        Offset(rpx - (rpx * c - rpy * s), rpy - (rpx * s + rpy * c));
  }

  /// Point fixe de rotation en coordonnées scène : centre + S·pivot (le gond
  /// ne tourne pas avec la forme). Pivot nul = [origin].
  Offset rotationCenterScene() {
    if (pivotDx == 0 && pivotDy == 0) return origin;
    return origin + Offset(sx * pivotDx, sy * pivotDy);
  }
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

  /// Rayon (px écran) d'une poignée de point de chemin (éditeur de points,
  /// v0.16) — et de la poignée ACTIVE (en cours de glisser).
  static const double pointHandleRadius = 5.5;
  static const double activePointHandleRadius = 9;

  /// Tolérance de toucher (px écran) d'un point de chemin : généreuse pour
  /// le doigt, et pour rattraper le décalage de reconnaissance du geste
  /// (onScaleStart arrive avec le foyer déjà déplacé — piège v0.10.1).
  static const double pointTouchSlop = 24;

  // ------------------------------------------------------------- poses

  /// Pose d'une forme à l'instant donné (valeurs interpolées).
  static Pose2D shapePose(VectorShape shape, int timeMs) => Pose2D(
    origin: Offset(
      shape.valueAt(AnimatableProperty.x, timeMs),
      shape.valueAt(AnimatableProperty.y, timeMs),
    ),
    rotation: shape.valueAt(AnimatableProperty.rotation, timeMs),
    scale: shape.valueAt(AnimatableProperty.scale, timeMs),
    scaleX: shape.valueAt(AnimatableProperty.scaleX, timeMs),
    scaleY: shape.valueAt(AnimatableProperty.scaleY, timeMs),
    pivotDx: shape.pivotDx,
    pivotDy: shape.pivotDy,
  );

  /// Pose d'une forme liée à un os : composition `os(t) ∘ os(repos)⁻¹ ∘ pose`.
  /// Le mouvement de l'os (rigide) emporte l'origine de la forme (elle orbite
  /// l'articulation), s'ajoute à sa rotation et emporte le pivot ; l'échelle
  /// passe inchangée. Sans os (ou hors rig), équivalent à [shapePose].
  static Pose2D shapePoseWithRig(
    VectorShape shape,
    int timeMs,
    BoneFrame? frame,
  ) {
    if (frame == null) return shapePose(shape, timeMs);
    final pose = shapePose(shape, timeMs);
    return Pose2D(
      origin: frame.mapPoint(pose.origin),
      rotation: pose.rotation + frame.worldDelta,
      scale: pose.scale,
      scaleX: pose.scaleX,
      scaleY: pose.scaleY,
      pivotDx: pose.pivotDx,
      pivotDy: pose.pivotDy,
    );
  }

  /// Pose d'une couche : composition de la transforme de la forme ∘ couche.
  /// L'origine de la couche (son centre, positionné par layer.x/y dans le
  /// repère de la forme) est transformée par la chaîne pivot de la forme ;
  /// rotations s'additionnent, échelles se multiplient (facteurs d'axe de la
  /// forme transmis, pivot déjà intégré à l'origine).
  static Pose2D layerPose(VectorShape shape, ShapeLayer layer, int timeMs) {
    final sp = shapePose(shape, timeMs);
    final cosR = math.cos(sp.rotation);
    final sinR = math.sin(sp.rotation);
    final Offset origin;
    if (sp.pivotDx == 0 && sp.pivotDy == 0) {
      final lx = layer.x * sp.sx;
      final ly = layer.y * sp.sy;
      origin = Offset(
        sp.origin.dx + lx * cosR - ly * sinR,
        sp.origin.dy + lx * sinR + ly * cosR,
      );
    } else {
      // Chaîne pivot : centre + S·pivot + R·S·(l − pivot).
      final rpx = sp.sx * sp.pivotDx;
      final rpy = sp.sy * sp.pivotDy;
      final lx = (layer.x - sp.pivotDx) * sp.sx;
      final ly = (layer.y - sp.pivotDy) * sp.sy;
      origin = Offset(
        sp.origin.dx + rpx + lx * cosR - ly * sinR,
        sp.origin.dy + rpy + lx * sinR + ly * cosR,
      );
    }
    return Pose2D(
      origin: origin,
      rotation: sp.rotation + layer.rotation,
      scale: sp.scale * layer.scale,
      scaleX: sp.scaleX,
      scaleY: sp.scaleY,
    );
  }

  // ---------------------------------------------------------- géométrie

  /// Projette un point du repère local de l'objet vers le canvas.
  static Offset localToCanvas(Offset local, Pose2D pose, SceneGeometry geo) {
    final sx = math.max(0.0001, pose.sx.abs());
    final sy = math.max(0.0001, pose.sy.abs());
    final ox = local.dx * sx;
    final oy = local.dy * sy;
    final cosR = math.cos(pose.rotation);
    final sinR = math.sin(pose.rotation);
    final o = pose.foldedOrigin;
    return geo.sceneToCanvas(
      Offset(o.dx + ox * cosR - oy * sinR, o.dy + ox * sinR + oy * cosR),
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

  /// Centre de l'objet en canvas : le POINT FIXE de rotation (centre + S·pivot).
  static Offset center(Pose2D pose, SceneGeometry geo) =>
      geo.sceneToCanvas(pose.rotationCenterScene());

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

  // -------------------------------------------------- points d'un chemin

  /// Positions ÉCRAN des poignées de points d'un chemin : le nuage [cloud]
  /// est échantillonné (repère « boîte » comme [ShapeLayer.points], rendu à
  /// `point − (w/2, h/2)` dans le repère local de la couche, identique au
  /// painter) ; [pose] = pose de la couche (`layerPose`).
  static List<Offset> pointHandlePositions(
    List<Offset> cloud,
    ShapeLayer layer,
    Pose2D pose,
    SceneGeometry geo,
  ) {
    final ox = -layer.width / 2;
    final oy = -layer.height / 2;
    return <Offset>[
      for (final p in cloud)
        // Miroir (v0.19) : le contenu dessiné est reflété autour de
        // l'origine de la couche — les poignées suivent le RENDU.
        localToCanvas(
          Offset(
            (p.dx + ox) * (layer.flipH ? -1 : 1),
            (p.dy + oy) * (layer.flipV ? -1 : 1),
          ),
          pose,
          geo,
        ),
    ];
  }

  /// Index du point le plus proche dans la tolérance (px écran), ou −1.
  static int hitPointIndex(List<Offset> handles, Offset point, double slop) {
    var best = -1;
    var bestDist = slop;
    for (var i = 0; i < handles.length; i++) {
      final d = (point - handles[i]).distance;
      if (d <= bestDist) {
        best = i;
        bestDist = d;
      }
    }
    return best;
  }

  /// Distance d'un point à un segment [a, b].
  static double distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.distanceSquared;
    if (len2 < 0.0001) return (p - a).distance;
    final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2).clamp(
      0.0,
      1.0,
    );
    return (p - a - ab * t).distance;
  }

  /// Plus proche segment d'un chemin FERMÉ (liste de positions écran) :
  /// renvoie (index du point de départ, distance). Le segment de fermeture
  /// (dernier → premier) part de l'index `n − 1` — l'insertion d'un point
  /// dessus se fait à l'index `départ + 1` (= n, en fin de liste).
  static (int, double) nearestClosedSegment(
    List<Offset> positions,
    Offset point,
  ) {
    if (positions.length < 2) return (0, double.infinity);
    var best = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < positions.length; i++) {
      final d = distanceToSegment(
        point,
        positions[i],
        positions[(i + 1) % positions.length],
      );
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return (best, bestDist);
  }

  // ---------------------------------------------------------- hit tests

  /// Le point canvas touche-t-il la poignée de rotation ?
  static bool hitRotationHandle(Offset point, Offset handleCenter) =>
      (point - handleCenter).distance <= touchSlop;

  /// Convertit un point canvas en coordonnées LOCALES de l'objet
  /// (inverse de [localToCanvas]) — deltas inclus : la différence des
  /// conversions de deux points canvas donne le delta local exact.
  static Offset canvasToLocal(
    Offset canvasPoint,
    Pose2D pose,
    SceneGeometry geo,
  ) {
    final sx = math.max(0.0001, pose.sx.abs());
    final sy = math.max(0.0001, pose.sy.abs());
    final scene = geo.canvasToScene(canvasPoint);
    final o = pose.foldedOrigin;
    final relX = scene.dx - o.dx;
    final relY = scene.dy - o.dy;
    final cosR = math.cos(-pose.rotation);
    final sinR = math.sin(-pose.rotation);
    return Offset(
      (relX * cosR - relY * sinR) / sx,
      (relX * sinR + relY * cosR) / sy,
    );
  }

  /// Le point canvas touche-t-il l'objet ? Rect local pivoté/zoomé avec une
  /// marge de toucher constante en pixels écran.
  static bool hit(
    Rect localBounds,
    Pose2D pose,
    SceneGeometry geo,
    Offset canvasPoint,
  ) {
    final local = canvasToLocal(canvasPoint, pose, geo);
    final sx = math.max(0.0001, pose.sx.abs());
    final sy = math.max(0.0001, pose.sy.abs());
    return localBounds
        .inflate(shapeTouchMargin / math.min(sx, sy))
        .contains(local);
  }
}
