import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../models/animation.dart';
import '../models/skeleton.dart';

/// Format d'échange « vasf-1 » : un JSON SIMPLE, pensé pour être ÉCRIT par un
/// agent IA (ou à la main), converti vers/depuis le projet interne. Spécification
/// complète et exemples : `docs/vasf-1-format.md`.
///
/// Contrats : temps en secondes, couleurs « #RRGGBB », angles en DEGRÉS monde
/// (y vers le bas, positif = horaire), keyframes partielles (une propriété
/// absente hérite de la keyframe précédente ou de la base), une forme = une
/// primitive, ordre de dessin = ordre de la liste, `joint`/`angle` d'os et
/// `keyframes[].angle` exprimés MONDE (l'import convertit en interne).
class SimpleAnimationFormat {
  SimpleAnimationFormat._();

  static const int version = 1;

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
    for (final shape in project.shapes) {
      if (shape.isInstance) continue;
      shapes.add(_shapeToJson(shape));
    }
    final json = <String, Object?>{
      'version': version,
      'name': project.name,
      'canvas': <String, Object?>{
        'width': project.width,
        'height': project.height,
        'fps': project.fps,
        'background': _colorToHex(project.backgroundValue),
      },
      'shapes': shapes,
    };
    final rig = project.skeleton;
    if (project.isSkeleton && rig != null) {
      json['skeleton'] = _skeletonToJson(rig, project);
    }
    return json;
  }

  static Map<String, Object?> _shapeToJson(VectorShape shape) {
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
      final points = layer.points;
      final minx = points.map((p) => p.dx).reduce(math.min);
      final maxx = points.map((p) => p.dx).reduce(math.max);
      final miny = points.map((p) => p.dy).reduce(math.min);
      final maxy = points.map((p) => p.dy).reduce(math.max);
      json['points'] = [
        for (final p in points)
          [
            p.dx - layer.width / 2 + (minx + maxx) / 2,
            p.dy - layer.height / 2 + (miny + maxy) / 2,
          ],
      ];
    }
    if (shape.hasKeyframes) {
      // Export sparse : une propriété égale à la keyframe précédente (ou à
      // la base pour la première) est omise.
      final previous = <AnimatableProperty, double>{
        for (final property in AnimatableProperty.values)
          property: shape.baseOf(property),
      };
      json['keyframes'] = [
        for (final key in shape.keyframes) _shapeKeyframeToJson(key, previous),
      ];
    }
    return json;
  }

  static Map<String, Object?> _shapeKeyframeToJson(
    ShapeKeyframe key,
    Map<AnimatableProperty, double> previous,
  ) {
    final json = <String, Object?>{
      't': key.timeMs / 1000,
      'easing': key.easing.name,
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
    // Liaisons par NOMS (les liaisons de couche ne sont pas représentées).
    final bindings = <String, Object?>{};
    for (final binding in rig.bindings) {
      if (binding.layerId != null) continue;
      final boneName = boneNameById[binding.boneId];
      final shape = project.shapeById(binding.shapeId);
      if (boneName == null || shape == null) continue;
      bindings[shape.name] = boneName;
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
          'easing': key.easing.name,
        };
        if (key.opacity != 1) json['opacity'] = key.opacity;
        if (key.stretch != 1) json['stretch'] = key.stretch;
        if (key.squash != 1) json['squash'] = key.squash;
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

  EasingKind easingAt(String path, Object? value) {
    if (value == null) return EasingKind.easeInOut;
    for (final easing in EasingKind.values) {
      if (easing.name == value) return easing;
    }
    problem(
      '$path : easing inconnu « $value » (valeurs : linear, easeIn, '
      'easeOut, easeInOut, step)',
    );
    return EasingKind.easeInOut;
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

  AnimationProject parse(Map<String, Object?> json) {
    final version = intAt('version', json['version'], fallback: 0);
    if (version != SimpleAnimationFormat.version) {
      problem(
        'version : ${SimpleAnimationFormat.version} attendu (trouvé $version)',
      );
    }

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
    final background = colorAt(
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
    final layer = ShapeLayer(
      name: 'Couche',
      kind: kindAt('$path.type', json['type']),
      colorValue: colorAt(
        '$path.color',
        json['color'],
        fallback: SimpleAnimationFormat.defaultShapeColor,
      ),
      filled: boolAt('$path.filled', json['filled'], fallback: true),
      strokeWidth: numAt('$path.strokeWidth', json['strokeWidth'], fallback: 4),
    );
    final shape = VectorShape(name: name, layers: [layer]);
    // Pose de base de la forme (centre du groupe) : la seule géométrie de
    // position — la couche reste locale-neutre.
    shape.x = numAt('$path.x', json['x'], fallback: project.width / 2);
    shape.y = numAt('$path.y', json['y'], fallback: project.height / 2);
    shape.rotation = _degToRad(
      numAt('$path.rotation', json['rotation'], fallback: 0),
    );
    shape.scale = numAt('$path.scale', json['scale'], fallback: 1);
    shape.opacity = numAt('$path.opacity', json['opacity'], fallback: 1);
    _parseShapeTime(path, json, shape);
    _parseShapeGeometry(path, json, shape);
    _parseShapeKeyframes('$path.keyframes', json['keyframes'], shape);
    project.shapes.add(shape);
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

  void _parseShapeGeometry(
    String path,
    Map<String, Object?> json,
    VectorShape shape,
  ) {
    final layer = shape.layers.first;
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

  void _parseShapeKeyframes(String path, Object? raw, VectorShape shape) {
    final list = listOf(path, raw) ?? const <Object?>[];
    if (list.isEmpty) return;
    // Porter les valeurs d'une keyframe à la suivante (poses complètes).
    final carried = <AnimatableProperty, double>{
      AnimatableProperty.x: shape.x,
      AnimatableProperty.y: shape.y,
      AnimatableProperty.rotation: shape.rotation,
      AnimatableProperty.scale: shape.scale,
      AnimatableProperty.opacity: shape.opacity,
      AnimatableProperty.strokeWidth: shape.strokeWidth,
    };
    for (var i = 0; i < list.length; i++) {
      final keyPath = '$path[$i]';
      final json = mapOf(keyPath, list[i]);
      if (json == null) continue;
      final t = numAt('$keyPath.t', json['t'], fallback: -1);
      if (t < 0) {
        problem('$keyPath.t : temps ≥ 0 attendu (en secondes)');
        continue;
      }
      final easing = easingAt('$keyPath.easing', json['easing']);
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
      shape.keyframes.add(
        ShapeKeyframe(
          timeMs: (t * 1000).round(),
          values: values,
          easing: easing,
        ),
      );
    }
    shape.keyframes.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    // Une keyframe au-delà de la fin du segment étend la fin.
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
      worldRestDeg[bone.id] =
          (parent == null ? 0.0 : worldRestDeg[parent.id]!) + angleWorldDeg;
      worldRestJoint[bone.id] = joint;
    }
    // Liaisons pièces → os (par noms).
    final bind = mapOf('skeleton.bind', json['bind']);
    if (bind != null) {
      for (final entry in bind.entries) {
        final shape = project.shapes
            .where((s) => s.name == entry.key)
            .firstOrNull;
        if (shape == null) {
          problem('skeleton.bind : forme « ${entry.key} » inconnue');
          continue;
        }
        final bone = byName[entry.value];
        if (bone == null) {
          problem('skeleton.bind : os « ${entry.value} » inconnu');
          continue;
        }
        rig.bindShape(shape.id, bone.id);
      }
    }
  }

  void _parseSkeletonKeyframes(Map<String, Object?> json, SkeletonRig rig) {
    final list =
        listOf('skeleton.keyframes', json['keyframes']) ?? const <Object?>[];
    for (var i = 0; i < list.length; i++) {
      final path = 'skeleton.keyframes[$i]';
      final json = mapOf(path, list[i]);
      if (json == null) continue;
      final boneName = strAt('$path.bone', json['bone'], fallback: '');
      final bone = rig.bones.where((b) => b.name == boneName).firstOrNull;
      if (bone == null) {
        problem('$path.bone : os « $boneName » inconnu');
        continue;
      }
      final t = numAt('$path.t', json['t'], fallback: -1);
      if (t < 0) {
        problem('$path.t : temps ≥ 0 attendu (en secondes)');
        continue;
      }
      // Angle MONDE absolu → delta par rapport à l'angle de repos monde.
      final restDeg = _restWorldDeg(rig, bone);
      final angleDeg = numAt('$path.angle', json['angle'], fallback: restDeg);
      rig.upsertKeyframe(
        bone.id,
        (t * 1000).round(),
        _degToRad(angleDeg - restDeg),
        easing: easingAt('$path.easing', json['easing']),
        opacity: numAt('$path.opacity', json['opacity'], fallback: 1),
        stretch: numAt('$path.stretch', json['stretch'], fallback: 1),
        squash: numAt('$path.squash', json['squash'], fallback: 1),
      );
    }
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
