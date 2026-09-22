import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vector_anim_studio/main.dart';

void main() {
  testWidgets('le studio démarre et affiche ses contrôles', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const VectorAnimStudioApp());
    await tester.pump();

    expect(find.text('Vector Anim Studio'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);

    // Libère le Ticker et le controlleur de timeline.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}