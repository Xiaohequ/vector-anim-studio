# Publication Google Play depuis GitHub Actions

Le workflow Android publie automatiquement le bundle AAB sur la piste **test fermé Alpha** (`alpha`) quand un commit est poussé sur `main` (donc après fusion d’une PR). La release GitHub et ses artefacts APK/AAB sont également créés par le workflow.

## Configuration requise une seule fois

1. Dans Google Cloud, activer l’API **Google Play Android Developer API** et créer un compte de service.
2. Dans la Play Console, donner à l’adresse de ce compte l’accès à l’application Keyform Studio avec les droits nécessaires aux releases de test fermé.
3. Créer une clé JSON pour le compte de service et enregistrer son contenu complet dans les secrets Actions du dépôt sous le nom `PLAY_SERVICE_ACCOUNT_JSON`.
4. Les secrets d’envoi déjà utilisés pour signer l’AAB restent nécessaires : `PLAY_UPLOAD_KEYSTORE_BASE64`, `PLAY_UPLOAD_KEY_ALIAS`, `PLAY_UPLOAD_STORE_PASSWORD` et `PLAY_UPLOAD_KEY_PASSWORD`.

Sans `PLAY_SERVICE_ACCOUNT_JSON`, le build Android et la release GitHub restent fonctionnels, mais la publication Play est ignorée et un avertissement apparaît dans le résumé du workflow.

La piste cible ne publiera que lorsqu’une nouvelle version (champ `version:` du `pubspec.yaml`, partie avant `+`) est introduite. Une exécution `workflow_dispatch` ne publie que si l’option `publish_to_play` est explicitement cochée.

## Choix de la piste

La piste par défaut est `alpha` (test fermé Alpha). Elle se change sans toucher au workflow :

- à la main, via l’entrée `play_track` de `workflow_dispatch` (`alpha`, `beta`, `internal`, `production`) ;
- pour les publications automatiques après fusion, en modifiant la valeur par défaut de `play_track` dans le bloc `workflow_dispatch` du workflow.

## Comportement

- Build et tests exécutés dans GitHub Actions ; aucun build Android local.
- Le workflow envoie uniquement l’AAB signé, jamais l’APK, à la piste choisie avec le statut `completed`.
- L’envoi ne remplace pas les examens ou exigences de conformité de Google Play. Suivre le statut de la release dans la Play Console.
- Une première publication doit généralement passer par une piste de test avant d’autoriser la production ; c’est le rôle de la piste `alpha`.
- Une exécution manuelle du workflow sur `main` ne publie l’AAB courant que si l’option `publish_to_play` est explicitement cochée.
