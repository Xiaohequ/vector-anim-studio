import 'dart:math' as math;

/// Échelle de temps de la timeline.
///
/// [viewMs] est le temps affiché sur toute la largeur de la timeline
/// (de 500 ms à 30 minutes) et [offsetMs] le temps affiché au bord gauche.
/// La durée du projet est lue via [durationOf] à chaque usage : elle est
/// dérivée de la timeline (fin du dernier segment) et peut évoluer pendant
/// l'édition. L'état de zoom vit en mémoire de session : rien n'est persisté.
class TimelineZoomState {
  TimelineZoomState({required this.durationOf})
      : viewMs = _clampView(durationOf()),
        offsetMs = 0;

  /// Pleine largeur au zoom maximal : 500 ms (15 images à 30 fps).
  static const int minViewMs = 500;

  /// Pleine largeur au zoom minimal : 30 minutes.
  static const int maxViewMs = 30 * 60 * 1000;

  /// Durée du projet, réévaluée à chaque usage.
  final int Function() durationOf;

  /// Temps affiché sur toute la largeur.
  int viewMs;

  /// Temps affiché au bord gauche.
  int offsetMs;

  static int _clampView(int value) =>
      value.clamp(minViewMs, math.max(minViewMs, maxViewMs));

  /// Décalage maximal : si la vue dépasse la durée du projet, celui-ci est
  /// collé au bord gauche (offset nul).
  int get maxOffset => math.max(0, durationOf() - viewMs);

  void _clampOffset() => offsetMs = offsetMs.clamp(0, maxOffset);

  /// Zoom ancré sur un pincement : [scale] est le rapport d'écartement des
  /// doigts (> 1 → zoom avant, la vue rétrécit) et [anchorFraction] (0..1)
  /// la position du point focal, qui reste immobile sous les doigts.
  void zoomAt(double scale, double anchorFraction) {
    if (!scale.isFinite || scale <= 0 || (scale - 1).abs() < 0.0001) {
      _clampOffset();
      return;
    }
    final anchor = anchorFraction.clamp(0.0, 1.0);
    final anchorTime = offsetMs + anchor * viewMs;
    viewMs = _clampView((viewMs / scale).round());
    offsetMs = (anchorTime - anchor * viewMs).round();
    _clampOffset();
  }

  /// Pas de zoom des boutons : ×1,5 par appui, ancré au centre.
  void zoomIn() => zoomAt(1.5, 0.5);

  void zoomOut() => zoomAt(1 / 1.5, 0.5);

  /// Défilement : [dxPixels] est le déplacement horizontal du point focal
  /// (positif → le contenu suit le doigt, l'offset recule). Borné au projet.
  void panByPixels(double dxPixels, double width) {
    if (width <= 0) return;
    offsetMs -= (dxPixels * viewMs / width).round();
    _clampOffset();
  }

  /// Réinitialise : toute la durée du projet sur la largeur.
  void fit() {
    viewMs = _clampView(durationOf());
    _clampOffset();
  }

  /// Garde la tête de lecture visible pendant la lecture. Renvoie true si
  /// l'offset a changé (défilement doux au-delà de 95 % de la vue).
  bool follow(int timeMs) {
    if (viewMs >= durationOf()) return false;
    final int? next;
    if (timeMs < offsetMs) {
      next = timeMs; // boucle ramenée au début ou saut en arrière
    } else if (timeMs > offsetMs + viewMs * 0.95) {
      next = (timeMs - viewMs * 0.95).round();
    } else {
      return false;
    }
    final clamped = next.clamp(0, maxOffset);
    if (clamped == offsetMs) return false;
    offsetMs = clamped;
    return true;
  }

  /// Temps à la position [dx] (pixels depuis le bord gauche), borné à la
  /// fenêtre visible et à la durée du projet.
  int timeFor(double dx, double width) {
    if (width <= 0) return offsetMs;
    final t = (offsetMs + dx * viewMs / width).round();
    final limit = math.min(offsetMs + viewMs, durationOf());
    return t.clamp(offsetMs, math.max(offsetMs, limit));
  }

  /// Position en pixels d'un temps (peut sortir de la vue : le Stack clippe).
  double xFor(int timeMs, double width) =>
      (timeMs - offsetMs) * width / math.max(1, viewMs);

  /// Millisecondes par pixel à la largeur [width].
  double msPerPixel(double width) => viewMs / math.max(1, width);
}
