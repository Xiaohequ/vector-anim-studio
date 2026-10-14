import 'package:flutter/material.dart';

import '../settings/language_settings.dart';

/// Notice résumant les données utilisées par les fonctionnalités locales de l’app.
class PrivacyNoticeScreen extends StatelessWidget {
  const PrivacyNoticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.text;
    return ValueListenableBuilder<String>(
      valueListenable: AppStrings.language,
      builder: (context, _, _) => Scaffold(
        appBar: AppBar(title: Text(t('Notice de confidentialité'))),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: <Widget>[
            Text(
              t('Confidentialité'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              t(
                'Cette notice décrit les données utilisées par Keyform Studio.',
              ),
            ),
            const SizedBox(height: 20),
            _Section(
              title: t('Données des projets'),
              body: t(
                'Les projets, formes, animations et réglages sont conservés localement sur votre appareil. L’application utilise le stockage local pour les enregistrer.',
              ),
            ),
            _Section(
              title: t('Importation et exportation'),
              body: t(
                'Lors d’un import, l’application lit le fichier que vous choisissez. Les exports sont créés à votre demande. Si vous utilisez le partage, le contenu est transmis à l’application que vous sélectionnez.',
              ),
            ),
            _Section(
              title: t('Préférence de langue'),
              body: t(
                'Votre choix de langue est enregistré localement sur l’appareil. « Langue du système » n’enregistre pas de préférence linguistique spécifique.',
              ),
            ),
            _Section(
              title: t('Aucun compte requis'),
              body: t(
                'Keyform Studio ne requiert pas de compte pour créer et modifier des projets. Cette version n’intègre ni publicité ni suivi analytique.',
              ),
            ),
            _Section(
              title: t('Contrôle des données'),
              body: t(
                'Vous gardez le contrôle des fichiers importés et partagés. Vous pouvez supprimer vos projets depuis l’application ou effacer les données de l’application dans les réglages de votre appareil.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(body),
      ],
    ),
  );
}
