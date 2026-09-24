import 'package:flutter_test/flutter_test.dart';
import 'package:vector_anim_studio/engine/timeline_zoom.dart';

void main() {
  group('TimelineZoomState', () {
    test('bornes de la vue : 500 ms à 30 minutes', () {
      final zoom = TimelineZoomState(durationOf: () => 4000);
      expect(zoom.viewMs, 4000);
      zoom.zoomAt(0.0001, 0.5); // zoom arrière extrême
      expect(zoom.viewMs, TimelineZoomState.maxViewMs);
      zoom.zoomAt(1e12, 0.5); // zoom avant extrême
      expect(zoom.viewMs, TimelineZoomState.minViewMs);
    });

    test('zoom ancré : le temps sous le point focal reste immobile', () {
      final zoom = TimelineZoomState(durationOf: () => 4000);
      const width = 360.0;
      // Temps sous le point focal à 25 % de la largeur : 1000 ms.
      expect(zoom.timeFor(0.25 * width, width), 1000);
      zoom.zoomAt(2, 0.25); // zoom avant ×2
      expect(zoom.timeFor(0.25 * width, width), 1000);
    });

    test('défilement borné à la durée du projet', () {
      final zoom = TimelineZoomState(durationOf: () => 4000);
      zoom.zoomAt(2, 0.5); // vue = 2000 ms
      zoom.panByPixels(9999, 360); // contenu suit le doigt → offset recule
      expect(zoom.offsetMs, 0);
      zoom.panByPixels(-9999, 360); // offset au maximum
      expect(zoom.offsetMs, zoom.maxOffset);
      expect(zoom.maxOffset, 2000);
    });

    test('vue plus large que le projet : projet collé à gauche', () {
      final zoom = TimelineZoomState(durationOf: () => 4000);
      zoom.zoomAt(0.001, 0.5); // vue = 30 min > projet
      expect(zoom.maxOffset, 0);
      expect(zoom.offsetMs, 0);
      expect(zoom.xFor(0, 360), 0);
    });

    test('fit ramène la vue à la durée du projet', () {
      final zoom = TimelineZoomState(durationOf: () => 4000);
      zoom.zoomAt(4, 0.2);
      expect(zoom.viewMs, 1000);
      zoom.fit();
      expect(zoom.viewMs, 4000);
      expect(zoom.offsetMs, 0);
    });

    test('follow garde la tête de lecture visible pendant la lecture', () {
      final zoom = TimelineZoomState(durationOf: () => 4000);
      zoom.zoomAt(4, 0.0); // vue = 1000 ms, offset 0
      expect(zoom.follow(940), isFalse); // sous 95 % → inchangé
      expect(zoom.follow(1000), isTrue); // la tête dépasse → défile
      expect(zoom.offsetMs, greaterThan(0));
      // Boucle ramenée au début : l'offset saute en arrière.
      expect(zoom.follow(0), isTrue);
      expect(zoom.offsetMs, 0);
      // Vue pleine largeur : pas de suivi.
      final full = TimelineZoomState(durationOf: () => 4000);
      expect(full.follow(4000), isFalse);
    });

    test('timeFor est borné à la fenêtre visible et au projet', () {
      final zoom = TimelineZoomState(durationOf: () => 4000);
      zoom.zoomAt(2, 0.5); // vue = 2000 ms, ancrée au centre → offset = 1000
      expect(zoom.offsetMs, 1000);
      expect(zoom.timeFor(-50, 360), 1000); // borne gauche = offset
      expect(zoom.timeFor(360 + 50, 360), 3000); // borne droite = offset + vue
      expect(zoom.timeFor(180, 360), 2000);
    });

    test('zoomIn/zoomOut avancent d\'un pas de ×1,5', () {
      final zoom = TimelineZoomState(durationOf: () => 40000);
      zoom.zoomIn();
      expect(zoom.viewMs, (40000 / 1.5).round());
      zoom.zoomOut();
      expect(zoom.viewMs, closeTo(40000, 2)); // arrondi intermédiaire ±1 ms
    });

    test('followEdge défile quand un bord manipulé dépasse la vue', () {
      final zoom = TimelineZoomState(durationOf: () => 4000);
      zoom.zoomAt(4, 0.0); // vue = 1000 ms, offset 0
      expect(zoom.followEdge(900), isFalse); // sous 95 % → inchangé
      expect(zoom.followEdge(1200), isTrue); // dépasse → l'offset suit
      // Le bord manipulé reste épinglé à 95 % de la largeur.
      expect(zoom.offsetMs, (1200 - 1000 * 0.95).round());
      expect(zoom.xFor(1200, 360), 0.95 * 360);
    });

    test('followEdge est borné à la durée du projet', () {
      final zoom = TimelineZoomState(durationOf: () => 4000);
      zoom.zoomAt(4, 0.0); // vue = 1000 ms ; maxOffset = 3000
      zoom.followEdge(20000); // au-delà du maximum possible
      expect(zoom.offsetMs, zoom.maxOffset);
    });

    test('la borne de vue s\'adapte aux projets plus longs que 30 minutes', () {
      const long = 45 * 60 * 1000;
      final zoom = TimelineZoomState(durationOf: () => long);
      zoom.fit();
      expect(zoom.viewMs, long); // au-delà de maxViewMs
      zoom.zoomAt(0.0001, 0.5); // zoom arrière extrême
      expect(zoom.viewMs, long); // pas de vue au-delà de la durée
    });
  });
}
