import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/animation.dart';
import 'selection_geometry.dart';

/// Dessine la scène vectorielle à un instant donné.
class ScenePainter extends CustomPainter {
  ScenePainter({
    required this.project,
    required this.timeMs,
    this.selectedShapeId,
    this.selectedLayerId,
    this.transparentBackground = false,
    this.showFrame = false,
  });

  final AnimationProject project;
  final int timeMs;
  final String? selectedShapeId;

  /// Couche sélectionnée à l'intérieur de la forme sélectionnée (éditeur de
  /// forme) : prioritaire sur la sélection de forme pour l'overlay.
  final String? selectedLayerId;
  final bool transparentBackground;

  /// Dessine la bordure du cadre projet (édition uniquement, jamais en export).
  final bool showFrame;

  /// Facteur d'échelle permettant d'inscrire la scène dans [size].
  static double scaleFor(AnimationProject project, Size size) => math.min(
        size.width / project.width,
        size.height / project.height,
      );

  @override
  void paint(Canvas canvas, Size size) {
    final geo = SceneGeometry.fitFor(project, size);

    canvas.save();
    canvas.translate(geo.dx, geo.dy);
    canvas.scale(geo.scale);

    if (!transparentBackground) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, project.width, project.height),
        Paint()..color = Color(project.backgroundValue),
      );
    }

    for (final shape in project.shapes) {
      if (!shape.isVisibleAt(timeMs)) continue;
      _paintShape(canvas, shape);
    }

    canvas.restore();

    // Bordure du cadre projet (édition uniquement : jamais en export).
    if (showFrame) {
      final topLeft = geo.sceneToCanvas(Offset.zero);
      final bottomRight =
          geo.sceneToCanvas(Offset(project.width, project.height));
      canvas.drawRect(
        Rect.fromPoints(topLeft, bottomRight),
        Paint()
          ..color = const Color(0xFF3A4050)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..isAntiAlias = true,
      );
    }

    // Sélection + poignées en espace écran : épaisseur constante quelle que
    // soit l'échelle de l'objet. La sélection de couche (éditeur) prime sur
    // celle de la forme.
    VectorShape? selected;
    if (selectedShapeId != null) {
      for (final shape in project.shapes) {
        if (shape.id == selectedShapeId && shape.isVisibleAt(timeMs)) {
          selected = shape;
          break;
        }
      }
    }
    if (selected == null) return;
    if (selectedLayerId != null) {
      for (final layer in selected.layers) {
        if (layer.id == selectedLayerId && layer.visible) {
          _paintPoseOverlay(
            canvas,
            layerBounds(layer),
            SelectionGeometry.layerPose(selected, layer, timeMs),
            geo,
          );
          return;
        }
      }
    }
    final bounds = shapeBounds(selected, timeMs);
    if (bounds != null) {
      _paintPoseOverlay(
        canvas,
        bounds,
        SelectionGeometry.shapePose(selected, timeMs),
        geo,
      );
    }
  }

  void _paintShape(Canvas canvas, VectorShape shape) {
    final x = shape.valueAt(AnimatableProperty.x, timeMs);
    final y = shape.valueAt(AnimatableProperty.y, timeMs);
    final rotation = shape.valueAt(AnimatableProperty.rotation, timeMs);
    final scale = shape.valueAt(AnimatableProperty.scale, timeMs);
    final opacity = shape.valueAt(AnimatableProperty.opacity, timeMs);
    final strokeFactor = shape.valueAt(AnimatableProperty.strokeWidth, timeMs);

    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(rotation);
    canvas.scale(scale <= 0 ? 0.0001 : scale);

    for (final layer in shape.layers) {
      if (!layer.visible) continue;
      _paintLayer(canvas, layer, opacity, strokeFactor);
    }

    canvas.restore();
  }

  void _paintLayer(
    Canvas canvas,
    ShapeLayer layer,
    double shapeOpacity,
    double strokeFactor,
  ) {
    final opacity = (shapeOpacity * layer.opacity).clamp(0.0, 1.0);
    if (opacity <= 0) return;
    final stroke = math.max(0.0, layer.strokeWidth * strokeFactor);
    final paint = Paint()
      ..color = Color(layer.colorValue).withValues(alpha: opacity)
      ..style = layer.filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    canvas.save();
    canvas.translate(layer.x, layer.y);
    canvas.rotate(layer.rotation);
    canvas.scale(layer.scale <= 0 ? 0.0001 : layer.scale);

    switch (layer.kind) {
      case ShapeKind.rect:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: layer.width,
              height: layer.height,
            ),
            Radius.circular(math.min(24, math.min(layer.width, layer.height) * 0.15)),
          ),
          paint,
        );
      case ShapeKind.circle:
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: layer.width,
            height: layer.height,
          ),
          paint,
        );
      case ShapeKind.line:
        canvas.drawLine(
          Offset(-layer.width / 2, 0),
          Offset(layer.width / 2, 0),
          paint..style = PaintingStyle.stroke,
        );
      case ShapeKind.path:
        final path = Path();
        final pts = layer.points;
        if (pts.isEmpty) {
          path.addRect(
            Rect.fromCenter(
              center: Offset.zero,
              width: layer.width,
              height: layer.height,
            ),
          );
        } else {
          path.moveTo(pts.first.dx - layer.width / 2, pts.first.dy - layer.height / 2);
          for (final point in pts.skip(1)) {
            path.lineTo(point.dx - layer.width / 2, point.dy - layer.height / 2);
          }
          path.close();
        }
        canvas.drawPath(path, paint);
    }

    canvas.restore();
  }

  /// Rectangle de sélection + poignée de rotation, dessinés en espace écran
  /// (le trait garde 2 px quelles que soient les échelles forme/vue).
  void _paintPoseOverlay(
    Canvas canvas,
    Rect bounds,
    Pose2D pose,
    SceneGeometry geo,
  ) {
    final corners = SelectionGeometry.corners(bounds, pose, geo);
    final border = Paint()
      ..color = const Color(0xFF7DD3FC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..isAntiAlias = true;
    canvas.drawPath(Path()..addPolygon(corners, true), border);

    final topCenter = SelectionGeometry.topCenter(bounds, pose, geo);
    final handle = SelectionGeometry.rotationHandle(bounds, pose, geo);
    canvas.drawLine(topCenter, handle, border..strokeWidth = 1.5);
    canvas.drawCircle(
      handle,
      SelectionGeometry.handleRadius,
      Paint()..color = const Color(0xFF0B0D12),
    );
    canvas.drawCircle(handle, SelectionGeometry.handleRadius, border);
  }

  /// Boîte englobante de la forme en coordonnées locales (avant transformation).
  static Rect? shapeBounds(VectorShape shape, int timeMs) {
    Rect? bounds;
    for (final layer in shape.layers) {
      if (!layer.visible) continue;
      final halfW = (layer.width * layer.scale.abs()) / 2 + layer.x.abs();
      final halfH = (layer.height * layer.scale.abs()) / 2 + layer.y.abs();
      final rect = Rect.fromLTRB(-halfW, -halfH, halfW, halfH);
      bounds = bounds == null ? rect : bounds.expandToInclude(rect);
    }
    return bounds;
  }

  /// Rect local d'une couche (son repère : centre à l'origine), gonflé de 6
  /// comme la sélection de forme. Les points d'un chemin ne sont pas pris en
  /// compte : largeur/hauteur déclarées seulement.
  static Rect layerBounds(ShapeLayer layer) => Rect.fromCenter(
        center: Offset.zero,
        width: math.max(1.0, layer.width.abs()),
        height: math.max(0.0, layer.height.abs()),
      ).inflate(6);

  /// Le projet est un objet **mutable** partagé : comparer `oldDelegate.project`
  /// ne détecte rien lorsqu'une valeur change au repos (le canvas ne serait pas
  /// repeint). On repeint donc à chaque reconstruction, ce qui reflète
  /// immédiatement toute édition de propriété ou de keyframe.
  @override
  bool shouldRepaint(covariant ScenePainter oldDelegate) => true;
}

/// Rend la scène en image (export PNG, vignettes, frames vidéo).
Future<ui.Image> renderProjectToImage(
  AnimationProject project,
  int timeMs, {
  double pixelRatio = 2,
  double? outputWidth,
  bool transparentBackground = false,
}) async {
  final ratio = outputWidth == null ? pixelRatio : outputWidth / project.width;
  final width = math.max(2, (project.width * ratio).round());
  final height = math.max(2, (project.height * ratio).round());

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (!transparentBackground) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = Color(project.backgroundValue),
    );
  }
  canvas.scale(width / project.width, height / project.height);
  ScenePainter(
    project: project,
    timeMs: timeMs,
    transparentBackground: transparentBackground,
  ).paint(canvas, Size(project.width, project.height));
  final picture = recorder.endRecording();
  return picture.toImage(width, height);
}

/// Rend une frame en RGBA 8 bits (entrée de l'encodeur vidéo).
Future<Uint8List> renderFrameRgba(
  AnimationProject project,
  int timeMs, {
  required int width,
  required int height,
}) async {
  final image = await renderProjectToImage(
    project,
    timeMs,
    outputWidth: width.toDouble(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List();
}
