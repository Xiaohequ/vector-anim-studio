import 'package:flutter_test/flutter_test.dart';
import 'package:vector_anim_studio/engine/timeline_layout.dart';
import 'package:vector_anim_studio/models/animation.dart';
import 'package:vector_anim_studio/models/skeleton.dart';

void main() {
  /// Forme animée dont le span de contenu va de [start] à [end] (ms).
  VectorShape shape(String name, int start, int end) {
    final s = VectorShape(name: name);
    s.upsertKeyframe(start, s.poseAt(0));
    s.upsertKeyframe(end, s.poseAt(0));
    return s;
  }

  group('TimelineLayout.packLanes', () {
    test('chaque forme occupe sa propre ligne, triée par nom (v0.18.2)', () {
      final lanes = TimelineLayout.packLanes(<VectorShape>[
        shape('B', 1000, 2000),
        VectorShape(name: 'Statique'),
        shape('A', 0, 500),
      ]);
      // Barre = durée de rendu [0, fullSpan] pour TOUTES les formes
      // (keyframes ou pas — v0.18.2) : chevauchement total → une ligne
      // par forme, ordre alphabétique.
      expect(lanes.length, 3);
      expect(lanes.map((l) => l.single.name), <String>['A', 'B', 'Statique']);
    });

    test('laneIndexOf retrouve la ligne d’une forme', () {
      final a = shape('A', 0, 2000);
      final b = shape('B', 500, 1500);
      final lanes = TimelineLayout.packLanes(<VectorShape>[a, b]);
      expect(TimelineLayout.laneIndexOf(lanes, a), 0);
      expect(TimelineLayout.laneIndexOf(lanes, b), 1);
    });

    test('deux formes statiques sans keyframe : deux lignes (v0.18.1)', () {
      final lanes = TimelineLayout.packLanes(<VectorShape>[
        VectorShape(name: 'S1'),
        VectorShape(name: 'S2'),
      ]);
      expect(lanes.length, 2);
    });
  });

  group('TimelineLayout.packBoneLanes', () {
    test('une barre par os animé, os sans keyframe ignoré', () {
      final rig = SkeletonRig();
      final a = RigBone(name: 'A');
      final b = RigBone(name: 'B');
      rig.addBone(a);
      rig.addBone(b);
      rig.upsertKeyframe(a.id, 200, 0.1);
      rig.upsertKeyframe(a.id, 1000, 0.3);

      final lanes = TimelineLayout.packBoneLanes(rig);
      expect(lanes.length, 1);
      expect(lanes.single.single.id, a.id);
    });

    test('deux pistes qui se chevauchent sur deux lignes', () {
      final rig = SkeletonRig();
      final a = RigBone(name: 'A');
      final b = RigBone(name: 'B');
      rig.addBone(a);
      rig.addBone(b);
      rig.upsertKeyframe(a.id, 0, 0.1);
      rig.upsertKeyframe(a.id, 2000, 0.2);
      rig.upsertKeyframe(b.id, 500, 0.1);
      rig.upsertKeyframe(b.id, 1500, 0.2);

      final lanes = TimelineLayout.packBoneLanes(rig);
      expect(lanes.length, 2);
    });
  });
}
