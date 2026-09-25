# Résumé du projet — vector_anim_studio

Studio d'animation Flutter (Android) : projets multiples, formes composées de couches,
keyframes « pose », timeline zoomable, undo, export MP4/GIF/PNG/JSON — et depuis la
v0.9.0, l'**animation squelette** (rig maître).

- Repo : https://github.com/Xiaohequ/vector-anim-studio (privé, branche `main`)
- Workspace : `/root/.nanobot/workspace/vector_anim_studio`
- Dernière version : **0.10.1** (correctif : le glisser IK marche depuis toute
  sélection — enfant, parent ou aucune — et les boutons ⚙/✥ ne recouvrent plus
  l'effecteur ; 123 tests)
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

## ⏳ En attente

- **Validation sur appareil réel** : v0.10.0 (z d'os, opacité/étirement/écrasement
  par os, IK 2 os — glisser l'effecteur, inverser le coude). Les versions v0.9.1 →
  v0.9.5 (chaîne rigging complète) sont déjà validées sur appareil.
- Retours utilisateur → le cas échéant patch v0.10.x.

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

### v0.10.0 (livrée — pose avancée du rig)
- **Ordre de dessin par os (z)** : `RigBone.z` (slider −10…+10 dans ⚙ os) —
  les pièces du projet squelette sont triées par `zForShape` (os porteur,
  sinon MIN du z des os de couches), z égal → ordre timeline ; couches triées
  par `zOfLayer`.
- **Keyframes d'os étendues** : `BoneKeyframe.opacity/stretch/squash` +
  samplers `opacityAt/stretchAt/squashAt` (tenue hors plage, interp easing,
  neutre 1 sans piste) ; `upsertKeyframe` FUSIONNE (écrire l'angle n'écrase
  pas l'opacité déjà posée à la même keyframe).
- **FK stretch** : `BoneFrame.stretchX/stretchY` (le long/perpendiculaire),
  `tip` et `mapPoint` étirés, l'articulation des os enfants suit le stretch
  du parent ; painter : `_applyBoneDelta` = translate·rotate·scale·rotate·translate,
  opacité portée × pose des pièces.
- **IK 2 os** : `RigBone.ikEnabled/bendSign` ; `onlyChildOf` (enfant unique
  requis) ; `solveTwoBoneIk` vérifié numériquement ; geste `boneIk` — hit sur
  l'extrémité de l'ENFANT (avant la poignée de rotation), marqueur losange
  vert sur l'effecteur ; auto-key si l'os a des keyframes, sinon pose du rig
  (`restAngle` + `carryBoundPieces`) ; « Inverser le coude » dans la sheet.

### v0.10.1 (livrée — le glisser IK était mort selon la sélection)
- Deux causes du « rien ne se passe » en v0.10.0 :
  - le geste IK n'était armé QUE si l'os PARENT était sélectionné — taper le
    poignet sélectionne l'ENFANT → glisser mort ; v0.10.1 : le losange vert
    est une vraie poignée (parent OU enfant OU aucune sélection).
  - le bouton ✥ (ancré près de l'enfant sélectionné) recouvait l'effecteur et
    avalait le press → v0.10.1 : boutons ⚙/✥ rangés au joint du PARENT
    (le coude) quand l'enfant IK est sélectionné.
- 3 tests widget pilotant de vrais glissers (ScaleStart/Update) : piège harnais
  — `onScaleStart` ne démarle qu'APRÈS un déplacement > 18 px écran, avec le
  foyer DÉJÀ déplacé : premier move de 22 px écran (< slop IK 26) puis move de
  correction ; rig initial JAMAIS tendu à fond (L1+L2 > distance joint→effecteur)
  sinon toute cible est hors de portée (le solveur clampe, tip ≠ cible).

### v0.11+ (proposé)
- Reciblage de binding à la keyframe (reprise de préhension).
- IK à plus de 2 os ou IK de translation (membres isolées).
- Test de rendu permanent en CI (capture PNG + comparaison).

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
