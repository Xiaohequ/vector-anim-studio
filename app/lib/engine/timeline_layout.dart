import '../models/animation.dart';

/// Empilement des formes sur la timeline : une ligne par "piste d'affichage".
///
/// Deux formes qui se chevauchent dans le temps occupent deux lignes
/// parallèles ; une forme dont la fenêtre ne croise aucune autre réutilise
/// la première ligne libre.
/// Entrée de la timeline : une forme, ou la ligne d'un groupe (v0.35).
/// Un groupe replié n'a qu'une ligne (sa barre, étendue dérivée de ses fils) ;
/// déplié, il a sa ligne puis une ligne par fil.
class TimelineRow {
  const TimelineRow.shape(this.shape) : group = null;
  const TimelineRow.group(this.group) : shape = null;

  final VectorShape? shape;
  final ShapeGroup? group;

  bool get isGroup => group != null;
}

class TimelineLayout {
  const TimelineLayout._();

  /// Lignes de la timeline : les formes non groupées et les groupes (repliés
  /// ou dépliés) rangés par leurs fils. Un fil déplié s'empile sous la ligne
  /// de son groupe.
  static List<List<TimelineRow>> packRows(AnimationProject project) {
    final rows = <TimelineRow>[];
    final groups = List<ShapeGroup>.from(project.groups)
      ..sort((a, b) {
        final aStart = project.groupSpanMs(a.id)?.$1 ?? 0;
        final bStart = project.groupSpanMs(b.id)?.$1 ?? 0;
        final byStart = aStart.compareTo(bStart);
        return byStart != 0 ? byStart : a.name.compareTo(b.name);
      });
    for (final group in groups) {
      if (project.groupSpanMs(group.id) == null) continue;
      rows.add(TimelineRow.group(group));
      if (group.collapsed) continue;
      final children =
          project.shapes.where((shape) => shape.groupId == group.id).toList()
            ..sort((a, b) {
              final byStart = a.startMs.compareTo(b.startMs);
              return byStart != 0 ? byStart : a.name.compareTo(b.name);
            });
      rows.addAll(children.map(TimelineRow.shape));
    }
    final ungrouped = project.shapes.where((shape) {
      final group = project.groupById(shape.groupId);
      return group == null;
    }).toList();
    return <List<TimelineRow>>[
      for (final row in rows) <TimelineRow>[row],
      for (final lane in packLanes(ungrouped))
        <TimelineRow>[for (final shape in lane) TimelineRow.shape(shape)],
    ];
  }

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
