import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/animation.dart';
import '../models/skeleton.dart';
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
    this.embeddedProjects = const {},
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

  /// Projets imbriqués préchargés, indexés par id (rendu des instances).
  final Map<String, AnimationProject> embeddedProjects;

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

    _paintProjectShapes(canvas, project, timeMs, depth: 0);

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
        SelectionGeometry.shapePoseWithRig(
          selected,
          timeMs,
          _rigFrameFor(project, selected),
        ),
        geo,
      );
    }
  }

  /// Os portant une forme (rig maître), pour la composition de rendu.
  BoneFrame? _rigFrameFor(
    AnimationProject project,
    VectorShape shape,
  ) {
    if (!project.isSkeleton || project.skeleton == null) return null;
    final pose = SkeletonPose.evaluate(project.skeleton!, timeMs);
    return pose.frameOf(project.skeleton!.boneIdForShape(shape.id));
  }

  /// Peint toutes les formes d'un projet à un instant (le projet principal
  /// comme les sous-projets imbriqués — le rig, s'il existe, est évalué au
  /// temps de CE projet).
  void _paintProjectShapes(
    Canvas canvas,
    AnimationProject project,
    int timeMs, {
    required int depth,
  }) {
    final rig = project.skeleton;
    final SkeletonPose? rigPose =
        project.isSkeleton && rig != null && rig.bones.isNotEmpty
            ? SkeletonPose.evaluate(rig, timeMs)
            : null;
    for (final shape in project.shapes) {
      // Projet squelette : les pièces sont visibles en permanence (le rig
      // porte toute l'animation) — pas de fenêtre d'affichage.
      final show =
          project.isSkeleton ? shape.visible : shape.isVisibleAt(timeMs);
      if (!show) continue;
      BoneFrame? frame;
      if (rigPose != null) {
        frame = rigPose.frameOf(rig!.boneIdForShape(shape.id));
      }
      _paintShape(canvas, shape, depth: depth, boneFrame: frame);
    }
  }

  void _paintShape(
    Canvas canvas,
    VectorShape shape, {
    required int depth,
    BoneFrame? boneFrame,
  }) {
    final x = shape.valueAt(AnimatableProperty.x, timeMs);
    final y = shape.valueAt(AnimatableProperty.y, timeMs);
    final rotation = shape.valueAt(AnimatableProperty.rotation, timeMs);
    final scale = shape.valueAt(AnimatableProperty.scale, timeMs);
    final opacity = shape.valueAt(AnimatableProperty.opacity, timeMs);
    final strokeFactor = shape.valueAt(AnimatableProperty.strokeWidth, timeMs);

    canvas.save();
    // Rig maître : l'os emporte la pièce (transformée os(t) ∘ os(repos)⁻¹),
    // la pose de la forme sert ensuite d'offset de repos.
    if (boneFrame != null) _applyBoneDelta(canvas, boneFrame);
    canvas.translate(x, y);
    canvas.rotate(rotation);
    canvas.scale(scale <= 0 ? 0.0001 : scale);

    if (shape.isInstance) {
      _paintInstance(canvas, shape, opacity, depth);
    } else {
      for (final layer in shape.layers) {
        if (!layer.visible) continue;
        _paintLayer(canvas, layer, opacity, strokeFactor);
      }
    }

    canvas.restore();
  }

  /// Mouvement rigide de l'os entre son repos et l'instant courant :
  /// `translate(joint_t) · rotate(worldAngle_t) · rotate(−angleRest) ·
  /// translate(−jointRest)` — identité au repos.
  void _applyBoneDelta(Canvas canvas, BoneFrame frame) {
    canvas.translate(frame.joint.dx, frame.joint.dy);
    canvas.rotate(frame.worldAngle);
    canvas.rotate(-frame.worldAngleRest);
    canvas.translate(-frame.jointRest.dx, -frame.jointRest.dy);
  }

  /// Instance d'animation : rend le projet source (en boucle) dans la pose de
  /// la forme, sans son fond (compositing sur la scène hôte). Un seul niveau
  /// d'imbrication : les instances internes sont ignorées.
  void _paintInstance(
    Canvas canvas,
    VectorShape shape,
    double opacity,
    int depth,
  ) {
    final sub = embeddedProjects[shape.embeddedProjectId];
    final w = shape.embeddedWidth <= 0 ? 200.0 : shape.embeddedWidth;
    final h = shape.embeddedHeight <= 0 ? 200.0 : shape.embeddedHeight;
    if (sub == null) {
      // Projet source introuvable : cadre translucide barré, la forme reste
      // sélectionnable et éditable (position, fenêtre…).
      final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
      canvas.drawRect(
        rect,
        Paint()..color = const Color(0x40C084FC),
      );
      final stroke = Paint()
        ..color = const Color(0x99C084FC)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRect(rect, stroke);
      canvas.drawLine(rect.topLeft, rect.bottomRight, stroke);
      canvas.drawLine(rect.topRight, rect.bottomLeft, stroke);
      return;
    }
    if (depth >= 1) return;
    final subTime = instanceTimeMs(timeMs, shape.startMs, sub.durationMs);
    if (opacity < 1) {
      canvas.saveLayer(
        null,
        Paint()..color = Colors.white.withValues(alpha: opacity),
      );
    }
    // Le sous-projet (vectoriel ou squelette) est rendu à son temps de
    // boucle ; son rig, s'il en a un, est évalué par _paintProjectShapes.
    _paintProjectShapes(canvas, sub, subTime, depth: depth + 1);
    if (opacity < 1) canvas.restore();
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
      case ShapeKind.triangle:
      case ShapeKind.star:
      case ShapeKind.hexagon:
      case ShapeKind.cross:
      case ShapeKind.heart:
      case ShapeKind.arrow:
        canvas.drawPath(_kindPath(layer), paint);
    }

    canvas.restore();
  }

  /// Chemin paramétrique des formes géométriques, défini dans la boîte
  /// [(-w/2, w/2) × (-h/2, h/2)] centrée sur l'origine de la couche.
  Path _kindPath(ShapeLayer layer) {
    final w = math.max(1.0, layer.width);
    final h = math.max(1.0, layer.height);
    final path = Path();
    switch (layer.kind) {
      case ShapeKind.triangle:
        path.moveTo(0, -h / 2);
        path.lineTo(w / 2, h / 2);
        path.lineTo(-w / 2, h / 2);
        path.close();
      case ShapeKind.star:
        const points = 5;
        const innerRatio = 0.45;
        for (var i = 0; i < points * 2; i++) {
          final angle = -math.pi / 2 + i * math.pi / points;
          final radius = i.isEven ? 1.0 : innerRatio;
          final x = math.cos(angle) * (w / 2) * radius;
          final y = math.sin(angle) * (h / 2) * radius;
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();
      case ShapeKind.hexagon:
        for (var i = 0; i < 6; i++) {
          final angle = -math.pi / 2 + i * math.pi / 3;
          final x = math.cos(angle) * w / 2;
          final y = math.sin(angle) * h / 2;
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();
      case ShapeKind.cross:
        final a = w / 2;
        final b = h / 2;
        final tx = w / 6;
        final ty = h / 6;
        path.addPolygon(<Offset>[
          Offset(-tx, -b),
          Offset(tx, -b),
          Offset(tx, -ty),
          Offset(a, -ty),
          Offset(a, ty),
          Offset(tx, ty),
          Offset(tx, b),
          Offset(-tx, b),
          Offset(-tx, ty),
          Offset(-a, ty),
          Offset(-a, -ty),
          Offset(-tx, -ty),
        ], true);
      case ShapeKind.heart:
        final cw = w / 2;
        final ch = h / 2;
        path.moveTo(0, ch);
        path.cubicTo(-cw, ch * 0.25, -cw * 0.55, -ch, 0, -ch * 0.35);
        path.cubicTo(cw * 0.55, -ch, cw, ch * 0.25, 0, ch);
        path.close();
      case ShapeKind.arrow:
        final a = w / 2;
        final b = h / 2;
        path.addPolygon(<Offset>[
          Offset(-a, -h * 0.2),
          Offset(w * 0.05, -h * 0.2),
          Offset(w * 0.05, -b),
          Offset(a, 0),
          Offset(w * 0.05, b),
          Offset(w * 0.05, h * 0.2),
          Offset(-a, h * 0.2),
        ], true);
      default:
        path.addRect(Rect.fromCenter(center: Offset.zero, width: w, height: h));
    }
    return path;
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
    if (shape.isInstance) {
      final w = shape.embeddedWidth <= 0 ? 200.0 : shape.embeddedWidth;
      final h = shape.embeddedHeight <= 0 ? 200.0 : shape.embeddedHeight;
      return Rect.fromCenter(center: Offset.zero, width: w, height: h);
    }
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
  Map<String, AnimationProject> embeddedProjects = const {},
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
    embeddedProjects: embeddedProjects,
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
  Map<String, AnimationProject> embeddedProjects = const {},
}) async {
  final image = await renderProjectToImage(
    project,
    timeMs,
    outputWidth: width.toDouble(),
    embeddedProjects: embeddedProjects,
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List();
}
