import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/animation.dart';

/// Dessine la scène vectorielle à un instant donné.
class ScenePainter extends CustomPainter {
  ScenePainter({required this.project, required this.timeMs});

  final AnimationProject project;
  final int timeMs;

  /// Facteur d'échelle permettant d'inscrire la scène dans [size].
  static double scaleFor(AnimationProject project, Size size) => math.min(
        size.width / project.width,
        size.height / project.height,
      );

  @override
  void paint(Canvas canvas, Size size) {
    final scale = scaleFor(project, size);
    final dx = (size.width - project.width * scale) / 2;
    final dy = (size.height - project.height * scale) / 2;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);

    final sceneRect = Rect.fromLTWH(0, 0, project.width, project.height);
    canvas.drawRect(
      sceneRect,
      Paint()..color = Color(project.backgroundValue),
    );

    for (final shape in project.shapes) {
      _paintShape(canvas, shape);
    }

    canvas.restore();
  }

  void _paintShape(Canvas canvas, VectorShape shape) {
    final x = shape.valueAt(AnimatableProperty.x, timeMs);
    final y = shape.valueAt(AnimatableProperty.y, timeMs);
    final w = shape.valueAt(AnimatableProperty.width, timeMs);
    final h = shape.valueAt(AnimatableProperty.height, timeMs);
    final rotation = shape.valueAt(AnimatableProperty.rotation, timeMs);
    final scale = shape.valueAt(AnimatableProperty.scale, timeMs);
    final opacity = shape.valueAt(AnimatableProperty.opacity, timeMs);
    final stroke = shape.valueAt(AnimatableProperty.strokeWidth, timeMs);

    final color = Color(shape.colorValue);
    final paint = Paint()
      ..color = color.withValues(alpha: opacity.clamp(0.0, 1.0))
      ..style = shape.filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(rotation);
    canvas.scale(scale <= 0 ? 0.0001 : scale);

    switch (shape.kind) {
      case ShapeKind.rect:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: w, height: h),
            Radius.circular(math.min(24, math.min(w, h) * 0.15)),
          ),
          paint,
        );
      case ShapeKind.circle:
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: w, height: h),
          paint,
        );
      case ShapeKind.line:
        canvas.drawLine(
          Offset(-w / 2, 0),
          Offset(w / 2, 0),
          paint..style = PaintingStyle.stroke,
        );
      case ShapeKind.path:
        final path = Path();
        final pts = shape.points;
        if (pts.isEmpty) {
          path.addRect(
            Rect.fromCenter(center: Offset.zero, width: w, height: h),
          );
        } else {
          path.moveTo(pts.first.dx - w / 2, pts.first.dy - h / 2);
          for (final point in pts.skip(1)) {
            path.lineTo(point.dx - w / 2, point.dy - h / 2);
          }
          path.close();
        }
        canvas.drawPath(path, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ScenePainter oldDelegate) =>
      oldDelegate.timeMs != timeMs || oldDelegate.project != project;
}

/// Rend la scène en image (pour l'export PNG).
Future<ui.Image> renderProjectToImage(
  AnimationProject project,
  int timeMs, {
  double pixelRatio = 2,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final size = Size(project.width * pixelRatio, project.height * pixelRatio);
  canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0x00000000));
  canvas.scale(pixelRatio);
  ScenePainter(project: project, timeMs: timeMs).paint(
    canvas,
    Size(project.width, project.height),
  );
  final picture = recorder.endRecording();
  return picture.toImage(size.width.round(), size.height.round());
}