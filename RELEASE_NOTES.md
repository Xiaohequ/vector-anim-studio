# Keyform Studio 0.27.0

## Résolution vidéo au choix

- L'export MP4 propose **480p, 720p et 1080p** (720p par défaut), en portrait,
  paysage ou carré selon le format du projet. Le dialogue affiche les dimensions
  exactes encodées, arrondies à des valeurs paires pour H.264 ; les proportions
  restent celles du projet.
- Les autres formats restent inchangés : le GIF garde son réglage actuel (320 px
  de large).

## Messages en haut de l'écran

- Les SnackBars deviennent des messages temporaires en haut, fermables, dans
  l'éditeur de forme et le Studio. Ils disparaissent après 5 secondes ; un
  nouveau message remplace le précédent.

## Nom de l'application

- L'app s'affiche maintenant sous **Keyform Studio** (Android, iOS, accueil et
  titre système) ; les identifiants techniques restent inchangés pour préserver
  les installations existantes. Le format d'échange conserve son identifiant
  VASF.

### Vérifications

- `flutter analyze` : aucun problème ; tests ciblés des résolutions, du GIF,
  de la bannière, des morphs et gestes : passés.
- Suite complète : **270/270 tests** passés.
- Le build APK local a rencontré le verrou Gradle `journal-1` après expiration
  d'une première commande ; build Android à valider par la CI sur la PR.
