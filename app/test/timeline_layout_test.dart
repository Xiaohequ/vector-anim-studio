import 'package:flutter_test/flutter_test.dart';
import 'package:vector_anim_studio/engine/timeline_layout.dart';
import 'package:vector_anim_studio/models/animation.dart';

void main() {
  VectorShape shape(String name, int start, int end) =>
      VectorShape(name: name, startMs: start, endMs: end);

  group('TimelineLayout.packRows (groupes v0.35)', () {
    test('un groupe replié ne produit qu’une ligne, ses fils sont masqués', () {
      final project = AnimationProject.blank(name: 'G');
      final group = ShapeGroup(name: 'Tête', collapsed: true);
      project.groups.add(group);
      project.shapes.addAll(<VectorShape>[
        VectorShape(name: 'A', startMs: 0, endMs: 1000, groupId: group.id),
        VectorShape(name: 'B', startMs: 500, endMs: 1500, groupId: group.id),
      ]);
      final rows = TimelineLayout.packRows(project).expand((l) => l).toList();
      expect(rows.where((r) => r.isGroup), hasLength(1));
      expect(rows.where((r) => !r.isGroup), isEmpty);
    });

    test('un groupe déplié affiche sa ligne puis chaque fil', () {
      final project = AnimationProject.blank(name: 'G');
      final group = ShapeGroup(name: 'Tête');
      project.groups.add(group);
      final a = VectorShape(
        name: 'A',
        startMs: 0,
        endMs: 1000,
        groupId: group.id,
      );
      final b = VectorShape(
        name: 'B',
        startMs: 0,
        endMs: 1000,
        groupId: group.id,
      );
      project.shapes.addAll(<VectorShape>[a, b]);
      final lanes = TimelineLayout.packRows(project);
      final rows = lanes.expand((l) => l).toList();
      expect(rows.where((r) => r.isGroup), hasLength(1));
      expect(rows.where((r) => r.shape == a || r.shape == b), hasLength(2));
    });

    test('une forme libre ne rejoint pas une ligne de groupe', () {
      final project = AnimationProject.blank(name: 'G');
      final group = ShapeGroup(name: 'Tête');
      project.groups.add(group);
      final fils = VectorShape(
        name: 'F',
        startMs: 0,
        endMs: 1000,
        groupId: group.id,
      );
      final libre = VectorShape(name: 'L', startMs: 0, endMs: 1000);
      project.shapes.addAll(<VectorShape>[fils, libre]);
      final rows = TimelineLayout.packRows(project).expand((l) => l).toList();
      expect(rows.where((r) => r.shape == libre), hasLength(1));
    });
  });

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
}
