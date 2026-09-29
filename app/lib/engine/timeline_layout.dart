import '../models/animation.dart';
import '../models/skeleton.dart';

/// Empilement des formes ANIMÉES sur la timeline : une ligne par « piste ».
///
/// La barre d'une forme couvre le span de son contenu (1re → dernière
/// keyframe) : les fenêtres d'affichage ont été supprimées (v0.18). Deux
/// formes dont les spans se chevauchent occupent deux lignes parallèles ;
/// une forme dont le span ne croise aucune autre réutilise la ligne libre.
class TimelineLayout {
  const TimelineLayout._();

  static List<List<VectorShape>> packLanes(
    List<VectorShape> shapes, {
    int fullSpanMs = 4000,
  }) {
    // Formes ANIMÉES + instances (une instance s'anime en boucle même sans
    // keyframe hôte → barre pleine durée) ; les formes statiques sans
    // keyframe n'ont pas de barre (sélection au canvas).
    final animated = shapes
        .where((s) => s.keyframes.isNotEmpty || s.isInstance)
        .toList()
      ..sort((a, b) {
        final byStart = _spanStart(
          a,
          fullSpanMs,
        ).compareTo(_spanStart(b, fullSpanMs));
        return byStart != 0 ? byStart : a.name.compareTo(b.name);
      });

    final lanes = <List<VectorShape>>[];
    final laneEnds = <int>[];

    for (final shape in animated) {
      final start = _spanStart(shape, fullSpanMs);
      var placed = false;
      for (var i = 0; i < lanes.length; i++) {
        if (laneEnds[i] <= start) {
          lanes[i].add(shape);
          laneEnds[i] = _spanEnd(shape, fullSpanMs);
          placed = true;
          break;
        }
      }
      if (!placed) {
        lanes.add(<VectorShape>[shape]);
        laneEnds.add(_spanEnd(shape, fullSpanMs));
      }
    }
    return lanes;
  }

  /// Début du span affiché : 1re keyframe, ou 0 pour une instance sans
  /// keyframe (barre pleine durée).
  static int _spanStart(VectorShape shape, int fullSpanMs) =>
      shape.keyframes.isEmpty ? 0 : shape.spanStartMs;

  /// Fin du span affiché : dernière keyframe, ou [fullSpanMs] pour une
  /// instance sans keyframe.
  static int _spanEnd(VectorShape shape, int fullSpanMs) =>
      shape.keyframes.isEmpty ? fullSpanMs : shape.spanEndMs;

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
