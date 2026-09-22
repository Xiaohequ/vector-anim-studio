import 'package:flutter/material.dart';

import 'ui/studio_screen.dart';

void main() => runApp(const VectorAnimStudioApp());

class VectorAnimStudioApp extends StatelessWidget {
  const VectorAnimStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vector Anim Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF5B8DEF),
      ),
      home: const StudioScreen(),
    );
  }
}