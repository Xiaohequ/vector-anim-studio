import 'package:flutter/material.dart';

import '../data/project_repository.dart';
import '../data/project_store.dart';
import '../models/animation.dart';
import 'studio_screen.dart';

/// Écran principal : liste des projets d'animation.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repository});

  final ProjectRepository repository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ProjectStore _store = ProjectStore(widget.repository);

  @override
  void initState() {
    super.initState();
    _store.refresh();
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  Future<void> _open(String projectId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            StudioScreen(projectId: projectId, repository: widget.repository),
      ),
    );
    await _store.refresh();
  }

  Future<void> _newProject() async {
    final result = await showDialog<_NewProjectResult>(
      context: context,
      builder: (_) => const _NewProjectDialog(),
    );
    if (result == null) return;
    if (result.sample) {
      final project = await _store.createSample();
      if (!mounted) return;
      await _open(project.id);
      return;
    }
    final project = await _store.createProject(
      name: result.name,
      format: result.format,
      type: result.type,
    );
    if (!mounted) return;
    await _open(project.id);
  }

  Future<void> _rename(ProjectSummary summary) async {
    final controller = TextEditingController(text: summary.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renommer le projet'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nom'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await _store.rename(summary.id, name.trim());
  }

  Future<void> _delete(ProjectSummary summary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le projet ?'),
        content: Text('« ${summary.name} » sera définitivement supprimé.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _store.delete(summary.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Keyform Studio'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _store.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newProject,
        icon: const Icon(Icons.add),
        label: const Text('Nouveau projet'),
      ),
      body: AnimatedBuilder(
        animation: _store,
        builder: (context, _) {
          if (_store.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_store.error != null) {
            return _Message(
              icon: Icons.error_outline,
              title: 'Impossible de charger les projets',
              message: _store.error!,
              actionLabel: 'Réessayer',
              onAction: _store.refresh,
            );
          }
          if (_store.isEmpty) {
            return _Message(
              icon: Icons.movie_creation_outlined,
              title: 'Aucun projet pour l’instant',
              message:
                  'Crée ton premier projet d’animation vectorielle : formes, '
                  'couches, keyframes, export MP4 et GIF.',
              actionLabel: 'Nouveau projet',
              onAction: _newProject,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: _store.projects.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final summary = _store.projects[index];
              return _ProjectTile(
                summary: summary,
                onTap: () => _open(summary.id),
                onRename: () => _rename(summary),
                onDuplicate: () async {
                  final project = await _store.duplicate(summary.id);
                  if (!mounted) return;
                  await _open(project.id);
                },
                onDelete: () => _delete(summary),
              );
            },
          );
        },
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({
    required this.summary,
    required this.onTap,
    required this.onRename,
    required this.onDuplicate,
    required this.onDelete,
  });

  final ProjectSummary summary;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  String get _subtitle {
    final seconds = (summary.durationMs / 1000).toStringAsFixed(1);
    final updated = summary.updatedAt;
    final date = updated == null
        ? ''
        : ' · ${updated.day.toString().padLeft(2, '0')}/'
              '${updated.month.toString().padLeft(2, '0')}/${updated.year}';
    final kind = summary.type == ProjectType.skeleton ? 'Squelette · ' : '';
    final unit = summary.type == ProjectType.skeleton ? 'pièce(s)' : 'forme(s)';
    return '$kind${summary.width.round()} × ${summary.height.round()} · '
        '$seconds s · ${summary.fps} fps · ${summary.shapeCount} $unit$date';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A3244),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  summary.type == ProjectType.skeleton
                      ? Icons.accessibility_new
                      : Icons.animation,
                  color: summary.type == ProjectType.skeleton
                      ? const Color(0xFF3ECF8E)
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      summary.name,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) => switch (value) {
                  'rename' => onRename(),
                  'duplicate' => onDuplicate(),
                  'delete' => onDelete(),
                  _ => null,
                },
                itemBuilder: (context) => const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'rename',
                    child: Text('Renommer'),
                  ),
                  PopupMenuItem<String>(
                    value: 'duplicate',
                    child: Text('Dupliquer'),
                  ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Text('Supprimer'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 48, color: Colors.white38),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _NewProjectResult {
  const _NewProjectResult({
    required this.name,
    required this.format,
    this.type = ProjectType.vector,
    this.sample = false,
  });

  final String name;
  final ProjectFormat format;
  final ProjectType type;
  final bool sample;
}

class _NewProjectDialog extends StatefulWidget {
  const _NewProjectDialog();

  @override
  State<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<_NewProjectDialog> {
  final TextEditingController _name = TextEditingController();
  ProjectFormat _format = ProjectFormat.portrait;
  ProjectType _type = ProjectType.vector;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouveau projet'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nom du projet',
                hintText: 'Mon animation',
              ),
            ),
            const SizedBox(height: 16),
            const Text('Type d’animation', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            SegmentedButton<ProjectType>(
              showSelectedIcon: false,
              segments: const <ButtonSegment<ProjectType>>[
                ButtonSegment<ProjectType>(
                  value: ProjectType.vector,
                  icon: Icon(Icons.animation, size: 16),
                  label: Text('Vectorielle', style: TextStyle(fontSize: 12)),
                ),
                ButtonSegment<ProjectType>(
                  value: ProjectType.skeleton,
                  icon: Icon(Icons.accessibility_new, size: 16),
                  label: Text('Squelette', style: TextStyle(fontSize: 12)),
                ),
              ],
              selected: <ProjectType>{_type},
              onSelectionChanged: (selection) =>
                  setState(() => _type = selection.first),
            ),
            const SizedBox(height: 4),
            Text(
              _type == ProjectType.skeleton
                  ? 'Un rig d’os anime les pièces du personnage (rig maître).'
                  : 'Formes animées par keyframes de pose.',
              style: const TextStyle(fontSize: 11, color: Colors.white38),
            ),
            const SizedBox(height: 16),
            const Text('Format', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            SegmentedButton<ProjectFormat>(
              showSelectedIcon: false,
              segments: <ButtonSegment<ProjectFormat>>[
                for (final format in ProjectFormat.values)
                  ButtonSegment<ProjectFormat>(
                    value: format,
                    label: Text(switch (format) {
                      ProjectFormat.portrait => 'Portrait',
                      ProjectFormat.landscape => 'Paysage',
                      ProjectFormat.square => 'Carré',
                    }, style: const TextStyle(fontSize: 12)),
                  ),
              ],
              selected: <ProjectFormat>{_format},
              onSelectionChanged: (selection) =>
                  setState(() => _format = selection.first),
            ),
            const SizedBox(height: 4),
            Text(
              'Durée du projet = celle des éléments posés sur la timeline ; '
              'les fps se règlent à l’export.',
              style: const TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            _NewProjectResult(name: _name.text, format: _format, sample: true),
          ),
          child: const Text('Créer avec la démo'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _NewProjectResult(name: _name.text, format: _format, type: _type),
          ),
          child: const Text('Créer'),
        ),
      ],
    );
  }
}
