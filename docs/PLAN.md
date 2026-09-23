# Plan technique — vector_anim_studio

## 1. Environnement d'exécution

Le projet vit dans le workspace nanobot (`/root/.nanobot/workspace/vector_anim_studio`). Aucune toolchain Flutter n'est installée dans le conteneur nanobot : les commandes sont exécutées dans l'image `ghcr.io/cirruslabs/flutter:stable` via le démon Docker de l'hôte.

Toolchain :
- Image `ghcr.io/cirruslabs/flutter:stable` (Flutter + Dart + Android SDK + JDK embarqués), version utilisée : Flutter 3.44.0 / Dart 3.12.0
- Démon Docker de l'hôte atteint par `/var/run/docker.sock` (le CLI `docker` n'est pas dans l'image nanobot : `skills/env-init` l'installe)
- Helper : `scripts/flutter_docker.sh` (monte le projet sur `/work` et un cache pub persistant sur `tmp/pub-cache`)
- Le build Android de référence est fait par GitHub Actions (`ubuntu-latest`), l'hôte n'ayant que ~950 Mio de RAM

## 2. Modèle de données

```
AnimationProject { id, name, format (portrait/landscape/square), width, height,
                   durationMs, fps, background, createdAt, updatedAt, coverPath }
 └─ VectorShape   { id, name, startMs, endMs, visible, z,
                    x, y, rotation, scale, opacity, strokeWidth, tracks }
     ├─ ShapeLayer { id, name, kind (rect/circle/line/path), x, y, width, height,
     │               rotation, scale, opacity, strokeWidth, color, filled, points }
     └─ AnimTrack  { property (x, y, rotation, scale, opacity, strokeWidth) }
         └─ Keyframe { timeMs, value, easing (linear, easeIn, easeOut, easeInOut, step) }
```

Deux niveaux de transformation : la **forme** (groupe) porte la fenêtre d'affichage
(`startMs` / `endMs`) et les keyframes ; ses **couches** portent la géométrie et le style.
Une couche est une forme basique, une forme est donc un agrégat de formes basiques.

## 3. Persistance

sqflite, base `vector_anim_studio.db` (schéma v1) dans le dossier documents de l'application.

- `projects` : métadonnées du projet (dont `cover_path`, `created_at`, `updated_at`)
- `shapes` : forme, fenêtre d'affichage, transformation de groupe, ordre (`z`)
- `layers` : formes basiques rattachées à une forme
- `tracks` / `keyframes` : pistes par propriété et points de contrôle
- `PRAGMA foreign_keys = ON` + `ON DELETE CASCADE` pour supprimer proprement un projet

L'écriture est différée de 600 ms côté éditeur (`_scheduleSave`) pour ne pas écrire à chaque frame ; un `flush` a lieu avant chaque export.

## 4. Moteur

- `TimelineController` : temps courant, lecture/pause, boucle, `advance(dt)` ; le ticker de l'éditeur ne tourne **que pendant la lecture** (au repos, aucun frame n'est produit).
- `TimelineLayout.packLanes` : algorithme glouton d'empilement — les formes sont triées par début, une forme dont le début est postérieur à la fin de la dernière forme d'une ligne réutilise cette ligne, sinon une nouvelle ligne est créée.
- `ScenePainter` : construit un `Path` par couche, applique la transformation du groupe au temps courant, dessine sur le `Canvas`.
- `animation_presets.dart` : les six presets génèrent des keyframes calés sur la fenêtre d'affichage de la forme (et non sur la durée totale du projet).
- Rendu offscreen pour l'export : `PictureRecorder` → PNG, ou frames RGBA brutes pour l'encodage vidéo.

## 5. Export

| Format | Mécanisme | Remarque |
| --- | --- | --- |
| MP4 | `flutter_quick_video_encoder` (MediaCodec / AVFoundation) | frame par frame, aucun ffmpeg embarqué ; l'APK reste léger |
| GIF | package `image` (pur Dart), encodage 128 couleurs | repli léger, sans dépendance native |
| PNG | frame courante en `PictureRecorder` | |
| JSON | projet complet, relisible par l'application | |

Après export, `share_plus` partage le fichier (feuille de partage système).

## 6. Interface

1. **Accueil** (`home_screen`) : liste des projets, nouvel projet, projet d'exemple, renommage, duplication, suppression, état vide explicite.
2. **Éditeur** (`studio_screen`) : menus Formes / Animations / Calques / Export, canvas, inspecteur, timeline à rectangles, barre de lecture, sauvegarde différée.
3. **Création de forme** (`shape_editor_screen`) : aperçu en haut, couches en bas, ajout de forme basique comme nouvelle couche, réglages taille / position / couleur, fenêtre d'affichage.
4. **Timeline** (`timeline_view`) : règle temporelle, une piste par ligne, rectangles avec poignées gauche/droite, tête de lecture.

## 7. Tests

- `test/repository_test.dart` : persistance réelle (sqflite ffi), sauvegarde/rechargement à l'identique, remplacement sans duplication, suppression, duplication.
- `test/timeline_layout_test.dart` : empilement des lignes (chevauchements, réutilisation de ligne).
- `test/animation_test.dart` : interpolation et échantillonnage des pistes.
- `test/widget_test.dart` : écran d'accueil (état vide, création de projet et retour à la liste). Ces tests utilisent un dépôt en mémoire : `sqflite_common_ffi` ne progresse pas dans la zone fake-async de `testWidgets`, donc la couche SQLite reste couverte par `repository_test.dart`.

## 8. Reste à faire

- Valider l'export MP4 sur un appareil réel (encodeur natif non testable sur le serveur).
- Job iOS sur runner macOS dans le workflow GitHub Actions.
- Backlog fonctionnel : import SVG, édition de courbes de Bézier, export SVG animé, calques imbriqués, partage cloud.
