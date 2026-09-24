import 'package:flutter_test/flutter_test.dart';
import 'package:vector_anim_studio/engine/timeline_layout.dart';
import 'package:vector_anim_studio/models/animation.dart';
import 'package:vector_anim_studio/models/skeleton.dart';

void main() {
  VectorShape shape(String name, int start, int end) =>
      VectorShape(name: name, startMs: start, endMs: end);

  group('TimelineLayout.packLanes', () {
    test('place deux formes qui ne se chevauchent pas sur la même ligne', () {
      final lanes = TimelineLayout.packLanes(<VectorShape>[
        shape('A', 0, 1000),
        shape('B', 1000, 2000),
      ]);
      expect(lanes.length, 1);
      expect(lanes.first.map((s) => s.name), <String>['A', 'B']);
    });

    test('empile deux formes qui se chevauchent sur deux lignes', () {
      final lanes = TimelineLayout.packLanes(<VectorShape>[
        shape('A', 0, 2000),
        shape('B', 500, 1500),
      ]);
      expect(lanes.length, 2);
      expect(lanes[0].first.name, 'A');
      expect(lanes[1].first.name, 'B');
    });

    test('réutilise la première ligne libre', () {
      final lanes = TimelineLayout.packLanes(<VectorShape>[
        shape('A', 0, 1000),
        shape('B', 0, 3000),
        shape('C', 1200, 2000),
      ]);
      expect(lanes.length, 2);
      expect(lanes[0].map((s) => s.name), <String>['A', 'C']);
      expect(lanes[1].map((s) => s.name), <String>['B']);
    });

    test('trie les formes par début d’affichage', () {
      final lanes = TimelineLayout.packLanes(<VectorShape>[
        shape('B', 1000, 2000),
        shape('A', 0, 500),
      ]);
      expect(lanes.first.map((s) => s.name), <String>['A', 'B']);
    });

    test('laneIndexOf retrouve la ligne d’une forme', () {
      final a = shape('A', 0, 2000);
      final b = shape('B', 500, 1500);
      final lanes = TimelineLayout.packLanes(<VectorShape>[a, b]);
      expect(TimelineLayout.laneIndexOf(lanes, a), 0);
      expect(TimelineLayout.laneIndexOf(lanes, b), 1);
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
