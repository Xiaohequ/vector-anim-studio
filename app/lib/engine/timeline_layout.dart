import '../models/animation.dart';
import '../models/skeleton.dart';

/// Empilement des formes sur la timeline : une ligne par "piste d'affichage".
///
/// Deux formes qui se chevauchent dans le temps occupent deux lignes
/// parallèles ; une forme dont la fenêtre ne croise aucune autre réutilise
/// la première ligne libre.
class TimelineLayout {
  const TimelineLayout._();

  static List<List<VectorShape>> packLanes(List<VectorShape> shapes) {
    final ordered = List<VectorShape>.from(shapes)
      ..sort((a, b) {
        final byStart = a.startMs.compareTo(b.startMs);
        return byStart != 0 ? byStart : a.name.compareTo(b.name);
      });

    final lanes = <List<VectorShape>>[];
    final laneEnds = <int>[];

    for (final shape in ordered) {
      var placed = false;
      for (var i = 0; i < lanes.length; i++) {
        if (laneEnds[i] <= shape.startMs) {
          lanes[i].add(shape);
          laneEnds[i] = shape.endMs;
          placed = true;
          break;
        }
      }
      if (!placed) {
        lanes.add(<VectorShape>[shape]);
        laneEnds.add(shape.endMs);
      }
    }
    return lanes;
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
