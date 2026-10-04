import 'dart:convert';

import 'simple_animation_format.dart';
import '../models/animation.dart';

/// Résultat du décodage d'un fichier JSON de projet ou au format VASF.
class JsonProjectImportResult {
  const JsonProjectImportResult({
    this.project,
    this.error,
    this.isVasf = false,
  });

  final AnimationProject? project;
  final String? error;
  final bool isVasf;

  bool get isSuccess => project != null;
}

/// Décodage commun des fichiers importés depuis l'écran d'accueil.
class JsonProjectImport {
  const JsonProjectImport._();

  static JsonProjectImportResult parse(String text) {
    Map<String, Object?> decoded;
    try {
      final value = jsonDecode(text);
      if (value is! Map) {
        return const JsonProjectImportResult(error: 'objet JSON attendu');
      }
      decoded = Map<String, Object?>.from(value);
    } on FormatException catch (error) {
      return JsonProjectImportResult(error: 'JSON illisible : ${error.message}');
    }

    try {
      final isSimple = SimpleAnimationFormat.isSimpleFormat(decoded);
      final project = isSimple
          ? SimpleAnimationFormat.fromJson(
              decoded,
              fallbackName: 'Animation importée',
            )
          : AnimationProject.fromJson(<String, Object?>{
              ...decoded,
              // Un import doit toujours créer un nouvel élément, même si le
              // JSON contient l'identifiant d'un projet déjà présent.
              'id': null,
            });
      return JsonProjectImportResult(project: project, isVasf: isSimple);
    } on SimpleFormatException catch (error) {
      return JsonProjectImportResult(error: error.toString());
    } catch (error) {
      return JsonProjectImportResult(error: error.toString());
    }
  }
}
