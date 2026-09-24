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
                     x, y, rotation, scale, opacity, strokeWidth, keyframes }
     ├─ ShapeLayer    { id, name, kind (rect/circle/line/path), x, y, width, height,
     │                  rotation, scale, opacity, strokeWidth, color, filled, points }
     └─ ShapeKeyframe { timeMs, easing, values { x, y, rotation, scale, opacity,
                                                 strokeWidth } }
```

Deux niveaux de transformation : la **forme** (groupe) porte la fenêtre d'affichage
(`startMs` / `endMs`) et les keyframes ; ses **couches** portent la géométrie et le style.
Une couche est une forme basique, une forme est donc un agrégat de formes basiques.

Une keyframe est une **pose** : elle fige les six propriétés de la forme à un instant.
`valueAt(propriété, t)` échantillonne la pose précédente et la suivante et interpole la
propriété avec la courbe (`easing`) de la pose d'arrivée — l'interpolation porte sur
*toutes* les propriétés. `applyValue()` est le point d'entrée unique de l'édition : sans
keyframe il écrit la valeur de base, avec keyframes il écrit (et crée si besoin) la pose au
curseur (**auto-key**), avec un snap de ~8 px sur une pose voisine
(`keyframeSnapToleranceMs`).

Conséquence assumée : deux presets ne se combinent pas (appliquer un preset remplace les
poses de la forme), et une pose fige les six propriétés.

## 3. Persistance

sqflite, base `vector_anim_studio.db` (schéma v3) dans le dossier documents de l'application.

- `projects` : métadonnées du projet (dont `cover_path`, `created_at`, `updated_at`)
- `shapes` : forme, fenêtre d'affichage, transformation de groupe, ordre (`z`)
- `layers` : formes basiques rattachées à une forme
- `shape_keyframes` : poses (`time_ms`, `easing`, `values_json` — les six propriétés)
- `PRAGMA foreign_keys = ON` + `ON DELETE CASCADE` pour supprimer proprement un projet

Le schéma est en **v3**. `onUpgrade` migre un schéma v1 (`tracks` + `keyframes` par
propriété) : chaque ancienne keyframe est échantillonnée sur les six propriétés pour
produire une pose, puis les tables `tracks` / `keyframes` sont supprimées. La v3 ajoute
les colonnes d'instance d'animation (`embedded_project_id`, `embedded_width`,
`embedded_height`). Piège SQLite :
`values` est un mot réservé, la colonne s'appelle donc `values_json`.

L'écriture est différée de 600 ms côté éditeur (`_scheduleSave`) pour ne pas écrire à chaque frame ; un `flush` a lieu avant chaque export.

## 4. Moteur

- `TimelineController` : temps courant, lecture/pause, boucle, `advance(dt)` ; le ticker de l'éditeur ne tourne **que pendant la lecture** (au repos, aucun frame n'est produit). Il expose aussi la tolérance de snap et la keyframe la plus proche du curseur.
- `TimelineLayout.packLanes` : algorithme glouton d'empilement — les formes sont triées par début, une forme dont le début est postérieur à la fin de la dernière forme d'une ligne réutilise cette ligne, sinon une nouvelle ligne est créée.
- `ScenePainter` : construit un `Path` par couche, applique la transformation du groupe au temps courant, dessine sur le `Canvas`. `shouldRepaint` renvoie **toujours vrai** : le projet est un objet mutable partagé, donc comparer les instances ne détecte pas un changement de valeur au repos (le canvas ne serait pas repeint).
- `animation_presets.dart` : les six presets produisent une séquence de poses calées sur la fenêtre d'affichage de la forme (et non sur la durée totale du projet), en repartant des valeurs de base.
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
3 bis. **Inspecteur** (`studio_screen`) : un curseur par propriété affichant la valeur **interpolée** à la tête de lecture (auto-key), un bouton keyframe unique (losange), un sélecteur de courbe pour le segment sous le curseur.
4. **Timeline** (`timeline_view`) : règle temporelle adaptative au zoom, une piste par
ligne, rectangles avec poignées gauche/droite, tête de lecture, un losange par pose.
Quand la tête de lecture approche d'une keyframe (tolérance ≈ 8 px), le losange devient
un bouton ✕ rouge de suppression ; le même seuil sert au snap à l'écriture.
L'échelle de temps se zoome de 500 ms à 30 minutes en pleine largeur : pincement à deux
doigts (zoom ancré, détecté via `Listener` pour ne pas perturber le scroll vertical ni le
scrub), glisser à deux doigts = défilement, boutons ＋/－/ajuster dans l'en-tête ; la tête
de lecture reste visible pendant la lecture. Un appui long sur un rectangle déplace tout
le segment (durée et keyframes conservées) ; le menu Formes propose « Dupliquer » qui
clone couches et keyframes à la même fenêtre (ids régénérés).

## 7. Tests

- `test/repository_test.dart` : persistance réelle (sqflite ffi), sauvegarde/rechargement des poses à l'identique, remplacement sans duplication, suppression, duplication.
- `test/timeline_layout_test.dart` : empilement des lignes (chevauchements, réutilisation de ligne).
- `test/animation_test.dart` : interpolation des poses (toutes propriétés), easing, remplacement au même temps, auto-key, snap, presets, duplication de forme (ids régénérés, keyframes copiées), déplacement de segment (`shiftBy`).
- `test/timeline_zoom_test.dart` : bornes de vue (500 ms – 30 min), zoom ancré, défilement borné, suivi de la tête de lecture, mapping temps↔pixel.
- `test/widget_test.dart` : écran d'accueil (état vide, création de projet et retour à la liste). Ces tests utilisent un dépôt en mémoire : `sqflite_common_ffi` ne progresse pas dans la zone fake-async de `testWidgets`, donc la couche SQLite reste couverte par `repository_test.dart`.

## 8. Reste à faire

- Valider l'export MP4 sur un appareil réel (encodeur natif non testable sur le serveur) — **fait** : validé par l'utilisateur le 2026-09-23 sur l'APK `0.2.0` (build 7). Export GIF et timeline (poignées début/fin, empilement des lignes) également validés le même jour.
- Job iOS sur runner macOS dans le workflow GitHub Actions.
- Backlog fonctionnel : import SVG, édition de courbes de Bézier, export SVG animé, calques imbriqués, partage cloud, test de migration v1 → v2 sur une base réelle.
