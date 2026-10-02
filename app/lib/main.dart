import 'package:flutter/material.dart';

import 'data/project_repository.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(VectorAnimStudioApp(repository: ProjectRepository()));
}

class VectorAnimStudioApp extends StatelessWidget {
  const VectorAnimStudioApp({super.key, required this.repository});

  final ProjectRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Keyform Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF5B8DEF),
      ),
      home: HomeScreen(repository: repository),
    );
  }
}
