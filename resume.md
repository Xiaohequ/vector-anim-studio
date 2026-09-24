# Résumé du projet — vector_anim_studio

Studio d'animation Flutter (Android) : projets multiples, formes composées de couches,
keyframes « pose », timeline zoomable, undo, export MP4/GIF/PNG/JSON — et depuis la
v0.9.0, l'**animation squelette** (rig maître).

- Repo : https://github.com/Xiaohequ/vector-anim-studio (privé, branche `main`)
- Workspace : `/root/.nanobot/workspace/vector_anim_studio`
- Dernière version : **0.9.1** (bugfix des 5 bugs v0.9.0 remontés en test
  appareil ; 101 tests verts, `flutter analyze` 0 problème)
- Détails techniques : `docs/PLAN.md` · Notes de version : `RELEASE_NOTES.md`

---

## ✅ Ce qui est fait

### Historique des versions
- **v0.1.4 → v0.5.0** : projets multiples persistés (sqflite), formes composées de
  couches, timeline à rectangles, export MP4 (MediaCodec) / GIF / PNG, preview direct
  sur canvas (drag/pinch/rotation, ⚙ bottom sheet), duplication de couche, 6 formes
  basiques supplémentaires, instances d'animation (imbriquer un projet, 1 niveau max).
- **v0.6.0 → v0.6.1** : duplication de forme avec keyframes, déplacement de segment
  par appui long, zoom temporel 500 ms–30 min, correction conversion px/ms des barres,
  pincement interruptible, scrub sur les barres.
- **v0.7.0** : durée dérivée du contenu (getter, plus de durée fixée), fps réglé au
  dialogue d'export, undo des 20 dernières actions (1 geste = 1 entrée, coalescing).
- **v0.8.0** : déplacement de segment sans limite (la durée s'étend), poignée droite
  sans borne haute, auto-scroll au bord de l'écran pendant les gestes, undo sur
  l'ajout de forme et d'instance.
- **v0.9.0 (squelette — validé en partie, bugs corrigés en v0.9.1)** :
  - Type de projet : **Animation vectorielle** (historique) / **Animation squelette**
    au choix à la création ; badge type + sous-titre « pièce(s) » sur l'accueil.
  - Rig maître (2a) par projet squelette : arbre d'os hiérarchique
    (`lib/models/skeleton.dart`), liaison pièce → os, os sélectionnés au toucher
    (extrémités d'abord, puis segments), overlay `RigOverlayPainter` en espace écran.
  - FK : glisser l'extrémité d'un os = rotation, les enfants suivent ; sans keyframe
    le glisser pose le rig (`restAngle` relatif au parent), avec keyframes → auto-key
    d'`angleDelta` au curseur (snap ~8 px, easings partagés avec les poses).
  - Timeline squelette : barre verte par os animé (`packBoneLanes`), appui long =
    décaler la piste, losanges supprimables près de la tête de lecture ; durée
    dérivée des keyframes avec plancher 4 s (curseur déplaçable avant la 1re pose).
  - Persistance v4 : colonnes `type` + `skeleton` (JSON) sur `projects` — migration
    additive, projets existants intacts ; duplication emporte le rig.
  - Undo couvre tout le rig ; export MP4/GIF/PNG/JSON OK sur les deux types.
  - Vérification empirique : rendu headless (test widget + RepaintBoundary → PNG) et
    mesure pixel par masques couleur — pièces et os alignés à <1,5 px.

---

## ⏳ En attente (bloquant la suite)

- **Validation v0.9.1 sur appareil réel** (APK `vector-anim-studio-0.9.1.apk`),
  scénario ciblé sur les 5 bugs corrigés :
  1. Projet Squelette → 2-3 pièces → timeline : les rectangles de pièces
     restent affichés AVANT et APRÈS la création d'un os.
  2. Mode rig : premier tap SUR une pièce, second tap ailleurs → message
     « os créé et lié » ; déplacer la pièce → l'os suit.
  3. Tourner un os sur le preview → fluide ; la pièce liée suit la rotation.
  4. Lier via Squelettes ▸ Lier la pièce… puis tourner l'os → la pièce suit.
  5. Playback → la tête de lecture avance (ex. 0,xx s / 4,00 s), pas 0 s / 0 s.
  6. Keyframes d'os (◆) : rotation auto-key, la pièce suit à la lecture.
  7. Export MP4 sur un projet avec keyframes d'os → l'animation est rendue.
- **Retours utilisateur** → le cas échéant patch v0.9.x.

---

## 🔜 Ce qui doit être fait (roadmap)

### v0.9.1 (livrée — bugfix des retours v0.9.0)
- Timeline : barres de pièces + barres d'os animés affichées ensemble.
- Ancrage automatique os↔pièce au premier tap du mode rig sur une pièce.
- Déplacer une pièce au repos → l'os suit (`translateBoneRest`) ; poser le
  rig (glisser d'os sans keyframes) → les pièces liées suivent
  (`carryBoundPieces`).
- Rotation d'os fluide (setState par update du geste).
- Playback : durée squelette incluant les pièces (plus de « 0 s / 0 s »).
- Bonus : poses des instances imbriquées échantillonnées au temps de boucle.

### v0.9.2 (décidé, pas entamé)
- **Liaison au niveau couche** : lier une couche précise (et plus seulement
  une forme entière) à un os + panneau d'offset d'attache.
- **Import d'une animation squelette dans un projet vectoriel** : « Formes ▸
  Insérer une animation… » liste les deux types ; le personnage riggé
  devient une instance animable (position/échelle/keyframes de forme) dans
  une scène. Le painter sait déjà rendre un sous-projet squelette
  (`_paintProjectShapes`) — il reste la sélection/insertion + garde-fou
  « 1 niveau d'imbrication ».
- Option proposée : test de rendu permanent en CI (capture PNG + comparaison).

### v0.10+ (proposé, non planifié)
- IK 2 os (bras/jambes) avec choix du sens du coude — leçon Chaperon : sur les rigs
  cartoon, les angles directs restent souvent plus lisibles.
- Ordre de dessin par os (z dans le rig), squash/stretch par os, opacité animable
  par os, reprise de préhension (recibler un binding à la keyframe).

### Backlog de long terme
- Signature release (keystore + secrets GitHub) et/ou App Bundle `.aab`.
- Job iOS sur runner macOS (même mécanisme de release).
- Import SVG, courbes de Bézier, export SVG animé, calques imbriqués.

---

## 📌 Environnement & pièges (pour reprendre sans rien casser)

- **Pas de toolchain Flutter locale** : tout passe par
  `scripts/flutter_docker.sh analyze|test` (image `cirruslabs/flutter`, démon Docker
  de l'hôte ; le CLI `docker` se réinstalle via `skills/env-init/scripts/init.sh`
  si le conteneur a été recréé).
- **Avant chaque push** : mettre à jour `RELEASE_NOTES.md` (lu tel quel par la CI
  comme description de la release) — sinon la release publie les notes de la
  version précédente (piège v0.6.0/0.6.1).
- **Push** : `git push https://${GITHUB_ACCES_TOKEN}@github.com/Xiaohequ/vector-anim-studio.git main` (branche `main`, pas de credential locale).
- **Ne pas lancer de process détaché** (`setsid`/`nohup`) dans le conteneur `--rm` :
  un daemon Gradle survivant verrouille `app/android/.gradle/.../fileHashes.lock`.
- **Pièges Flutter tests** : `find.byIcon(Icons.undo)` trouve l'`Icon`, pas
  l'`IconButton` → `find.widgetWithIcon(...)` ; `sqflite_common_ffi` ne progresse
  pas en fake-async → dépôt en mémoire pour `testWidgets`, SQLite réelle dans les
  `test()` classiques.
- **Pièges rig** : restAngle d'un enfant est RELATIF au parent ; la pièce liée est
  rendue sous `os(t) ∘ os(repos)⁻¹` — son slider = offset de repos (rien n'est figé
  à la liaison) ; l'overlay rig et la scène doivent partager le MÊME
  `SceneGeometry` (tailles de canvas identiques) sinon les os sont désalignés.
- Durée squelette : plancher 4 s tant que le rig a un os ; sans keyframe, exporter
  produit un clip statique de 4 s.
