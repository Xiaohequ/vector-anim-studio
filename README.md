# Keyform Studio

> Nom commercial depuis v0.26.0. Les identifiants techniques restent en place :
> package Dart `vector_anim_studio`, `applicationId` / namespace Android
> `fr.xqu.vector_anim_studio`, bundle iOS `fr.xqu.vectorAnimStudio`, dépôt Git
> `vector-anim-studio` — changer un identifiant casserait la mise à jour de
> l'app installée et les URL des releases.

Application Flutter (Android, iOS configuré) pour **créer des animations vectorielles** : projets multiples, formes composées de couches, keyframes par propriété, timeline à rectangles d'affichage, lecture et export MP4 / GIF / PNG / JSON.

## Fonctionnalités

**Écran d'accueil** — liste des projets enregistrés (nom, format, durée, fps, nombre de formes, date de modification), création d'un nouveau projet (nom, format portrait/paysage/carré, durée, fps), projet d'exemple, renommage, duplication, suppression.

**Éditeur de projet** — quatre menus :
- **Formes** : liste des formes, sélection, édition, suppression, bouton « Ajouter » qui ouvre la création de forme.
- **Animations** (forme sélectionnée requise) : six presets — apparition, disparition, déplacement, rotation, pulsation, fondu — plus la gestion des keyframes. Une keyframe est une **pose** : elle enregistre toutes les propriétés de la forme (position, rotation, échelle, opacité, épaisseur) à un instant, et l'interpolation entre deux poses s'applique à toutes ces propriétés. Dès qu'une forme est animée, toute modification de propriété écrit automatiquement une keyframe au curseur (auto-key). La courbe du segment (linéaire, easeIn, easeOut, easeInOut, step) se règle dans l'inspecteur.
- **Calques** : ordre de rendu, visibilité, suppression.
- **Export** : MP4 (H.264 via `flutter_quick_video_encoder`), GIF animé, PNG de la frame courante, JSON du projet — puis partage via `share_plus`.

**Timeline** — chaque forme est un rectangle : bord gauche = début d'affichage, bord droit = fin, poignées déplaçables. Deux formes qui se chevauchent dans le temps occupent automatiquement deux lignes parallèles. Tête de lecture scrubbable, lecture/pause, boucle, règle temporelle et losanges de keyframes. Quand la tête de lecture approche d'une keyframe, celle-ci devient un bouton ✕ rouge qui la supprime.

**Création de forme** — aperçu en haut de l'écran, liste des couches en bas : ajout de formes basiques (rectangle, cercle, ligne, chemin) comme nouvelles couches, changement de couche, réglage taille / position / couleur / rotation / opacité / épaisseur, et fenêtre d'affichage (début–fin) sur la timeline.

## Pile technique

- Flutter stable / Dart 3 — cible `android` (iOS configuré mais non compilé : pas de macOS ici)
- Rendu vectoriel 100 % `CustomPainter`, aucun asset image
- État : `ChangeNotifier` + `InheritedNotifier`
- Persistance : **sqflite** (projet, formes, couches, pistes de keyframes) + images/JSON exportés dans le dossier documents de l'application
- Export : rendu offscreen `ui.PictureRecorder` → PNG / frames RGBA → encodeur MP4 natif ou GIF pur Dart

## Structure

```
vector_anim_studio/
├─ app/
│  ├─ lib/
│  │  ├─ models/animation.dart          # projet, forme, couche, keyframes (poses), presets de format
│  │  ├─ data/project_repository.dart   # schéma et accès sqflite
│  │  ├─ data/project_store.dart        # état de l'écran d'accueil
│  │  ├─ engine/scene_painter.dart      # rendu vectoriel (CustomPainter)
│  │  ├─ engine/timeline_controller.dart# temps courant, lecture, boucle, keyframes
│  │  ├─ engine/timeline_layout.dart    # empilement des rectangles sur la timeline
│  │  ├─ engine/animation_presets.dart  # presets d'animation
│  │  ├─ engine/export_service.dart     # MP4, GIF, PNG, JSON
│  │  └─ ui/                            # home_screen, studio_screen, shape_editor_screen, timeline_view, palette
│  └─ test/                             # repository, timeline layout, modèle, widgets
├─ docs/PLAN.md                         # décisions techniques
├─ docs/vasf-1-format.md                # spec du format d'échange VASF (source de vérité)
├─ scripts/flutter_docker.sh            # CLI Flutter via le conteneur cirruslabs
├─ scripts/sync_skill.sh                # synchronise le skill (dépôt séparé + workspace)
└─ tmp/                                 # artefacts de build (non versionné)
```

## Travail sur le projet

Aucune toolchain Flutter n'est installée dans le conteneur nanobot : tout passe par l'image `ghcr.io/cirruslabs/flutter:stable` lancée sur le démon Docker de l'hôte.

```bash
# Dépendances + analyse + tests (le cache pub est partagé via tmp/pub-cache)
scripts/flutter_docker.sh bash -lc "flutter pub get && flutter analyze && flutter test"

# Build local (bridé : ~950 Mio de RAM sur l'hôte)
scripts/flutter_docker.sh flutter build apk --release
```

Le build Android de référence est fait par **GitHub Actions** (`.github/workflows/android.yml`) : `flutter analyze`, `flutter test`, build de l'APK release, puis publication d'une release GitHub contenant l'APK. Le workflow ne produit volontairement **pas** d'App Bundle (`.aab`).

## Skill agent VASF

Le skill `keyformstudio-animation-json` apprend à un agent à générer et valider un fichier VASF importable. Il vit dans son **propre dépôt public** — https://github.com/Xiaohequ/keyformstudio-animation-json — et est publié sur ClawHub.

Ce dépôt-ci reste la source de vérité : `docs/vasf-1-format.md` et `docs/vasf-example.json` (un exemple unique couvrant toutes les fonctionnalités) sont recopiés dans `references/` du dépôt du skill. Les fichiers `docs/vasf-*-example.json` restent des fixtures des tests Flutter.

```bash
# Vérifier la cohérence (references/ du skill = docs/, frontmatter, validateur)
scripts/sync_skill.sh --check

# Recopier docs/ vers le dépôt du skill, puis vers le workspace de l'agent
scripts/sync_skill.sh

# Rapatrier une édition faite côté skill (à relire avant commit)
scripts/sync_skill.sh --pull
```

Le dépôt du skill est cherché dans `$SKILL_REPO`, sinon dans un dossier voisin (`../keyformstudio-animation-json`). Le frontmatter de son `SKILL.md` porte `version` (skill), `vasf` (version de format couverte) et `app` (version d'appli de référence) ; son historique est dans son `CHANGELOG.md`. Une évolution du format touche `docs/`, le code et les tests dans le **même commit**, puis on lance `sync_skill.sh` et on publie une nouvelle version du skill. La CI de ce dépôt exécute `sync_skill.sh --check` à chaque build.

## Contraintes d'environnement

- Hôte : 2 vCPU, ~950 Mio de RAM → builds Gradle limités (`-Xmx512m`, `-j1`, `--no-daemon`) ou déportés sur GitHub Actions.
- Pas de macOS disponible : la compilation iOS (bundle id déjà configuré) doit passer par un runner macOS.
- Pas d'émulateur Android possible sur le serveur (pas de `/dev/kvm`) : la validation visuelle se fait en installant l'APK sur un téléphone.

## Statut

- [x] MVP : scène, formes, keyframes, timeline, export JSON/PNG
- [x] Projets multiples persistés (sqflite) + écran d'accueil
- [x] Formes composées de couches + écran de création de forme (aperçu + couches)
- [x] Menus Formes / Animations / Calques / Export
- [x] Timeline à rectangles d'affichage empilés en lignes parallèles
- [x] Keyframes « pose » : interpolation de toutes les propriétés, auto-key, suppression contextuelle sur la timeline, courbe par segment (v0.3.0)
- [x] Export MP4 et GIF
- [x] CI : analyse, tests, APK release, release GitHub (pas d'App Bundle)
- [x] Validation de l'export MP4 sur un appareil réel (MediaCodec) — validé par l'utilisateur le 2026-09-23
- [x] Validation de l'export GIF et de la timeline sur appareil réel (poignées début/fin, empilement des lignes) — validé par l'utilisateur le 2026-09-23
- [ ] Build iOS (runner macOS)
