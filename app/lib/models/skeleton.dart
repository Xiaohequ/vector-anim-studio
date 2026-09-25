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
    this.z = 0,
    this.ikEnabled = false,
    this.bendSign = 1,
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

  /// Ordre de dessin (v0.10) : les pièces portées sont triées par z croissant
  /// (les z négatifs passent derrière). Les pièces à z égal gardent l'ordre
  /// de la timeline.
  int z;

  /// IK 2 os (v0.10) : quand activé sur un os portant exactement UN enfant,
  /// le glisser de l'EXTRÉMITÉ de l'enfant résout la chaîne (l'extrémité de
  /// l'enfant suit le doigt, le coude plie) au lieu de pivoter l'enfant.
  bool ikEnabled;

  /// Sens du coude de la chaîne IK : +1 ou -1 (côté du pli).
  double bendSign;

  RigBone copy({String? id, String? parentId}) => RigBone(
    id: id ?? this.id,
    name: name,
    parentId: parentId ?? this.parentId,
    offsetX: offsetX,
    offsetY: offsetY,
    restAngle: restAngle,
    length: length,
    z: z,
    ikEnabled: ikEnabled,
    bendSign: bendSign,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'parentId': parentId,
    'offsetX': offsetX,
    'offsetY': offsetY,
    'restAngle': restAngle,
    'length': length,
    if (z != 0) 'z': z,
    if (ikEnabled) 'ikEnabled': true,
    if (bendSign != 1) 'bendSign': bendSign,
  };

  factory RigBone.fromJson(Map<String, Object?> json) => RigBone(
    id: json['id'] as String?,
    name: json['name'] as String? ?? 'Os',
    parentId: json['parentId'] as String?,
    offsetX: (json['offsetX'] as num?)?.toDouble() ?? 0,
    offsetY: (json['offsetY'] as num?)?.toDouble() ?? 0,
    restAngle: (json['restAngle'] as num?)?.toDouble() ?? 0,
    length: (json['length'] as num?)?.toDouble() ?? 80,
    z: (json['z'] as num?)?.toInt() ?? 0,
    ikEnabled: json['ikEnabled'] as bool? ?? false,
    bendSign: (json['bendSign'] as num?)?.toDouble() ?? 1,
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
    this.opacity = 1,
    this.stretch = 1,
    this.squash = 1,
  });

  int timeMs;
  EasingKind easing;
  double angleDelta;

  /// Opacité des pièces portées (v0.10) : 1 = opaque.
  double opacity;

  /// Étirement le long de l'os (v0.10) : 1 = neutre, > 1 allonge.
  double stretch;

  /// Écrasement perpendiculaire à l'os (v0.10) : 1 = neutre.
  double squash;

  BoneKeyframe copy() => BoneKeyframe(
    timeMs: timeMs,
    easing: easing,
    angleDelta: angleDelta,
    opacity: opacity,
    stretch: stretch,
    squash: squash,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'timeMs': timeMs,
    'easing': easing.name,
    'angleDelta': angleDelta,
    'opacity': opacity,
    'stretch': stretch,
    'squash': squash,
  };

  factory BoneKeyframe.fromJson(Map<String, Object?> json) => BoneKeyframe(
    timeMs: (json['timeMs'] as num).toInt(),
    easing: EasingKind.values.firstWhere(
      (e) => e.name == json['easing'],
      orElse: () => EasingKind.easeInOut,
    ),
    angleDelta: (json['angleDelta'] as num?)?.toDouble() ?? 0,
    opacity: (json['opacity'] as num?)?.toDouble() ?? 1,
    stretch: (json['stretch'] as num?)?.toDouble() ?? 1,
    squash: (json['squash'] as num?)?.toDouble() ?? 1,
  );
}

/// Liaison rig maître : une pièce (ou une couche précise, v0.9.6) suit un os.
///
/// L'offset de repos n'est PAS figé à la liaison : la pose de base de la forme
/// (x, y, rotation, échelle — ses sliders) sert d'offset de repos. À l'instant
/// t la pièce est rendue sous la transformée `os(t) ∘ os(repos)⁻¹ ∘ forme`.
class BoneBinding {
  BoneBinding({required this.shapeId, required this.boneId, this.layerId});

  final String shapeId;
  final String boneId;

  /// Couche liée à l'intérieur de la forme (v0.9.6) ; null = la forme
  /// ENTIÈRE suit l'os (liaison historique). Une liaison de couche prend le
  /// pas sur la liaison de forme pour cette couche — la couche liée suit
  /// SON os uniquement.
  final String? layerId;

  Map<String, Object?> toJson() => <String, Object?>{
    'shapeId': shapeId,
    'boneId': boneId,
    if (layerId != null) 'layerId': layerId,
  };

  factory BoneBinding.fromJson(Map<String, Object?> json) => BoneBinding(
    shapeId: json['shapeId'] as String,
    boneId: json['boneId'] as String,
    layerId: json['layerId'] as String?,
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
  }) : name = name ?? 'Squelette',
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
      if (binding.shapeId == shapeId && binding.layerId == null) {
        return binding;
      }
    }
    return null;
  }

  /// Liaison d'une couche précise de la forme (v0.9.6), ou null.
  BoneBinding? bindingForLayer(String? shapeId, String? layerId) {
    if (shapeId == null || layerId == null) return null;
    for (final binding in bindings) {
      if (binding.shapeId == shapeId && binding.layerId == layerId) {
        return binding;
      }
    }
    return null;
  }

  /// Lie (ou re-lie) une couche précise à un os — remplace la liaison
  /// précédente de cette couche.
  void bindLayer(String shapeId, String layerId, String boneId) {
    bindings.removeWhere((b) => b.shapeId == shapeId && b.layerId == layerId);
    bindings.add(
      BoneBinding(shapeId: shapeId, boneId: boneId, layerId: layerId),
    );
  }

  void unbindLayer(String shapeId, String layerId) =>
      bindings.removeWhere((b) => b.shapeId == shapeId && b.layerId == layerId);

  /// Emporte les liaisons d'une forme clonée (forme entière et couches) —
  /// les ids de couches sont régénérés dans le clone : [layerIdMap] =
  /// ancien id → id du clone (même ordre).
  void duplicateBindings(
    String shapeId,
    String cloneShapeId,
    Map<String, String> layerIdMap,
  ) {
    for (final binding
        in bindings.where((b) => b.shapeId == shapeId).toList()) {
      bindings.add(
        BoneBinding(
          shapeId: cloneShapeId,
          boneId: binding.boneId,
          layerId: binding.layerId == null
              ? null
              : layerIdMap[binding.layerId!],
        ),
      );
    }
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
        final ready =
            parent == null ||
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

  /// Échantillonnage générique d'une propriété de keyframe d'os
  /// (opacité, étirement, écrasement) : tenue hors plage, easing entre
  /// deux keyframes, valeur 1 (neutre) sans piste.
  double _numAt(String boneId, int timeMs, double Function(BoneKeyframe) pick) {
    final track = tracks[boneId];
    if (track == null || track.isEmpty) return 1;
    if (timeMs <= track.first.timeMs) return pick(track.first);
    if (timeMs >= track.last.timeMs) return pick(track.last);
    for (var i = 0; i < track.length - 1; i++) {
      final a = track[i];
      final b = track[i + 1];
      if (timeMs >= a.timeMs && timeMs <= b.timeMs) {
        final span = math.max(1, b.timeMs - a.timeMs);
        final progress = applyEasing(b.easing, (timeMs - a.timeMs) / span);
        return pick(a) + (pick(b) - pick(a)) * progress;
      }
    }
    return pick(track.last);
  }

  /// Opacité des pièces portées par l'os à [timeMs] (1 sans piste).
  double opacityAt(String boneId, int timeMs) =>
      _numAt(boneId, timeMs, (k) => k.opacity);

  /// Étirement le long de l'os à [timeMs] (1 sans piste).
  double stretchAt(String boneId, int timeMs) =>
      _numAt(boneId, timeMs, (k) => k.stretch);

  /// Écrasement perpendiculaire à l'os à [timeMs] (1 sans piste).
  double squashAt(String boneId, int timeMs) =>
      _numAt(boneId, timeMs, (k) => k.squash);

  /// z de dessin des pièces d'une forme : os porteur (liaison forme
  /// entière), sinon le plus petit z des os portant ses couches, sinon 0.
  int zForShape(String? shapeId) {
    final shapeBinding = bindingForShape(shapeId);
    final bone = boneById(shapeBinding?.boneId);
    if (bone != null) return bone.z;
    var min = 0;
    var found = false;
    for (final binding in bindings) {
      if (binding.shapeId != shapeId || binding.layerId == null) continue;
      final carrier = boneById(binding.boneId);
      if (carrier == null) continue;
      min = found ? math.min(min, carrier.z) : carrier.z;
      found = true;
    }
    return found ? min : 0;
  }

  /// z de dessin d'une couche précise (os qui la porte), ou null.
  int? zOfLayer(String? shapeId, String? layerId) =>
      boneById(bindingForLayer(shapeId, layerId)?.boneId)?.z;

  /// Enfant unique d'un os (chaîne IK 2 os), ou null.
  RigBone? onlyChildOf(String boneId) {
    RigBone? child;
    for (final bone in bones) {
      if (bone.parentId == boneId) {
        if (child != null) return null; // plusieurs enfants : pas d'IK
        child = bone;
      }
    }
    return child;
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

  /// Ajoute ou remplace la keyframe d'os à [timeMs], triées à chaque fois.
  /// Si une keyframe existe déjà à ce temps, elle est FUSIONNÉE : son easing
  /// et ses propriétés (opacité, étirement, écrasement) sont conservés sauf
  /// valeurs explicitement fournies — écrire un angle n'écrase pas l'opacité.
  void upsertKeyframe(
    String boneId,
    int timeMs,
    double angleDelta, {
    EasingKind? easing,
    double? opacity,
    double? stretch,
    double? squash,
  }) {
    final track = tracks.putIfAbsent(boneId, () => <BoneKeyframe>[]);
    BoneKeyframe? existing;
    for (final key in track) {
      if (key.timeMs == timeMs) {
        existing = key;
        break;
      }
    }
    track.removeWhere((k) => k.timeMs == timeMs);
    track.add(
      BoneKeyframe(
        timeMs: timeMs,
        easing: easing ?? existing?.easing ?? EasingKind.easeInOut,
        angleDelta: angleDelta,
        opacity: opacity ?? existing?.opacity ?? 1,
        stretch: stretch ?? existing?.stretch ?? 1,
        squash: squash ?? existing?.squash ?? 1,
      ),
    );
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

  /// Re-parente un os SANS saut visuel : l'offset et l'angle de repos sont
  /// recalculés dans le repère du nouveau parent (coordonnées projet + angle
  /// monde quand l'os devient racine). L'os « reste ancré sur place » au
  /// preview, sa descendance (offsets relatifs) suit automatiquement, et
  /// l'ancien parent n'a plus d'effet sur lui — v0.9.2 changeait juste le
  /// parentId : l'offset restait dans le repère de l'ANCIEN parent → les os
  /// sautaient hors du preview. [pose] = évaluation du rig AVANT la mutation
  /// (les frames de repos ne dépendent pas du temps).
  void reparentBone(RigBone bone, String? newParentId, SkeletonPose pose) {
    final frame = pose.frameOf(bone.id);
    bone.parentId = newParentId;
    if (frame == null) return;
    final parent = boneById(newParentId);
    final parentFrame = parent == null ? null : pose.frameOf(parent.id);
    if (parentFrame == null) {
      bone.offsetX = frame.jointRest.dx;
      bone.offsetY = frame.jointRest.dy;
      bone.restAngle = frame.worldAngleRest;
    } else {
      final local = rotateVector(
        frame.jointRest - parentFrame.jointRest,
        -parentFrame.worldAngleRest,
      );
      bone.offsetX = local.dx;
      bone.offsetY = local.dy;
      bone.restAngle = frame.worldAngleRest - parentFrame.worldAngleRest;
    }
  }

  /// Déplace l'articulation de repos d'un os de [worldDelta] (coordonnées
  /// monde/projet). Racine : le delta s'applique tel quel à l'offset. Enfant :
  /// le delta est ramené dans le repère de repos du parent (angle monde
  /// courant). Les os enfants (offsets relatifs) suivent automatiquement.
  void translateBoneRest(RigBone bone, SkeletonPose pose, Offset worldDelta) {
    final parent = boneById(bone.parentId);
    final parentFrame = parent == null ? null : pose.frameOf(parent.id);
    final local = parentFrame == null
        ? worldDelta
        : rotateVector(worldDelta, -parentFrame.worldAngle);
    bone.offsetX += local.dx;
    bone.offsetY += local.dy;
  }

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
      for (final entry
          in ((json['tracks'] as Map?)?.cast<String, Object?>() ??
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
    this.stretchX = 1,
    this.stretchY = 1,
    this.opacity = 1,
  });

  /// Articulation au repos (coordonnées projet) et angle monde au repos.
  final Offset jointRest;
  final double worldAngleRest;

  /// Articulation et angle monde à l'instant courant.
  final Offset joint;
  final double worldAngle;
  final double length;

  /// Étirement/écrasement PROPRES à l'os à l'instant courant (le long de
  /// l'os et perpendiculaire, dans son repère à lui). Les os ENFANTS suivent
  /// le stretch du parent via leur articulation (voir FK).
  final double stretchX;
  final double stretchY;

  /// Opacité des pièces portées par cet os à l'instant courant.
  final double opacity;

  /// Delta d'angle accumulé (parents + propre) par rapport au repos.
  double get worldDelta => worldAngle - worldAngleRest;

  /// Extrémité de l'os à l'instant courant (l'étirement l'allonge).
  Offset get tip =>
      joint + rotateVector(Offset(length * stretchX, 0), worldAngle);

  /// Extrémité au repos (neutre).
  Offset get tipRest =>
      jointRest + Offset.fromDirection(worldAngleRest, length);

  /// Applique le mouvement de l'os (repos → instant courant) à un point du
  /// repère projet de repos : `joint + R(θt)·S·R(−θrest)·(p − jointRest)`.
  /// Identité au repos — c'est exactement la transformée que le painter
  /// applique au canvas avant la pose de la pièce.
  Offset mapPoint(Offset p) {
    final local = rotateVector(p - jointRest, -worldAngleRest);
    final scaled = Offset(local.dx * stretchX, local.dy * stretchY);
    return joint + rotateVector(scaled, worldAngle);
  }
}

/// Évaluation FK du rig à un instant donné : transformée monde de chaque os.
class SkeletonPose {
  const SkeletonPose(this.frames);

  final Map<String, BoneFrame> frames;

  BoneFrame? frameOf(String? boneId) => boneId == null ? null : frames[boneId];

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
        jointRest =
            parentFrame.jointRest +
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
                  Offset(
                    bone.offsetX * (parentFrame.stretchX),
                    bone.offsetY * (parentFrame.stretchY),
                  ),
                  parentFrame.worldAngleRest + parentDelta,
                );
      final worldAngle =
          angleRest + parentDelta + rig.angleDeltaAt(bone.id, timeMs);

      frames[bone.id] = BoneFrame(
        jointRest: jointRest,
        worldAngleRest: angleRest,
        joint: joint,
        worldAngle: worldAngle,
        length: bone.length,
        stretchX: rig.stretchAt(bone.id, timeMs),
        stretchY: rig.squashAt(bone.id, timeMs),
        opacity: rig.opacityAt(bone.id, timeMs),
      );
    }
    return SkeletonPose(frames);
  }
}

/// Résout l'IK 2 os : angles MONDE du parent et de l'enfant pour que
/// l'extrémité de l'enfant (longueur [length2]) atteigne [target] depuis
/// l'articulation [joint] (le coude est au bout du parent, longueur
/// [length1]). [bend] = +1 ou -1 : côté du pli du coude. Cible hors de
/// portée : la chaîne s'allonge au maximum vers la cible.
(double parentAngle, double childAngle) solveTwoBoneIk({
  required Offset joint,
  required double length1,
  required double length2,
  required Offset target,
  required double bend,
}) {
  final delta = target - joint;
  var d = delta.distance;
  final minD = math.max(0.001, (length1 - length2).abs() + 0.001);
  final maxD = math.max(minD + 0.002, length1 + length2 - 0.001);
  d = d.clamp(minD, maxD);
  final beta = math.atan2(delta.dy, delta.dx);
  final cosA =
      (length1 * length1 + d * d - length2 * length2) / (2 * length1 * d);
  final alpha = math.acos(cosA.clamp(-1.0, 1.0));
  final parentAngle = beta + bend * alpha;
  final cosG =
      (length1 * length1 + length2 * length2 - d * d) / (2 * length1 * length2);
  final gamma = math.acos(cosG.clamp(-1.0, 1.0));
  final childAngle = parentAngle - bend * (math.pi - gamma);
  return (parentAngle, childAngle);
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

/// Crée un os entre [joint] (premier tap = articulation) et [tip]
/// (deuxième tap = extrémité), exprimés en coordonnées monde au temps
/// courant. Avec [parentFrame] (frame de repos de l'os parent), l'angle de
/// repos est relatif et l'offset est ramené dans le repère de repos du
/// parent : l'ARTICULATION posée suit ensuite tout mouvement du parent —
/// v0.9.1 la plaçait au deuxième tap (ancrage décalé du point touché).
RigBone boneBetween(
  Offset joint,
  Offset tip, {
  required String name,
  String? parentId,
  BoneFrame? parentFrame,
}) {
  final bone = RigBone(
    name: name,
    parentId: parentId,
    length: math.max(4.0, (tip - joint).distance),
  );
  bone.restAngle =
      math.atan2(tip.dy - joint.dy, tip.dx - joint.dx) -
      (parentFrame?.worldAngleRest ?? 0);
  if (parentFrame == null) {
    // Racine : articulation en coordonnées projet, angle monde.
    bone.offsetX = joint.dx;
    bone.offsetY = joint.dy;
  } else {
    // Enfant : l'articulation est ramenée dans le repère de repos du parent.
    final restPoint =
        parentFrame.jointRest +
        rotateVector(joint - parentFrame.joint, -parentFrame.worldDelta);
    final local = rotateVector(
      restPoint - parentFrame.jointRest,
      -parentFrame.worldAngleRest,
    );
    bone.offsetX = local.dx;
    bone.offsetY = local.dy;
  }
  return bone;
}

/// Emporte les pièces liées lors d'une modification de la pose de repos du
/// rig (entre [before] et [after], deux évaluations du MÊME rig autour de la
/// mutation). La transformée rigide repos→repos de l'os porteur — pivot à
/// son articulation, rotation deltaAngle — s'applique au centre et à la
/// rotation de chaque pièce dont la frame de repos a changé (l'os porteur
/// comme les os descendants). Liaison de couche : c'est l'ancrage MONDE de
/// la couche qui est transporté, puis réécrit dans le repère de la forme
/// (les couches ne sont pas animables). Écriture auto-key pour les formes :
/// pose au curseur si la pièce est animée, valeur de base sinon.
void carryBoundPieces(
  AnimationProject project,
  SkeletonRig rig,
  SkeletonPose before,
  SkeletonPose after,
  int timeMs, {
  int toleranceMs = 0,
}) {
  for (final binding in rig.bindings) {
    final shape = project.shapeById(binding.shapeId);
    final oldFrame = before.frameOf(binding.boneId);
    final newFrame = after.frameOf(binding.boneId);
    if (shape == null || oldFrame == null || newFrame == null) continue;
    final deltaAngle = newFrame.worldAngleRest - oldFrame.worldAngleRest;
    final moved =
        (newFrame.jointRest - oldFrame.jointRest).distance > 1e-9 ||
        deltaAngle.abs() > 1e-9;
    if (!moved) continue;

    // Liaison de couche (v0.9.6) : transporter l'ancrage monde de la couche.
    if (binding.layerId != null) {
      ShapeLayer? layer;
      for (final candidate in shape.layers) {
        if (candidate.id == binding.layerId) {
          layer = candidate;
          break;
        }
      }
      if (layer == null) continue; // couche supprimée : liaison inerte
      final sX = shape.valueAt(AnimatableProperty.x, timeMs);
      final sY = shape.valueAt(AnimatableProperty.y, timeMs);
      final sRot = shape.valueAt(AnimatableProperty.rotation, timeMs);
      final sScale = shape.valueAt(AnimatableProperty.scale, timeMs);
      // Ancrage monde de repos de la couche (pose de la forme ∘ couche).
      final world =
          Offset(sX, sY) +
          rotateVector(Offset(layer.x, layer.y), sRot) *
              math.max(0.0001, sScale.abs());
      final mappedWorld =
          newFrame.jointRest +
          rotateVector(world - oldFrame.jointRest, deltaAngle);
      // Retour au repère local de la forme (inverse de la pose de la forme).
      final local =
          rotateVector(mappedWorld - Offset(sX, sY), -sRot) /
          math.max(0.0001, sScale.abs());
      layer.x = local.dx;
      layer.y = local.dy;
      layer.rotation += deltaAngle;
      continue;
    }

    final x = shape.valueAt(AnimatableProperty.x, timeMs);
    final y = shape.valueAt(AnimatableProperty.y, timeMs);
    final rotation = shape.valueAt(AnimatableProperty.rotation, timeMs);
    final mapped =
        newFrame.jointRest +
        rotateVector(Offset(x, y) - oldFrame.jointRest, deltaAngle);
    shape.applyValue(
      AnimatableProperty.x,
      mapped.dx,
      timeMs,
      autoKey: true,
      toleranceMs: toleranceMs,
    );
    shape.applyValue(
      AnimatableProperty.y,
      mapped.dy,
      timeMs,
      autoKey: true,
      toleranceMs: toleranceMs,
    );
    shape.applyValue(
      AnimatableProperty.rotation,
      rotation + deltaAngle,
      timeMs,
      autoKey: true,
      toleranceMs: toleranceMs,
    );
  }
}
