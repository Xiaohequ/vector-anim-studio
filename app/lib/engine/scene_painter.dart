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
    this.showLayerPoints = false,
    this.activePointIndex = -1,
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

  /// Dessine les poignées de points de la couche sélectionnée si c'est un
  /// chemin (éditeur de points, v0.16) — éditeur seulement, jamais en export.
  final bool showLayerPoints;

  /// Index du point en cours de glisser (surbrillance), ou −1.
  final int activePointIndex;

  /// Facteur d'échelle permettant d'inscrire la scène dans [size].
  static double scaleFor(AnimationProject project, Size size) =>
      math.min(size.width / project.width, size.height / project.height);

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
      final bottomRight = geo.sceneToCanvas(
        Offset(project.width, project.height),
      );
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
          final pose = SelectionGeometry.layerPose(selected, layer, timeMs);
          _paintPoseOverlay(canvas, layerBounds(layer), pose, geo);
          if (showLayerPoints && layer.kind == ShapeKind.path) {
            _paintPointHandles(canvas, selected, layer, pose, geo);
          }
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
  BoneFrame? _rigFrameFor(AnimationProject project, VectorShape shape) {
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

    void paintShape(VectorShape shape) {
      // Le rectangle de la timeline est la fenêtre d'affichage de la pièce,
      // quel que soit le type de projet. Un rig peut avoir des keyframes
      // après cette fenêtre, mais il ne doit pas prolonger la visibilité de
      // la forme : elle disparaît dès que le playhead sort de start → end.
      if (!shape.isVisibleAt(timeMs)) return;
      BoneFrame? frame;
      if (rigPose != null) {
        frame = rigPose.frameOf(rig!.boneIdForShape(shape.id));
      }
      _paintShape(
        canvas,
        shape,
        depth: depth,
        boneFrame: frame,
        rig: rig,
        rigPose: rigPose,
        sampleMs: timeMs,
      );
    }

    // Ordre de dessin par os (v0.10) : en projet squelette, les pièces sont
    // triées par le z de leur os porteur — z égal → ordre de la timeline.
    if (rigPose != null) {
      final indexes = List<int>.generate(project.shapes.length, (i) => i);
      indexes.sort((a, b) {
        final za = rig!.zForShape(project.shapes[a].id);
        final zb = rig.zForShape(project.shapes[b].id);
        return za != zb ? za.compareTo(zb) : a.compareTo(b);
      });
      for (final index in indexes) {
        paintShape(project.shapes[index]);
      }
    } else {
      for (final shape in project.shapes) {
        paintShape(shape);
      }
    }
  }

  void _paintShape(
    Canvas canvas,
    VectorShape shape, {
    required int depth,
    BoneFrame? boneFrame,
    required SkeletonRig? rig,
    required SkeletonPose? rigPose,
    required int sampleMs,
  }) {
    final x = shape.valueAt(AnimatableProperty.x, sampleMs);
    final y = shape.valueAt(AnimatableProperty.y, sampleMs);
    final rotation = shape.valueAt(AnimatableProperty.rotation, sampleMs);
    final scale = shape.valueAt(AnimatableProperty.scale, sampleMs);
    // Échelle par axe (v0.13) : effective = scale × facteur.
    final effX = scale * shape.valueAt(AnimatableProperty.scaleX, sampleMs);
    final effY = scale * shape.valueAt(AnimatableProperty.scaleY, sampleMs);
    // Pivot de rotation (v0.13) : offset DANS le repère de la forme — la
    // chaîne tourne autour de centre + pivot sans déplacer le centre.
    final px = shape.pivotDx;
    final py = shape.pivotDy;
    final opacity = shape.valueAt(AnimatableProperty.opacity, sampleMs);
    final strokeFactor = shape.valueAt(
      AnimatableProperty.strokeWidth,
      sampleMs,
    );

    if (shape.isInstance) {
      canvas.save();
      // Rig maître : l'os emporte l'instance (transformée os(t) ∘ os(repos)⁻¹),
      // la pose de la forme sert ensuite d'offset de repos.
      if (boneFrame != null) _applyBoneDelta(canvas, boneFrame);
      final cx = effX <= 0 ? 0.0001 : effX;
      final cy = effY <= 0 ? 0.0001 : effY;
      // Pivot ancré à sa position VISUELLE (S·pivot) : sous une échelle non
      // uniforme, le gond reste collé au bord visuel de la forme.
      canvas.translate(x, y);
      canvas.translate(cx * px, cy * py);
      canvas.rotate(rotation);
      canvas.scale(cx, cy);
      canvas.translate(-px, -py);
      _paintInstance(canvas, shape, opacity, depth, sampleMs);
      canvas.restore();
      return;
    }

    // Liaison au niveau couche (v0.9.6) : la transformée de l'os porteur est
    // exprimée en coordonnées PROJET — elle enveloppe la chaîne complète
    // (pose de la forme puis couche), donc elle s'applique AVANT la pose de
    // la forme. Une couche liée à un os suit SON os (la liaison de couche
    // prend le pas sur la liaison de la forme entière). Ordre de dessin par
    // os (v0.10) : les couches sont triées par le z de leur os porteur.
    final layerOrder = List<int>.generate(shape.layers.length, (i) => i);
    if (rigPose != null) {
      layerOrder.sort((a, b) {
        final za = rig?.zOfLayer(shape.id, shape.layers[a].id) ?? 0;
        final zb = rig?.zOfLayer(shape.id, shape.layers[b].id) ?? 0;
        return za != zb ? za.compareTo(zb) : a.compareTo(b);
      });
    }
    for (final layerIndex in layerOrder) {
      final layer = shape.layers[layerIndex];
      if (!layer.visible) continue;
      BoneFrame? layerFrame;
      final layerBinding = rig?.bindingForLayer(shape.id, layer.id);
      if (layerBinding != null && rigPose != null) {
        layerFrame = rigPose.frameOf(layerBinding.boneId);
      }
      // Opacité (v0.10) : celle de l'os porteur multiplie la pose.
      final carried = layerFrame ?? boneFrame;
      final boneOpacity = carried?.opacity ?? 1;
      final effectiveOpacity = (opacity * boneOpacity).clamp(0.0, 1.0);
      final cx = effX <= 0 ? 0.0001 : effX;
      final cy = effY <= 0 ? 0.0001 : effY;
      // Couleur animée + morph de points (v0.15) : échantillonnés dans les
      // poses de la forme — retombent sur la base sans keyframe colorée/morphée.
      final layerColor = shape.colorAtLayer(
        layer.id,
        sampleMs,
        layer.colorValue,
      );
      final layerPoints = shape.pointsAtLayer(layer.id, layer.points, sampleMs);
      canvas.save();
      if (carried != null) _applyBoneDelta(canvas, carried);
      canvas.translate(x, y);
      canvas.translate(cx * px, cy * py);
      canvas.rotate(rotation);
      canvas.scale(cx, cy);
      canvas.translate(-px, -py);
      _paintLayer(
        canvas,
        layer,
        effectiveOpacity,
        strokeFactor,
        colorValue: layerColor,
        points: layerPoints,
      );
      canvas.restore();
    }
  }

  /// Mouvement rigide de l'os entre son repos et l'instant courant :
  /// `translate(joint_t) · rotate(worldAngle_t) · scale(S) · rotate(−angleRest)
  /// · translate(−jointRest)` — identité au repos. S = étirement/écrasement
  /// de l'os (v0.10), neutre (1) sans keyframe.
  void _applyBoneDelta(Canvas canvas, BoneFrame frame) {
    canvas.translate(frame.joint.dx, frame.joint.dy);
    canvas.rotate(frame.worldAngle);
    canvas.scale(frame.stretchX, frame.stretchY);
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
    int sampleMs,
  ) {
    final sub = embeddedProjects[shape.embeddedProjectId];
    final w = shape.embeddedWidth <= 0 ? 200.0 : shape.embeddedWidth;
    final h = shape.embeddedHeight <= 0 ? 200.0 : shape.embeddedHeight;
    if (sub == null) {
      // Projet source introuvable : cadre translucide barré, la forme reste
      // sélectionnable et éditable (position, fenêtre…).
      final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
      canvas.drawRect(rect, Paint()..color = const Color(0x40C084FC));
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
    final subTime = instanceTimeMs(sampleMs, shape.startMs, sub.durationMs);
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
    double strokeFactor, {
    required int colorValue,
    required List<Offset> points,
  }) {
    final opacity = (shapeOpacity * layer.opacity).clamp(0.0, 1.0);
    if (opacity <= 0) return;
    final stroke = math.max(0.0, layer.strokeWidth * strokeFactor);
    final paint = Paint()
      ..color = Color(colorValue).withValues(alpha: opacity)
      ..style = layer.filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    canvas.save();
    canvas.translate(layer.x, layer.y);
    canvas.rotate(layer.rotation);
    canvas.scale(layer.scale <= 0 ? 0.0001 : layer.scale);
    // Miroir (v0.19) : réflexion du contenu autour de l'origine de la
    // couche — primitive ou path, points de base comme nuages de morph
    // sont dessinés à travers cette transformée.
    if (layer.flipH || layer.flipV) {
      canvas.scale(layer.flipH ? -1 : 1, layer.flipV ? -1 : 1);
    }

    switch (layer.kind) {
      case ShapeKind.rect:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: layer.width,
              height: layer.height,
            ),
            Radius.circular(
              math.min(24, math.min(layer.width, layer.height) * 0.15),
            ),
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
        final pts = points;
        if (pts.isEmpty) {
          path.addRect(
            Rect.fromCenter(
              center: Offset.zero,
              width: layer.width,
              height: layer.height,
            ),
          );
        } else {
          path.moveTo(
            pts.first.dx - layer.width / 2,
            pts.first.dy - layer.height / 2,
          );
          for (final point in pts.skip(1)) {
            path.lineTo(
              point.dx - layer.width / 2,
              point.dy - layer.height / 2,
            );
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

  /// Poignées de points du chemin sélectionné (v0.16, éditeur de points) :
  /// le nuage échantillonné au temps affiché, projeté en espace écran via la
  /// pose de la couche — cercles à rayon constant en pixels écran, point
  /// actif surligné en orange.
  void _paintPointHandles(
    Canvas canvas,
    VectorShape shape,
    ShapeLayer layer,
    Pose2D pose,
    SceneGeometry geo,
  ) {
    final cloud = shape.pointsAtLayer(layer.id, layer.points, timeMs);
    final positions = SelectionGeometry.pointHandlePositions(
      cloud,
      layer,
      pose,
      geo,
    );
    final fill = Paint()..style = PaintingStyle.fill;
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFF0B0D12)
      ..isAntiAlias = true;
    for (var i = 0; i < positions.length; i++) {
      final active = i == activePointIndex;
      final radius = active
          ? SelectionGeometry.activePointHandleRadius
          : SelectionGeometry.pointHandleRadius;
      fill.color = active ? const Color(0xFFF2994A) : const Color(0xFFF2F4F8);
      canvas.drawCircle(positions[i], radius, fill);
      canvas.drawCircle(positions[i], radius, border);
    }
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
