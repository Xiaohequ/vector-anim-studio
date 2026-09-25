# Résumé du projet — vector_anim_studio

Studio d'animation Flutter (Android) : projets multiples, formes composées de couches,
keyframes « pose », timeline zoomable, undo, export MP4/GIF/PNG/JSON — et depuis la
v0.9.0, l'**animation squelette** (rig maître).

- Repo : https://github.com/Xiaohequ/vector-anim-studio (privé, branche `main`)
- Workspace : `/root/.nanobot/workspace/vector_anim_studio`
- Dernière version : **0.9.6** (liaison au niveau couche + import
  squelette→vectoriel avec badge de type ; 112 tests)
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

- **Validé sur appareil réel (25/09)** : toute la chaîne rigging v0.9.1 →
  v0.9.5 — barres de pièces + d'os sur la timeline, ancrage os sur pièce,
  attachement auto os→os avec confirmation, liaison pièce manuelle,
  re-parentage racine sans saut, poignée de rotation, ✥ poignée draggable,
  playback avec keyframes d'os, export MP4.
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

### v0.9.2 (livrée — rigging affiné, retours v0.9.1)
- **Ancrage du 2e os réparé** : v0.9.1 plaçait l'articulation d'un os enfant
  au DEUXIÈME tap (`scenePoint`) au lieu du premier (`joint`) → décalage.
- **Attachement auto os→os** : tap 1 priorité ① extrémité d'os (snap au
  poignet) ② segment d'os ③ pièce liée → l'os qui la porte ④ os sélectionné
  — l'ancrage posé suit le parent (FK). `boneBetween()` extrait dans
  models/skeleton.dart (testée, y compris parent animé).
- **Plus de liaison auto pièce→os à la création** (demande utilisateur) :
  la liaison reste manuelle (menu Squelettes ▸ Lier…).
- **Sélection exclusive** : sélectionner un os désélectionne la forme et
  inversement (tap, menus, geste de rotation d'os).
- **Boutons d'os sur preview** : ⚙ (sheet os) + ✥ (mode déplacement —
  glisser = translateBoneRest + carry, chaîne et pièces liées suivent).
- ⚙ des formes ancré à la pose rig-aware (shapePoseWithRig).
- Déplacer une pièce au repos : l'os suit ET la pièce suit le doigt
  (`_translateBoneFollow` = translation + emport des pièces collées).

### v0.9.3 (livrée — retours v0.9.2)
- **Re-parentage sans saut** : « racine » ne fait plus disparaître l'os et
  ses fils — `SkeletonRig.reparentBone(bone, newParentId, pose)` recalcule
  offset + restAngle dans le repère du NOUVEAU parent (l'os reste ancré sur
  place, la descendance suit, l'ancien parent ne l'entraîne plus).
- **Confirmation d'attachement** : si le nouvel os se rattache à un os
  (poignet/segment/pièce portée/os sélectionné) → dialogue
  « Attacher ? » ; non → os racine sur place ; dialogue fermé → rien créé.
- **Poignée de rotation dédiée** : sort de l'extrémité de l'os sélectionné
  (`rotationHandle`/`hitRotationHandle` dans rig_overlay_painter.dart,
  distance 26 px écran, slop 24 px) ; rotation via le 2e point désactivée
  (le geste boneRotate ne démarre que sur la poignée).
- **Déplacement one-shot** : ✥ arme le prochain glisser (aucun état collant)
  — `_onCanvasGestureEnd` désarme ; terminateur ✓ retiré pour ce mode.

### v0.9.4 (livrée — bugfix retours v0.9.3)
- **✥ sans effet corrigé** : le garde-fou de `_onCanvasGestureUpdate`
  (`shape == null && geste != boneRotate → return`) bloquait aussi boneMove
  — avec la sélection exclusive, un os sélectionné laisse la forme à null.
  Exemption étendue à boneMove + test widget (armer → glisser → translation
  de l'ancrage → désarmement auto au relâchement).

### v0.9.5 (livrée — choix utilisateur : ✥ = poignée draggable)
- Le bouton ✥ devient la POIGNÉE de déplacement : appui + glisser sur le
  bouton → l'os suit le doigt en direct (`_onBonePanStart/Update/End`, delta
  écran → scène par geo.scale, `_translateBoneFollow` pour chaîne + pièces).
- Plus de mode armé : `_boneMoveMode`, `_toggleBoneMove`, le geste canvas
  `boneMove` et le désarmement auto supprimés — un tap sur ✥ ne fait rien.
- Le bouton reste ancré à l'os (il « colle » au doigt pendant le glisser).
- Undo : 1 glisser = 1 entrée (snapshot au panStart, poussé au panEnd).

### v0.9.6 (livrée — liaison par couche + import squelette)
- **Liaison au niveau couche** : `BoneBinding.layerId` (null = forme
  entière, back-compat JSON) ; `bindingForLayer/bindLayer/unbindLayer` +
  `bindingForShape` NE capture plus les liaisons de couche (sinon double-transport).
- **Painter par couche** : la transformée os (coordonnées projet) enveloppe
  la chaîne pose forme ∘ couche — appliquée AVANT la pose de la forme, par
  couche (couche liée → son os ; sinon liaison de forme).
- **carryBoundPieces** : couche liée → transport de son ancrage MONDE puis
  réécriture dans le repère de la forme (couches non animables, base).
- **Sheet forme** : section « Couches liées au rig » (une ligne par couche,
  os porteur + Lier…/Délier) ; dialogue `_pickBone` partagé avec la liaison
  de pièce.
- **Duplication** : `duplicateBindings(shape, clone, layerIdMap)` remappe
  les ids de couches régénérés.
- **Import squelette→vectoriel** : le mécanisme existait (menu + painter
  récursif + garde-fou depth>=1) — vérifié par test widget (instance de
  squelette animé dans un vectoriel, lecture sans plantage) + badge de type
  dans le sélecteur (label type · durée · pièces).

### v0.9.7 (décidé, pas entamé)
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
