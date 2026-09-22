import 'dart:math' as math;
import 'dart:ui' show Offset;

/// Type de forme vectorielle dessinable.
enum ShapeKind { rect, circle, line, path }

/// Propriétés pouvant être animées par keyframes.
enum AnimatableProperty {
  x,
  y,
  width,
  height,
  rotation,
  scale,
  opacity,
  strokeWidth,
}

/// Interpolations disponibles entre deux keyframes.
enum EasingKind { linear, easeIn, easeOut, easeInOut, step }

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
String propertyLabel(AnimatableProperty property) {
  switch (property) {
    case AnimatableProperty.x:
      return 'Position X';
    case AnimatableProperty.y:
      return 'Position Y';
    case AnimatableProperty.width:
      return 'Largeur';
    case AnimatableProperty.height:
      return 'Hauteur';
    case AnimatableProperty.rotation:
      return 'Rotation';
    case AnimatableProperty.scale:
      return 'Échelle';
    case AnimatableProperty.opacity:
      return 'Opacité';
    case AnimatableProperty.strokeWidth:
      return 'Épaisseur';
  }
}

/// Un point de contrôle temporel : valeur atteinte à `timeMs`.
class Keyframe {
  Keyframe(this.timeMs, this.value, {this.easing = EasingKind.easeInOut});

  final int timeMs;
  final double value;
  final EasingKind easing;

  Map<String, Object?> toJson() => {
        'timeMs': timeMs,
        'value': value,
        'easing': easing.name,
      };

  factory Keyframe.fromJson(Map<String, Object?> json) => Keyframe(
        (json['timeMs'] as num).toInt(),
        (json['value'] as num).toDouble(),
        easing: EasingKind.values.firstWhere(
          (e) => e.name == json['easing'],
          orElse: () => EasingKind.easeInOut,
        ),
      );
}

/// Piste d'animation d'une propriété : suite de keyframes triées.
class AnimTrack {
  AnimTrack(this.property);

  final AnimatableProperty property;
  final List<Keyframe> keys = <Keyframe>[];

  bool get isEmpty => keys.isEmpty;

  /// Ajoute (ou remplace) une keyframe au temps donné.
  void setKey(int timeMs, double value, {EasingKind? easing}) {
    keys.removeWhere((k) => k.timeMs == timeMs);
    keys.add(Keyframe(timeMs, value, easing: easing ?? EasingKind.easeInOut));
    keys.sort((a, b) => a.timeMs.compareTo(b.timeMs));
  }

  void removeKeyAt(int timeMs) => keys.removeWhere((k) => k.timeMs == timeMs);

  /// Échantillonne la piste à l'instant `timeMs`.
  double sample(int timeMs, double fallback) {
    if (keys.isEmpty) return fallback;
    if (timeMs <= keys.first.timeMs) return keys.first.value;
    if (timeMs >= keys.last.timeMs) return keys.last.value;
    for (var i = 0; i < keys.length - 1; i++) {
      final a = keys[i];
      final b = keys[i + 1];
      if (timeMs >= a.timeMs && timeMs <= b.timeMs) {
        final span = math.max(1, b.timeMs - a.timeMs);
        final progress = applyEasing(b.easing, (timeMs - a.timeMs) / span);
        return a.value + (b.value - a.value) * progress;
      }
    }
    return keys.last.value;
  }

  Map<String, Object?> toJson() => {
        'property': property.name,
        'keys': keys.map((k) => k.toJson()).toList(),
      };

  factory AnimTrack.fromJson(Map<String, Object?> json) {
    final track = AnimTrack(
      AnimatableProperty.values.firstWhere((p) => p.name == json['property']),
    );
    for (final entry in (json['keys'] as List<Object?>)) {
      track.keys.add(Keyframe.fromJson((entry as Map).cast<String, Object?>()));
    }
    track.keys.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return track;
  }
}

/// Une forme vectorielle de la scène, avec ses valeurs de base et ses pistes.
class VectorShape {
  VectorShape({
    required this.id,
    required this.name,
    required this.kind,
    this.x = 180,
    this.y = 320,
    this.width = 120,
    this.height = 120,
    this.rotation = 0,
    this.scale = 1,
    this.opacity = 1,
    this.strokeWidth = 4,
    this.colorValue = 0xFF5B8DEF,
    this.filled = true,
    List<Offset>? points,
  }) : points = points ?? <Offset>[];

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

  final Map<AnimatableProperty, AnimTrack> tracks =
      <AnimatableProperty, AnimTrack>{};

  double baseOf(AnimatableProperty property) {
    switch (property) {
      case AnimatableProperty.x:
        return x;
      case AnimatableProperty.y:
        return y;
      case AnimatableProperty.width:
        return width;
      case AnimatableProperty.height:
        return height;
      case AnimatableProperty.rotation:
        return rotation;
      case AnimatableProperty.scale:
        return scale;
      case AnimatableProperty.opacity:
        return opacity;
      case AnimatableProperty.strokeWidth:
        return strokeWidth;
    }
  }

  void setBase(AnimatableProperty property, double value) {
    switch (property) {
      case AnimatableProperty.x:
        x = value;
      case AnimatableProperty.y:
        y = value;
      case AnimatableProperty.width:
        width = value;
      case AnimatableProperty.height:
        height = value;
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

  /// Valeur animée de la propriété à l'instant `timeMs`.
  double valueAt(AnimatableProperty property, int timeMs) {
    final track = tracks[property];
    final base = baseOf(property);
    if (track == null || track.isEmpty) return base;
    return track.sample(timeMs, base);
  }

  bool isAnimated(AnimatableProperty property) {
    final track = tracks[property];
    return track != null && !track.isEmpty;
  }

  /// Ajoute une keyframe à l'instant courant, avec la valeur courante.
  void addKeyframeAt(AnimatableProperty property, int timeMs) {
    final track = tracks.putIfAbsent(property, () => AnimTrack(property));
    track.setKey(timeMs, valueAt(property, timeMs));
  }

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
        'tracks': tracks.values.map((t) => t.toJson()).toList(),
      };

  factory VectorShape.fromJson(Map<String, Object?> json) {
    final shape = VectorShape(
      id: json['id'] as String,
      name: json['name'] as String,
      kind: ShapeKind.values.firstWhere((k) => k.name == json['kind']),
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      rotation: (json['rotation'] as num).toDouble(),
      scale: (json['scale'] as num).toDouble(),
      opacity: (json['opacity'] as num).toDouble(),
      strokeWidth: (json['strokeWidth'] as num).toDouble(),
      colorValue: (json['colorValue'] as num).toInt(),
      filled: json['filled'] as bool,
      points: (json['points'] as List<Object?>)
          .map((p) => (p as List<Object?>))
          .map((p) => Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()))
          .toList(),
    );
    for (final entry in (json['tracks'] as List<Object?>? ?? const [])) {
      final track = AnimTrack.fromJson((entry as Map).cast<String, Object?>());
      shape.tracks[track.property] = track;
    }
    return shape;
  }
}

/// Le document complet : scène, réglages de temps et formes.
class AnimationProject {
  AnimationProject({
    this.name = 'Nouvelle animation',
    this.width = 360,
    this.height = 640,
    this.durationMs = 4000,
    this.fps = 30,
    this.backgroundValue = 0xFF14161C,
    List<VectorShape>? shapes,
  }) : shapes = shapes ?? <VectorShape>[];

  String name;
  double width;
  double height;
  int durationMs;
  int fps;
  int backgroundValue;
  final List<VectorShape> shapes;

  VectorShape? shapeById(String? id) {
    if (id == null) return null;
    for (final shape in shapes) {
      if (shape.id == id) return shape;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'name': name,
        'width': width,
        'height': height,
        'durationMs': durationMs,
        'fps': fps,
        'backgroundValue': backgroundValue,
        'shapes': shapes.map((s) => s.toJson()).toList(),
      };

  factory AnimationProject.fromJson(Map<String, Object?> json) =>
      AnimationProject(
        name: json['name'] as String,
        width: (json['width'] as num).toDouble(),
        height: (json['height'] as num).toDouble(),
        durationMs: (json['durationMs'] as num).toInt(),
        fps: (json['fps'] as num).toInt(),
        backgroundValue: (json['backgroundValue'] as num).toInt(),
        shapes: (json['shapes'] as List<Object?>)
            .map((s) => VectorShape.fromJson((s as Map).cast<String, Object?>()))
            .toList(),
      );

  /// Scène de démonstration : un carré qui tourne + un cercle qui pulse.
  static AnimationProject demo() {
    final project = AnimationProject(durationMs: 4000);
    final square = VectorShape(
      id: 'shape-1',
      name: 'Carré',
      kind: ShapeKind.rect,
      x: 180,
      y: 240,
      width: 130,
      height: 130,
      colorValue: 0xFF5B8DEF,
    );
    square.tracks[AnimatableProperty.rotation] =
        AnimTrack(AnimatableProperty.rotation)
          ..setKey(0, 0)
          ..setKey(2000, 3.14159)
          ..setKey(4000, 6.28318);
    square.tracks[AnimatableProperty.y] = AnimTrack(AnimatableProperty.y)
      ..setKey(0, 240)
      ..setKey(2000, 160)
      ..setKey(4000, 240);

    final circle = VectorShape(
      id: 'shape-2',
      name: 'Cercle',
      kind: ShapeKind.circle,
      x: 180,
      y: 480,
      width: 90,
      height: 90,
      colorValue: 0xFF3ECF8E,
      filled: false,
      strokeWidth: 8,
    );
    circle.tracks[AnimatableProperty.scale] = AnimTrack(AnimatableProperty.scale)
      ..setKey(0, 0.6)
      ..setKey(1500, 1.4)
      ..setKey(3000, 0.6)
      ..setKey(4000, 0.6);

    project.shapes.addAll(<VectorShape>[square, circle]);
    return project;
  }
}