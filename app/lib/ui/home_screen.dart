import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/project_repository.dart';
import '../data/project_store.dart';
import '../engine/json_project_import.dart';
import '../settings/language_settings.dart';
import 'studio_screen.dart';

/// Écran principal : liste des projets d'animation.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repository, this.onOpenSettings});

  final ProjectRepository repository;
  final ValueChanged<BuildContext>? onOpenSettings;

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

  Future<void> _importJsonFile() async {
    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(
        dialogTitle: AppStrings.text('Importer une animation'),
        type: FileType.custom,
        allowedExtensions: <String>['json'],
      );
    } catch (error) {
      _snack(
        '${AppStrings.text('Sélecteur de fichiers indisponible')} : $error',
      );
      return;
    }
    if (picked.isEmpty || !mounted) return;

    String text;
    try {
      text = utf8.decode(await picked.first.readAsBytes());
    } catch (error) {
      _snack('${AppStrings.text('Fichier illisible')} : $error');
      return;
    }

    final result = JsonProjectImport.parse(text);
    final imported = result.project;
    if (imported == null) {
      await _showImportProblems(result.error ?? 'JSON invalide');
      return;
    }
    await widget.repository.save(imported);
    await _store.refresh();
    if (!mounted) return;
    await _open(imported.id);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showImportProblems(String problems) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.text('Import impossible')),
        content: SingleChildScrollView(
          child: Text(
            problems,
            style: const TextStyle(fontSize: 12, color: Color(0xFFFF8A8A)),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(AppStrings.text('Fermer')),
          ),
        ],
      ),
    );
  }

  Future<void> _newProject() async {
    final project = await _store.createProject();
    if (!mounted) return;
    await _open(project.id);
  }

  Future<void> _rename(ProjectSummary summary) async {
    final controller = TextEditingController(text: summary.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.text('Renommer le projet')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: AppStrings.text('Nom')),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppStrings.text('Annuler')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(AppStrings.text('Valider')),
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
        title: Text(AppStrings.text('Supprimer le projet ?')),
        content: Text(
          '« ${summary.name} » ${AppStrings.text('sera définitivement supprimé.')}',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppStrings.text('Annuler')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(AppStrings.text('Supprimer')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _store.delete(summary.id);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppStrings.language,
      builder: (context, _, _) => _buildLocalized(context),
    );
  }

  Widget _buildLocalized(BuildContext context) {
    final t = AppStrings.text;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/brand/keyform-studio-icon.png',
                width: 32,
                height: 32,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            Text(t('Keyform Studio')),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: t('Importer un fichier JSON'),
            onPressed: _importJsonFile,
            icon: const Icon(Icons.file_open_outlined),
          ),
          IconButton(
            tooltip: t('Actualiser'),
            onPressed: _store.refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: t('Paramètres'),
            onPressed: widget.onOpenSettings == null
                ? null
                : () => widget.onOpenSettings!(context),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newProject,
        icon: const Icon(Icons.add),
        label: Text(t('Nouveau projet')),
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
              title: t('Impossible de charger les projets'),
              message: _store.error!,
              actionLabel: t('Réessayer'),
              onAction: _store.refresh,
            );
          }
          if (_store.isEmpty) {
            return _Message(
              icon: Icons.movie_creation_outlined,
              title: t('Aucun projet pour l’instant'),
              message: t(
                'Crée ton premier projet d’animation vectorielle : formes, couches, keyframes, export MP4 et GIF.',
              ),
              actionLabel: t('Nouveau projet'),
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
    return '${summary.width.round()} × ${summary.height.round()} · '
        '$seconds s · ${summary.fps} fps · ${summary.shapeCount} élément(s)$date';
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
                  Icons.movie_outlined,
                  color: Theme.of(context).colorScheme.primary,
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
                itemBuilder: (context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'rename',
                    child: Text(AppStrings.text('Renommer')),
                  ),
                  PopupMenuItem<String>(
                    value: 'duplicate',
                    child: Text(AppStrings.text('Dupliquer')),
                  ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Text(AppStrings.text('Supprimer')),
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
