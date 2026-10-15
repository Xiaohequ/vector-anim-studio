# Publication Google Play depuis GitHub Actions

Le workflow Android publie automatiquement le bundle AAB sur la piste **Production** quand un commit est poussé sur `main` (donc après fusion d’une PR). La release GitHub et ses artefacts APK/AAB sont également créés par le workflow.

## Configuration requise une seule fois

1. Dans Google Cloud, activer l’API **Google Play Android Developer API** et créer un compte de service.
2. Dans la Play Console, donner à l’adresse de ce compte l’accès à l’application Keyform Studio avec les droits nécessaires aux releases de production.
3. Créer une clé JSON pour le compte de service et enregistrer son contenu complet dans les secrets Actions du dépôt sous le nom `PLAY_SERVICE_ACCOUNT_JSON`.
4. Les secrets d’envoi déjà utilisés pour signer l’AAB restent nécessaires : `PLAY_UPLOAD_KEYSTORE_BASE64`, `PLAY_UPLOAD_KEY_ALIAS`, `PLAY_UPLOAD_STORE_PASSWORD` et `PLAY_UPLOAD_KEY_PASSWORD`.

Sans `PLAY_SERVICE_ACCOUNT_JSON`, le build Android et la release GitHub restent fonctionnels, mais la publication Play est ignorée et un avertissement apparaît dans le résumé du workflow. À la vérification du dépôt, ce secret n’est pas encore configuré : il faudra l’ajouter dans Settings → Secrets and variables → Actions avant qu’un AAB soit envoyé à Google Play.

La piste production ne publiera que lorsqu’une nouvelle version (champ `version:` du `pubspec.yaml`, partie avant `+`) est introduite. Une exécution `workflow_dispatch` ne publie que si l’option `publish_to_play` est explicitement cochée.

## Comportement

- Build et tests exécutés dans GitHub Actions ; aucun build Android local.
- Le workflow envoie uniquement l’AAB signé, jamais l’APK, à la piste `production` avec le statut `completed`.
- L’envoi à la piste production ne remplace pas les examens ou exigences de conformité de Google Play. Suivre le statut de la release dans la Play Console.
- Google Play peut demander qu’une première version passe par une piste de test avant d’autoriser la piste production ; si l’API refuse, compléter cette étape dans la Play Console, puis relancer `workflow_dispatch` avec `publish_to_play=true`.
- Une exécution manuelle du workflow sur `main` ne publie l’AAB courant en production que si l’option `publish_to_play` est explicitement cochée.
