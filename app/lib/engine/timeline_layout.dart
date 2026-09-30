import '../models/animation.dart';
import '../models/skeleton.dart';

/// Empilement des formes sur la timeline : une ligne par « piste ».
///
/// v0.18.2 : la barre d'une forme = sa durée de rendu [0, fullSpanMs],
/// indépendante des keyframes — ajouter une keyframe ne rétrécit plus le
/// segment (comportement v0.17 retrouvé). Toutes les barres couvrent donc
/// la même plage et se chevauchent : chaque forme occupe sa propre ligne,
/// triée par nom (l'ancien tri par début de span n'a plus de sens).
/// Les barres d'OS (packBoneLanes) restent au span de leur piste.
class TimelineLayout {
  const TimelineLayout._();

  static List<List<VectorShape>> packLanes(List<VectorShape> shapes) {
    final sorted = shapes.toList()..sort((a, b) => a.name.compareTo(b.name));
    return <List<VectorShape>>[
      for (final shape in sorted) <VectorShape>[shape],
    ];
  }

  static int laneIndexOf(List<List<VectorShape>> lanes, VectorShape shape) {
    for (var i = 0; i < lanes.length; i++) {
      if (lanes[i].any((s) => s.id == shape.id)) return i;
    }
    return 0;
  }

  /// Empilement des pistes d'OS (projet squelette) : même glouton que les
  /// formes, appliqué aux plages [première keyframe, dernière keyframe].
  /// Seuls les os avec au moins une keyframe apparaissent.
  static List<List<RigBone>> packBoneLanes(SkeletonRig rig) {
    final entries = <(RigBone, int, int)>[];
    for (final bone in rig.bones) {
      final track = rig.trackOf(bone.id);
      if (track == null || track.isEmpty) continue;
      entries.add((bone, track.first.timeMs, track.last.timeMs));
    }
    entries.sort((a, b) {
      final byStart = a.$2.compareTo(b.$2);
      return byStart != 0 ? byStart : a.$1.name.compareTo(b.$1.name);
    });

    final lanes = <List<RigBone>>[];
    final laneEnds = <int>[];
    for (final entry in entries) {
      var placed = false;
      for (var i = 0; i < lanes.length; i++) {
        if (laneEnds[i] <= entry.$2) {
          lanes[i].add(entry.$1);
          laneEnds[i] = entry.$3;
          placed = true;
          break;
        }
      }
      if (!placed) {
        lanes.add(<RigBone>[entry.$1]);
        laneEnds.add(entry.$3);
      }
    }
    return lanes;
  }
}
