import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_quick_video_encoder/flutter_quick_video_encoder.dart';

import '../models/animation.dart';
import 'scene_painter.dart';
import 'simple_animation_format.dart';

/// Format de sortie vidéo.
enum VideoFormat { mp4, gif }

extension VideoFormatInfo on VideoFormat {
  String get label => switch (this) {
    VideoFormat.mp4 => 'Vidéo MP4 (H.264)',
    VideoFormat.gif => 'GIF animé',
  };

  String get extension => switch (this) {
    VideoFormat.mp4 => 'mp4',
    VideoFormat.gif => 'gif',
  };

  String get mimeType => switch (this) {
    VideoFormat.mp4 => 'video/mp4',
    VideoFormat.gif => 'image/gif',
  };
}

/// Export d'un projet : vidéo MP4 (MediaCodec natif), GIF (pur Dart), PNG, JSON.
class ExportService {
  ExportService(this.project, {this.embeddedProjects = const {}});

  final AnimationProject project;

  /// Projets imbriqués préchargés (rendu des instances dans les exports).
  final Map<String, AnimationProject> embeddedProjects;

  static Future<Directory> outputDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(documents.path, 'exports'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  static String _stamp() =>
      DateTime.now().toIso8601String().replaceAll(RegExp('[:.]'), '-');

  static String _slug(String value) {
    final slug = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'animation' : slug;
  }

  int frameCount({required int fps}) =>
      ((project.durationMs / 1000) * fps).round().clamp(1, 100000);

  int _even(int value) => value.isEven ? value : value + 1;

  /// Exporte la vidéo complète, frame par frame.
  Future<File> exportVideo({
    required VideoFormat format,
    int? fps,
    double? width,
    void Function(double progress)? onProgress,
  }) async {
    final dir = await outputDirectory();
    final name = '${_slug(project.name)}-${_stamp()}.${format.extension}';
    final file = File(p.join(dir.path, name));
    switch (format) {
      case VideoFormat.mp4:
        return _exportMp4(
          file,
          fps: fps ?? project.fps,
          width: width,
          onProgress: onProgress,
        );
      case VideoFormat.gif:
        return _exportGif(
          file,
          fps: fps ?? 12,
          width: width ?? 320,
          onProgress: onProgress,
        );
    }
  }

  Future<File> _exportMp4(
    File file, {
    required int fps,
    double? width,
    void Function(double)? onProgress,
  }) async {
    final targetWidth = _even((width ?? project.width).round().clamp(16, 1920));
    final targetHeight = _even(
      ((width ?? project.width) * project.height / project.width).round().clamp(
        16,
        1920,
      ),
    );
    final frames = frameCount(fps: fps);
    final bitrate = (targetWidth * targetHeight * fps * 0.11).round().clamp(
      500000,
      20000000,
    );

    await FlutterQuickVideoEncoder.setLogLevel(LogLevel.none);
    await FlutterQuickVideoEncoder.setup(
      width: targetWidth,
      height: targetHeight,
      fps: fps,
      videoBitrate: bitrate,
      profileLevel: ProfileLevel.any,
      audioChannels: 0,
      audioBitrate: 0,
      sampleRate: 0,
      filepath: file.path,
    );

    for (var i = 0; i < frames; i++) {
      final timeMs = (i * 1000 / fps).round().clamp(0, project.durationMs);
      final frame = await renderFrameRgba(
        project,
        timeMs,
        width: targetWidth,
        height: targetHeight,
        embeddedProjects: embeddedProjects,
      );
      await FlutterQuickVideoEncoder.appendVideoFrame(frame);
      onProgress?.call((i + 1) / frames);
    }
    await FlutterQuickVideoEncoder.finish();
    return file;
  }

  Future<File> _exportGif(
    File file, {
    required int fps,
    required double width,
    void Function(double)? onProgress,
  }) async {
    final targetWidth = width.round().clamp(64, 720);
    final targetHeight = (width * project.height / project.width).round().clamp(
      64,
      720,
    );
    final frames = frameCount(fps: fps);
    final encoder = img.GifEncoder(
      delay: (100 / fps).round().clamp(2, 200),
      repeat: 0,
      numColors: 128,
    );

    for (var i = 0; i < frames; i++) {
      final timeMs = (i * 1000 / fps).round().clamp(0, project.durationMs);
      final rgba = await renderFrameRgba(
        project,
        timeMs,
        width: targetWidth,
        height: targetHeight,
        embeddedProjects: embeddedProjects,
      );
      final frame = img.Image.fromBytes(
        width: targetWidth,
        height: targetHeight,
        bytes: rgba.buffer,
        numChannels: 4,
      );
      encoder.addFrame(frame, duration: (100 / fps).round().clamp(2, 200));
      onProgress?.call((i + 1) / frames);
    }

    final bytes = encoder.finish();
    if (bytes == null) {
      throw StateError('Encodage GIF impossible : aucune frame encodée');
    }
    await file.writeAsBytes(bytes);
    return file;
  }

  /// Exporte la frame courante en PNG.
  Future<File> exportFramePng(int timeMs, {double pixelRatio = 2}) async {
    final image = await renderProjectToImage(
      project,
      timeMs,
      pixelRatio: pixelRatio,
      embeddedProjects: embeddedProjects,
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final dir = await outputDirectory();
    final file = File(
      p.join(dir.path, '${_slug(project.name)}-frame-$timeMs.png'),
    );
    await file.writeAsBytes(data!.buffer.asUint8List());
    return file;
  }

  /// Exporte le projet complet au format JSON (lisible par l'application).
  Future<File> exportJson() async {
    final dir = await outputDirectory();
    final file = File(
      p.join(dir.path, '${_slug(project.name)}-${_stamp()}.json'),
    );
    await file.writeAsString(_prettyJson(project.toJson()));
    return file;
  }

  /// Exporte le projet au format SIMPLE « vasf-1 » (pour agents IA) — les
  /// instances imbriquées sont ignorées.
  Future<File> exportSimpleJson() async {
    final dir = await outputDirectory();
    final file = File(
      p.join(dir.path, '${_slug(project.name)}-${_stamp()}-vasf.json'),
    );
    await file.writeAsString(
      _prettyJson(SimpleAnimationFormat.toJson(project)),
    );
    return file;
  }

  static String _prettyJson(Map<String, Object?> json) =>
      const JsonEncoder.withIndent('  ').convert(json);
}
