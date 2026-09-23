import 'package:flutter/foundation.dart';

import '../models/animation.dart';

/// État de lecture de la timeline : temps courant, boucle, play/pause.
class TimelineController extends ChangeNotifier {
  TimelineController(this.project);

  final AnimationProject project;

  int _timeMs = 0;
  bool _playing = false;
  bool _loop = true;

  int get timeMs => _timeMs;
  bool get playing => _playing;
  bool get loop => _loop;
  double get progress =>
      project.durationMs == 0 ? 0 : _timeMs / project.durationMs;

  void setTime(int value) {
    final clamped = value.clamp(0, project.durationMs).toInt();
    if (clamped == _timeMs) return;
    _timeMs = clamped;
    notifyListeners();
  }

  void setProgress(double value) =>
      setTime((value.clamp(0.0, 1.0) * project.durationMs).round());

  void togglePlay() {
    _playing = !_playing;
    notifyListeners();
  }

  void pause() {
    if (!_playing) return;
    _playing = false;
    notifyListeners();
  }

  void rewind() {
    _timeMs = 0;
    notifyListeners();
  }

  void setLoop(bool value) {
    _loop = value;
    notifyListeners();
  }

  /// Avance le temps de la durée écoulée (appelé par le ticker).
  void advance(Duration elapsed) {
    if (!_playing) return;
    final next = _timeMs + (elapsed.inMicroseconds / 1000).round();
    if (next >= project.durationMs) {
      if (_loop) {
        _timeMs = project.durationMs == 0 ? 0 : next % project.durationMs;
      } else {
        _timeMs = project.durationMs;
        _playing = false;
      }
    } else {
      _timeMs = next;
    }
    notifyListeners();
  }

  /// Tolérance de proximité des keyframes pour le projet courant (≈ 8 px).
  int get snapToleranceMs => keyframeSnapToleranceMs(project.durationMs);

  /// Keyframe la plus proche du curseur, dans la tolérance.
  ShapeKeyframe? nearestKeyframe(VectorShape shape) =>
      shape.keyframeNear(_timeMs, snapToleranceMs);

  /// Ajoute une pose au curseur, ou la retire si le curseur est dessus.
  void toggleKeyframe(VectorShape shape) {
    final near = nearestKeyframe(shape);
    if (near != null) {
      shape.removeKeyframeAt(near.timeMs);
    } else {
      shape.addKeyframeAt(_timeMs);
    }
    notifyListeners();
  }

  bool hasKeyframeAtPlayhead(VectorShape shape) =>
      nearestKeyframe(shape) != null;
}
