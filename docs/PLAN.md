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
                   fps (fps du dernier export), background, createdAt, updatedAt, coverPath,
                   type (vector | skeleton), skeleton (rig, JSON) }
 └─ VectorShape   { id, name, startMs, endMs, visible, z,
                     x, y, rotation, scale, opacity, strokeWidth, keyframes }
     ├─ ShapeLayer    { id, name, kind (rect/circle/line/path), x, y, width, height,
     │                  rotation, scale, opacity, strokeWidth, color, filled, points }
     └─ ShapeKeyframe { timeMs, easing, values { x, y, rotation, scale, opacity,
                                                 strokeWidth } }

SkeletonRig (projet de type `skeleton` uniquement, colonne JSON `projects.skeleton`)
 ├─ RigBone     { id, name, parentId, offsetX, offsetY, restAngle, length }
 ├─ BoneBinding { shapeId, boneId }              — rig maître : la pièce suit l'os
 └─ tracks      { boneId → [ BoneKeyframe { timeMs, easing, angleDelta
                    (+ opacity/stretch/squash v0.10) } ] } ; os : z, ik/bend
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

## 2 bis. Animation squelette (v0.9.0)

Un projet de type `skeleton` = un personnage : les pièces (formes) sont **toujours
visibles** (pas de fenêtre d'affichage) et l'animation passe entièrement par le rig.

- **Hiérarchie** : `RigBone.offset` est exprimé dans le repère de repos du parent
  (origine = articulation du parent, X le long du parent) ; `restAngle` est **relatif**
  au parent (monde pour la racine). Bouger/tourner un parent entraîne toute la chaîne,
  au repos comme à l'animation.
- **Rig maître (2a)** : la pièce liée est rendue sous la transformée
  `os(t) ∘ os(repos)⁻¹ ∘ pose_forme` — identité au repos. La pose de base de la forme
  (ses sliders) sert d'offset de repos : RIEN n'est figé à la liaison. Glisser une pièce
  liée écrit le décalage corrigé par `R(−worldDelta)` pour que la pièce suive le doigt.
- **FK** (`SkeletonPose.evaluate`) : parents résolus avant enfants ; angle monde =
  repos en chaîne + delta du parent + delta propre ; keyframes d'os = delta d'angle
  (même échantillonnage clampé que les poses de forme).
- **Édition** : glisser l'extrémité d'un os = rotation FK. Sans keyframe → écrit
  `restAngle` (pose du rig, relative à l'angle monde courant du parent) ; avec
  keyframes → auto-key de `angleDelta` au curseur (snap ~8 px).
- **Durée** : `maxKeyframeTimeMs`, avec plancher 4 s tant que le rig a au moins un os
  (le curseur doit rester déplaçable avant la première keyframe) ; 0 sans rig/os.
- **Timeline** : une barre verte par piste d'os (`packBoneLanes`, plage
  première→dernière keyframe) ; appui long = décaler la piste (`shiftTrackTo`,
  keyframes rabotées à zéro). Pas de poignées de fenêtre.
- **Overlay rig** : `RigOverlayPainter` en espace écran (segments + articulations +
  poignées d'extrémité), même `SceneGeometry` que `ScenePainter` (jamais exporté).
  Hit-test : extrémités d'abord (26 px écran), puis segments (13 px).
- **0.9.1+ fait** : liaison au niveau couche (`BoneBinding.layerId`), import
  d'un projet squelette comme instance dans un projet vectoriel (le painter
  sait déjà rendre un sous-projet squelette via `_paintProjectShapes`).

## 3. Persistance

sqflite, base `vector_anim_studio.db` (schéma v4) dans le dossier documents de l'application.

- `projects` : métadonnées du projet (dont `cover_path`, `created_at`, `updated_at`,
  `type` — `vector`/`skeleton` — et `skeleton`, le rig sérialisé en JSON)
- `shapes` : forme, fenêtre d'affichage, transformation de groupe, ordre (`z`)
- `layers` : formes basiques rattachées à une forme
- `shape_keyframes` : poses (`time_ms`, `easing`, `values_json` — les six propriétés)
- `PRAGMA foreign_keys = ON` + `ON DELETE CASCADE` pour supprimer proprement un projet

Le schéma est en **v4**. `onUpgrade` migre un schéma v1 (`tracks` + `keyframes` par
propriété) : chaque ancienne keyframe est échantillonnée sur les six propriétés pour
produire une pose, puis les tables `tracks` / `keyframes` sont supprimées. La v3 ajoute
les colonnes d'instance d'animation (`embedded_project_id`, `embedded_width`,
`embedded_height`). La v4 ajoute `type` (défaut `vector`) et `skeleton` (JSON) sur
`projects` — additif, aucun projet existant n'est modifié. Piège SQLite :
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
| JSON | projet complet, relisible par l'application | + « JSON simple (vasf) » pour agents IA, voir 5 bis |

Après export, `share_plus` partage le fichier (feuille de partage système).

## 5 bis. Format d'échange agents IA — VASF (v0.11.0)

`lib/engine/simple_animation_format.dart` — conversion bidirectionnelle projet
↔ JSON simple pour les agents IA. L'import (Export ▸ « Importer un JSON… »)
crée un NOUVEAU projet et collecte TOUTES les erreurs, affichées en français
avec leur chemin. Spec : `docs/vasf-1-format.md`, exemples :
`docs/vasf-1-examples.json` — import des exemples validé sur appareil le
26/09.

Principes v1 : secondes / degrés monde / couleurs hex ; une forme = UNE
primitive (couche locale neutre) ; keyframes partielles portées en poses
complètes ; squelette en coordonnées MONDE (os : joint + angle de repos,
keyframe `angle` = monde absolu → delta interne ; opacité/étirement/écrasement
par keyframe d'os, z, ik/bend) ; liaisons `bind` par NOMS ; défauts
720×1280 / 25 fps / `#14161C`.

Limites v1 : une primitive par forme, pas d'instances imbriquées, liaisons de
couche ignorées.

### vasf-2 — extensions VALIDÉES (26/09), par paquets de coût

**Groupe 1 — format seul, l'importeur développe (moteur inchangé) —
IMPLÉMENTÉ v0.12.0 (26/09) :**
- **Couches multiples par forme** : `layers[]` (couleur, remplissage,
  points, tailles + pose locale `x`/`y` par couche) — le moteur gère déjà
  les couches ; un personnage détaillé (yeux, bouche, reliefs) n'a plus
  besoin d'une forme par primitive. Export : `layers[]` pour les formes
  multi-couches (version 2), à plat sinon (version 1).
- **Palette d'alias** : `"theme": {"peau": "#FFE3C2", …}` puis
  `"color": "$peau"` — cohérence et retouche globale en 1 ligne.
- **Cycles** : `"cycle": {"repeat": N}` au niveau forme ET squelette
  (duplication des keyframes à l'import, période = dernier − premier
  temps, raccord : 1ʳᵉ keyframe répétée sautée si temps déjà posé).
- **Définitions réutilisables** : `"defs"` + `"ref"` (géométrie seule,
  surcharge par champ, pas de refs imbriquées ni de ref dans `layers[]`).

**Groupe 2 — petites additions moteur :**
- `scaleX`/`scaleY` séparés dans les keyframes de forme (squash non
  uniforme ; `scale` uniforme aujourd'hui).
- **Pivot de rotation** par forme (`pivot: [x, y]`) — portes, balances
  (sinon passage obligatoire par un os).
- **Easing personnalisés** (cubic-bezier) en plus des 5 courbes nommées.
- **Liaison de couche** exposée dans `bind` (la structure
  `BoneBinding.layerId` existe déjà, le format l'ignore).

**Groupe 3 — gros morceaux moteur :**
- **Morph de points** : animer `points` d'un path entre keyframes (visages,
  expressions, flammes) — interpolation point par point à ajouter au moteur.
- **Couleur animée** par keyframe de forme (coucher de soleil, rougeur,
  pulsation).
- **Translation d'os** (`dx`/`dy`) et **IK à plus de 2 os** (chaînes).

Compatibilité : tout en champs optionnels — un vasf-1 reste importable ;
`version: 2` marque les fichiers qui dépendent des extensions. Côté agent :
skill `generer-animation-json` (workspace nanobot) — génère le vasf-1 et le
valide (`scripts/validate_vasf.py`) ; à étendre à la v2 le moment venu.

## 6. Interface

1. **Accueil** (`home_screen`) : liste des projets, nouvel projet, projet d'exemple, renommage, duplication, suppression, état vide explicite.
2. **Éditeur** (`studio_screen`) : menus Formes / Animations / Calques / Export, canvas, timeline à rectangles, barre de lecture avec bouton ⎌ Annuler (20 dernières actions, pile de snapshots en session — ajout de forme, insertion d'instance, suppression, gestes et réglages inclus), sauvegarde différée. L'export MP4/GIF ouvre un dialogue de réglage des fps (`fps` = dernier choix).

La **durée du projet est dérivée du contenu** : `AnimationProject.durationMs` est un getter = max des `endMs` des formes (projet vide → 0) ; rien n'est fixé à la création (nom + format seulement) ; une forme posée au-delà de la fin courante étend le projet, supprimer la dernière forme le raccourcit ; la colonne DB `duration_ms` est réécrite à chaque save.
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
le segment (durée et keyframes conservées) **sans limite horizontale** : dépasser la fin
du projet l'étend (durée dérivée), un trou entre deux segments reste possible (même
ligne), et la timeline défile automatiquement sous le doigt quand le bord manipulé
atteint 95 % de la vue (`TimelineZoomState.followEdge`). La poignée droite étire la fin
sans borne haute (la durée s'étend) ; la poignée gauche reste bornée à ≥ 0. Le menu
Formes propose « Dupliquer » qui clone couches et keyframes à la même fenêtre (ids
régénérés).

## 7. Tests

- `test/repository_test.dart` : persistance réelle (sqflite ffi), sauvegarde/rechargement des poses à l'identique, remplacement sans duplication, suppression, duplication.
- `test/timeline_layout_test.dart` : empilement des lignes (chevauchements, réutilisation de ligne).
- `test/animation_test.dart` : interpolation des poses (toutes propriétés), easing, remplacement au même temps, auto-key, snap, presets, duplication de forme (ids régénérés, keyframes copiées), déplacement de segment (`shiftBy` — y compris au-delà de la fin : la durée dérivée s'étend, trous possibles sur une même ligne).
- `test/timeline_zoom_test.dart` : bornes de vue (500 ms – 30 min, s'adaptant aux projets plus longs), zoom ancré, défilement borné, suivi de la tête de lecture et de l'edge pendant un geste, mapping temps↔pixel.
- `test/widget_test.dart` : écran d'accueil (état vide, création de projet et retour à la liste) + undo d'ajout et de suppression de forme dans le studio (dépôt en mémoire : `sqflite_common_ffi` ne progresse pas dans la zone fake-async de `testWidgets`, donc la couche SQLite reste couverte par `repository_test.dart`).

## 8. Reste à faire

- **Fait (2026-09-23)** : validation de l'export MP4 sur un appareil réel (encodeur natif non testable sur le serveur) sur l'APK `0.2.0` (build 7). Export GIF et timeline (poignées début/fin, empilement des lignes) également validés le même jour.
- **vasf-2 (validé 26/09, voir 5 bis)** : extensions du format d'échange —
  **Groupe 1 livré en v0.12.0** (couches multiples, palette, cycles,
  définitions) ; restent groupes 2 et 3.
- Job iOS sur runner macOS dans le workflow GitHub Actions.
- Backlog fonctionnel : import SVG, édition de courbes de Bézier, export SVG animé, calques imbriqués, partage cloud, test de migration v1 → v2 sur une base réelle.
