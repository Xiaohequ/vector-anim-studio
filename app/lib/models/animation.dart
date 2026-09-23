import 'dart:math' as math;
import 'dart:ui' show Offset;

/// Type de forme basique dessinable dans une couche.
enum ShapeKind { rect, circle, line, path, triangle, star, hexagon, cross, heart, arrow }

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
enum AnimatableProperty { x, y, rotation, scale, opacity, strokeWidth }

/// Interpolations disponibles entre deux keyframes.
enum EasingKind { linear, easeIn, easeOut, easeInOut, step }

/// Formats de projet proposés à la création.
enum ProjectFormat { portrait, landscape, square }

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
  }
}

/// Étiquette lisible d'une propriété (interface).
String propertyLabel(AnimatableProperty property) => switch (property) {
      AnimatableProperty.x => 'Position X',
      AnimatableProperty.y => 'Position Y',
      AnimatableProperty.rotation => 'Rotation',
      AnimatableProperty.scale => 'Échelle',
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
      (durationMs * keyframeSnapTolerancePx / keyframeNominalTimelineWidth)
          .round(),
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
    };

/// Une keyframe « pose » : toutes les propriétés de la forme à `timeMs`.
class ShapeKeyframe {
  ShapeKeyframe({
    required this.timeMs,
    Map<AnimatableProperty, double>? values,
    this.easing = EasingKind.easeInOut,
  }) : values = values ?? <AnimatableProperty, double>{};

  int timeMs;

  /// Courbe d'interpolation du segment qui arrive sur cette keyframe.
  EasingKind easing;

  final Map<AnimatableProperty, double> values;

  double? valueOf(AnimatableProperty property) => values[property];

  ShapeKeyframe copy() => ShapeKeyframe(
        timeMs: timeMs,
        values: Map<AnimatableProperty, double>.from(values),
        easing: easing,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'timeMs': timeMs,
        'easing': easing.name,
        'values': <String, double>{
          for (final entry in values.entries) entry.key.name: entry.value,
        },
      };

  static ShapeKeyframe fromJson(Map<String, Object?> json) {
    final raw = (json['values'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};
    return ShapeKeyframe(
      timeMs: (json['timeMs'] as num).toInt(),
      easing: EasingKind.values.firstWhere(
        (e) => e.name == json['easing'],
        orElse: () => EasingKind.easeInOut,
      ),
      values: <AnimatableProperty, double>{
        for (final property in AnimatableProperty.values)
          if (raw[property.name] != null)
            property: (raw[property.name] as num).toDouble(),
      },
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
  })  : id = id ?? generateId('layer'),
        points = points ?? <Offset>[];

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
      );
}

/// Propriétés éditables d'une couche (non animées).
enum LayerProperty { x, y, width, height, rotation, scale, opacity, strokeWidth }

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
    this.opacity = 1,
    this.strokeWidth = 1,
    this.startMs = 0,
    this.endMs = 4000,
    this.visible = true,
    this.embeddedProjectId,
    this.embeddedWidth = 0,
    this.embeddedHeight = 0,
  })  : id = id ?? generateId('shape'),
        layers = layers ?? <ShapeLayer>[];

  final String id;
  String name;

  /// Identifiant du projet imbriqué (instance d'animation) : la forme ne
  /// porte aucune couche, elle rend le projet source dans sa pose.
  String? embeddedProjectId;

  /// Dimensions du projet source, capturées à l'insertion (sélection, bounds).
  double embeddedWidth;
  double embeddedHeight;

  bool get isInstance => embeddedProjectId != null;

  /// Transformation de groupe (centre de la forme).
  double x;
  double y;
  double rotation;
  double scale;
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
        final progress = applyEasing(b.easing, (timeMs - a.timeMs) / span);
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

  /// La propriété varie-t-elle entre les keyframes (indicateur d'UI) ?
  bool isAnimated(AnimatableProperty property) {
    if (keyframes.length < 2) return false;
    final reference = valueAt(property, keyframes.first.timeMs);
    return keyframes.any((k) => (k.valueOf(property) ?? reference) != reference);
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

  /// Ajoute ou remplace la pose à `timeMs`.
  void upsertKeyframe(
    int timeMs,
    Map<AnimatableProperty, double> values, {
    EasingKind? easing,
  }) {
    keyframes.removeWhere((k) => k.timeMs == timeMs);
    keyframes.add(
      ShapeKeyframe(
        timeMs: timeMs,
        values: Map<AnimatableProperty, double>.from(values),
        easing: easing ?? EasingKind.easeInOut,
      ),
    );
    keyframes.sort((a, b) => a.timeMs.compareTo(b.timeMs));
  }

  /// Ajoute une keyframe au temps donné, en capturant les valeurs courantes.
  void addKeyframeAt(int timeMs) => upsertKeyframe(timeMs, poseAt(timeMs));

  void removeKeyframeAt(int timeMs) =>
      keyframes.removeWhere((k) => k.timeMs == timeMs);

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
      opacity: opacity,
      strokeWidth: strokeWidth,
      startMs: startMs,
      endMs: endMs,
      visible: visible,
      embeddedProjectId: embeddedProjectId,
      embeddedWidth: embeddedWidth,
      embeddedHeight: embeddedHeight,
    );
    for (final key in keyframes) {
      clone.keyframes.add(key.copy());
    }
    return clone;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'x': x,
        'y': y,
        'rotation': rotation,
        'scale': scale,
        'opacity': opacity,
        'strokeWidth': strokeWidth,
        'startMs': startMs,
        'endMs': endMs,
        'visible': visible,
        'embeddedProjectId': embeddedProjectId,
        'embeddedWidth': embeddedWidth,
        'embeddedHeight': embeddedHeight,
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
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1,
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 1,
      startMs: (json['startMs'] as num?)?.toInt() ?? 0,
      endMs: (json['endMs'] as num?)?.toInt() ?? 4000,
      visible: json['visible'] as bool? ?? true,
      embeddedProjectId: json['embeddedProjectId'] as String?,
      embeddedWidth: (json['embeddedWidth'] as num?)?.toDouble() ?? 0,
      embeddedHeight: (json['embeddedHeight'] as num?)?.toDouble() ?? 0,
      layers: (json['layers'] as List<Object?>? ?? const [])
          .map((l) => ShapeLayer.fromJson((l as Map).cast<String, Object?>()))
          .toList(),
    );
    for (final entry in (json['keyframes'] as List<Object?>? ?? const [])) {
      shape.keyframes
          .add(ShapeKeyframe.fromJson((entry as Map).cast<String, Object?>()));
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
    this.width = 360,
    this.height = 640,
    this.durationMs = 4000,
    this.fps = 30,
    this.backgroundValue = 0xFF14161C,
    this.coverPath,
    this.createdAt,
    this.updatedAt,
    List<VectorShape>? shapes,
  })  : id = id ?? generateId('project'),
        shapes = shapes ?? <VectorShape>[];

  final String id;
  String name;
  double width;
  double height;
  int durationMs;
  int fps;
  int backgroundValue;
  String? coverPath;
  DateTime? createdAt;
  DateTime? updatedAt;
  final List<VectorShape> shapes;

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

  factory AnimationProject.fromJson(Map<String, Object?> json) =>
      AnimationProject(
        id: json['id'] as String?,
        name: json['name'] as String? ?? 'Projet',
        width: (json['width'] as num?)?.toDouble() ?? 360,
        height: (json['height'] as num?)?.toDouble() ?? 640,
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 4000,
        fps: (json['fps'] as num?)?.toInt() ?? 30,
        backgroundValue:
            (json['backgroundValue'] as num?)?.toInt() ?? 0xFF14161C,
        coverPath: json['coverPath'] as String?,
        createdAt: json['createdAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((json['createdAt'] as num).toInt()),
        updatedAt: json['updatedAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((json['updatedAt'] as num).toInt()),
        shapes: (json['shapes'] as List<Object?>? ?? const [])
            .map((s) => VectorShape.fromJson((s as Map).cast<String, Object?>()))
            .toList(),
      );

  /// Projet vierge prêt à être édité.
  static AnimationProject blank({
    String name = 'Nouvelle animation',
    ProjectFormat format = ProjectFormat.portrait,
    int durationMs = 4000,
    int fps = 30,
  }) =>
      AnimationProject(
        name: name,
        width: format.width,
        height: format.height,
        durationMs: durationMs,
        fps: fps,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

  /// Scène de démonstration : un carré qui tourne + un cercle qui pulse.
  static AnimationProject demo() {
    final project = AnimationProject(
      name: 'Démo',
      durationMs: 4000,
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
