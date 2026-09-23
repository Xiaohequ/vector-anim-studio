import 'dart:math' as math;
import 'dart:ui' show Offset;

/// Type de forme basique dessinable dans une couche.
enum ShapeKind { rect, circle, line, path }

String shapeKindLabel(ShapeKind kind) => switch (kind) {
      ShapeKind.rect => 'Rectangle',
      ShapeKind.circle => 'Cercle',
      ShapeKind.line => 'Ligne',
      ShapeKind.path => 'Chemin',
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

/// Un point de contrôle temporel : valeur atteinte à `timeMs`.
class Keyframe {
  Keyframe(this.timeMs, this.value, {this.easing = EasingKind.easeInOut});

  final int timeMs;
  final double value;
  final EasingKind easing;

  Keyframe copyWith({int? timeMs, double? value, EasingKind? easing}) =>
      Keyframe(timeMs ?? this.timeMs, value ?? this.value,
          easing: easing ?? this.easing);

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
  bool get isNotEmpty => keys.isNotEmpty;

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
      AnimatableProperty.values.firstWhere(
        (p) => p.name == json['property'],
        orElse: () => AnimatableProperty.x,
      ),
    );
    for (final entry in (json['keys'] as List<Object?>? ?? const [])) {
      track.keys.add(Keyframe.fromJson((entry as Map).cast<String, Object?>()));
    }
    track.keys.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return track;
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
  })  : id = id ?? generateId('shape'),
        layers = layers ?? <ShapeLayer>[];

  final String id;
  String name;

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
  final Map<AnimatableProperty, AnimTrack> tracks =
      <AnimatableProperty, AnimTrack>{};

  int get durationMs => math.max(0, endMs - startMs);

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

  /// Valeur animée de la propriété à l'instant `timeMs`.
  double valueAt(AnimatableProperty property, int timeMs) {
    final track = tracks[property];
    final base = baseOf(property);
    if (track == null || track.isEmpty) return base;
    return track.sample(timeMs, base);
  }

  bool isAnimated(AnimatableProperty property) {
    final track = tracks[property];
    return track != null && track.isNotEmpty;
  }

  /// Ajoute une keyframe à l'instant courant, avec la valeur courante.
  void addKeyframeAt(AnimatableProperty property, int timeMs) {
    final track = tracks.putIfAbsent(property, () => AnimTrack(property));
    track.setKey(timeMs, valueAt(property, timeMs));
  }

  void removeTrack(AnimatableProperty property) => tracks.remove(property);

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
    );
    for (final entry in tracks.entries) {
      final track = AnimTrack(entry.key);
      for (final key in entry.value.keys) {
        track.keys.add(key.copyWith());
      }
      clone.tracks[entry.key] = track;
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
        'layers': layers.map((l) => l.toJson()).toList(),
        'tracks': tracks.values.map((t) => t.toJson()).toList(),
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
      layers: (json['layers'] as List<Object?>? ?? const [])
          .map((l) => ShapeLayer.fromJson((l as Map).cast<String, Object?>()))
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
    square.tracks[AnimatableProperty.rotation] = AnimTrack(
      AnimatableProperty.rotation,
    )
      ..setKey(0, 0)
      ..setKey(2000, 3.14159)
      ..setKey(4000, 6.28318);
    square.tracks[AnimatableProperty.y] = AnimTrack(AnimatableProperty.y)
      ..setKey(0, 240)
      ..setKey(2000, 160)
      ..setKey(4000, 240);

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
    circle.tracks[AnimatableProperty.scale] = AnimTrack(AnimatableProperty.scale)
      ..setKey(500, 0.6)
      ..setKey(1500, 1.4)
      ..setKey(3000, 0.6)
      ..setKey(3500, 0.6);

    project.shapes.addAll(<VectorShape>[square, circle]);
    return project;
  }
}
