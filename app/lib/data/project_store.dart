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

  List<ProjectSummary> get projects => List<ProjectSummary>.unmodifiable(_projects);
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
    required String name,
    required ProjectFormat format,
  }) async {
    final project = AnimationProject.blank(
      name: name.trim().isEmpty ? 'Nouvelle animation' : name.trim(),
      format: format,
    );
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