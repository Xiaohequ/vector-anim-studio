import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../settings/language_settings.dart';
import 'privacy_notice_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    this.versionOverride,
  });

  final LanguageSettings settings;
  final String? versionOverride;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.text;
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[settings, AppStrings.language]),
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(t('Paramètres'))),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Text(
              t('Réglages généraux'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      t('Langue'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(t('Choisissez la langue utilisée par l’application.')),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>(settings.selectionValue),
                      initialValue: settings.selectionValue,
                      decoration: InputDecoration(labelText: t('Langue')),
                      items: <DropdownMenuItem<String>>[
                        DropdownMenuItem<String>(
                          value: 'system',
                          child: Text(t('Langue du système')),
                        ),
                        DropdownMenuItem<String>(
                          value: 'fr',
                          child: Text(t('Français')),
                        ),
                        DropdownMenuItem<String>(
                          value: 'en',
                          child: Text(t('Anglais')),
                        ),
                        DropdownMenuItem<String>(
                          value: 'zh',
                          child: Text(t('Chinois')),
                        ),
                      ],
                      onChanged: (value) =>
                          settings.select(value == 'system' ? null : value),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              t('Informations'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: <Widget>[
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(t('Version de l’application')),
                    subtitle: FutureBuilder<String>(
                      future: versionOverride == null
                          ? _appVersion()
                          : Future<String>.value(versionOverride!),
                      builder: (context, snapshot) =>
                          Text(snapshot.data ?? t('Chargement…')),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: Text(t('Notice de confidentialité')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PrivacyNoticeScreen(),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.code),
                    title: Text(t('Bibliothèques open source')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: 'Keyform Studio',
                      applicationVersion: versionOverride,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String> _appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version} (${info.buildNumber})';
    } catch (_) {
      return '—';
    }
  }
}
