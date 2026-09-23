import 'dart:convert';
import 'dart:ui' show Offset;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/animation.dart';

/// Résumé de projet affiché sur l'écran d'accueil.
class ProjectSummary {
  const ProjectSummary({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    required this.durationMs,
    required this.fps,
    required this.shapeCount,
    this.updatedAt,
  });

  final String id;
  final String name;
  final double width;
  final double height;
  final int durationMs;
  final int fps;
  final int shapeCount;
  final DateTime? updatedAt;
}

/// Persistance SQLite (sqflite) des projets d'animation.
///
/// Un projet contient des formes, chaque forme contient des couches et des
/// pistes d'animation (keyframes).
class ProjectRepository {
  ProjectRepository({DatabaseFactory? factory, this.databasePath})
      : _factory = factory ?? databaseFactory;

  static const String fileName = 'vector_anim_studio.db';
  static const int schemaVersion = 1;

  final DatabaseFactory _factory;
  final String? databasePath;

  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final path = databasePath ??
        p.join(await _factory.getDatabasesPath(), fileName);
    return _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE projects (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              width REAL NOT NULL,
              height REAL NOT NULL,
              duration_ms INTEGER NOT NULL,
              fps INTEGER NOT NULL,
              background_value INTEGER NOT NULL,
              cover_path TEXT,
              created_at INTEGER,
              updated_at INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE shapes (
              id TEXT PRIMARY KEY,
              project_id TEXT NOT NULL,
              name TEXT NOT NULL,
              x REAL NOT NULL,
              y REAL NOT NULL,
              rotation REAL NOT NULL,
              scale REAL NOT NULL,
              opacity REAL NOT NULL,
              stroke_width REAL NOT NULL,
              start_ms INTEGER NOT NULL,
              end_ms INTEGER NOT NULL,
              visible INTEGER NOT NULL,
              z INTEGER NOT NULL,
              FOREIGN KEY (project_id) REFERENCES projects (id) ON DELETE CASCADE
            )
          ''');
          await db.execute('''
            CREATE TABLE layers (
              id TEXT PRIMARY KEY,
              shape_id TEXT NOT NULL,
              name TEXT NOT NULL,
              kind TEXT NOT NULL,
              x REAL NOT NULL,
              y REAL NOT NULL,
              width REAL NOT NULL,
              height REAL NOT NULL,
              rotation REAL NOT NULL,
              scale REAL NOT NULL,
              opacity REAL NOT NULL,
              stroke_width REAL NOT NULL,
              color_value INTEGER NOT NULL,
              filled INTEGER NOT NULL,
              points TEXT NOT NULL,
              visible INTEGER NOT NULL,
              z INTEGER NOT NULL,
              FOREIGN KEY (shape_id) REFERENCES shapes (id) ON DELETE CASCADE
            )
          ''');
          await db.execute('''
            CREATE TABLE tracks (
              id TEXT PRIMARY KEY,
              shape_id TEXT NOT NULL,
              property TEXT NOT NULL,
              FOREIGN KEY (shape_id) REFERENCES shapes (id) ON DELETE CASCADE
            )
          ''');
          await db.execute('''
            CREATE TABLE keyframes (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              track_id TEXT NOT NULL,
              time_ms INTEGER NOT NULL,
              value REAL NOT NULL,
              easing TEXT NOT NULL,
              FOREIGN KEY (track_id) REFERENCES tracks (id) ON DELETE CASCADE
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_shapes_project ON shapes (project_id)',
          );
          await db.execute('CREATE INDEX idx_layers_shape ON layers (shape_id)');
          await db.execute('CREATE INDEX idx_tracks_shape ON tracks (shape_id)');
          await db.execute(
            'CREATE INDEX idx_keyframes_track ON keyframes (track_id)',
          );
        },
      ),
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<List<ProjectSummary>> listSummaries() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT p.id, p.name, p.width, p.height, p.duration_ms, p.fps, p.updated_at,
             (SELECT COUNT(*) FROM shapes s WHERE s.project_id = p.id) AS shape_count
      FROM projects p
      ORDER BY COALESCE(p.updated_at, 0) DESC
    ''');
    return rows
        .map(
          (row) => ProjectSummary(
            id: row['id'] as String,
            name: row['name'] as String,
            width: (row['width'] as num).toDouble(),
            height: (row['height'] as num).toDouble(),
            durationMs: (row['duration_ms'] as num).toInt(),
            fps: (row['fps'] as num).toInt(),
            shapeCount: (row['shape_count'] as num).toInt(),
            updatedAt: row['updated_at'] == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                    (row['updated_at'] as num).toInt(),
                  ),
          ),
        )
        .toList();
  }

  Future<int> countProjects() async {
    final db = await database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM projects');
    return (rows.first['n'] as num).toInt();
  }

  Future<AnimationProject> load(String id) async {
    final db = await database;
    final projectRows = await db.query(
      'projects',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (projectRows.isEmpty) {
      throw StateError('Projet introuvable : $id');
    }
    final projectRow = projectRows.first;
    final project = AnimationProject(
      id: projectRow['id'] as String,
      name: projectRow['name'] as String,
      width: (projectRow['width'] as num).toDouble(),
      height: (projectRow['height'] as num).toDouble(),
      durationMs: (projectRow['duration_ms'] as num).toInt(),
      fps: (projectRow['fps'] as num).toInt(),
      backgroundValue: (projectRow['background_value'] as num).toInt(),
      coverPath: projectRow['cover_path'] as String?,
      createdAt: _date(projectRow['created_at']),
      updatedAt: _date(projectRow['updated_at']),
    );

    final shapeRows = await db.query(
      'shapes',
      where: 'project_id = ?',
      whereArgs: <Object?>[id],
      orderBy: 'z ASC',
    );
    for (final shapeRow in shapeRows) {
      final shapeId = shapeRow['id'] as String;
      final shape = VectorShape(
        id: shapeId,
        name: shapeRow['name'] as String,
        x: (shapeRow['x'] as num).toDouble(),
        y: (shapeRow['y'] as num).toDouble(),
        rotation: (shapeRow['rotation'] as num).toDouble(),
        scale: (shapeRow['scale'] as num).toDouble(),
        opacity: (shapeRow['opacity'] as num).toDouble(),
        strokeWidth: (shapeRow['stroke_width'] as num).toDouble(),
        startMs: (shapeRow['start_ms'] as num).toInt(),
        endMs: (shapeRow['end_ms'] as num).toInt(),
        visible: (shapeRow['visible'] as num).toInt() == 1,
      );

      final layerRows = await db.query(
        'layers',
        where: 'shape_id = ?',
        whereArgs: <Object?>[shapeId],
        orderBy: 'z ASC',
      );
      for (final layerRow in layerRows) {
        shape.layers.add(
          ShapeLayer(
            id: layerRow['id'] as String,
            name: layerRow['name'] as String,
            kind: ShapeKind.values.firstWhere(
              (k) => k.name == layerRow['kind'],
              orElse: () => ShapeKind.rect,
            ),
            x: (layerRow['x'] as num).toDouble(),
            y: (layerRow['y'] as num).toDouble(),
            width: (layerRow['width'] as num).toDouble(),
            height: (layerRow['height'] as num).toDouble(),
            rotation: (layerRow['rotation'] as num).toDouble(),
            scale: (layerRow['scale'] as num).toDouble(),
            opacity: (layerRow['opacity'] as num).toDouble(),
            strokeWidth: (layerRow['stroke_width'] as num).toDouble(),
            colorValue: (layerRow['color_value'] as num).toInt(),
            filled: (layerRow['filled'] as num).toInt() == 1,
            points: _decodePoints(layerRow['points'] as String),
            visible: (layerRow['visible'] as num).toInt() == 1,
          ),
        );
      }

      final trackRows = await db.query(
        'tracks',
        where: 'shape_id = ?',
        whereArgs: <Object?>[shapeId],
      );
      for (final trackRow in trackRows) {
        final trackId = trackRow['id'] as String;
        final property = AnimatableProperty.values.firstWhere(
          (prop) => prop.name == trackRow['property'],
          orElse: () => AnimatableProperty.x,
        );
        final track = AnimTrack(property);
        final keyRows = await db.query(
          'keyframes',
          where: 'track_id = ?',
          whereArgs: <Object?>[trackId],
          orderBy: 'time_ms ASC',
        );
        for (final keyRow in keyRows) {
          track.keys.add(
            Keyframe(
              (keyRow['time_ms'] as num).toInt(),
              (keyRow['value'] as num).toDouble(),
              easing: EasingKind.values.firstWhere(
                (e) => e.name == keyRow['easing'],
                orElse: () => EasingKind.easeInOut,
              ),
            ),
          );
        }
        shape.tracks[property] = track;
      }

      project.shapes.add(shape);
    }
    return project;
  }

  /// Enregistre le projet (insert ou remplacement complet de ses enfants).
  Future<void> save(AnimationProject project, {bool touch = true}) async {
    final db = await database;
    project.updatedAt = DateTime.now();
    await db.transaction((txn) async {
      final existing = await txn.query(
        'projects',
        columns: <String>['id'],
        where: 'id = ?',
        whereArgs: <Object?>[project.id],
        limit: 1,
      );
      final values = <String, Object?>{
        'id': project.id,
        'name': project.name,
        'width': project.width,
        'height': project.height,
        'duration_ms': project.durationMs,
        'fps': project.fps,
        'background_value': project.backgroundValue,
        'cover_path': project.coverPath,
        'created_at': (project.createdAt ?? DateTime.now())
            .millisecondsSinceEpoch,
        'updated_at': touch
            ? DateTime.now().millisecondsSinceEpoch
            : project.updatedAt?.millisecondsSinceEpoch,
      };
      if (existing.isEmpty) {
        await txn.insert('projects', values);
      } else {
        await txn.update(
          'projects',
          values,
          where: 'id = ?',
          whereArgs: <Object?>[project.id],
        );
      }

      final shapeIds = <String>[
        for (final row in await txn.query(
          'shapes',
          columns: <String>['id'],
          where: 'project_id = ?',
          whereArgs: <Object?>[project.id],
        ))
          row['id'] as String,
      ];
      for (final shapeId in shapeIds) {
        await _deleteTrackTrees(txn, shapeId);
      }
      await txn.delete(
        'shapes',
        where: 'project_id = ?',
        whereArgs: <Object?>[project.id],
      );

      for (var i = 0; i < project.shapes.length; i++) {
        final shape = project.shapes[i];
        await txn.insert('shapes', <String, Object?>{
          'id': shape.id,
          'project_id': project.id,
          'name': shape.name,
          'x': shape.x,
          'y': shape.y,
          'rotation': shape.rotation,
          'scale': shape.scale,
          'opacity': shape.opacity,
          'stroke_width': shape.strokeWidth,
          'start_ms': shape.startMs,
          'end_ms': shape.endMs,
          'visible': shape.visible ? 1 : 0,
          'z': i,
        });
        for (var j = 0; j < shape.layers.length; j++) {
          final layer = shape.layers[j];
          await txn.insert('layers', <String, Object?>{
            'id': layer.id,
            'shape_id': shape.id,
            'name': layer.name,
            'kind': layer.kind.name,
            'x': layer.x,
            'y': layer.y,
            'width': layer.width,
            'height': layer.height,
            'rotation': layer.rotation,
            'scale': layer.scale,
            'opacity': layer.opacity,
            'stroke_width': layer.strokeWidth,
            'color_value': layer.colorValue,
            'filled': layer.filled ? 1 : 0,
            'points': _encodePoints(layer.points),
            'visible': layer.visible ? 1 : 0,
            'z': j,
          });
        }
        for (final track in shape.tracks.values) {
          if (track.isEmpty) continue;
          final trackId = generateId('track');
          await txn.insert('tracks', <String, Object?>{
            'id': trackId,
            'shape_id': shape.id,
            'property': track.property.name,
          });
          for (final key in track.keys) {
            await txn.insert('keyframes', <String, Object?>{
              'track_id': trackId,
              'time_ms': key.timeMs,
              'value': key.value,
              'easing': key.easing.name,
            });
          }
        }
      }
    });
  }

  Future<void> _deleteTrackTrees(DatabaseExecutor txn, String shapeId) async {
    final trackIds = <String>[
      for (final row in await txn.query(
        'tracks',
        columns: <String>['id'],
        where: 'shape_id = ?',
        whereArgs: <Object?>[shapeId],
      ))
        row['id'] as String,
    ];
    for (final trackId in trackIds) {
      await txn.delete(
        'keyframes',
        where: 'track_id = ?',
        whereArgs: <Object?>[trackId],
      );
    }
    await txn.delete(
      'tracks',
      where: 'shape_id = ?',
      whereArgs: <Object?>[shapeId],
    );
    await txn.delete(
      'layers',
      where: 'shape_id = ?',
      whereArgs: <Object?>[shapeId],
    );
  }

  Future<void> delete(String id) async {
    final db = await database;
    await db.delete('projects', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<void> rename(String id, String name) async {
    final db = await database;
    await db.update(
      'projects',
      <String, Object?>{
        'name': name,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// Duplique un projet et toutes ses formes.
  Future<AnimationProject> duplicate(String id) async {
    final source = await load(id);
    final copy = AnimationProject(
      name: '${source.name} (copie)',
      width: source.width,
      height: source.height,
      durationMs: source.durationMs,
      fps: source.fps,
      backgroundValue: source.backgroundValue,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      shapes: source.shapes
          .map((shape) => shape.copy(id: generateId('shape')))
          .toList(),
    );
    for (final shape in copy.shapes) {
      for (var i = 0; i < shape.layers.length; i++) {
        shape.layers[i] = shape.layers[i].copy(id: generateId('layer'));
      }
    }
    await save(copy);
    return copy;
  }

  static DateTime? _date(Object? value) => value == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch((value as num).toInt());

  static String _encodePoints(List<Offset> points) =>
      jsonEncode(<List<double>>[
        for (final point in points) <double>[point.dx, point.dy],
      ]);

  static List<Offset> _decodePoints(String raw) {
    if (raw.trim().isEmpty) return <Offset>[];
    final dynamic decoded = jsonDecode(raw);
    if (decoded is! List) return <Offset>[];
    return <Offset>[
      for (final dynamic point in decoded)
        Offset(
          ((point as List<Object?>)[0] as num).toDouble(),
          (point[1] as num).toDouble(),
        ),
    ];
  }
}
