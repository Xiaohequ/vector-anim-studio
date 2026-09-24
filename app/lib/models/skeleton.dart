import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'animation.dart';

/// Un os du rig : maillon d'une hiérarchie parent → enfant.
///
/// Position de repos : `offsetX/offsetY` est exprimé dans le repère local de
/// repos du parent (origine = articulation du parent, axe X le long du parent).
/// Pour la racine (`parentId == null`), l'offset est exprimé en coordonnées
/// projet et `restAngle` est un angle monde. Pour un enfant, `restAngle` est
/// RELATIF à la direction du parent : bouger ou tourner le parent entraîne
/// toute la chaîne (à l'animation comme au repos).
class RigBone {
  RigBone({
    String? id,
    required this.name,
    this.parentId,
    this.offsetX = 0,
    this.offsetY = 0,
    this.restAngle = 0,
    this.length = 80,
  }) : id = id ?? generateId('bone');

  final String id;
  String name;
  String? parentId;

  /// Articulation dans le repère de repos du parent (projet pour la racine).
  double offsetX;
  double offsetY;

  /// Angle de repos : relatif au parent (monde pour la racine), en radians.
  double restAngle;

  /// Longueur de l'os (unités projet).
  double length;

  RigBone copy({String? id, String? parentId}) => RigBone(
        id: id ?? this.id,
        name: name,
        parentId: parentId ?? this.parentId,
        offsetX: offsetX,
        offsetY: offsetY,
        restAngle: restAngle,
        length: length,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'parentId': parentId,
        'offsetX': offsetX,
        'offsetY': offsetY,
        'restAngle': restAngle,
        'length': length,
      };

  factory RigBone.fromJson(Map<String, Object?> json) => RigBone(
        id: json['id'] as String?,
        name: json['name'] as String? ?? 'Os',
        parentId: json['parentId'] as String?,
        offsetX: (json['offsetX'] as num?)?.toDouble() ?? 0,
        offsetY: (json['offsetY'] as num?)?.toDouble() ?? 0,
        restAngle: (json['restAngle'] as num?)?.toDouble() ?? 0,
        length: (json['length'] as num?)?.toDouble() ?? 80,
      );
}

/// Keyframe d'un os : le delta d'angle (radians) ajouté à l'angle de repos
/// de l'os à cet instant. Une keyframe d'os est une « pose » à une seule
/// propriété (l'angle) — même sémantique d'échantillonnage que les poses de
/// forme : hors de la plage, la première/dernière keyframe est tenue.
class BoneKeyframe {
  BoneKeyframe({
    required this.timeMs,
    this.easing = EasingKind.easeInOut,
    this.angleDelta = 0,
  });

  int timeMs;
  EasingKind easing;
  double angleDelta;

  BoneKeyframe copy() => BoneKeyframe(
        timeMs: timeMs,
        easing: easing,
        angleDelta: angleDelta,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'timeMs': timeMs,
        'easing': easing.name,
        'angleDelta': angleDelta,
      };

  factory BoneKeyframe.fromJson(Map<String, Object?> json) => BoneKeyframe(
        timeMs: (json['timeMs'] as num).toInt(),
        easing: EasingKind.values.firstWhere(
          (e) => e.name == json['easing'],
          orElse: () => EasingKind.easeInOut,
        ),
        angleDelta: (json['angleDelta'] as num?)?.toDouble() ?? 0,
      );
}

/// Liaison rig maître : une pièce (forme entière) suit un os.
///
/// L'offset de repos n'est PAS figé à la liaison : la pose de base de la forme
/// (x, y, rotation, échelle — ses sliders) sert d'offset de repos. À l'instant
/// t la pièce est rendue sous la transformée `os(t) ∘ os(repos)⁻¹ ∘ forme`.
class BoneBinding {
  BoneBinding({required this.shapeId, required this.boneId});

  final String shapeId;
  final String boneId;

  Map<String, Object?> toJson() => <String, Object?>{
        'shapeId': shapeId,
        'boneId': boneId,
      };

  factory BoneBinding.fromJson(Map<String, Object?> json) => BoneBinding(
        shapeId: json['shapeId'] as String,
        boneId: json['boneId'] as String,
      );
}

/// Le rig complet d'un projet squelette : arbre d'os, liaisons pièces → os
/// et pistes d'animation (keyframes d'angle par os).
class SkeletonRig {
  SkeletonRig({
    String? name,
    List<RigBone>? bones,
    List<BoneBinding>? bindings,
    Map<String, List<BoneKeyframe>>? tracks,
  })  : name = name ?? 'Squelette',
        bones = bones ?? <RigBone>[],
        bindings = bindings ?? <BoneBinding>[],
        tracks = tracks ?? <String, List<BoneKeyframe>>{};

  String name;
  final List<RigBone> bones;
  final List<BoneBinding> bindings;
  final Map<String, List<BoneKeyframe>> tracks;

  RigBone? boneById(String? id) {
    if (id == null) return null;
    for (final bone in bones) {
      if (bone.id == id) return bone;
    }
    return null;
  }

  BoneBinding? bindingForShape(String? shapeId) {
    if (shapeId == null) return null;
    for (final binding in bindings) {
      if (binding.shapeId == shapeId) return binding;
    }
    return null;
  }

  String? boneIdForShape(String? shapeId) => bindingForShape(shapeId)?.boneId;

  bool isBound(String shapeId) => bindingForShape(shapeId) != null;

  /// Profondeur dans l'arbre (racine = 0), pour l'indentation de l'UI.
  int depthOf(String boneId) {
    var depth = 0;
    String? current = boneId;
    while (true) {
      final bone = boneById(current);
      if (bone == null) return depth;
      depth++;
      current = bone.parentId;
      if (current == null) return depth - 1;
    }
  }

  /// Os parents avant enfants (évaluation FK dans l'ordre de la chaîne).
  List<RigBone> orderedParentsFirst() {
    final byId = <String, RigBone>{for (final bone in bones) bone.id: bone};
    final resolved = <String>{};
    final ordered = <RigBone>[];
    var progress = true;
    while (progress && resolved.length < bones.length) {
      progress = false;
      for (final bone in bones) {
        if (resolved.contains(bone.id)) continue;
        final parent = bone.parentId;
        final ready = parent == null ||
            !byId.containsKey(parent) || // parent absent : traité en racine
            resolved.contains(parent);
        if (!ready) continue;
        ordered.add(bone);
        resolved.add(bone.id);
        progress = true;
      }
    }
    // Cycle résiduel (ne devrait jamais arriver) : on boucle le reste en racine.
    for (final bone in bones) {
      if (!resolved.contains(bone.id)) ordered.add(bone);
    }
    return ordered;
  }

  // -------------------------------------------------------------- pistes

  List<BoneKeyframe>? trackOf(String boneId) => tracks[boneId];

  bool hasKeyframes(String boneId) => (tracks[boneId] ?? const []).isNotEmpty;

  /// Delta d'angle échantillonné à [timeMs] (0 hors de toute plage : repos).
  double angleDeltaAt(String boneId, int timeMs) {
    final track = tracks[boneId];
    if (track == null || track.isEmpty) return 0;
    if (timeMs <= track.first.timeMs) return track.first.angleDelta;
    if (timeMs >= track.last.timeMs) return track.last.angleDelta;
    for (var i = 0; i < track.length - 1; i++) {
      final a = track[i];
      final b = track[i + 1];
      if (timeMs >= a.timeMs && timeMs <= b.timeMs) {
        final span = math.max(1, b.timeMs - a.timeMs);
        final progress = applyEasing(b.easing, (timeMs - a.timeMs) / span);
        return a.angleDelta + (b.angleDelta - a.angleDelta) * progress;
      }
    }
    return track.last.angleDelta;
  }

  /// Keyframe la plus proche du curseur dans la tolérance, ou null.
  BoneKeyframe? keyframeNear(String boneId, int timeMs, int toleranceMs) {
    BoneKeyframe? best;
    var bestDelta = toleranceMs;
    for (final key in tracks[boneId] ?? const <BoneKeyframe>[]) {
      final delta = (key.timeMs - timeMs).abs();
      if (delta <= bestDelta) {
        best = key;
        bestDelta = delta;
      }
    }
    return best;
  }

  /// Ajoute ou remplace la keyframe d'angle à [timeMs], triées à chaque fois.
  void upsertKeyframe(String boneId, int timeMs, double angleDelta,
      {EasingKind? easing}) {
    final track = tracks.putIfAbsent(boneId, () => <BoneKeyframe>[]);
    track.removeWhere((k) => k.timeMs == timeMs);
    track.add(BoneKeyframe(
      timeMs: timeMs,
      easing: easing ?? EasingKind.easeInOut,
      angleDelta: angleDelta,
    ));
    track.sort((a, b) => a.timeMs.compareTo(b.timeMs));
  }

  void removeKeyframeAt(String boneId, int timeMs) {
    tracks[boneId]?.removeWhere((k) => k.timeMs == timeMs);
    if (tracks[boneId]?.isEmpty ?? false) tracks.remove(boneId);
  }

  void setKeyframeEasing(String boneId, int timeMs, EasingKind easing) {
    for (final key in tracks[boneId] ?? const <BoneKeyframe>[]) {
      if (key.timeMs == timeMs) key.easing = easing;
    }
  }

  /// Décale toute la piste de [deltaMs] ; les keyframes passées sous zéro
  /// sont rabotées à zéro (mêmes règles que `VectorShape.shiftBy`).
  void shiftTrack(String boneId, int deltaMs) {
    final track = tracks[boneId];
    if (track == null || deltaMs == 0) return;
    for (final key in track) {
      key.timeMs = math.max(0, key.timeMs + deltaMs);
    }
  }

  /// Décale la piste pour que sa première keyframe atterrisse à
  /// [targetFirstMs] (écart relatif et courbes préservés).
  void shiftTrackTo(String boneId, int targetFirstMs) {
    final track = tracks[boneId];
    if (track == null || track.isEmpty) return;
    shiftTrack(boneId, targetFirstMs - track.first.timeMs);
  }

  int get maxKeyframeTimeMs {
    var max = 0;
    for (final track in tracks.values) {
      for (final key in track) {
        if (key.timeMs > max) max = key.timeMs;
      }
    }
    return max;
  }

  // ------------------------------------------------------------ édition

  void addBone(RigBone bone) => bones.add(bone);

  void bindShape(String shapeId, String boneId) {
    bindings.removeWhere((b) => b.shapeId == shapeId);
    bindings.add(BoneBinding(shapeId: shapeId, boneId: boneId));
  }

  void unbindShape(String shapeId) =>
      bindings.removeWhere((b) => b.shapeId == shapeId);

  /// Supprime un os : les enfants sont re-parentés à son parent (le rig reste
  /// connexe), ses liaisons et sa piste d'animation sont retirées.
  void removeBone(String boneId) {
    final bone = boneById(boneId);
    if (bone == null) return;
    for (final child in bones) {
      if (child.parentId == boneId) child.parentId = bone.parentId;
    }
    bones.removeWhere((b) => b.id == boneId);
    bindings.removeWhere((b) => b.boneId == boneId);
    tracks.remove(boneId);
  }

  SkeletonRig copy() => SkeletonRig(
        name: name,
        bones: [for (final bone in bones) bone.copy()],
        bindings: [
          for (final binding in bindings)
            BoneBinding(shapeId: binding.shapeId, boneId: binding.boneId),
        ],
        tracks: <String, List<BoneKeyframe>>{
          for (final entry in tracks.entries)
            entry.key: [for (final key in entry.value) key.copy()],
        },
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'bones': [for (final bone in bones) bone.toJson()],
        'bindings': [for (final binding in bindings) binding.toJson()],
        'tracks': <String, Object?>{
          for (final entry in tracks.entries)
            entry.key: [for (final key in entry.value) key.toJson()],
        },
      };

  factory SkeletonRig.fromJson(Map<String, Object?> json) => SkeletonRig(
        name: json['name'] as String? ?? 'Squelette',
        bones: (json['bones'] as List<Object?>? ?? const [])
            .map((b) => RigBone.fromJson((b as Map).cast<String, Object?>()))
            .toList(),
        bindings: (json['bindings'] as List<Object?>? ?? const [])
            .map((b) => BoneBinding.fromJson((b as Map).cast<String, Object?>()))
            .toList(),
        tracks: <String, List<BoneKeyframe>>{
          for (final entry in
              ((json['tracks'] as Map?)?.cast<String, Object?>() ??
                      const <String, Object?>{})
                  .entries)
            entry.key: [
              for (final key in (entry.value as List<Object?>? ?? const []))
                BoneKeyframe.fromJson((key as Map).cast<String, Object?>()),
            ]..sort((a, b) => a.timeMs.compareTo(b.timeMs)),
        },
      );
}

/// État d'un os à un instant donné : frame de repos (monde) et frame animée.
class BoneFrame {
  const BoneFrame({
    required this.jointRest,
    required this.worldAngleRest,
    required this.joint,
    required this.worldAngle,
    required this.length,
  });

  /// Articulation au repos (coordonnées projet) et angle monde au repos.
  final Offset jointRest;
  final double worldAngleRest;

  /// Articulation et angle monde à l'instant courant.
  final Offset joint;
  final double worldAngle;
  final double length;

  /// Delta d'angle accumulé (parents + propre) par rapport au repos.
  double get worldDelta => worldAngle - worldAngleRest;

  /// Extrémité de l'os à l'instant courant.
  Offset get tip => joint + Offset.fromDirection(worldAngle, length);

  /// Extrémité au repos.
  Offset get tipRest =>
      jointRest + Offset.fromDirection(worldAngleRest, length);

  /// Applique le mouvement de l'os (repos → instant courant) à un point du
  /// repère projet de repos : `joint + R(worldDelta)·(p − jointRest)`.
  /// Identité au repos — c'est exactement la transformée que le painter
  /// applique au canvas avant la pose de la pièce.
  Offset mapPoint(Offset p) =>
      joint + rotateVector(p - jointRest, worldDelta);
}

/// Évaluation FK du rig à un instant donné : transformée monde de chaque os.
class SkeletonPose {
  const SkeletonPose(this.frames);

  final Map<String, BoneFrame> frames;

  BoneFrame? frameOf(String? boneId) =>
      boneId == null ? null : frames[boneId];

  /// Les parents sont résolus avant les enfants (voir `orderedParentsFirst`).
  /// Un parent absent de l'arbre est traité comme une racine (robustesse
  /// face à un JSON corrompu) ; un cycle éventuel est dénoué en racines.
  static SkeletonPose evaluate(SkeletonRig rig, int timeMs) {
    final frames = <String, BoneFrame>{};
    for (final bone in rig.orderedParentsFirst()) {
      final parentFrame = rig.bones.any((b) => b.id == bone.parentId)
          ? frames[bone.parentId]
          : null;

      // Repos : le parent impose sa frame de repos à la chaîne.
      final Offset jointRest;
      final double angleRest;
      if (parentFrame == null) {
        jointRest = Offset(bone.offsetX, bone.offsetY);
        angleRest = bone.restAngle;
      } else {
        jointRest = parentFrame.jointRest +
            rotateVector(
              Offset(bone.offsetX, bone.offsetY),
              parentFrame.worldAngleRest,
            );
        angleRest = parentFrame.worldAngleRest + bone.restAngle;
      }

      // Animation : le mouvement du parent se propage, + le delta propre.
      final double parentDelta;
      final Offset parentDeltaPos;
      if (parentFrame == null) {
        parentDelta = 0;
        parentDeltaPos = Offset.zero;
      } else {
        parentDelta = parentFrame.worldDelta;
        parentDeltaPos = parentFrame.joint - parentFrame.jointRest;
      }
      final joint = parentFrame == null
          ? Offset(bone.offsetX, bone.offsetY)
          : parentFrame.jointRest +
              parentDeltaPos +
              rotateVector(
                Offset(bone.offsetX, bone.offsetY),
                parentFrame.worldAngleRest + parentDelta,
              );
      final worldAngle = angleRest + parentDelta + rig.angleDeltaAt(
            bone.id,
            timeMs,
          );

      frames[bone.id] = BoneFrame(
        jointRest: jointRest,
        worldAngleRest: angleRest,
        joint: joint,
        worldAngle: worldAngle,
        length: bone.length,
      );
    }
    return SkeletonPose(frames);
  }
}

/// Tourne un vecteur de [angle] radians (repère écran : y vers le bas).
Offset rotateVector(Offset vector, double angle) {
  final cos = math.cos(angle);
  final sin = math.sin(angle);
  return Offset(
    vector.dx * cos - vector.dy * sin,
    vector.dx * sin + vector.dy * cos,
  );
}
