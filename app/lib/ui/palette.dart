import 'package:flutter/material.dart';

import '../models/animation.dart';

/// Palette partagée par l'inspecteur et l'éditeur de forme.
const List<int> kColorPalette = <int>[
  0xFF5B8DEF,
  0xFF3ECF8E,
  0xFFFF5C5C,
  0xFFF2C94C,
  0xFFC084FC,
  0xFF7DD3FC,
  0xFFFFFFFF,
  0xFF14161C,
];

/// Icône représentant un type de forme basique.
IconData shapeKindIcon(ShapeKind kind) => switch (kind) {
      ShapeKind.rect => Icons.crop_square,
      ShapeKind.circle => Icons.circle_outlined,
      ShapeKind.line => Icons.horizontal_rule,
      ShapeKind.path => Icons.polyline,
    };