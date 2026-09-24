import '../models/animation.dart';

/// Pile d'annulation : copies profondes du projet prises avant chaque action
/// mutante, limitée aux [limit] dernières actions (FIFO). En mémoire de
/// session seulement : rien n'est persisté.
class UndoStack {
  UndoStack({this.limit = 20});

  final int limit;
  final List<AnimationProject> _items = <AnimationProject>[];

  bool get canUndo => _items.isNotEmpty;
  int get length => _items.length;

  /// Copie profonde (sérialisation JSON) de l'état avant une action.
  void push(AnimationProject project) {
    _items.add(AnimationProject.fromJson(project.toJson()));
    while (_items.length > limit) {
      _items.removeAt(0);
    }
  }

  AnimationProject? pop() => canUndo ? _items.removeLast() : null;
}
