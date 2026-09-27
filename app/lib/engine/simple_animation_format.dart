import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../models/animation.dart';
import '../models/skeleton.dart';

/// Format d'échange « vasf » : un JSON SIMPLE, pensé pour être ÉCRIT par un
/// agent IA (ou à la main), converti vers/depuis le projet interne. Spécification
/// complète et exemples : `docs/vasf-1-format.md`.
///
/// Contrats : temps en secondes, couleurs « #RRGGBB » (ou alias « $nom » de la
/// palette `theme`), angles en DEGRÉS monde (y vers le bas, positif = horaire),
/// keyframes partielles (une propriété absente hérite de la keyframe précédente
/// ou de la base), ordre de dessin = ordre de la liste, `joint`/`angle` d'os et
/// `keyframes[].angle` exprimés MONDE (l'import convertit en interne).
///
/// Extensions v2 (champs optionnels, l'import développe, le moteur est
/// inchangé) : `theme` (palette d'alias), `layers[]` (formes multi-couches),
/// `cycle.repeat` (répétition du motif de keyframes), `defs` + `ref`
/// (définitions réutilisables). Un fichier `version: 1` reste importable.
class SimpleAnimationFormat {
  SimpleAnimationFormat._();

  static const int version = 1;

  /// Version des fichiers qui utilisent les extensions v2 (multi-couches).
  static const int version2 = 2;

  /// Version des fichiers qui utilisent les extensions v3 (v0.15, moteur
  /// lourd) : couleur animée, morph de points, translation d'os.
  static const int version3 = 3;

  // Défauts (canvas validé utilisateur : 720×1280, 25 fps).
  static const double defaultWidth = 720;
  static const double defaultHeight = 1280;
  static const int defaultFps = 25;
  static const int defaultBackground = 0xFF14161C;
  static const int defaultShapeColor = 0xFF5B8DEF;
  static const double defaultShapeSize = 110;

  /// Le JSON est-il au format simple (vasf) plutôt qu'au format interne ?
  static bool isSimpleFormat(Map<String, Object?> json) =>
      json.containsKey('version');

  // ------------------------------------------------------------------ export

  /// Projet interne → JSON simple. Les instances de projet imbriquées sont
  /// ignorées (non représentées en v1, voir la doc).
  static Map<String, Object?> toJson(AnimationProject project) {
    final shapes = <Map<String, Object?>>[];
    var usesV2 = false;
    var usesV3 = false;
    // Une forme avec une liaison de COUCHE est exportée en layers[] (avec
    // une seule couche si besoin) : le nom de couche doit survivre au
    // round-trip pour que « Forme/Couche » reste importable.
    final layerBoundIds = project.isSkeleton && project.skeleton != null
        ? project.skeleton!.bindings
              .where((b) => b.layerId != null)
              .map((b) => b.shapeId)
              .toSet()
        : <String>{};
    for (final shape in project.shapes) {
      if (shape.isInstance) continue;
      final forceLayers = layerBoundIds.contains(shape.id);
      if (shape.layers.length > 1 || forceLayers || _shapeExtrasUseV2(shape)) {
        usesV2 = true;
      }
      if (_shapeUsesV3(shape)) usesV3 = true;
      shapes.add(_shapeToJson(shape, forceLayers: forceLayers));
    }
    final rig = project.skeleton;
    if (project.isSkeleton && rig != null) {
      for (final track in rig.tracks.values) {
        if (track.any((k) => k.easing == EasingKind.customBezier)) {
          usesV2 = true;
        }
        if (track.any((k) => k.tx != 0 || k.ty != 0)) usesV3 = true;
      }
      if (rig.bindings.any((b) => b.layerId != null)) usesV2 = true;
    }
    final json = <String, Object?>{
      'version': usesV3
          ? version3
          : usesV2
          ? version2
          : version,
      'name': project.name,
      'canvas': <String, Object?>{
        'width': project.width,
        'height': project.height,
        'fps': project.fps,
        'background': _colorToHex(project.backgroundValue),
      },
      'shapes': shapes,
    };
    if (project.isSkeleton && rig != null) {
      json['skeleton'] = _skeletonToJson(rig, project);
    }
    return json;
  }

  static Map<String, Object?> _shapeToJson(
    VectorShape shape, {
    bool forceLayers = false,
  }) {
    if (shape.layers.length > 1 || forceLayers) {
      return _multiLayerShapeToJson(shape);
    }
    final layer = shape.layers.isEmpty
        ? ShapeLayer(name: 'Couche', kind: ShapeKind.rect)
        : shape.layers.first;
    final json = <String, Object?>{
      'name': shape.name,
      'type': layer.kind.name,
      'color': _colorToHex(layer.colorValue),
      'filled': layer.filled,
      'strokeWidth': layer.strokeWidth,
      'width': layer.width,
      'height': layer.height,
      'start': shape.startMs / 1000,
      'end': shape.endMs / 1000,
      'x': shape.x,
      'y': shape.y,
      'rotation': _radToDeg(shape.rotation),
      'scale': shape.scale,
      'opacity': shape.opacity,
    };
    if (layer.kind == ShapeKind.path && layer.points.isNotEmpty) {
      json['points'] = _pointsToJson(layer);
    }
    _addShapeLevelExtras(json, shape);
    _addShapeKeyframes(json, shape, multiLayer: false);
    return json;
  }

  /// Les champs extras de la forme (axes, pivot, bezier) forcent-ils la v2 ?
  static bool _shapeExtrasUseV2(VectorShape shape) {
    if (shape.scaleX != 1 || shape.scaleY != 1) return true;
    if (shape.pivotDx != 0 || shape.pivotDy != 0) return true;
    for (final key in shape.keyframes) {
      if (key.easing == EasingKind.customBezier) return true;
    }
    return false;
  }

  /// La forme utilise-t-elle une extension v3 (couleur animée, morph) ?
  static bool _shapeUsesV3(VectorShape shape) {
    for (final key in shape.keyframes) {
      if (key.layerColors.isNotEmpty) return true;
      if (key.layerPoints.isNotEmpty) return true;
    }
    return false;
  }

  /// Champs v2 au niveau forme (facteurs d'axe, pivot) — émis seulement
  /// quand ils s'écartent des défauts.
  static void _addShapeLevelExtras(
    Map<String, Object?> json,
    VectorShape shape,
  ) {
    if (shape.scaleX != 1) json['scaleX'] = shape.scaleX;
    if (shape.scaleY != 1) json['scaleY'] = shape.scaleY;
    if (shape.pivotDx != 0 || shape.pivotDy != 0) {
      json['pivot'] = [shape.pivotDx, shape.pivotDy];
    }
  }

  /// Forme multi-couches (vasf-2) : chaque couche porte sa primitive.
  static Map<String, Object?> _multiLayerShapeToJson(VectorShape shape) {
    final json = <String, Object?>{
      'name': shape.name,
      'layers': [for (final layer in shape.layers) _layerToJson(layer)],
      'start': shape.startMs / 1000,
      'end': shape.endMs / 1000,
      'x': shape.x,
      'y': shape.y,
      'rotation': _radToDeg(shape.rotation),
      'scale': shape.scale,
      'opacity': shape.opacity,
    };
    _addShapeLevelExtras(json, shape);
    _addShapeKeyframes(json, shape, multiLayer: true);
    return json;
  }

  static Map<String, Object?> _layerToJson(ShapeLayer layer) {
    final json = <String, Object?>{
      'name': layer.name,
      'type': layer.kind.name,
      'color': _colorToHex(layer.colorValue),
      'filled': layer.filled,
      'strokeWidth': layer.strokeWidth,
      'width': layer.width,
      'height': layer.height,
    };
    if (layer.x != 0) json['x'] = layer.x;
    if (layer.y != 0) json['y'] = layer.y;
    if (layer.rotation != 0) json['rotation'] = _radToDeg(layer.rotation);
    if (layer.scale != 1) json['scale'] = layer.scale;
    if (layer.opacity != 1) json['opacity'] = layer.opacity;
    if (layer.kind == ShapeKind.path && layer.points.isNotEmpty) {
      json['points'] = _pointsToJson(layer);
    }
    return json;
  }

  static void _addShapeKeyframes(
    Map<String, Object?> json,
    VectorShape shape, {
    required bool multiLayer,
  }) {
    if (!shape.hasKeyframes) return;
    // Export sparse : une propriété égale à la keyframe précédente (ou à
    // la base pour la première) est omise.
    final previous = <AnimatableProperty, double>{
      for (final property in AnimatableProperty.values)
        property: shape.baseOf(property),
    };
    // Mode à plat : la (seule) couche porte la couleur/le morph dans la
    // keyframe (`color` / `points`). Mode layers[] : maps par NOM de couche
    // (`colors` / `layerPoints`).
    final flatLayer = multiLayer
        ? null
        : (shape.layers.isEmpty ? null : shape.layers.first);
    final layersByName = multiLayer
        ? <String, ShapeLayer>{
            for (final layer in shape.layers) layer.name: layer,
          }
        : null;
    json['keyframes'] = [
      for (final key in shape.keyframes)
        _shapeKeyframeToJson(
          key,
          previous,
          flatLayer: flatLayer,
          layersByName: layersByName,
        ),
    ];
  }

  /// Centre du nuage de points STOCKÉS d'une couche (repère boîte) — la
  /// même constante que l'export des points de base : keyframes et base
  /// partagent un repère cohérent (morph, v0.15).
  static Offset _storedPointsCenter(ShapeLayer layer) {
    if (layer.points.isEmpty) return Offset(layer.width / 2, layer.height / 2);
    final minx = layer.points.map((p) => p.dx).reduce(math.min);
    final maxx = layer.points.map((p) => p.dx).reduce(math.max);
    final miny = layer.points.map((p) => p.dy).reduce(math.min);
    final maxy = layer.points.map((p) => p.dy).reduce(math.max);
    return Offset((minx + maxx) / 2, (miny + maxy) / 2);
  }

  static List<Object?> _pointsToJson(ShapeLayer layer) => [
    for (final p in layer.points)
      [
        p.dx - layer.width / 2 + _storedPointsCenter(layer).dx,
        p.dy - layer.height / 2 + _storedPointsCenter(layer).dy,
      ],
  ];

  /// Points exportés avec un centre DONNÉ (keyframes de morph : le centre
  /// de la BASE — recentrer chaque keyframe indépendamment briserait le
  /// morph).
  static List<Object?> _pointsToCenteredJson(
    List<Offset> points,
    double width,
    double height,
    Offset center,
  ) => [
    for (final p in points)
      [p.dx - width / 2 + center.dx, p.dy - height / 2 + center.dy],
  ];

  static Map<String, Object?> _shapeKeyframeToJson(
    ShapeKeyframe key,
    Map<AnimatableProperty, double> previous, {
    ShapeLayer? flatLayer,
    Map<String, ShapeLayer>? layersByName,
  }) {
    final json = <String, Object?>{
      't': key.timeMs / 1000,
      'easing': key.easing == EasingKind.customBezier
          ? _bezierToJson(key.bezier)
          : key.easing.name,
    };
    for (final property in AnimatableProperty.values) {
      final value = key.valueOf(property);
      if (value == null) continue;
      if ((previous[property]! - value).abs() < 1e-9) continue;
      json[property.name] = property == AnimatableProperty.rotation
          ? _radToDeg(value)
          : value;
      previous[property] = value;
    }
    // Couleur animée (v0.15) : `color` (à plat) ou `colors` par nom (couches).
    if (flatLayer != null) {
      final color = key.layerColors[flatLayer.id];
      if (color != null) json['color'] = _colorToHex(color);
    } else if (layersByName != null && key.layerColors.isNotEmpty) {
      final colors = <String, Object?>{};
      for (final entry in key.layerColors.entries) {
        final layer = layersByName.values
            .where((l) => l.id == entry.key)
            .firstOrNull;
        if (layer != null) colors[layer.name] = _colorToHex(entry.value);
      }
      if (colors.isNotEmpty) json['colors'] = colors;
    }
    // Morph de points (v0.15) : `points` (à plat) ou `layerPoints` par nom.
    if (flatLayer != null) {
      final points = key.layerPoints[flatLayer.id];
      if (points != null && points.isNotEmpty && flatLayer.points.isNotEmpty) {
        json['points'] = _pointsToCenteredJson(
          points,
          flatLayer.width,
          flatLayer.height,
          _storedPointsCenter(flatLayer),
        );
      }
    } else if (layersByName != null && key.layerPoints.isNotEmpty) {
      final byName = <String, Object?>{};
      for (final entry in key.layerPoints.entries) {
        final layer = layersByName.values
            .where((l) => l.id == entry.key)
            .firstOrNull;
        if (layer == null || entry.value.isEmpty || layer.points.isEmpty) {
          continue;
        }
        byName[layer.name] = _pointsToCenteredJson(
          entry.value,
          layer.width,
          layer.height,
          _storedPointsCenter(layer),
        );
      }
      if (byName.isNotEmpty) json['layerPoints'] = byName;
    }
    return json;
  }

  static Map<String, Object?> _skeletonToJson(
    SkeletonRig rig,
    AnimationProject project,
  ) {
    final restPose = SkeletonPose.evaluate(rig, 0);
    final boneNameById = <String, String>{
      for (final bone in rig.bones) bone.id: bone.name,
    };
    final bones = <Map<String, Object?>>[];
    for (final bone in rig.bones) {
      final frame = restPose.frameOf(bone.id);
      final json = <String, Object?>{
        'name': bone.name,
        // Articulation et angle MONDE au repos (l'import reconstruit les
        // offsets relatifs + restAngle internes).
        'joint': frame == null
            ? [bone.offsetX, bone.offsetY]
            : [frame.jointRest.dx, frame.jointRest.dy],
        'angle': _radToDeg(frame?.worldAngleRest ?? bone.restAngle),
        'length': bone.length,
      };
      if (bone.parentId != null) json['parent'] = boneNameById[bone.parentId];
      if (bone.z != 0) json['z'] = bone.z;
      if (bone.ikEnabled) json['ik'] = true;
      if (bone.bendSign != 1) json['bend'] = bone.bendSign;
      bones.add(json);
    }
    // Liaisons par NOMS ; une liaison de COUCHE (v0.9.6) s'écrit
    // « Forme/Couche » (vasf-2).
    final bindings = <String, Object?>{};
    for (final binding in rig.bindings) {
      final boneName = boneNameById[binding.boneId];
      final shape = project.shapeById(binding.shapeId);
      if (boneName == null || shape == null) continue;
      if (binding.layerId != null) {
        final layer = shape.layers
            .where((l) => l.id == binding.layerId)
            .firstOrNull;
        if (layer == null) continue;
        bindings['${shape.name}/${layer.name}'] = boneName;
      } else {
        bindings[shape.name] = boneName;
      }
    }
    final keyframes = <Map<String, Object?>>[];
    for (final entry in rig.tracks.entries) {
      final bone = rig.boneById(entry.key);
      final frame = restPose.frameOf(entry.key);
      if (bone == null || frame == null) continue;
      final restDeg = _radToDeg(frame.worldAngleRest);
      for (final key in entry.value) {
        final json = <String, Object?>{
          'bone': bone.name,
          't': key.timeMs / 1000,
          // Angle MONDE absolu (delta interne + angle de repos monde).
          'angle': restDeg + _radToDeg(key.angleDelta),
          'easing': key.easing == EasingKind.customBezier
              ? _bezierToJson(key.bezier)
              : key.easing.name,
        };
        if (key.opacity != 1) json['opacity'] = key.opacity;
        if (key.stretch != 1) json['stretch'] = key.stretch;
        if (key.squash != 1) json['squash'] = key.squash;
        // Translation d'os (v0.15) : stockée dans le repère de repos du
        // PARENT → émise en MONDE (delta depuis la position de repos),
        // symétrique de l'import.
        if (key.tx != 0 || key.ty != 0) {
          final move = rotateVector(
            Offset(key.tx, key.ty),
            _restWorldAngleRad(rig, rig.boneById(bone.parentId)),
          );
          json['move'] = [move.dx, move.dy];
        }
        keyframes.add(json);
      }
    }
    return <String, Object?>{
      'name': rig.name,
      'bones': bones,
      if (bindings.isNotEmpty) 'bind': bindings,
      if (keyframes.isNotEmpty) 'keyframes': keyframes,
    };
  }

  /// Angle de repos MONDE (radians) d'un os — somme des restAngle de la
  /// chaîne (os null → 0). Sert à convertir les translations `move` (v0.15).
  static double _restWorldAngleRad(SkeletonRig rig, RigBone? bone) {
    var angle = 0.0;
    String? current = bone?.id;
    while (current != null) {
      final b = rig.boneById(current);
      if (b == null) break;
      angle += b.restAngle;
      current = b.parentId;
    }
    return angle;
  }

  /// Easing sérialisé : courbes nommées telles quelles, cubic-bezier en
  /// chaîne CSS `cubic-bezier(x1, y1, x2, y2)`.
  static String _bezierToJson(List<double>? bezier) {
    final b = (bezier != null && bezier.length == 4) ? bezier : defaultBezier;
    String f(double v) => v
        .toStringAsFixed(4)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
    return 'cubic-bezier(${f(b[0])}, ${f(b[1])}, ${f(b[2])}, ${f(b[3])})';
  }

  // ------------------------------------------------------------------ import

  /// JSON simple → AnimationProject (ids régénérés, horodatage maintenant).
  /// Tous les problèmes sont collectés : [SimpleFormatException.problems].
  static AnimationProject fromJson(
    Map<String, Object?> json, {
    String? fallbackName,
  }) {
    final p = _Parse(fallbackName: fallbackName);
    final project = p.parse(json);
    if (p.problems.isNotEmpty) throw SimpleFormatException(p.problems);
    return project;
  }
}

/// Erreur d'import : la liste de tous les problèmes détectés, en français.
class SimpleFormatException implements Exception {
  SimpleFormatException(this.problems);

  final List<String> problems;

  @override
  String toString() => 'Format simple invalide :\n- ${problems.join('\n- ')}';
}

/// Keyframe d'os en attente (l'import la parse, applique le cycle, puis
/// insère le tout dans le rig).
class _PendingBoneKey {
  _PendingBoneKey(
    this.boneId,
    this.timeMs,
    this.angleDelta,
    this.easing,
    this.bezier,
    this.opacity,
    this.stretch,
    this.squash, {
    this.tx = 0,
    this.ty = 0,
  });

  final String boneId;
  int timeMs;
  final double angleDelta;
  final EasingKind easing;
  final List<double>? bezier;
  final double opacity;
  final double stretch;
  final double squash;

  /// Translation animée (v0.15), repère de repos du parent.
  final double tx;
  final double ty;

  _PendingBoneKey withTime(int timeMs) => _PendingBoneKey(
    boneId,
    timeMs,
    angleDelta,
    easing,
    bezier,
    opacity,
    stretch,
    squash,
    tx: tx,
    ty: ty,
  );
}

double _radToDeg(double radians) => radians * 180 / 3.1415926535897932;
double _degToRad(double degrees) => degrees * 3.1415926535897932 / 180;

String _colorToHex(int value) {
  final argb = value & 0xFFFFFFFF;
  if ((argb >> 24) == 0xFF) {
    return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
  return '#${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}';
}

// ==== PARSE_PART2 ====

class _Parse {
  _Parse({this.fallbackName});

  final String? fallbackName;
  final List<String> problems = [];

  void problem(String message) => problems.add(message);

  // ------------------------------------------------------------ primitives

  Map<String, Object?>? mapOf(String path, Object? value) {
    if (value == null) return null;
    if (value is Map<String, Object?>) return value;
    if (value is Map) return value.cast<String, Object?>();
    problem('$path : objet attendu');
    return null;
  }

  List<Object?>? listOf(String path, Object? value) {
    if (value == null) return null;
    if (value is List<Object?>) return value;
    if (value is List) return value;
    problem('$path : liste attendue');
    return null;
  }

  Object? _at(List<Object?> list, int index) =>
      index < list.length ? list[index] : null;

  double numAt(String path, Object? value, {required double fallback}) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    problem('$path : nombre attendu (trouvé « $value »)');
    return fallback;
  }

  int intAt(String path, Object? value, {required int fallback}) {
    if (value == null) return fallback;
    if (value is num) return value.round();
    problem('$path : nombre entier attendu (trouvé « $value »)');
    return fallback;
  }

  String strAt(String path, Object? value, {required String fallback}) {
    if (value == null) return fallback;
    if (value is String && value.trim().isNotEmpty) return value.trim();
    problem('$path : texte non vide attendu');
    return fallback;
  }

  bool boolAt(String path, Object? value, {required bool fallback}) =>
      value is bool ? value : fallback;

  int colorAt(String path, Object? value, {required int fallback}) {
    if (value == null) return fallback;
    if (value is! String) {
      problem('$path : couleur attendue (« #RRGGBB »)');
      return fallback;
    }
    var hex = value.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (hex.length == 6) hex = 'FF$hex';
    final parsed = hex.length == 8 ? int.tryParse(hex, radix: 16) : null;
    if (parsed == null) {
      problem('$path : couleur attendue (« #RRGGBB », trouvé « $value »)');
      return fallback;
    }
    return parsed;
  }

  /// Easing nommé OU cubic-bezier CSS : retourne (easing, bezier).
  ({EasingKind easing, List<double>? bezier}) easingSpecAt(
    String path,
    Object? value,
  ) {
    if (value == null) return (easing: EasingKind.easeInOut, bezier: null);
    if (value is String) {
      final s = value.trim();
      if (s.startsWith('cubic-bezier(') && s.endsWith(')')) {
        final parts = s
            .substring('cubic-bezier('.length, s.length - 1)
            .split(',');
        final xs = [for (final p in parts) double.tryParse(p.trim())];
        if (parts.length == 4 && xs.every((x) => x != null)) {
          final bezier = [for (final x in xs) x!];
          if (bezier[0] < 0 ||
              bezier[0] > 1 ||
              bezier[2] < 0 ||
              bezier[2] > 1) {
            problem('$path : cubic-bezier — x1 et x2 dans [0, 1] attendus');
          }
          return (easing: EasingKind.customBezier, bezier: bezier);
        }
        problem('$path : cubic-bezier(x1, y1, x2, y2) attendu');
        return (easing: EasingKind.easeInOut, bezier: null);
      }
    }
    for (final easing in EasingKind.values) {
      if (easing.name == value) return (easing: easing, bezier: null);
    }
    problem(
      '$path : easing inconnu « $value » (valeurs : linear, easeIn, '
      'easeOut, easeInOut, step, cubic-bezier(x1, y1, x2, y2))',
    );
    return (easing: EasingKind.easeInOut, bezier: null);
  }

  ShapeKind kindAt(String path, Object? value) {
    if (value == null) return ShapeKind.rect;
    for (final kind in ShapeKind.values) {
      if (kind.name == value) return kind;
    }
    problem(
      '$path : type de forme inconnu « $value » (valeurs : rect, circle, '
      'line, path, triangle, star, hexagon, cross, heart, arrow)',
    );
    return ShapeKind.rect;
  }

  // ----------------------------------------------------------- structure

  late AnimationProject project;
  final _usedShapeNames = <String>{};

  // Palette « theme » (alias → couleur) et définitions réutilisables (vasf-2).
  final _palette = <String, int>{};
  final _defs = <String, Map<String, Object?>>{};

  /// Clés de géométrie portées par une définition `defs`.
  static const _defGeometryKeys = [
    'type',
    'color',
    'filled',
    'strokeWidth',
    'width',
    'height',
    'points',
  ];

  void _parseTheme(Object? raw) {
    final map = mapOf('theme', raw);
    if (map == null) return;
    for (final entry in map.entries) {
      final color = colorAt('theme.${entry.key}', entry.value, fallback: 0);
      if (color != 0) _palette[entry.key] = color;
    }
  }

  void _parseDefs(Object? raw) {
    final map = mapOf('defs', raw);
    if (map == null) return;
    for (final entry in map.entries) {
      final def = mapOf('defs.${entry.key}', entry.value);
      if (def == null) continue;
      _defs[entry.key] = def;
    }
  }

  /// Couleur littérale ou alias « $nom » résolu dans la palette `theme`.
  int colorRef(String path, Object? value, {required int fallback}) {
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.startsWith('\$')) {
        final alias = trimmed.substring(1);
        final resolved = _palette[alias];
        if (resolved == null) {
          problem('$path : alias « $alias » inconnu (palette « theme »)');
          return fallback;
        }
        return resolved;
      }
    }
    return colorAt(path, value, fallback: fallback);
  }

  AnimationProject parse(Map<String, Object?> json) {
    final version = intAt('version', json['version'], fallback: 0);
    if (version != SimpleAnimationFormat.version &&
        version != SimpleAnimationFormat.version2 &&
        version != SimpleAnimationFormat.version3) {
      problem('version : 1, 2 ou 3 attendu (trouvé $version)');
    }
    _parseTheme(json['theme']);
    _parseDefs(json['defs']);

    final canvas = mapOf('canvas', json['canvas']) ?? const <String, Object?>{};
    final width = numAt(
      'canvas.width',
      canvas['width'],
      fallback: SimpleAnimationFormat.defaultWidth,
    );
    final height = numAt(
      'canvas.height',
      canvas['height'],
      fallback: SimpleAnimationFormat.defaultHeight,
    );
    if (width < 16 || height < 16 || width > 4096 || height > 4096) {
      problem(
        'canvas : dimensions entre 16 et 4096 attendues ($width×$height)',
      );
    }
    final fps = intAt(
      'canvas.fps',
      canvas['fps'],
      fallback: SimpleAnimationFormat.defaultFps,
    );
    if (fps < 5 || fps > 60) {
      problem('canvas.fps : entre 5 et 60 attendu ($fps)');
    }
    final background = colorRef(
      'canvas.background',
      canvas['background'],
      fallback: SimpleAnimationFormat.defaultBackground,
    );
    project = AnimationProject(
      name: strAt(
        'name',
        json['name'],
        fallback: fallbackName ?? 'Animation importée',
      ),
      type: json['skeleton'] == null
          ? ProjectType.vector
          : ProjectType.skeleton,
      width: width,
      height: height,
      fps: fps,
      backgroundValue: background,
    );

    _parseShapes(json['shapes']);
    if (json['skeleton'] != null) _parseSkeleton(json['skeleton']);
    return project;
  }

  void _parseShapes(Object? raw) {
    final list = listOf('shapes', raw) ?? const <Object?>[];
    if (list.isEmpty) {
      problem('shapes : au moins une forme attendue');
      return;
    }
    for (var i = 0; i < list.length; i++) {
      final path = 'shapes[$i]';
      final json = mapOf(path, list[i]);
      if (json == null) continue;
      _parseShape(path, json);
    }
  }

  void _parseShape(String path, Map<String, Object?> json) {
    var name = strAt('$path.name', json['name'], fallback: 'Forme');
    if (_usedShapeNames.contains(name)) {
      var n = 2;
      while (_usedShapeNames.contains('$name $n')) {
        n++;
      }
      name = '$name $n';
    }
    _usedShapeNames.add(name);
    // Définition réutilisable (vasf-2) : la def fournit la géométrie par
    // défaut, la forme peut surcharger chaque champ. Pas de ref imbriquée.
    var effective = json;
    final refRaw = json['ref'];
    if (refRaw != null) {
      final refName = refRaw is String && refRaw.trim().isNotEmpty
          ? refRaw.trim()
          : null;
      if (refName == null) {
        problem('$path.ref : texte non vide attendu');
      } else {
        final def = _defs[refName];
        if (def == null) {
          problem('$path.ref : définition « $refName » inconnue');
        } else {
          effective = <String, Object?>{
            for (final key in _defGeometryKeys)
              if (def[key] != null) key: def[key],
            ...json,
          };
        }
      }
    }
    final layers = <ShapeLayer>[];
    final rawLayers = listOf('$path.layers', effective['layers']);
    // Couleurs/morph de keyframes (v0.15) : centre bbox de la liste points
    // de BASE (json) de chaque couche — les points de morph des keyframes
    // partagent son repère (recentrer chaque keyframe briserait le morph).
    final basePointsCenter = <String, (double, double)>{}; // layerId → (cx, cy)
    if (rawLayers != null) {
      for (var i = 0; i < rawLayers.length; i++) {
        final layerPath = '$path.layers[$i]';
        final layerJson = mapOf(layerPath, rawLayers[i]);
        if (layerJson == null) continue;
        final layer = _parseLayer(layerPath, layerJson, localPose: true);
        final center = _jsonPointsCenter(layerJson['points']);
        if (center != null) basePointsCenter[layer.id] = center;
        layers.add(layer);
      }
      if (layers.isEmpty) {
        problem('$path.layers : au moins une couche attendue');
      }
    } else {
      final layer = _parseLayer(path, effective, localPose: false);
      final center = _jsonPointsCenter(effective['points']);
      if (center != null) basePointsCenter[layer.id] = center;
      layers.add(layer);
    }
    final shape = VectorShape(name: name, layers: layers);
    // Pose de base de la forme (centre du groupe) : la seule géométrie de
    // position — les couches restent locales.
    shape.x = numAt('$path.x', json['x'], fallback: project.width / 2);
    shape.y = numAt('$path.y', json['y'], fallback: project.height / 2);
    shape.rotation = _degToRad(
      numAt('$path.rotation', json['rotation'], fallback: 0),
    );
    shape.scale = numAt('$path.scale', json['scale'], fallback: 1);
    shape.scaleX = numAt('$path.scaleX', json['scaleX'], fallback: 1);
    shape.scaleY = numAt('$path.scaleY', json['scaleY'], fallback: 1);
    // Pivot de rotation (vasf-2) : [dx, dy] en unités scène depuis le centre.
    final pivotPair = listOf('$path.pivot', json['pivot']) ?? const <Object?>[];
    shape.pivotDx = numAt('$path.pivot[0]', _at(pivotPair, 0), fallback: 0);
    shape.pivotDy = numAt('$path.pivot[1]', _at(pivotPair, 1), fallback: 0);
    shape.opacity = numAt('$path.opacity', json['opacity'], fallback: 1);
    _parseShapeTime(path, json, shape);
    _parseShapeKeyframes(
      '$path.keyframes',
      json['keyframes'],
      shape,
      isMultiLayer: rawLayers != null,
      basePointsCenter: basePointsCenter,
    );
    _applyShapeCycle(path, json, shape);
    project.shapes.add(shape);
  }

  /// Centre (bbox) d'une liste de points json — sert de repère commun aux
  /// points de morph des keyframes (v0.15).
  (double, double)? _jsonPointsCenter(Object? rawPoints) {
    final list = rawPoints is List ? rawPoints : null;
    if (list == null || list.isEmpty) return null;
    double? minx;
    double? maxx;
    double? miny;
    double? maxy;
    for (final raw in list) {
      if (raw is! List || raw.length < 2) continue;
      final x = (raw[0] as num?)?.toDouble();
      final y = (raw[1] as num?)?.toDouble();
      if (x == null || y == null) continue;
      minx = minx == null ? x : math.min(minx, x);
      maxx = maxx == null ? x : math.max(maxx, x);
      miny = miny == null ? y : math.min(miny, y);
      maxy = maxy == null ? y : math.max(maxy, y);
    }
    if (minx == null || maxx == null || miny == null || maxy == null) {
      return null;
    }
    return ((minx + maxx) / 2, (miny + maxy) / 2);
  }

  /// Une couche : primitive locale à la forme. En mode `layers[]` (localPose)
  /// la couche porte aussi sa pose locale (x/y/rotation/scale/opacité) ; à
  /// plat (vasf-1) la couche reste locale-neutre.
  ShapeLayer _parseLayer(
    String path,
    Map<String, Object?> json, {
    required bool localPose,
  }) {
    final layer = ShapeLayer(
      name: localPose
          ? strAt('$path.name', json['name'], fallback: 'Couche')
          : 'Couche',
      kind: kindAt('$path.type', json['type']),
      colorValue: colorRef(
        '$path.color',
        json['color'],
        fallback: SimpleAnimationFormat.defaultShapeColor,
      ),
      filled: boolAt('$path.filled', json['filled'], fallback: true),
      strokeWidth: numAt('$path.strokeWidth', json['strokeWidth'], fallback: 4),
    );
    if (localPose) {
      layer.x = numAt('$path.x', json['x'], fallback: 0);
      layer.y = numAt('$path.y', json['y'], fallback: 0);
      layer.rotation = _degToRad(
        numAt('$path.rotation', json['rotation'], fallback: 0),
      );
      layer.scale = numAt('$path.scale', json['scale'], fallback: 1);
      layer.opacity = numAt('$path.opacity', json['opacity'], fallback: 1);
      // Pivot de rotation (v0.13.1) : réglage au niveau de la FORME — dans
      // layers[] il serait ignoré en silence et la forme tournerait autour
      // de son centre « comme avant ». Refus explicite pour forcer le fix.
      if (json['pivot'] != null) {
        problem(
          '$path.pivot : le pivot de rotation se règle au niveau de la '
          'FORME (champ « pivot » de la forme, ex. porte : [-largeur/2, 0]), '
          'pas dans layers[]',
        );
      }
    }
    _applyGeometry(path, json, layer);
    return layer;
  }

  void _parseShapeTime(
    String path,
    Map<String, Object?> json,
    VectorShape shape,
  ) {
    final start = numAt('$path.start', json['start'], fallback: 0);
    var end = numAt('$path.end', json['end'], fallback: 0);
    if (end <= 0) {
      // Fin par défaut : la fin la plus tardive des autres formes, sinon 4 s.
      end = project.shapes.isEmpty
          ? 4
          : project.shapes.map((s) => s.endMs / 1000).reduce(math.max);
    }
    if (start < 0) problem('$path.start : ≥ 0 attendu ($start)');
    if (end <= start) {
      problem('$path.end : fin > début attendu ($end ≤ $start)');
    }
    shape.startMs = (start * 1000).round();
    shape.endMs = (end * 1000).round();
  }

  void _applyGeometry(
    String path,
    Map<String, Object?> json,
    ShapeLayer layer,
  ) {
    final rawPoints = listOf('$path.points', json['points']);
    if (layer.kind == ShapeKind.path && rawPoints != null) {
      final points = <Offset>[];
      for (var i = 0; i < rawPoints.length; i++) {
        final pair =
            listOf('$path.points[$i]', rawPoints[i]) ?? const <Object?>[];
        if (pair.length < 2) {
          problem('$path.points[$i] : [x, y] attendu');
          continue;
        }
        points.add(
          Offset(
            numAt('$path.points[$i][0]', _at(pair, 0), fallback: 0),
            numAt('$path.points[$i][1]', _at(pair, 1), fallback: 0),
          ),
        );
      }
      if (points.length >= 2) {
        // L'application dessine `point − (w/2, h/2)` : on convertit pour que
        // le nuage rendu soit centré sur la forme, avec w/h = bbox.
        final minx = points.map((p) => p.dx).reduce(math.min);
        final maxx = points.map((p) => p.dx).reduce(math.max);
        final miny = points.map((p) => p.dy).reduce(math.min);
        final maxy = points.map((p) => p.dy).reduce(math.max);
        final cx = (minx + maxx) / 2;
        final cy = (miny + maxy) / 2;
        layer.width = math.max(1.0, maxx - minx);
        layer.height = math.max(1.0, maxy - miny);
        layer.points
          ..clear()
          ..addAll([
            for (final p in points)
              Offset(p.dx - cx + layer.width / 2, p.dy - cy + layer.height / 2),
          ]);
      } else {
        problem('$path.points : au moins 2 points attendus pour un path');
      }
    } else {
      layer.width = numAt(
        '$path.width',
        json['width'],
        fallback: SimpleAnimationFormat.defaultShapeSize,
      );
      layer.height = numAt(
        '$path.height',
        json['height'],
        fallback: SimpleAnimationFormat.defaultShapeSize,
      );
    }
    if (layer.width <= 0 || layer.height <= 0) {
      problem('$path.width/height : dimensions > 0 attendues');
    }
  }

  void _parseShapeKeyframes(
    String path,
    Object? raw,
    VectorShape shape, {
    required bool isMultiLayer,
    required Map<String, (double, double)> basePointsCenter,
  }) {
    final list = listOf(path, raw) ?? const <Object?>[];
    if (list.isEmpty) return;
    // Porter les valeurs d'une keyframe à la suivante (poses complètes) —
    // y compris couleurs et points de morph (v0.15).
    final carried = <AnimatableProperty, double>{
      AnimatableProperty.x: shape.x,
      AnimatableProperty.y: shape.y,
      AnimatableProperty.rotation: shape.rotation,
      AnimatableProperty.scale: shape.scale,
      AnimatableProperty.scaleX: shape.scaleX,
      AnimatableProperty.scaleY: shape.scaleY,
      AnimatableProperty.opacity: shape.opacity,
      AnimatableProperty.strokeWidth: shape.strokeWidth,
    };
    var carriedColors = <String, int>{}; // layerId → ARGB
    var carriedPoints = <String, List<Offset>>{}; // layerId → points stockés
    for (var i = 0; i < list.length; i++) {
      final keyPath = '$path[$i]';
      final json = mapOf(keyPath, list[i]);
      if (json == null) continue;
      final t = numAt('$keyPath.t', json['t'], fallback: -1);
      if (t < 0) {
        problem('$keyPath.t : temps ≥ 0 attendu (en secondes)');
        continue;
      }
      final spec = easingSpecAt('$keyPath.easing', json['easing']);
      final values = <AnimatableProperty, double>{};
      for (final property in AnimatableProperty.values) {
        final raw = json[property.name];
        var value = carried[property]!;
        if (raw != null) {
          if (raw is! num) {
            problem('$keyPath.${property.name} : nombre attendu');
          } else {
            value = raw.toDouble();
            if (property == AnimatableProperty.rotation) {
              value = _degToRad(value);
            }
          }
        }
        carried[property] = value;
        values[property] = value;
      }

      // Couleur animée (v0.15) : `color` (forme à plat) ou `colors` (map
      // nom de couche → hex, couches multiples). Portés en carry.
      final colors = Map<String, int>.from(carriedColors);
      final flatColor = json['color'];
      if (flatColor != null) {
        if (isMultiLayer) {
          problem(
            '$keyPath.color : réservé aux formes à UNE couche — pour une '
            'forme en layers[], utiliser « colors » (nom de couche → hex)',
          );
        } else {
          final resolved = colorRef('$keyPath.color', flatColor, fallback: 0);
          if (resolved != 0) colors[shape.layers.first.id] = resolved;
        }
      }
      final colorsMap = mapOf('$keyPath.colors', json['colors']);
      if (colorsMap != null) {
        if (!isMultiLayer) {
          problem(
            '$keyPath.colors : réservé aux formes en layers[] — pour une '
            'forme à une couche, utiliser « color »',
          );
        } else {
          for (final entry in colorsMap.entries) {
            final layer = shape.layers
                .where((l) => l.name == entry.key)
                .firstOrNull;
            if (layer == null) {
              problem('$keyPath.colors.${entry.key} : couche inconnue');
              continue;
            }
            final resolved = colorRef(
              '$keyPath.colors.${entry.key}',
              entry.value,
              fallback: 0,
            );
            if (resolved != 0) colors[layer.id] = resolved;
          }
        }
      }
      carriedColors = colors;

      // Morph de points (v0.15) : `points` (à plat) ou `layerPoints` (map
      // nom de couche → points, même repère que la liste points de base).
      final points = <String, List<Offset>>{};
      for (final entry in carriedPoints.entries) {
        points[entry.key] = List<Offset>.from(entry.value);
      }
      final flatPoints = listOf('$keyPath.points', json['points']);
      if (flatPoints != null) {
        if (isMultiLayer) {
          problem(
            '$keyPath.points : réservé aux formes à UNE couche — pour une '
            'forme en layers[], utiliser « layerPoints »',
          );
        } else {
          final stored = _morphPointsStored(
            '$keyPath.points',
            flatPoints,
            basePointsCenter[shape.layers.first.id],
            shape.layers.first,
          );
          if (stored.isNotEmpty) points[shape.layers.first.id] = stored;
        }
      }
      final pointsMap = mapOf('$keyPath.layerPoints', json['layerPoints']);
      if (pointsMap != null) {
        if (!isMultiLayer) {
          problem(
            '$keyPath.layerPoints : réservé aux formes en layers[] — pour '
            'une forme à une couche, utiliser « points »',
          );
        } else {
          for (final entry in pointsMap.entries) {
            final layer = shape.layers
                .where((l) => l.name == entry.key)
                .firstOrNull;
            if (layer == null) {
              problem('$keyPath.layerPoints.${entry.key} : couche inconnue');
              continue;
            }
            final rawPoints = listOf(
              '$keyPath.layerPoints.${entry.key}',
              entry.value,
            );
            if (rawPoints == null) continue;
            final stored = _morphPointsStored(
              '$keyPath.layerPoints.${entry.key}',
              rawPoints,
              basePointsCenter[layer.id],
              layer,
            );
            if (stored.isNotEmpty) points[layer.id] = stored;
          }
        }
      }
      carriedPoints = points;

      shape.keyframes.add(
        ShapeKeyframe(
          timeMs: (t * 1000).round(),
          values: values,
          easing: spec.easing,
          bezier: spec.bezier,
          layerColors: colors.isEmpty ? null : Map<String, int>.from(colors),
          layerPoints: points.isEmpty ? null : points,
        ),
      );
    }
    shape.keyframes.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    // Une keyframe au-delà de la fin du segment étend la fin.
    for (final key in shape.keyframes) {
      if (key.timeMs > shape.endMs) shape.endMs = key.timeMs;
    }
  }

  /// Points d'une keyframe de morph (json « autour du centre », MÊME repère
  /// que la liste points de la base) → points stockés (repère boîte de la
  /// couche, rendus à `point − (w/2, h/2)`).
  List<Offset> _morphPointsStored(
    String path,
    List<Object?> rawPoints,
    (double, double)? baseCenter,
    ShapeLayer layer,
  ) {
    final points = <Offset>[];
    for (var i = 0; i < rawPoints.length; i++) {
      final pair = listOf('$path[$i]', rawPoints[i]) ?? const <Object?>[];
      if (pair.length < 2) {
        problem('$path[$i] : [x, y] attendu');
        continue;
      }
      points.add(
        Offset(
          numAt('$path[$i][0]', _at(pair, 0), fallback: 0),
          numAt('$path[$i][1]', _at(pair, 1), fallback: 0),
        ),
      );
    }
    if (points.length < 2) {
      problem('$path : au moins 2 points attendus');
      return const <Offset>[];
    }
    final (cx, cy) = baseCenter ?? (layer.width / 2, layer.height / 2);
    return [
      for (final p in points)
        Offset(p.dx - cx + layer.width / 2, p.dy - cy + layer.height / 2),
    ];
  }

  /// `cycle.repeat` (vasf-2) : le motif de keyframes est répété N fois de plus
  /// après la dernière keyframe, période = dernier − premier temps. Au
  /// raccord, la première keyframe d'une répétition est sautée quand son
  /// temps tombe sur la dernière déjà posée (motif bouclé → timeline
  /// propre). Sans keyframes, `cycle` est ignoré.
  void _applyShapeCycle(
    String path,
    Map<String, Object?> json,
    VectorShape shape,
  ) {
    final cycle = mapOf('$path.cycle', json['cycle']);
    if (cycle == null) return;
    final repeat = intAt('$path.cycle.repeat', cycle['repeat'], fallback: 0);
    if (repeat < 1) {
      problem('$path.cycle.repeat : entier ≥ 1 attendu ($repeat)');
      return;
    }
    if (shape.keyframes.isEmpty) return;
    final first = shape.keyframes.first.timeMs;
    final last = shape.keyframes.last.timeMs;
    final period = last - first;
    if (period <= 0) return;
    final count = shape.keyframes.length;
    for (var r = 1; r <= repeat; r++) {
      for (var i = 0; i < count; i++) {
        if (i == 0) continue; // raccord
        final key = shape.keyframes[i];
        shape.keyframes.add(key.copy()..timeMs = key.timeMs + r * period);
      }
    }
    for (final key in shape.keyframes) {
      if (key.timeMs > shape.endMs) shape.endMs = key.timeMs;
    }
  }

  // -------------------------------------------------------------- squelette

  void _parseSkeleton(Object? raw) {
    final json = mapOf('skeleton', raw);
    if (json == null) {
      problem('skeleton : objet attendu');
      project.type = ProjectType.vector;
      return;
    }
    final rig = SkeletonRig(
      name: strAt('skeleton.name', json['name'], fallback: 'Squelette'),
    );
    _parseBones(json, rig);
    _parseSkeletonKeyframes(json, rig);
    project.skeleton = rig;
    project.type = ProjectType.skeleton;
  }

  void _parseBones(Map<String, Object?> json, SkeletonRig rig) {
    final list = listOf('skeleton.bones', json['bones']) ?? const <Object?>[];
    if (list.isEmpty) {
      problem('skeleton.bones : au moins un os attendu');
      return;
    }
    // Les parents doivent apparaître avant leurs enfants (ordre de la liste).
    final byName = <String, RigBone>{};
    final worldRestDeg = <String, double>{};
    final worldRestJoint = <String, Offset>{};
    for (var i = 0; i < list.length; i++) {
      final path = 'skeleton.bones[$i]';
      final json = mapOf(path, list[i]);
      if (json == null) continue;
      final name = strAt('$path.name', json['name'], fallback: 'Os');
      if (byName.containsKey(name)) {
        problem('$path.name : os « $name » en double');
        continue;
      }
      final parentName = strAt('$path.parent', json['parent'], fallback: '');
      final parent = parentName.isEmpty ? null : byName[parentName];
      if (parentName.isNotEmpty && parent == null) {
        problem(
          '$path.parent : os « $parentName » inconnu — les parents doivent '
          'être listés AVANT leurs enfants',
        );
      }
      final jointPair =
          listOf('$path.joint', json['joint']) ?? const <Object?>[];
      if (jointPair.length < 2) problem('$path.joint : [x, y] attendu');
      final joint = Offset(
        numAt('$path.joint[0]', _at(jointPair, 0), fallback: 0),
        numAt('$path.joint[1]', _at(jointPair, 1), fallback: 0),
      );
      final length = numAt('$path.length', json['length'], fallback: 80);
      if (length <= 0) {
        problem('$path.length : longueur > 0 attendue ($length)');
      }
      final angleWorldDeg = numAt('$path.angle', json['angle'], fallback: 0);
      final bone = RigBone(name: name, parentId: parent?.id, length: length);
      bone.z = intAt('$path.z', json['z'], fallback: 0);
      bone.ikEnabled = boolAt('$path.ik', json['ik'], fallback: false);
      bone.bendSign = numAt('$path.bend', json['bend'], fallback: 1) >= 0
          ? 1
          : -1;
      if (parent == null) {
        bone.offsetX = joint.dx;
        bone.offsetY = joint.dy;
        bone.restAngle = _degToRad(angleWorldDeg);
      } else {
        // Offset dans le repère de repos du parent : delta monde ramené par
        // R(−angleMondeParent).
        final local = rotateVector(
          joint - worldRestJoint[parent.id]!,
          -_degToRad(worldRestDeg[parent.id]!),
        );
        bone.offsetX = local.dx;
        bone.offsetY = local.dy;
        bone.restAngle = _degToRad(angleWorldDeg - worldRestDeg[parent.id]!);
      }
      rig.addBone(bone);
      byName[name] = bone;
      // L'angle déclaré est MONDE : le bookkeeping pour les ENFANTS de cet
      // os doit le reprendre tel quel. (v0.11 additionnait le résumé du
      // parent — les chaînes ≥ 3 os se posaient fausses dès le 3e niveau,
      // auto-cohérent en round-trip donc invisible jusqu'au test `move`
      // v0.15 : l'angle et l'offset d'un 3e os étaient calculés contre un
      // faux angle monde du parent.)
      worldRestDeg[bone.id] = angleWorldDeg;
      worldRestJoint[bone.id] = joint;
    }
    // Liaisons pièces → os (par noms). Une clé « Forme/Couche » (vasf-2)
    // lie la couche nommée de la forme ; une clé simple = forme entière.
    final bind = mapOf('skeleton.bind', json['bind']);
    if (bind != null) {
      for (final entry in bind.entries) {
        final slash = entry.key.indexOf('/');
        final shapeName = slash < 0 ? entry.key : entry.key.substring(0, slash);
        final layerName = slash < 0 ? null : entry.key.substring(slash + 1);
        final shape = project.shapes
            .where((s) => s.name == shapeName)
            .firstOrNull;
        if (shape == null) {
          problem('skeleton.bind : forme « $shapeName » inconnue');
          continue;
        }
        final bone = byName[entry.value];
        if (bone == null) {
          problem('skeleton.bind : os « ${entry.value} » inconnu');
          continue;
        }
        if (layerName == null) {
          rig.bindShape(shape.id, bone.id);
        } else {
          final layer = shape.layers
              .where((l) => l.name == layerName)
              .firstOrNull;
          if (layer == null) {
            problem(
              'skeleton.bind : couche « $layerName » inconnue sur la forme '
              '« $shapeName »',
            );
            continue;
          }
          rig.bindLayer(shape.id, layer.id, bone.id);
        }
      }
    }
  }

  void _parseSkeletonKeyframes(Map<String, Object?> json, SkeletonRig rig) {
    final list =
        listOf('skeleton.keyframes', json['keyframes']) ?? const <Object?>[];
    final pending = <_PendingBoneKey>[];
    for (var i = 0; i < list.length; i++) {
      final path = 'skeleton.keyframes[$i]';
      final keyJson = mapOf(path, list[i]);
      if (keyJson == null) continue;
      final boneName = strAt('$path.bone', keyJson['bone'], fallback: '');
      final bone = rig.bones.where((b) => b.name == boneName).firstOrNull;
      if (bone == null) {
        problem('$path.bone : os « $boneName » inconnu');
        continue;
      }
      final t = numAt('$path.t', keyJson['t'], fallback: -1);
      if (t < 0) {
        problem('$path.t : temps ≥ 0 attendu (en secondes)');
        continue;
      }
      // Angle MONDE absolu → delta par rapport à l'angle de repos monde.
      final restDeg = _restWorldDeg(rig, bone);
      final angleDeg = numAt(
        '$path.angle',
        keyJson['angle'],
        fallback: restDeg,
      );
      final spec = easingSpecAt('$path.easing', keyJson['easing']);
      // Translation d'os (v0.15) : `move` = [dx, dy] MONDE (delta depuis la
      // position de repos de l'articulation) → ramené dans le repère de
      // repos du parent (même convention que offsetX/offsetY).
      var tx = 0.0;
      var ty = 0.0;
      final movePair =
          listOf('$path.move', keyJson['move']) ?? const <Object?>[];
      if (movePair.isNotEmpty) {
        if (movePair.length < 2) {
          problem('$path.move : [dx, dy] attendu');
        } else {
          final world = Offset(
            numAt('$path.move[0]', _at(movePair, 0), fallback: 0),
            numAt('$path.move[1]', _at(movePair, 1), fallback: 0),
          );
          final parent = rig.boneById(bone.parentId);
          final local = rotateVector(
            world,
            -SimpleAnimationFormat._restWorldAngleRad(rig, parent),
          );
          tx = local.dx;
          ty = local.dy;
        }
      }
      pending.add(
        _PendingBoneKey(
          bone.id,
          (t * 1000).round(),
          _degToRad(angleDeg - restDeg),
          spec.easing,
          spec.bezier,
          numAt('$path.opacity', keyJson['opacity'], fallback: 1),
          numAt('$path.stretch', keyJson['stretch'], fallback: 1),
          numAt('$path.squash', keyJson['squash'], fallback: 1),
          tx: tx,
          ty: ty,
        ),
      );
    }
    _applySkeletonCycle(json, pending);
    for (final key in pending) {
      rig.upsertKeyframe(
        key.boneId,
        key.timeMs,
        key.angleDelta,
        easing: key.easing,
        bezier: key.bezier,
        opacity: key.opacity,
        stretch: key.stretch,
        squash: key.squash,
        tx: key.tx == 0 ? null : key.tx,
        ty: key.ty == 0 ? null : key.ty,
      );
    }
  }

  /// `skeleton.cycle.repeat` (vasf-2) : répète le motif de keyframes de TOUS
  /// les os, période = (plus grand − plus petit temps) du squelette. Au
  /// raccord, une keyframe tombant sur un temps déjà posé pour le même os
  /// est sautée (motif bouclé → timeline propre).
  void _applySkeletonCycle(
    Map<String, Object?> json,
    List<_PendingBoneKey> pending,
  ) {
    final cycle = mapOf('skeleton.cycle', json['cycle']);
    if (cycle == null) return;
    final repeat = intAt('skeleton.cycle.repeat', cycle['repeat'], fallback: 0);
    if (repeat < 1) {
      problem('skeleton.cycle.repeat : entier ≥ 1 attendu ($repeat)');
      return;
    }
    if (pending.isEmpty) return;
    final first = pending.map((k) => k.timeMs).reduce(math.min);
    final last = pending.map((k) => k.timeMs).reduce(math.max);
    final period = last - first;
    if (period <= 0) return;
    final extra = <_PendingBoneKey>[];
    for (var r = 1; r <= repeat; r++) {
      for (final key in pending) {
        final time = key.timeMs + r * period;
        final exists =
            pending.any((x) => x.boneId == key.boneId && x.timeMs == time) ||
            extra.any((x) => x.boneId == key.boneId && x.timeMs == time);
        if (!exists) extra.add(key.withTime(time));
      }
    }
    pending.addAll(extra);
  }

  /// Angle de repos MONDE d'un os (somme des restAngle de la chaîne).
  double _restWorldDeg(SkeletonRig rig, RigBone bone) {
    var deg = 0.0;
    String? current = bone.id;
    while (current != null) {
      final b = rig.boneById(current);
      if (b == null) break;
      deg += _radToDeg(b.restAngle);
      current = b.parentId;
    }
    return deg;
  }
}
