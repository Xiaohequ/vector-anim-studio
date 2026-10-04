import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'skeleton.dart';

/// Type de forme basique dessinable dans une couche.
enum ShapeKind {
  rect,
  circle,
  line,
  path,
  triangle,
  star,
  hexagon,
  cross,
  heart,
  arrow,
}

String shapeKindLabel(ShapeKind kind) => switch (kind) {
  ShapeKind.rect => 'Rectangle',
  ShapeKind.circle => 'Cercle',
  ShapeKind.line => 'Ligne',
  ShapeKind.path => 'Chemin',
  ShapeKind.triangle => 'Triangle',
  ShapeKind.star => 'Étoile',
  ShapeKind.hexagon => 'Hexagone',
  ShapeKind.cross => 'Croix',
  ShapeKind.heart => 'Cœur',
  ShapeKind.arrow => 'Flèche',
};

/// Propriétés animables d'une forme complète (transformation de groupe).
/// `scale` = échelle uniforme ; `scaleX`/`scaleY` = facteurs d'axe (v0.13,
/// squash & stretch non uniforme — échelle effective = scale × facteur).
enum AnimatableProperty {
  x,
  y,
  rotation,
  scale,
  scaleX,
  scaleY,
  opacity,
  strokeWidth,
}

/// Interpolations disponibles entre deux keyframes. `customBezier` = courbe
/// cubic-bezier paramétrée par les 4 valeurs `bezier` de la keyframe (défauts
/// dans [defaultBezier] quand `bezier` est null).
enum EasingKind { linear, easeIn, easeOut, easeInOut, step, customBezier }

/// Formats de projet proposés à la création.
enum ProjectFormat { portrait, landscape, square }

/// Type de projet : vectoriel (formes + keyframes de pose, comportement
/// historique) ou squelette (un rig d'os anime les pièces — rig maître).
enum ProjectType { vector, skeleton }

extension ProjectTypeInfo on ProjectType {
  String get label => switch (this) {
    ProjectType.vector => 'Animation vectorielle',
    ProjectType.skeleton => 'Animation squelette',
  };
}

extension ProjectFormatInfo on ProjectFormat {
  String get label => switch (this) {
    ProjectFormat.portrait => 'Portrait 360 × 640',
    ProjectFormat.landscape => 'Paysage 640 × 360',
    ProjectFormat.square => 'Carré 480 × 480',
  };

  double get width => switch (this) {
    ProjectFormat.portrait => 360,
    ProjectFormat.landscape => 640,
    ProjectFormat.square => 480,
  };

  double get height => switch (this) {
    ProjectFormat.portrait => 640,
    ProjectFormat.landscape => 360,
    ProjectFormat.square => 480,
  };
}

/// Applique une courbe d'accélération sur une progression normalisée [0,1].
double applyEasing(EasingKind easing, double t) {
  final u = t.clamp(0.0, 1.0);
  switch (easing) {
    case EasingKind.linear:
      return u;
    case EasingKind.easeIn:
      return u * u;
    case EasingKind.easeOut:
      return 1 - (1 - u) * (1 - u);
    case EasingKind.easeInOut:
      if (u < 0.5) return 2 * u * u;
      return (1 - math.pow(-2 * u + 2, 2) / 2).toDouble();
    case EasingKind.step:
      return 0;
    case EasingKind.customBezier:
      // Sans paramètre ici : neutre (linéaire). Les échantillonneurs passent
      // par [easingProgress], qui connaît la bezier de la keyframe.
      return u;
  }
}

/// Paramètres cubic-bezier par défaut (proche d'easeInOut).
const List<double> defaultBezier = <double>[0.25, 0.1, 0.25, 1.0];

/// Évalue une courbe cubic-bezier CSS : x et y sont des polynômes de [0,1]
/// (`3u(1-u)²·x1 + 3u²(1-u)·x2 + u³`). On résout x(u) = t par dichotomie
/// (robuste, x monotone quand x1/x2 ∈ [0,1]) puis on renvoie y(u).
double applyBezierEasing(double x1, double y1, double x2, double y2, double t) {
  double xOf(double u) =>
      3 * u * (1 - u) * (1 - u) * x1 + 3 * u * u * (1 - u) * x2 + u * u * u;
  double yOf(double u) =>
      3 * u * (1 - u) * (1 - u) * y1 + 3 * u * u * (1 - u) * y2 + u * u * u;
  final target = t.clamp(0.0, 1.0);
  if (target <= 0) return 0;
  if (target >= 1) return 1;
  var lo = 0.0;
  var hi = 1.0;
  for (var i = 0; i < 60; i++) {
    final mid = (lo + hi) / 2;
    if (xOf(mid) < target) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return yOf((lo + hi) / 2);
}

/// Progression d'interpolation d'une keyframe : courbe nommée, ou cubic-bezier
/// quand `easing` vaut `customBezier` (`bezier` de la keyframe, sinon
/// [defaultBezier]). Sert aux poses de forme ET aux keyframes d'os.
double easingProgress(EasingKind easing, List<double>? bezier, double p) =>
    (easing == EasingKind.customBezier &&
        (bezier == null || bezier.length == 4))
    ? applyBezierEasing(
        bezier?[0] ?? defaultBezier[0],
        bezier?[1] ?? defaultBezier[1],
        bezier?[2] ?? defaultBezier[2],
        bezier?[3] ?? defaultBezier[3],
        p,
      )
    : applyEasing(easing, p);

/// Étiquette lisible d'une propriété (interface).
String propertyLabel(AnimatableProperty property) => switch (property) {
  AnimatableProperty.x => 'Position X',
  AnimatableProperty.y => 'Position Y',
  AnimatableProperty.rotation => 'Rotation',
  AnimatableProperty.scale => 'Échelle',
  AnimatableProperty.scaleX => 'Échelle X',
  AnimatableProperty.scaleY => 'Échelle Y',
  AnimatableProperty.opacity => 'Opacité',
  AnimatableProperty.strokeWidth => 'Épaisseur',
};

int _idSeed = 0;

/// Identifiant unique local (projets, formes, couches).
String generateId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_idSeed++}';

/// Tolérance de proximité des keyframes : équivalent à ~8 px sur une timeline
/// de référence large de 400 px. Sert au bouton de suppression contextuel et
/// au snap lors de l'écriture d'une valeur.
const double keyframeSnapTolerancePx = 8;
const double keyframeNominalTimelineWidth = 400;

int keyframeSnapToleranceMs(int durationMs) => math.max(
  1,
  (durationMs * keyframeSnapTolerancePx / keyframeNominalTimelineWidth).round(),
);

/// Temps interne d'une instance d'animation (sémantique « boucle ») :
/// l'animation source tourne à vitesse naturelle et recommence tant que la
/// fenêtre d'affichage est ouverte. Avant le début de la fenêtre → 0.
int instanceTimeMs(int timeMs, int startMs, int subDurationMs) {
  if (subDurationMs <= 0) return 0;
  final elapsed = timeMs - startMs;
  if (elapsed <= 0) return 0;
  return elapsed % subDurationMs;
}

/// Étiquette lisible d'une courbe d'interpolation (interface).
String easingLabel(EasingKind easing) => switch (easing) {
  EasingKind.linear => 'Linéaire',
  EasingKind.easeIn => 'Entrée',
  EasingKind.easeOut => 'Sortie',
  EasingKind.easeInOut => 'Entrée/sortie',
  EasingKind.step => 'Palier',
  EasingKind.customBezier => 'Personnalisé (Bézier)',
};

/// Interpolation point par point : le nuage le plus court est bourré par
/// répétition de son dernier point, puis lerp un à un (morph de path, v0.15).
List<Offset> lerpPointLists(List<Offset> a, List<Offset> b, double t) {
  final n = math.max(a.length, b.length);
  final u = t.clamp(0.0, 1.0);
  return <Offset>[
    for (var i = 0; i < n; i++)
      Offset.lerp(
        a[math.min(i, a.length - 1)],
        b[math.min(i, b.length - 1)],
        u,
      )!,
  ];
}

/// Mélange deux couleurs ARGB canal par canal (couleur animée, v0.15).
int lerpArgb(int from, int to, double t) {
  final u = t.clamp(0.0, 1.0);
  int channel(int shift) {
    final a = (from >> shift) & 0xFF;
    final b = (to >> shift) & 0xFF;
    return (a + (b - a) * u).round().clamp(0, 255);
  }

  return (channel(24) << 24) |
      (channel(16) << 16) |
      (channel(8) << 8) |
      channel(0);
}

/// Une keyframe « pose » : toutes les propriétés de la forme à `timeMs`.
class ShapeKeyframe {
  ShapeKeyframe({
    required this.timeMs,
    Map<AnimatableProperty, double>? values,
    this.easing = EasingKind.easeInOut,
    List<double>? bezier,
    Map<String, int>? layerColors,
    Map<String, List<Offset>>? layerPoints,
  }) : values = values ?? <AnimatableProperty, double>{},
       bezier = (bezier != null && bezier.length == 4)
           ? List<double>.from(bezier)
           : null,
       layerColors = layerColors == null
           ? <String, int>{}
           : Map<String, int>.from(layerColors),
       layerPoints = layerPoints == null
           ? <String, List<Offset>>{}
           : <String, List<Offset>>{
               for (final entry in layerPoints.entries)
                 entry.key: List<Offset>.from(entry.value),
             };

  int timeMs;

  /// Courbe d'interpolation du segment qui arrive sur cette keyframe.
  EasingKind easing;

  /// Paramètres cubic-bezier `[x1, y1, x2, y2]` quand `easing` vaut
  /// `customBezier` (null → [defaultBezier]).
  List<double>? bezier;

  final Map<AnimatableProperty, double> values;

  /// Couleurs par couche portées par cette pose (v0.15, couleur animée) :
  /// id de couche → ARGB. Une couche absente garde sa couleur précédente
  /// (carry) ou de base. Vide = aucune couleur animée sur cette pose.
  final Map<String, int> layerColors;

  /// Points de path par couche portés par cette pose (v0.15, morph) :
  /// id de couche → points dans le MÊME repère que `ShapeLayer.points`.
  /// Vide = pas de morph sur cette pose.
  final Map<String, List<Offset>> layerPoints;

  double? valueOf(AnimatableProperty property) => values[property];

  ShapeKeyframe copy() => ShapeKeyframe(
    timeMs: timeMs,
    values: Map<AnimatableProperty, double>.from(values),
    easing: easing,
    bezier: bezier,
    layerColors: Map<String, int>.from(layerColors),
    layerPoints: <String, List<Offset>>{
      for (final entry in layerPoints.entries)
        entry.key: List<Offset>.from(entry.value),
    },
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'timeMs': timeMs,
    'easing': easing.name,
    if (bezier != null) 'bezier': List<double>.from(bezier!),
    'values': <String, double>{
      for (final entry in values.entries) entry.key.name: entry.value,
    },
    if (layerColors.isNotEmpty)
      'layerColors': Map<String, int>.from(layerColors),
    if (layerPoints.isNotEmpty)
      'layerPoints': <String, Object?>{
        for (final entry in layerPoints.entries)
          entry.key: [
            for (final p in entry.value) [p.dx, p.dy],
          ],
      },
  };

  static ShapeKeyframe fromJson(Map<String, Object?> json) {
    final raw =
        (json['values'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};
    return ShapeKeyframe(
      timeMs: (json['timeMs'] as num).toInt(),
      easing: EasingKind.values.firstWhere(
        (e) => e.name == json['easing'],
        orElse: () => EasingKind.easeInOut,
      ),
      bezier: (json['bezier'] as List<Object?>?)
          ?.map((v) => (v as num).toDouble())
          .toList(),
      values: <AnimatableProperty, double>{
        for (final property in AnimatableProperty.values)
          if (raw[property.name] != null)
            property: (raw[property.name] as num).toDouble(),
      },
      layerColors: (json['layerColors'] as Map?)?.cast<String, Object?>().map(
        (key, value) => MapEntry(key, (value as num).toInt()),
      ),
      layerPoints: (json['layerPoints'] as Map?)?.map(
        (key, value) => MapEntry(key as String, <Offset>[
          for (final point in (value as List<Object?>? ?? const []))
            Offset(
              ((point as List<Object?>)[0] as num).toDouble(),
              (point[1] as num).toDouble(),
            ),
        ]),
      ),
    );
  }
}

/// Une couche : une forme basique, en coordonnées locales à la forme parente.
class ShapeLayer {
  ShapeLayer({
    String? id,
    required this.name,
    required this.kind,
    this.x = 0,
    this.y = 0,
    this.width = 110,
    this.height = 110,
    this.rotation = 0,
    this.scale = 1,
    this.opacity = 1,
    this.strokeWidth = 4,
    this.colorValue = 0xFF5B8DEF,
    this.filled = true,
    List<Offset>? points,
    this.visible = true,
    this.flipH = false,
    this.flipV = false,
  }) : id = id ?? generateId('layer'),
       // Normalisé en liste modifiable : des points passés const (littéraux
       // par défaut de l'éditeur) doivent accepter l'insertion/suppression
       // structurelle de l'éditeur de points (v0.16).
       points = List<Offset>.from(points ?? const <Offset>[]);

  final String id;
  String name;
  ShapeKind kind;

  double x;
  double y;
  double width;
  double height;
  double rotation;
  double scale;
  double opacity;
  double strokeWidth;
  int colorValue;
  bool filled;
  List<Offset> points;
  bool visible;

  /// Miroir du contenu (v0.19) : le painter reflète la primitive ou le path
  /// autour de l'origine de la couche. Posé par « Miroir H/V » de la sheet
  /// de la forme (qui négue aussi x/y et la rotation de la couche) — jamais
  /// animé (statique) ; la composition action ∘ flip de rendu redonne le
  /// contenu d'origine, points et nuages de morph restent donc intacts.
  bool flipH;
  bool flipV;

  double baseOf(LayerProperty property) => switch (property) {
    LayerProperty.x => x,
    LayerProperty.y => y,
    LayerProperty.width => width,
    LayerProperty.height => height,
    LayerProperty.rotation => rotation,
    LayerProperty.scale => scale,
    LayerProperty.opacity => opacity,
    LayerProperty.strokeWidth => strokeWidth,
  };

  void setBase(LayerProperty property, double value) {
    switch (property) {
      case LayerProperty.x:
        x = value;
      case LayerProperty.y:
        y = value;
      case LayerProperty.width:
        width = value;
      case LayerProperty.height:
        height = value;
      case LayerProperty.rotation:
        rotation = value;
      case LayerProperty.scale:
        scale = value;
      case LayerProperty.opacity:
        opacity = value;
      case LayerProperty.strokeWidth:
        strokeWidth = value;
    }
  }

  ShapeLayer copy({String? id, String? name}) => ShapeLayer(
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind,
    x: x,
    y: y,
    width: width,
    height: height,
    rotation: rotation,
    scale: scale,
    opacity: opacity,
    strokeWidth: strokeWidth,
    colorValue: colorValue,
    filled: filled,
    points: List<Offset>.from(points),
    visible: visible,
    flipH: flipH,
    flipV: flipV,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'rotation': rotation,
    'scale': scale,
    'opacity': opacity,
    'strokeWidth': strokeWidth,
    'colorValue': colorValue,
    'filled': filled,
    'points': points.map((p) => [p.dx, p.dy]).toList(),
    'visible': visible,
    'flipH': flipH,
    'flipV': flipV,
  };

  factory ShapeLayer.fromJson(Map<String, Object?> json) => ShapeLayer(
    id: json['id'] as String?,
    name: json['name'] as String? ?? 'Couche',
    kind: ShapeKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => ShapeKind.rect,
    ),
    x: (json['x'] as num?)?.toDouble() ?? 0,
    y: (json['y'] as num?)?.toDouble() ?? 0,
    width: (json['width'] as num?)?.toDouble() ?? 110,
    height: (json['height'] as num?)?.toDouble() ?? 110,
    rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
    scale: (json['scale'] as num?)?.toDouble() ?? 1,
    opacity: (json['opacity'] as num?)?.toDouble() ?? 1,
    strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 4,
    colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFF5B8DEF,
    filled: json['filled'] as bool? ?? true,
    points: (json['points'] as List<Object?>? ?? const [])
        .map((p) => (p as List<Object?>))
        .map((p) => Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()))
        .toList(),
    visible: json['visible'] as bool? ?? true,
    flipH: json['flipH'] as bool? ?? false,
    flipV: json['flipV'] as bool? ?? false,
  );
}

/// Propriétés éditables d'une couche (non animées).
enum LayerProperty {
  x,
  y,
  width,
  height,
  rotation,
  scale,
  opacity,
  strokeWidth,
}

String layerPropertyLabel(LayerProperty property) => switch (property) {
  LayerProperty.x => 'Position X',
  LayerProperty.y => 'Position Y',
  LayerProperty.width => 'Largeur',
  LayerProperty.height => 'Hauteur',
  LayerProperty.rotation => 'Rotation',
  LayerProperty.scale => 'Échelle',
  LayerProperty.opacity => 'Opacité',
  LayerProperty.strokeWidth => 'Épaisseur',
};

/// Une forme du projet : un groupe de couches, animable et affiché sur [startMs, endMs].
class VectorShape {
  VectorShape({
    String? id,
    required this.name,
    List<ShapeLayer>? layers,
    this.x = 180,
    this.y = 320,
    this.rotation = 0,
    this.scale = 1,
    this.scaleX = 1,
    this.scaleY = 1,
    this.pivotDx = 0,
    this.pivotDy = 0,
    this.opacity = 1,
    this.strokeWidth = 1,
    this.startMs = 0,
    this.endMs = 4000,
    this.visible = true,
    this.embeddedProjectId,
    this.embeddedWidth = 0,
    this.embeddedHeight = 0,
    this.embeddedIsSkeleton = false,
    this.flipH = false,
    this.flipV = false,
  }) : id = id ?? generateId('shape'),
       layers = layers ?? <ShapeLayer>[];

  final String id;
  String name;

  /// Identifiant du projet imbriqué (instance d'animation) : la forme ne
  /// porte aucune couche, elle rend le projet source dans sa pose.
  String? embeddedProjectId;

  /// Dimensions du projet source, capturées à l'insertion (sélection, bounds).
  double embeddedWidth;
  double embeddedHeight;

  /// Type du projet imbriqué au moment de son insertion (sert à distinguer
  /// les éléments squelette sur la timeline).
  bool embeddedIsSkeleton;

  /// Miroir du groupe complet, principalement utilisé sur les instances.
  bool flipH;
  bool flipV;

  bool get isInstance => embeddedProjectId != null;

  /// Transformation de groupe (centre de la forme).
  double x;
  double y;
  double rotation;
  double scale;

  /// Facteurs d'axe (v0.13, squash & stretch non uniforme) : l'échelle
  /// effective = scale × facteur, par axe.
  double scaleX;
  double scaleY;

  /// Pivot de rotation (v0.13) : offset en unités scène depuis le centre,
  /// DANS le repère de la forme (la porte tourne autour de son gond). La
  /// position du centre est inchangée ; non animable (statique).
  double pivotDx;
  double pivotDy;

  /// Opacité du groupe (multiplie celle des couches).
  double opacity;

  /// Multiplicateur d'épaisseur de trait appliqué à toutes les couches.
  double strokeWidth;

  /// Fenêtre d'affichage de la forme sur la timeline.
  int startMs;
  int endMs;
  bool visible;

  final List<ShapeLayer> layers;

  /// Keyframes « pose » : chaque entrée porte toutes les propriétés de la forme.
  final List<ShapeKeyframe> keyframes = <ShapeKeyframe>[];

  int get durationMs => math.max(0, endMs - startMs);

  bool get hasKeyframes => keyframes.isNotEmpty;

  bool isVisibleAt(int timeMs) =>
      visible && timeMs >= startMs && timeMs <= endMs;

  double baseOf(AnimatableProperty property) => switch (property) {
    AnimatableProperty.x => x,
    AnimatableProperty.y => y,
    AnimatableProperty.rotation => rotation,
    AnimatableProperty.scale => scale,
    AnimatableProperty.scaleX => scaleX,
    AnimatableProperty.scaleY => scaleY,
    AnimatableProperty.opacity => opacity,
    AnimatableProperty.strokeWidth => strokeWidth,
  };

  void setBase(AnimatableProperty property, double value) {
    switch (property) {
      case AnimatableProperty.x:
        x = value;
      case AnimatableProperty.y:
        y = value;
      case AnimatableProperty.rotation:
        rotation = value;
      case AnimatableProperty.scale:
        scale = value;
      case AnimatableProperty.scaleX:
        scaleX = value;
      case AnimatableProperty.scaleY:
        scaleY = value;
      case AnimatableProperty.opacity:
        opacity = value;
      case AnimatableProperty.strokeWidth:
        strokeWidth = value;
    }
  }

  /// Valeur (interpolée) de la propriété à l'instant `timeMs`.
  double valueAt(AnimatableProperty property, int timeMs) {
    final base = baseOf(property);
    if (keyframes.isEmpty) return base;
    if (timeMs <= keyframes.first.timeMs) {
      return keyframes.first.valueOf(property) ?? base;
    }
    if (timeMs >= keyframes.last.timeMs) {
      return keyframes.last.valueOf(property) ?? base;
    }
    for (var i = 0; i < keyframes.length - 1; i++) {
      final a = keyframes[i];
      final b = keyframes[i + 1];
      if (timeMs >= a.timeMs && timeMs <= b.timeMs) {
        final span = math.max(1, b.timeMs - a.timeMs);
        final progress = easingProgress(
          b.easing,
          b.bezier,
          (timeMs - a.timeMs) / span,
        );
        final from = a.valueOf(property) ?? base;
        final to = b.valueOf(property) ?? base;
        return from + (to - from) * progress;
      }
    }
    return keyframes.last.valueOf(property) ?? base;
  }

  /// Toutes les propriétés effectives à `timeMs` (base d'une nouvelle pose).
  Map<AnimatableProperty, double> poseAt(int timeMs) =>
      <AnimatableProperty, double>{
        for (final property in AnimatableProperty.values)
          property: valueAt(property, timeMs),
      };

  // ------------------------------------------------------- v0.15 couleur/morph

  /// La pose définit-elle une couleur pour cette couche (indicateur d'UI) ?
  bool layerColorAnimated(String layerId) =>
      keyframes.any((k) => k.layerColors[layerId] != null);

  /// La pose définit-elle des points de morph pour cette couche ?
  bool layerPointsAnimated(String layerId) =>
      keyframes.any((k) => (k.layerPoints[layerId] ?? const []).isNotEmpty);

  /// Couleur RENDUE d'une couche à [timeMs] (v0.15, couleur animée) —
  /// sémantique identique aux poses numériques : chaque pose a une valeur
  /// RÉSOLUE (son entrée, sinon la dernière couleur posée avant elle — carry,
  /// sinon la couleur de base) ; on interpole entre les poses encadrantes
  /// avec la courbe de la pose d'arrivée. Tenue avant la 1re/après la
  /// dernière pose. Aucune pose colorée → [fallback].
  int colorAtLayer(String layerId, int timeMs, int fallback) {
    if (keyframes.isEmpty) return fallback;
    var carry = fallback;
    final resolved =
        <({int timeMs, int color, EasingKind easing, List<double>? bezier})>[];
    for (final key in keyframes) {
      final own = key.layerColors[layerId];
      if (own != null) carry = own;
      resolved.add((
        timeMs: key.timeMs,
        color: carry,
        easing: key.easing,
        bezier: key.bezier,
      ));
    }
    if (timeMs <= resolved.first.timeMs) return resolved.first.color;
    if (timeMs >= resolved.last.timeMs) return resolved.last.color;
    for (var i = 0; i < resolved.length - 1; i++) {
      final a = resolved[i];
      final b = resolved[i + 1];
      if (timeMs >= a.timeMs && timeMs <= b.timeMs) {
        final span = math.max(1, b.timeMs - a.timeMs);
        final progress = easingProgress(
          b.easing,
          b.bezier,
          (timeMs - a.timeMs) / span,
        );
        return lerpArgb(a.color, b.color, progress);
      }
    }
    return resolved.last.color;
  }

  /// Points de path RENDUS d'une couche à [timeMs] (v0.15, morph) — même
  /// sémantique que [colorAtLayer] : valeur résolue par pose (son nuage, sinon
  /// carry, sinon les points de base), interpolation point par point entre
  /// les poses encadrantes, nuage le plus court bourré par répétition de son
  /// dernier point.
  List<Offset> pointsAtLayer(
    String layerId,
    List<Offset> fallback,
    int timeMs,
  ) {
    if (keyframes.isEmpty) return fallback;
    List<Offset> carry = fallback;
    final resolved =
        <
          ({
            int timeMs,
            List<Offset> points,
            EasingKind easing,
            List<double>? bezier,
          })
        >[];
    for (final key in keyframes) {
      final own = key.layerPoints[layerId];
      if (own != null && own.isNotEmpty) carry = own;
      resolved.add((
        timeMs: key.timeMs,
        points: carry,
        easing: key.easing,
        bezier: key.bezier,
      ));
    }
    if (timeMs <= resolved.first.timeMs) return resolved.first.points;
    if (timeMs >= resolved.last.timeMs) return resolved.last.points;
    for (var i = 0; i < resolved.length - 1; i++) {
      final a = resolved[i];
      final b = resolved[i + 1];
      if (timeMs >= a.timeMs && timeMs <= b.timeMs) {
        final span = math.max(1, b.timeMs - a.timeMs);
        final progress = easingProgress(
          b.easing,
          b.bezier,
          (timeMs - a.timeMs) / span,
        );
        return lerpPointLists(a.points, b.points, progress);
      }
    }
    return resolved.last.points;
  }

  /// Écrit la couleur d'une couche (v0.15) : dans la valeur de base si la
  /// forme n'a aucune keyframe, sinon entrée de couleur dans la pose au
  /// curseur (auto-key) — la pose numérique existante est conservée.
  void applyLayerColor(
    ShapeLayer layer,
    int colorValue,
    int timeMs, {
    required bool autoKey,
    int toleranceMs = 0,
  }) {
    if (!autoKey || keyframes.isEmpty) {
      layer.colorValue = colorValue;
      return;
    }
    final target = keyframeNear(timeMs, toleranceMs)?.timeMs ?? timeMs;
    final existing = keyframes.where((k) => k.timeMs == target).firstOrNull;
    if (existing != null) {
      // Fusion : l'entrée de couleur s'ajoute à la pose existante (numérique,
      // easings, couleurs et morph des autres couches préservés).
      existing.layerColors[layer.id] = colorValue;
    } else {
      final pose = poseAt(target);
      final colors = <String, int>{layer.id: colorValue};
      upsertKeyframe(target, pose, layerColors: colors);
    }
  }

  /// Écrit le nuage de points d'une couche (v0.16, éditeur de points) : dans
  /// les points de base si la forme n'a aucune keyframe, sinon entrée de
  /// morph dans la pose au curseur (auto-key) — pose numérique, easings,
  /// couleurs et morph des autres couches conservés. Le nuage fourni est le
  /// nuage COMPLET de la couche (même repère que `ShapeLayer.points`) ; pour
  /// n'éditer qu'un point, l'appelant part de [pointsAtLayer] et déplace
  /// l'index visé — semer le nuage échantillonné est visuellement neutre
  /// (l'extrémité du segment interpolé garde sa valeur).
  void applyLayerPoints(
    ShapeLayer layer,
    List<Offset> points,
    int timeMs, {
    required bool autoKey,
    int toleranceMs = 0,
  }) {
    final cloud = List<Offset>.from(points);
    if (!autoKey || keyframes.isEmpty) {
      layer.points = cloud;
      return;
    }
    final target = keyframeNear(timeMs, toleranceMs)?.timeMs ?? timeMs;
    final existing = keyframes.where((k) => k.timeMs == target).firstOrNull;
    if (existing != null) {
      existing.layerPoints[layer.id] = cloud;
    } else {
      final pose = poseAt(target);
      upsertKeyframe(
        target,
        pose,
        layerPoints: <String, List<Offset>>{layer.id: cloud},
      );
    }
  }

  /// Ajoute un point au chemin d'une couche (v0.16, éditeur de points) :
  /// insertion structurelle dans la base ET dans chaque nuage de morph
  /// existant au même index — la correspondance positionnelle des nuages
  /// (lerp point par point) est préservée. Le même point est inséré partout
  /// (morph plat à cet instant : il diverge dès qu'on le déplace par pose).
  void insertLayerPoint(ShapeLayer layer, int index, Offset point) {
    final i = index.clamp(0, layer.points.length).toInt();
    layer.points.insert(i, point);
    for (final key in keyframes) {
      final entry = key.layerPoints[layer.id];
      if (entry == null || entry.isEmpty) continue;
      entry.insert(i.clamp(0, entry.length).toInt(), point);
    }
  }

  /// Supprime un point du chemin d'une couche (v0.16) : même logique que
  /// [insertLayerPoint] en miroir. Un nuage plus court que [index] est laissé
  /// tel quel (pas de point à supprimer à cette position).
  void removeLayerPoint(ShapeLayer layer, int index) {
    if (index < 0 || index >= layer.points.length) return;
    layer.points.removeAt(index);
    for (final key in keyframes) {
      final entry = key.layerPoints[layer.id];
      if (entry == null || entry.isEmpty || entry.length <= index) continue;
      entry.removeAt(index);
    }
  }

  /// La propriété varie-t-elle entre les keyframes (indicateur d'UI) ?
  bool isAnimated(AnimatableProperty property) {
    if (keyframes.length < 2) return false;
    final reference = valueAt(property, keyframes.first.timeMs);
    return keyframes.any(
      (k) => (k.valueOf(property) ?? reference) != reference,
    );
  }

  /// Keyframe la plus proche de `timeMs` dans la tolérance, ou `null`.
  ShapeKeyframe? keyframeNear(int timeMs, int toleranceMs) {
    ShapeKeyframe? best;
    var bestDelta = toleranceMs;
    for (final key in keyframes) {
      final delta = (key.timeMs - timeMs).abs();
      if (delta <= bestDelta) {
        best = key;
        bestDelta = delta;
      }
    }
    return best;
  }

  /// Ajoute ou remplace la pose à `timeMs`. Remplacement = FUSION : l'easing,
  /// la bézier, les couleurs et les points de morph de la pose existante sont
  /// conservés sauf valeurs explicitement fournies (écrire une position à la
  /// même keyframe n'écrase plus sa courbe custom-bezier — bug v0.13 corrigé
  /// en v0.15, même sémantique que les keyframes d'os).
  void upsertKeyframe(
    int timeMs,
    Map<AnimatableProperty, double> values, {
    EasingKind? easing,
    List<double>? bezier,
    Map<String, int>? layerColors,
    Map<String, List<Offset>>? layerPoints,
  }) {
    ShapeKeyframe? existing;
    for (final key in keyframes) {
      if (key.timeMs == timeMs) {
        existing = key;
        break;
      }
    }
    keyframes.removeWhere((k) => k.timeMs == timeMs);
    keyframes.add(
      ShapeKeyframe(
        timeMs: timeMs,
        values: Map<AnimatableProperty, double>.from(values),
        easing: easing ?? existing?.easing ?? EasingKind.easeInOut,
        bezier: bezier ?? existing?.bezier,
        layerColors: layerColors ?? existing?.layerColors,
        layerPoints: layerPoints ?? existing?.layerPoints,
      ),
    );
    keyframes.sort((a, b) => a.timeMs.compareTo(b.timeMs));
  }

  /// Ajoute une keyframe au temps donné, en capturant les valeurs courantes.
  void addKeyframeAt(int timeMs) => upsertKeyframe(timeMs, poseAt(timeMs));

  void removeKeyframeAt(int timeMs) =>
      keyframes.removeWhere((k) => k.timeMs == timeMs);

  /// Propriétés de TRANSFORMATION keyframables (v0.20) : à la liaison avec
  /// un os, la pièce ne se déplace plus par elle-même — ce sont elles que
  /// [clearTransformKeyframes] efface. Morph, couleurs et opacité ne sont
  /// PAS dans la liste (conservées).
  static const List<AnimatableProperty> transformProperties =
      <AnimatableProperty>[
        AnimatableProperty.x,
        AnimatableProperty.y,
        AnimatableProperty.rotation,
        AnimatableProperty.scale,
        AnimatableProperty.scaleX,
        AnimatableProperty.scaleY,
      ];

  /// Nombre d'entrées de transformation keyframées — affiché dans le
  /// dialogue de confirmation qui précède l'effacement (v0.20).
  int get transformKeyframeCount {
    var count = 0;
    for (final key in keyframes) {
      for (final property in transformProperties) {
        if (key.values.containsKey(property)) count++;
      }
    }
    return count;
  }

  /// Efface les keyframes de TRANSFORMATION (v0.20, à la liaison avec un
  /// os) : position, rotation et échelle disparaissent ; les keyframes de
  /// morph, de couleur et d'opacité sont CONSERVÉES. Une keyframe qui ne
  /// porte plus rien (ni valeur, ni couleur, ni morph) est supprimée.
  /// Retourne le nombre de transformations retirées.
  int clearTransformKeyframes() {
    var cleared = 0;
    for (final key in keyframes) {
      for (final property in transformProperties) {
        if (key.values.remove(property) != null) cleared++;
      }
    }
    keyframes.removeWhere(
      (key) =>
          key.values.isEmpty &&
          key.layerColors.isEmpty &&
          key.layerPoints.isEmpty,
    );
    return cleared;
  }

  /// Miroir du groupe de couches (v0.19) : réflexion du CONTENU autour de
  /// l'origine de la forme. Par couche : drapeau de flip (le painter reflète
  /// le contenu dessiné autour de l'origine de la couche), position et
  /// rotation négées — la double réflexion (action ∘ flip de rendu) est
  /// l'identité sur le contenu : les points de base et les nuages de morph
  /// restent inchangés, tout comme les keyframes de la forme (poses de
  /// scène). [horizontal] = miroir d'axe vertical (gauche ↔ droite), sinon
  /// d'axe horizontal (haut ↔ bas). Deux appels identiques = retour à
  /// l'original (le flip est auto-inverse).
  void mirror({required bool horizontal}) {
    if (isInstance) {
      if (horizontal) {
        flipH = !flipH;
      } else {
        flipV = !flipV;
      }
      return;
    }
    for (final layer in layers) {
      if (horizontal) {
        layer.flipH = !layer.flipH;
        layer.x = -layer.x;
      } else {
        layer.flipV = !layer.flipV;
        layer.y = -layer.y;
      }
      layer.rotation = -layer.rotation;
    }
  }

  /// Remplace toutes les keyframes (presets).
  void setKeyframes(List<ShapeKeyframe> next) {
    keyframes
      ..clear()
      ..addAll(next)
      ..sort((a, b) => a.timeMs.compareTo(b.timeMs));
  }

  void setKeyframeEasing(int timeMs, EasingKind easing) {
    for (final key in keyframes) {
      if (key.timeMs == timeMs) key.easing = easing;
    }
  }

  /// Écrit une propriété : dans la pose au curseur si la forme est déjà
  /// animée, sinon dans la valeur de base.
  void applyValue(
    AnimatableProperty property,
    double value,
    int timeMs, {
    required bool autoKey,
    int toleranceMs = 0,
  }) {
    if (!autoKey || keyframes.isEmpty) {
      setBase(property, value);
      return;
    }
    final target = keyframeNear(timeMs, toleranceMs)?.timeMs ?? timeMs;
    final pose = poseAt(target);
    pose[property] = value;
    upsertKeyframe(target, pose);
  }

  VectorShape copy({String? id, String? name}) {
    final clone = VectorShape(
      id: id ?? this.id,
      name: name ?? this.name,
      layers: layers.map((l) => l.copy()).toList(),
      x: x,
      y: y,
      rotation: rotation,
      scale: scale,
      scaleX: scaleX,
      scaleY: scaleY,
      pivotDx: pivotDx,
      pivotDy: pivotDy,
      opacity: opacity,
      strokeWidth: strokeWidth,
      startMs: startMs,
      endMs: endMs,
      visible: visible,
      embeddedProjectId: embeddedProjectId,
      embeddedWidth: embeddedWidth,
      embeddedHeight: embeddedHeight,
      embeddedIsSkeleton: embeddedIsSkeleton,
      flipH: flipH,
      flipV: flipV,
    );
    for (final key in keyframes) {
      clone.keyframes.add(key.copy());
    }
    return clone;
  }

  /// Clone complet de la forme : couches régénérées (un id de couche est une
  /// clé primaire en base : deux formes ne peuvent pas partager leurs ids)
  /// et keyframes copiées à l'identique (mêmes temps, mêmes courbes). La
  /// fenêtre d'affichage est conservée : le clone se superpose à l'original.
  VectorShape duplicated({String? name}) {
    final clone = copy(
      id: generateId('shape'),
      name: name ?? '${this.name} (copie)',
    );
    for (var i = 0; i < clone.layers.length; i++) {
      clone.layers[i] = clone.layers[i].copy(id: generateId('layer'));
    }
    return clone;
  }

  /// Déplace la fenêtre d'affichage de [deltaMs] (durée inchangée) et décale
  /// toutes les keyframes du même décalage — leurs écarts relatifs et leurs
  /// courbes sont préservés. Pur décalage relatif : borner le décalage pour
  /// que la fenêtre reste dans le projet est du ressort de l'appelant ; les
  /// keyframes hors fenêtre qui passeraient sous zéro sont rabotées à zéro.
  void shiftBy(int deltaMs) {
    if (deltaMs == 0) return;
    startMs += deltaMs;
    endMs += deltaMs;
    for (final key in keyframes) {
      key.timeMs = math.max(0, key.timeMs + deltaMs);
    }
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'x': x,
    'y': y,
    'rotation': rotation,
    'scale': scale,
    'scaleX': scaleX,
    'scaleY': scaleY,
    'pivotDx': pivotDx,
    'pivotDy': pivotDy,
    'opacity': opacity,
    'strokeWidth': strokeWidth,
    'startMs': startMs,
    'endMs': endMs,
    'visible': visible,
    'embeddedProjectId': embeddedProjectId,
    'embeddedWidth': embeddedWidth,
    'embeddedHeight': embeddedHeight,
    'embeddedIsSkeleton': embeddedIsSkeleton,
    'flipH': flipH,
    'flipV': flipV,
    'layers': layers.map((l) => l.toJson()).toList(),
    'keyframes': keyframes.map((k) => k.toJson()).toList(),
  };

  factory VectorShape.fromJson(Map<String, Object?> json) {
    final shape = VectorShape(
      id: json['id'] as String?,
      name: json['name'] as String? ?? 'Forme',
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
      scale: (json['scale'] as num?)?.toDouble() ?? 1,
      scaleX: (json['scaleX'] as num?)?.toDouble() ?? 1,
      scaleY: (json['scaleY'] as num?)?.toDouble() ?? 1,
      pivotDx: (json['pivotDx'] as num?)?.toDouble() ?? 0,
      pivotDy: (json['pivotDy'] as num?)?.toDouble() ?? 0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1,
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 1,
      startMs: (json['startMs'] as num?)?.toInt() ?? 0,
      endMs: (json['endMs'] as num?)?.toInt() ?? 4000,
      visible: json['visible'] as bool? ?? true,
      embeddedProjectId: json['embeddedProjectId'] as String?,
      embeddedWidth: (json['embeddedWidth'] as num?)?.toDouble() ?? 0,
      embeddedHeight: (json['embeddedHeight'] as num?)?.toDouble() ?? 0,
      embeddedIsSkeleton: json['embeddedIsSkeleton'] as bool? ?? false,
      flipH: json['flipH'] as bool? ?? false,
      flipV: json['flipV'] as bool? ?? false,
      layers: (json['layers'] as List<Object?>? ?? const [])
          .map((l) => ShapeLayer.fromJson((l as Map).cast<String, Object?>()))
          .toList(),
    );
    for (final entry in (json['keyframes'] as List<Object?>? ?? const [])) {
      shape.keyframes.add(
        ShapeKeyframe.fromJson((entry as Map).cast<String, Object?>()),
      );
    }
    shape.keyframes.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return shape;
  }
}

/// Le document complet : scène, réglages de temps et formes.
class AnimationProject {
  AnimationProject({
    String? id,
    this.name = 'Nouvelle animation',
    this.type = ProjectType.vector,
    this.skeleton,
    this.width = 360,
    this.height = 640,
    this.fps = 30,
    this.backgroundValue = 0xFF14161C,
    this.coverPath,
    this.createdAt,
    this.updatedAt,
    List<VectorShape>? shapes,
  }) : id = id ?? generateId('project'),
       shapes = shapes ?? <VectorShape>[];

  final String id;
  String name;

  /// Type de projet : `vector` (comportement historique) ou `skeleton`
  /// (un rig d'os anime les pièces du personnage).
  ProjectType type;

  /// Rig du projet squelette (os, liaisons, pistes d'angle). Null pour un
  /// projet vectoriel. Sérialisé en JSON dans la colonne `skeleton`.
  SkeletonRig? skeleton;

  /// Les projets ont tous accès au rig ; ce prédicat conserve les comportements
  /// particuliers d'édition lorsque le projet est historique « squelette » ou
  /// qu'un rig a effectivement été créé/importé.
  bool get usesRigWorkflow => isSkeleton || skeleton != null;

  /// Legacy type retained on disk; it no longer determines capabilities.
  bool get isSkeleton => type == ProjectType.skeleton;

  double width;
  double height;

  /// FPS de l'export le plus récent (choisi dans le dialogue d'export,
  /// jamais à la création) ; sert de défaut au prochain export.
  int fps;
  int backgroundValue;
  String? coverPath;
  DateTime? createdAt;
  DateTime? updatedAt;
  final List<VectorShape> shapes;

  /// Durée du projet : le maximum des fins de segments des formes ; les
  /// keyframes du rig s'ajoutent quel que soit le type historique du projet,
  /// avec un plancher de 4 s tant qu'un rig ou une forme existe. Projet vide → 0.
  int get durationMs {
    var max = 0;
    for (final shape in shapes) {
      if (shape.endMs > max) max = shape.endMs;
    }
    final rig = skeleton;
    if (rig != null && (rig.bones.isNotEmpty || shapes.isNotEmpty)) {
      max = math.max(math.max(max, rig.maxKeyframeTimeMs), 4000);
    }
    return max;
  }

  VectorShape? shapeById(String? id) {
    if (id == null) return null;
    for (final shape in shapes) {
      if (shape.id == id) return shape;
    }
    return null;
  }

  /// Formes visibles à l'instant donné, dans l'ordre de rendu (fond → avant).
  Iterable<VectorShape> visibleShapesAt(int timeMs) =>
      shapes.where((s) => s.isVisibleAt(timeMs));

  void moveShape(int from, int to) {
    if (from < 0 || from >= shapes.length) return;
    final target = to.clamp(0, shapes.length - 1);
    final shape = shapes.removeAt(from);
    shapes.insert(target, shape);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'skeleton': skeleton?.toJson(),
    'width': width,
    'height': height,
    'durationMs': durationMs,
    'fps': fps,
    'backgroundValue': backgroundValue,
    'coverPath': coverPath,
    'createdAt': createdAt?.millisecondsSinceEpoch,
    'updatedAt': updatedAt?.millisecondsSinceEpoch,
    'shapes': shapes.map((s) => s.toJson()).toList(),
  };

  factory AnimationProject.fromJson(
    Map<String, Object?> json,
  ) => AnimationProject(
    id: json['id'] as String?,
    name: json['name'] as String? ?? 'Projet',
    type: ProjectType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => ProjectType.vector,
    ),
    skeleton: json['skeleton'] == null
        ? null
        : SkeletonRig.fromJson(
            (json['skeleton'] as Map).cast<String, Object?>(),
          ),
    width: (json['width'] as num?)?.toDouble() ?? 360,
    height: (json['height'] as num?)?.toDouble() ?? 640,
    fps: (json['fps'] as num?)?.toInt() ?? 30,
    backgroundValue: (json['backgroundValue'] as num?)?.toInt() ?? 0xFF14161C,
    coverPath: json['coverPath'] as String?,
    createdAt: json['createdAt'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            (json['createdAt'] as num).toInt(),
          ),
    updatedAt: json['updatedAt'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            (json['updatedAt'] as num).toInt(),
          ),
    shapes: (json['shapes'] as List<Object?>? ?? const [])
        .map((s) => VectorShape.fromJson((s as Map).cast<String, Object?>()))
        .toList(),
  );

  /// Projet vierge prêt à être édité : pas de durée ni de fps fixés — la
  /// durée sera celle du contenu posé sur la timeline.
  static AnimationProject blank({
    String name = 'Nouvelle animation',
    ProjectFormat format = ProjectFormat.portrait,
    ProjectType type = ProjectType.vector,
  }) => AnimationProject(
    name: name,
    type: type,
    width: format.width,
    height: format.height,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  /// Scène de démonstration : un carré qui tourne + un cercle qui pulse.
  static AnimationProject demo() {
    final project = AnimationProject(
      name: 'Démo',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final square = VectorShape(
      name: 'Carré',
      x: 180,
      y: 240,
      startMs: 0,
      endMs: 4000,
      layers: <ShapeLayer>[
        ShapeLayer(
          name: 'Rectangle',
          kind: ShapeKind.rect,
          width: 130,
          height: 130,
          colorValue: 0xFF5B8DEF,
        ),
      ],
    );
    final squarePose = square.poseAt(0);
    square.setKeyframes(<ShapeKeyframe>[
      ShapeKeyframe(
        timeMs: 0,
        values: <AnimatableProperty, double>{
          ...squarePose,
          AnimatableProperty.rotation: 0,
          AnimatableProperty.y: 240,
        },
      ),
      ShapeKeyframe(
        timeMs: 2000,
        values: <AnimatableProperty, double>{
          ...squarePose,
          AnimatableProperty.rotation: 3.14159,
          AnimatableProperty.y: 160,
        },
      ),
      ShapeKeyframe(
        timeMs: 4000,
        values: <AnimatableProperty, double>{
          ...squarePose,
          AnimatableProperty.rotation: 6.28318,
          AnimatableProperty.y: 240,
        },
      ),
    ]);

    final circle = VectorShape(
      name: 'Cercle',
      x: 180,
      y: 480,
      startMs: 500,
      endMs: 3500,
      layers: <ShapeLayer>[
        ShapeLayer(
          name: 'Cercle',
          kind: ShapeKind.circle,
          width: 90,
          height: 90,
          colorValue: 0xFF3ECF8E,
          filled: false,
          strokeWidth: 8,
        ),
      ],
    );
    final circlePose = circle.poseAt(0);
    circle.setKeyframes(<ShapeKeyframe>[
      for (final (time, scale) in <(int, double)>[
        (500, 0.6),
        (1500, 1.4),
        (3000, 0.6),
        (3500, 0.6),
      ])
        ShapeKeyframe(
          timeMs: time,
          values: <AnimatableProperty, double>{
            ...circlePose,
            AnimatableProperty.scale: scale,
          },
        ),
    ]);

    project.shapes.addAll(<VectorShape>[square, circle]);
    return project;
  }
}
