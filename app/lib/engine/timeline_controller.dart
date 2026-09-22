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

  /// Ajoute/retire une keyframe pour la forme et la propriété données.
  void toggleKeyframe(VectorShape shape, AnimatableProperty property) {
    final track = shape.tracks[property];
    if (track != null && track.keys.any((k) => k.timeMs == _timeMs)) {
      track.removeKeyAt(_timeMs);
      if (track.isEmpty) shape.tracks.remove(property);
    } else {
      shape.addKeyframeAt(property, _timeMs);
    }
    notifyListeners();
  }

  bool hasKeyframeAtPlayhead(VectorShape shape, AnimatableProperty property) {
    final track = shape.tracks[property];
    if (track == null) return false;
    return track.keys.any((k) => k.timeMs == _timeMs);
  }
}