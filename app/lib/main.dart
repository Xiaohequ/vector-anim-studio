import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/project_repository.dart';
import 'settings/language_settings.dart';
import 'ui/home_screen.dart';
import 'ui/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(VectorAnimStudioApp(repository: ProjectRepository()));
}

class VectorAnimStudioApp extends StatefulWidget {
  const VectorAnimStudioApp({super.key, required this.repository});

  final ProjectRepository repository;

  @override
  State<VectorAnimStudioApp> createState() => _VectorAnimStudioAppState();
}

class _VectorAnimStudioAppState extends State<VectorAnimStudioApp> {
  late final LanguageSettings _language = LanguageSettings()..load();

  @override
  void dispose() {
    _language.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _language,
      builder: (context, _) {
        AppStrings.languageCode = _language.languageCode;
        return MaterialApp(
          title: 'Keyform Studio',
          debugShowCheckedModeBanner: false,
          locale: _language.locale,
          localeListResolutionCallback: (locales, supportedLocales) {
            for (final deviceLocale in locales ?? const <Locale>[]) {
              for (final supported in supportedLocales) {
                if (supported.languageCode == deviceLocale.languageCode) {
                  return supported;
                }
              }
            }
            return const Locale('en');
          },
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const <Locale>[
            Locale('fr'),
            Locale('en'),
            Locale('zh'),
          ],
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorSchemeSeed: const Color(0xFF5B8DEF),
          ),
          home: HomeScreen(
            repository: widget.repository,
            onOpenSettings: (homeContext) => Navigator.of(homeContext).push(
              MaterialPageRoute<void>(
                builder: (_) => SettingsScreen(settings: _language),
              ),
            ),
          ),
        );
      },
    );
  }
}
