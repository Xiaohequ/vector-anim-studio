import '../models/animation.dart';

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
}
