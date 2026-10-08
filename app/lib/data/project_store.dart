import 'package:flutter/foundation.dart';

import '../models/animation.dart';
import 'project_repository.dart';

/// État de l'écran d'accueil : liste des projets persistés.
class ProjectStore extends ChangeNotifier {
  ProjectStore(this.repository);

  final ProjectRepository repository;

  List<ProjectSummary> _projects = <ProjectSummary>[];
  bool _loading = true;
  String? _error;

  List<ProjectSummary> get projects =>
      List<ProjectSummary>.unmodifiable(_projects);
  bool get loading => _loading;
  String? get error => _error;
  bool get isEmpty => !_loading && _projects.isEmpty;

  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _projects = await repository.listSummaries();
    } catch (error) {
      _error = '$error';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<AnimationProject> createProject({
    String? name,
    ProjectFormat format = ProjectFormat.portrait,
    DateTime? now,
  }) async {
    final createdAt = now ?? DateTime.now();
    final trimmedName = name?.trim();
    final project =
        AnimationProject.blank(
            name: trimmedName == null || trimmedName.isEmpty
                ? _generatedProjectName(createdAt)
                : trimmedName,
            format: format,
          )
          ..createdAt = createdAt
          ..updatedAt = createdAt;
    await repository.save(project);
    await refresh();
    return project;
  }

  Future<AnimationProject> createSample() async {
    final project = AnimationProject.demo();
    project.createdAt = DateTime.now();
    project.updatedAt = DateTime.now();
    await repository.save(project);
    await refresh();
    return project;
  }

  Future<void> delete(String id) async {
    await repository.delete(id);
    await refresh();
  }

  Future<void> rename(String id, String name) async {
    await repository.rename(id, name);
    await refresh();
  }

  Future<AnimationProject> duplicate(String id) async {
    final project = await repository.duplicate(id);
    await refresh();
    return project;
  }
}

String _generatedProjectName(DateTime dateTime) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return 'Animation ${dateTime.year}-'
      '${twoDigits(dateTime.month)}-'
      '${twoDigits(dateTime.day)} '
      '${twoDigits(dateTime.hour)}:'
      '${twoDigits(dateTime.minute)}:'
      '${twoDigits(dateTime.second)}.'
      '${dateTime.millisecond.toString().padLeft(3, '0')}'
      '${dateTime.microsecond.toString().padLeft(3, '0')}';
}
