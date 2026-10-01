# Résumé du projet — vector_anim_studio

Studio d'animation Flutter (Android) : projets multiples, formes composées de couches,
keyframes « pose », timeline zoomable, undo, export MP4/GIF/PNG/JSON — et depuis la
v0.9.0, l'**animation squelette** (rig maître).

- Repo : https://github.com/Xiaohequ/vector-anim-studio (privé, branche `main`)
- Workspace : `/root/.nanobot/workspace/vector_anim_studio`
- Dernière version : **0.21.1** (corrections timeline/preview : la visibilité
  respecte `startMs → endMs` même pour les pièces liées à un os, une forme
  sélectionnée désélectionne l'os précédent ; 257/257 tests ; CI run #49
  verte ; release `v0.21.1-build49`, APK 54,1 Mo publiée).
- **v0.20.3 VALIDÉE APPAREIL (01/10)** — retour : « je valide v0.20.3 ».
  (un seul os par forme dans l'éditeur, pivot, bouton feuille d'os).
- v0.20.2 (retours v0.20.1 : **pivot de l'os** dans l'éditeur (glisser
  l'EXTRÉMITÉ = pivoter, le MILIEU = déplacer), **sélecteur de forme
  masqué**, bouton **« Ouvrir l'éditeur d'os… »** dans la feuille
  Propriétés de l'os ; 257/257 tests ; commit `e1752b8`, CI run #46
  verte, release `v0.20.2-build46`, APK 54,1 Mo).
- v0.20.1 (bugfix — la section os de la feuille ⚙ était conditionnée à
  l'existence du rig, donc INVISIBLE sur un projet squelette neuf :
  désormais conditionnée au type de projet ; 254/254 tests ; commit
  `9b85334`, CI run #45 verte, release `v0.20.1-build45`, APK 54,1 Mo —
  **retour appareil : accès éditeur ok, glisser sans bouger la forme ok**).
- v0.20.0 (vague 1 — « l'os n'existe que par une forme » : **nouvel éditeur
  d'os** (forme seule centrée, dessin en 2 taps, déplacement de l'os sans
  bouger la forme), boutons **Ajouter / Modifier / Supprimer l'os** dans la
  sheet ⚙, **confirmation avant effacement** des keyframes de transform
  (morph/couleurs/opacité conservés), **menu Squelette supprimé** ;
  253/253 tests ; commit `1c08626`, CI run #44 verte, release
  `v0.20.0-build44`, APK 54,1 Mo — **retour appareil : bouton d'ajout
  d'os introuvable → corrigé en v0.20.1**).
- v0.19.1 (pièce portée par un os = plus aucune manipulation au doigt :
  **non sélectionnable** au tap, déplacement / rotation / échelle bloqués,
  sliders X/Y/rotation/échelle verrouillés ; seul l'os, ou une
  dissociation, la bouge ; 247/247 tests ; commit `29b470e`, CI run #43
  verte, release `v0.19.1-build43`, APK 54,1 Mo — **VALIDÉE APPAREIL :
  déplacement / rotation / échelle verrouillés OK**).
- v0.19.0 (miroir H/V d'un groupe de couches — drapeaux `flipH`/`flipV`,
  schéma DB v7, format vasf v4 ; CI run #42 verte, release
  `v0.19.0-build42`, APK 54,1 Mo — **VALIDÉE APPAREIL : miroir OK**).
  v0.17.0 (pipeline agents — aperçu headless officiel via le vrai moteur,
  import strict, cycles par os). v0.16.3 (bugfix — le curseur de l'éditeur
  démarre au playhead du STUDIO) **VALIDÉE APPAREIL 28/09 : le morphing
  marche**.
  v0.16.2 (morph — 1ᵉʳ glisser = 1ʳᵉ pose, ◆ dans l'éditeur,
  snack, aide). v0.16.1 (bugfix — ◆ de la playbar anime la PIÈCE d'un
  projet squelette ; sheet ⚙ des pièces avec ◆ + Interpolation). v0.16.0 = éditeur de points
  in-app (poignées, curseur de temps, auto-key morph). v0.15.0 (vasf-3 : couleur animée, morph de
  points, translation d'os, IK chaînes N os, schéma DB v6). v0.14.0
  (import par fichier, reciblage, rendu CI) et v0.13.2 (persistance
  pivot/axes/bézier, schéma v5) validées appareil le 27/09.
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

## ✅ Validé sur appareil

- **v0.19.1 (30/09)** : pièce liée à un os = transformations verrouillées
  — « verrouiller déplacement, rotation, échelle forme marche ».
- **v0.19.0 (30/09)** : miroir H/V — « miroir marche » (contenu reflété,
  forme en place, keyframes/pivot intacts, double appui = retour).
- **v0.10.1 (25/09)** : la chaîne rigging complète v0.9.1 → v0.9.5 ET la
  v0.10.1 (z d'os, opacité/étirement/écrasement par os, **IK 2 os
  opérationnel** — « Ça a marché »).
- **v0.11.0 (26/09)** : format d'échange vasf-1 — les JSON exemples
  (`docs/vasf-1-examples.json` : balle rebondissante + squelette saluant)
  s'importent correctement sur appareil via « Importer un JSON… ».
- **v0.12.0 (26/09)** : vasf-2 Groupe 1 (couches multiples, palette d'alias,
  cycles, defs+ref) validé par l'utilisateur.
- **v0.13.2 (27/09)** : pivot de rotation persistant (schéma SQLite v5) —
  configuré sur l'appareil, lisible dans la sheet et présent dans le JSON
  exporté ; JSON exporté depuis l'exemple G2 comparé à la source :
  conforme (pivot, scaleX/scaleY par keyframe, cubic-bezier, liaison de
  couche `Lampadaire/Lampe` → `Tête`, coordonnées monde du squelette,
  cycles développés en timelines équivalentes).
- Retours utilisateur → le cas échéant patch v0.13.x.

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

### v0.21.0 (vague 2 — la timeline)
- **Demande** : « afficher l'os dans timeline », « ne plus afficher de
  nouveau segment pour les keyframes de l'os », « segment d'une forme avec
  os = couleur différente », « segment sélectionné → l'os sélectionné dans
  le preview ».
- **Pistes d'os SUPPRIMÉES** : `TimelineLayout.packBoneLanes` retiré du
  modèle, `_BoneBar` + son bloc de déplacement (`_movingBone`,
  `_handleBoneMove*`, `_cancelBoneMove`) supprimés de la vue, params
  `onBoneMoveChanged/onBoneMoveEnd/onBoneGestureStart` retirés de
  `TimelineView` ET du studio ; `laneCount = lanes.length` (une ligne par
  pièce).
- **Keyframes de l'os sur le segment lié** : `_shapeBar()` calcule le
  porteur (`rig.carrierBoneId`) et alimente `_ShapeBar(rig:, carrier:)` →
  `keyTimes` = piste de l'OS si lié, sinon celles de la forme ;
  `onDeleteKeyframe` route vers `onDeleteBoneKeyframe` (segment lié) ou
  `onDeleteKeyframe` (libre).
- **Couleur** : segment lié = vert `0xFF3ECF8E` (vs bleu primaire /
  violet instance).
- **Sélection** : clic sur un segment lié → `onSelectBone` → le studio
  fait ` _selectedBoneId = bone.id; _selectedId = null` (sélection
  exclusive — **fix** : avant, `onSelectBone` ne vidait pas la sélection de
  forme) ; le segment se surligne aussi quand c'est SON os qui est
  sélectionné (`selectedBoneId`).
- **Conséquence notée dans les notes de release** : morph/couleurs/
  opacité d'une pièce liée restent dans le modèle mais ne sont plus
  affichés/supprimables depuis la timeline (éditables via feuille ⚙ et
  éditeur de forme).
- **Tests : 255/255** (−2 `packBoneLanes` ; le test « barre d'os » devient
  « segment lié : keyframes de l'os, couleur, clic = os sélectionné » et
  vérifie les 4 exigences), analyze 0.
- **Livraison** : commit `5aa77ae`, CI run #48 VERTE, release
  `v0.21.0-build48` (`vector-anim-studio-0.21.0.apk`, 54,1 Mo).

### v0.20.3 (retour v0.20.2 — un seul os par forme)
- **Retour** : « Éditeur os : ne pas autoriser d'ajouter plusieurs os » →
  `_onTapUp` rend dès que `_bones.isNotEmpty` : la forme a SON os, plus
  aucun ajout ; indice dédié (« La forme a déjà son os — glisser au MILIEU
  = le déplacer, sur son EXTRÉMITÉ = le pivoter »).
- **Déplacement et pivot inchangés** (gestes d'échelle, pas des taps) ;
  ✓ livre toujours l'unique os lié.
- **Conséquence D.1** : on ne CRÉE plus de chaîne d'os depuis l'éditeur
  (la règle 1 forme = 1 os prime) — une chaîne importée reste éditable
  (déplacer/pivoter chaque os).
- **Résolution du chaînage (choix utilisateur 01/10)** : l'option 2
  (bouton explicite « + os enfant ») est **ANNULÉE — rien à développer**.
  Le chaînage passe par la propriété **« Os parent »** de la feuille
  Propriétés de l'os, DÉJÀ LIVRÉE : avec ≥ 2 formes (1 os chacune), le
  listbox propose tous les os sauf soi-même et ses descendants →
  `reparentBone` (ancrage préservé, liaisons intactes), couvert par 2
  tests `reparentBone` (racine / autre os).
- **Tests : 257/257** (le test « chaîne » devient « un seul os » :
  2ᵉ tentative refusée + indice, résultat = 1 os lié), analyze 0.
- **Livraison** : commit `58d17fe`, CI run #47 VERTE, release
  `v0.20.3-build47` (`vector-anim-studio-0.20.3.apk`, 54,1 Mo).

### v0.20.2 (retours v0.20.1 — pivot, sélecteur, accès feuille d'os)
- **Retour** : « Éditeur os : os possible de pivoter » → le glisser est
  devenu AMBIGU selon le point de départ : **extrémité** (dans
  `tipTouchSlop` 26 px) = pivot (`_rotating`, `restAngle += delta` avec
  delta incrémental normalisé ±π — relatif au parent, donc FK correcte),
  **segment** = déplacement (inchangé). Indice sous le preview à jour.
- **Retour** : « ne pas afficher le sélecteur de la forme » →
  `selectedShapeId` retiré + `showFrame: false` dans l'éditeur.
- **Retour** : bouton dans la **feuille Propriétés de l'os** →
  `onOpenEditor` (nouveau paramètre de `BonePropertiesSheet`) →
  `_editBoneInEditor()` retrouve la forme portée par l'os (racine OU
  descendance via `chainFrom`) puis enchaîne sur `_editShapeBone` ; os sans
  forme → snack explicite.
- **Tests : 257/257** (+3 : aucun sélecteur, pivot articulation fixe +
  forme immobile, bouton de la feuille d'os → éditeur), analyze 0.
- **Piège de geste (corrigé)** : le hit ET le mode (pivot/déplacement) se
  décident sur la position d'appui BRUTE (`Listener.onPointerDown` →
  `_downPos`) — le foyer de `onScaleStart` est déjà déplacé par la slop
  (18-45 px) et sortait à la fois de la zone d'extrémité (pas de pivot) et
  de l'os (hit nul) ; l'ANGLE de référence, lui, est pris au foyer courant
  pour absorber la slop (pas de saut au démarrage).
- **Livraison** : commit `e1752b8`, CI run #46 VERTE, release
  `v0.20.2-build46` (`vector-anim-studio-0.20.2.apk`, 54,1 Mo).
- **Validé v0.20.1** : accès éditeur ok, glisser os sans bouger la forme ok.

### v0.20.1 (bugfix : bouton « Ajouter un os… » introuvable)
- **Retour appareil v0.20.0** : « pas de bouton pour ajouter un os sur une
  forme » — la section os de la sheet ⚙ testait `skeletonRig != null`, or
  un projet squelette NEUF a `project.skeleton == null` (le rig naît à la
  validation de l'éditeur) → bouton invisible, parcours bloqué dès le
  premier os.
- **Fix** : condition au TYPE de projet (`widget.skeletonPiece`), plus à
  l'existence du rig — « Aucun os » + « Ajouter un os… » affichés d'entrée ;
  « Modifier/Supprimer l'os » restent conditionnés à un os réel.
- **Retour aussi** : le bouton « Squelette » du bas remplacé par
  « Animations » = **normal** (D.4) ; les actions d'os vivent dans la sheet ⚙
  (ajout/modif/suppression) et sur le canvas (tap = sélection d'os,
  ✥/rotation/IK = animation, ◆ de la playbar cible l'os).
- **Tests : 254/254** (+1 non-régression : projet squelette neuf → bouton
  présent → éditeur ouvert, rig créé au ✓), analyze 0.
- **Livraison** : commit `9b85334`, CI run #45 VERTE, release
  `v0.20.1-build45` (`vector-anim-studio-0.20.1.apk`, 54,1 Mo).

### v0.20.0 (vague 1 — l'os n'existe que par une forme)
- **Demande utilisateur** : os affiché via la forme, éditeur d'os dédié,
  keyframes de forme remplacées par celles de l'os, segment coloré,
  menus ajustés, suppression d'os, sélection par segment, effacement avec
  confirmation. **Décisions** : D.1 chaînes d'os conservées, D.2 effacer
  les TRANSFORMS seul, D.3 import vasf inchangé (autre version), D.4 menu
  Squelette supprimé, D.5 ✥/rotation/IK gardés dans le studio.
- **Nouvel éditeur d'os** (`ui/bone_editor_screen.dart`) : ouvert depuis la
  sheet ⚙ (« Ajouter un os… » / « Modifier l'os… ») ; contient la SEULE
  forme, **centrée/ancrée au milieu de l'écran** (canvas = bbox ×1,6 de la
  pièce, forme recopiée au centre du canvas éditeur) ; tap ① articulation
  (aimantée au poignet/segment d'un os existant → chaînes/IK ✓) puis tap ②
  extrémité ; glisser un os = `translateBoneRest` **SANS** `carryBoundPieces`
  → l'os bouge, la forme reste ancrée ; ✓ = `BoneEditorResult` (os en
  coords PROJET — conversion par `_shift` sur les RACINES recalculées à la
  sauvegarde, pas à l'ouverture).
- **Liaison + effacement contrôlé** : `_editShapeBone` montre le dialogue
  « Lier la pièce à un os ? » AVANT d'ouvrir l'éditeur si
  `transformKeyframeCount > 0` ; à la liaison, `clearTransformKeyframes()`
  efface position/rotation/échelle et garde morph/couleurs/opacité (les
  keyframes vides sont supprimées) ; sélection exclusive → l'OS porte la
  pièce.
- **« Supprimer l'os »** (sheet ⚙) : dialogue annonçant n os + m
  keyframes, puis `SkeletonRig.removeBoneForShape()` = os porteur +
  TOUTE descendance + `tracks` + `bindings` (la pièce redevient
  sélectionnable).
- **Menus/studio** : `_skeletonsMenu` supprimé (le bas de barre affiche
  Formes + Animations en projet squelette), mode rig 2-taps du canvas
  supprimé (`_startAddBone`/`_finishAddBone`/`_addBoneMode`/…), liaisons de
  couche sorties de la sheet (`_buildRigLayerRows` retiré, callbacks
  `onBindLayer`/`onUnbindLayer` remplacés par `onOpenBoneEditor` /
  `onDeleteBone`), `_renameRig`/`_deleteRig` supprimés (rig = interne).
- **Tests : 253/253** (+6 : `bone_editor_test.dart` ×4, `widget_test` ×2),
  analyze 0. **Pièges harnais** : `find.byTooltip` renvoie `RawTooltip` →
  `find.widgetWithIcon(IconButton, Icons.check)` ; la liste `const` d'os
  refuse l'ajout (`List.of`) ; taps en coords CANVAS vs os en coords SCÈNE
  (`geo.canvasToScene`) ; le 1ᵉʳ move d'un geste est avalé par la slop
  (18 px) — il faut un 2ᵉ move pour voir le déplacement ; `canvasHarness`
  doit être déclaré AVANT les tests qui l'utilisent (fonction locale).
- **Livraison** : commit `1c08626`, CI run #44 VERTE, release
  `v0.20.0-build44` (`vector-anim-studio-0.20.0.apk`, 54,1 Mo) —
  **validation appareil en attente**.
- **Vague 2 (prochaine release)** : timeline — pistes d'os supprimées,
  losanges d'os sur le segment de la forme liée, segment coloré,
  sélection du segment → os sélectionné.

### v0.19.1 (pièce portée par un os : plus aucune manipulation au doigt)
- **Demande utilisateur** : « ne pas déplacer une forme quand la forme est
  associée à un os — seul déplacement autorisé via l'os ou après
  dissociation », puis « verrouiller aussi la rotation et échelle,
  rendre la forme non sélectionnable ».
- **Détection** : `SkeletonRig.isAttached(shapeId)` + `carrierBoneId`
  (liaison de la forme entière, sinon la 1ʳᵉ couche liée de cette forme).
- **Geste canvas** : garde UNIQUE dans `_onCanvasGestureStart`, placée
  AVANT les branches échelle / rotation / déplacement → tout geste de
  transformation est refusé (`_gesture = none`, aucun snapshot d'undo).
  `_snack` nommant l'os seulement si le doigt est SUR la pièce. Les
  gestes d'os (IK, poignée ✥, rotation d'os) sont traités AU-DESSUS et
  restent libres.
- **Non sélectionnable** : dans `_onCanvasTapUp`, le tap sur une pièce
  liée n'élève pas la sélection + message « non sélectionnable » ; le menu
  Formes la choisit quand même (passerelle obligatoire pour la sheet ⚙ et
  pour Squelettes ▸ Délier, sinon dead-end).
- **Sheet ⚙** : `transformLocked` (jeu `_transformProperties`) désactive
  Position X/Y, Rotation, Échelle, Échelle X/Y ; rappel ambre AU-DESSUS
  des sliders (construit avant → visible même avec la liste paresseuse).
  Opacité et Épaisseur restent libres.
- **Changement de comportement** : le glisser d'une pièce liée AU REPOS ne
  déplace plus l'ancrage de l'os (v0.9.5 « l'os suit la pièce ») — le
  verrou prime ; déplacer l'ancrage = poignée ✥ de l'os.
- **Tests : 247/247** (+11 : 7 dans `bound_shape_lock_test.dart` = 3
  modèle + 4 sheet, 4 dans `widget_test.dart` = glisser bloqué + témoin
  non lié, tap non sélectionnable, pincement bloqué, rotation par poignée
  bloquée), analyze 0.
- **Pièges harnais (les 4 tombés en debug)** : ① la preview du studio est
  clamped à ~200 px en fenêtre 800×600 (échelle 0,159) → mettre
  `tester.view.physicalSize` en HAUTEUR (800×1400 → ~366 px, échelle
  0,286) ET une pièce assez grande (400×300) pour que le pointeur reste
  dedans après la slop (18 px) — sinon `SelectionGeometry.hit` est faux
  et « rien ne se passe » sans erreur ; ② `_load()` AUTO-SÉLECTIONNE la
  dernière forme au chargement → un test de « non sélectionnable » doit
  d'abord désélectionner (tap sur l'OS, sélection exclusive) ; ③ le
  SnackBar apparaît en BAS et recouvre la barre d'outils → pomper 5 s
  avant d'utiliser un menu (sinon le tap tombe sur le message, et
  `find.textContaining('Bloc')` matche même le texte du snack) ; ④ l'os
  de test doit être LOIN de la pièce (`segmentTouchSlop` 13 px,
  `tipTouchSlop` 26 px : sinon le tap sur la pièce est absorbé par l'os).
- **Livraison** : commit `29b470e`, CI run #43 VERTE, release
  `v0.19.1-build43` (`vector-anim-studio-0.19.1.apk`, 54,1 Mo) —
  **VALIDÉE APPAREIL : « verrouiller déplacement, rotation, échelle
  forme marche »** (le tap non sélectionnable n'est pas mentionné dans le
  retour).
- Hors périmètre (à décider) : les couches d'une pièce liée restent
  déplaçables dans l'éditeur de forme (X/Y de couche).

### v0.19.0 (miroir H/V d'un groupe de couches)
- **Boutons « Miroir H » / « Miroir V »** dans la sheet ⚙ de la forme
  (`onMirror` → `_mirrorShape` : 1 pression = 1 entrée d'undo + save
  différée ; pas d'instance — aucune couche) : `VectorShape.mirror()`
  négue, par couche, `x` (H) ou `y` (V) ET la rotation, et bascule le
  drapeau `flipH`/`flipV`.
- **Rendu** : `ScenePainter` ajoute `scale(−1|1, −1|1)` après la pose de
  la couche → le contenu (primitive, path, points de base ET nuages de
  morph) est réfléchi autour de l'origine de la couche. La composition
  action ∘ flip est l'identité sur le contenu → **points/keyframes
  intacts**, auto-inverse au 2ᵉ appui. Testée par 3 sondes pixel
  (centroid de masque : miroir H, miroir V, morph à travers le flip).
- **Éditeur de points** : poignées reflétées (`pointHandlePositions`
  multiplie par le flip) et delta de glisser / point inséré reconverti
  dans le repère des données (réflexion auto-inverse).
- **Persistance** : schéma **v7** (`flip_h`/`flip_v` sur `layers`, ALTER
  additif) — leçon v0.13.2 appliquée dès le départ ; format **vasf-4**
  (`flipH`/`flipV` à plat ou dans `layers[]`, émis seulement si vrais,
  `version: 4` ; import 1→4, 5 → « version : 1, 2, 3 ou 4 attendu »).
- **Docs/skill** : spec + section « Mirror — flipH/flipV », skill
  `generer-animation-json` (SKILL.md + references + validateur
  `validate_vasf.py` + `preview_vasf.py`) alignés.
- Tests : **236/236** (+12 dans `test/mirror_test.dart`, test de version
  de `simple_format_test.dart` passé de 4→5), analyze 0 problème.
- **Livraison** : commit `6c1c078`, CI run #42 VERTE, release
  `v0.19.0-build42` (`vector-anim-studio-0.19.0.apk`, 54,1 Mo) —
  **VALIDÉE APPAREIL : « miroir marche »**. (Les pushes de `.md`/`docs/**`
  ne déclenchent pas la CI : `paths-ignore` du workflow.)
- **Numérotation (choix utilisateur)** : livré en **0.19.0**, PAS 0.18.0 —
  les releases `v0.18.0/0.18.1/0.18.2` (branche `archive-v0.18x`, main
  remise à 0.17 le 30/09) sont déjà publiées sur GitHub ; un second
  0.18.0 aurait deux releases homonymes à contenu différent.
- **Skill/validateur laissés « en avance » (choix utilisateur, option B)** :
  `SKILL.md`, `validate_vasf.py` et `preview_vasf.py` décrivent encore la
  v0.18 archivée (start/end supprimés, alpha `#AARRGGBB` honoré, carry des
  keyframes d'os) que l'app NE fait pas → le validateur émet un
  avertissement « start/end ignorés (supprimés en v0.18) » alors que
  l'app les applique encore, et le preview n'est plus fidèle sur ces
  points. À réaligner (ou à implémenter) au prochain lot ; seules les
  mentions du MIROIR ont été renumérotées v0.19.

### v0.17.0 (29/09, pipeline agents : aperçu headless officiel + import strict + cycles par os)
- **Aperçu headless OFFICIEL** (`test/vasf_preview_test.dart`) : rend un
  JSON vasf avec le VRAI `ScenePainter` → planche PNG + frames pleine
  résolution dans `tmp/vasf_preview/`. À la demande par env
  (`VASF_PREVIEW_INPUT/OUT/TIMES/SCALE`), no-op en CI normale ;
  `flutter_docker.sh` transmet les variables. L'import qui échoue fait
  échouer le test avec les erreurs françaises — même diagnostic que
  l'appli. Remplace l'approximation FK pycairo (`tmp/preview_petit_prince.py`).
- **Import strict** : tout champ inconnu (racine/canvas/forme/os) est
  refusé avec chemin + nom (avant : silence → liage perdu, planète
  immobile) ; champ `bone` sur une forme = raccourci de bind (conflit
  avec `skeleton.bind` → erreur ; sans squelette → erreur).
- **Keyframes/cycle embarqués dans un os** : acceptés et fusionnés
  (sémantique `skeleton.keyframes`, `bone` implicite — avant : ignorés
  en silence). **Cycle PAR OS** : chaque os répète SON motif (période =
  dernier − premier de ses keyframes) ; `skeleton.cycle` global épargne
  les os à cycle propre → marche ×9 + rotation lente coexistent (42
  keyframes au lieu de 330 sur le Petit Prince).
- Format + validateur Python + skill `generer-animation-json` alignés ;
  exemples officiels revalidés. Dogfood : Petit Prince régénéré avec
  cycle par os, aperçu réel vérifié (rose t=3, baobab t=9, bottes au
  sol). +8 tests — 224/224, analyze 0.

### v0.16.0 (27/09, CI run #34 verte, release `v0.16.0-build34`, APK 51,6 Mo — éditeur de points in-app ; commit `dd53e6b`)
- **Poignées de points** (éditeur de forme, couche Chemin sélectionnée) :
  cercles blancs en espace écran (`ScenePainter.showLayerPoints` +
  `activePointIndex` orange pendant le glisser — jamais en export) ; le
  nuage affiché = échantillon au temps AFFICHÉ du nouveau curseur.
- **Curseur de temps** : slider sous le preview, pas de 50 ms, borné à la
  fenêtre de la forme ; toutes les poses/poignées échantillonnent à
  `_previewMs` (les couches restent statiques — x/y/rotation/scale de
  couche n'auto-keyent PAS dans l'éditeur, seuls les POINTS).
- **Auto-key morph** : `VectorShape.applyLayerPoints` (miroir de
  `applyLayerColor`) — sans keyframe → écrit la base ; avec keyframes →
  nuage complet dans la pose au curseur, SEMÉ du rendu courant
  (`pointsAtLayer` à la cible — l'extrémité du segment interpolé garde sa
  valeur : semer est visuellement neutre) ; pose numérique, easings,
  couleurs et morph des autres couches préservés ; snap `keyframeNear` à
  la tolérance de la timeline (80 ms pour 4 s).
- **Ajouter un point** (bouton ✚ du preview) : toucher un segment à
  ≤ 28 px écran insère le point tapé dans la base ET chaque nuage de morph
  au MÊME index (`insertLayerPoint` — correspondance positionnelle
  préservée, morph plat au nouveau point) ; une activation = une
  insertion. **Supprimer** : appui long sur une poignée → base + nuages au
  même index (`removeLayerPoint`, nuages plus courts ignorés).
- **Robustesse** : `ShapeLayer.points` est TOUJOURS une liste modifiable
  (normalisation `List.from` au constructeur — les listes const passées
  par les littéraux par défaut/import ne cassent plus l'insertion).
- **Géométrie** : `SelectionGeometry.canvasToLocal` (inverse exact de
  `localToCanvas`, pivot inclus), `pointHandlePositions`,
  `hitPointIndex`, `nearestClosedSegment` (chemin fermé, segment de
  fermeture = insertion en fin), `distanceToSegment` ; hit des poignées
  sur la position BRUTE du doigt (`_downPos` du Listener — la
  reconnaissance du geste arrive le foyer déjà déplacé, piège v0.10.1).
- Tests : **209/209** (+15 unitaires modèle/géométrie/vasf round-trip,
  +5 widget : glisser auto-key, base sans keyframe, appui long, mode ✚,
  légende) ; analyze 0 problème. Piège harnais de test :
  `find.byType(Listener).first` = un Listener interne Material plein écran
  (800×600), PAS le preview — viser le CustomPaint dont le painter est un
  `ScenePainter` (un seul par écran).

### v0.16.3 (27/09, CI run #37 verte, release `v0.16.3-build37`, APK 51,6 Mo ; commit `368502c` — bugfix : curseur de l'éditeur = playhead du studio) — VALIDÉE APPAREIL (28/09) : le morphing marche
- **Symptôme (retours v0.16.2)** : le snack affiche toujours « Pose à
  0,00 s enregistrée (morph) » même en éditant une keyframe à 2 s.
- **Cause** : le curseur du preview de l'éditeur était initialisé à
  `_draft.startMs` (0 s), INDÉPENDANT du playhead du studio. Scrubber le
  studio à 2 s puis ouvrir l'éditeur remettait le curseur à 0 — le
  glisser de point écrivait donc TOUTES les poses à 0 s (le snack était
  honnête). C'était aussi la vraie cause du « pas de morphing » v0.16.2 :
  les nuages s'accumulaient sur la pose 0 au lieu de se répartir.
- **Fix** : `ShapeEditorScreen.initialTimeMs` — `_editShape` passe le
  `controller.timeMs` du studio, borné à la fenêtre de la forme dans
  initState ; l'instant scrubé reste affiché dans l'éditeur, l'auto-key
  morph écrit bien à CET instant (snack « Pose à 2,00 s »).
- **Test** (+1 widget, 215/215) : ◆ pièce à 0 s → scrub studio 2 s →
  sheet ⚙ → éditeur (label « 2,00 s ») → glisser une poignée → pose
  écrite À 2000 ms, pose 0 intacte. Piège : `_editShape` REMPLACE
  l'objet pièce par le brouillon (`project.shapes[index] = edited`) —
  relire `project.shapes.first`, pas la référence d'avant l'éditeur.

### v0.16.2 (27/09, CI run #36 verte, release `v0.16.2-build36`, APK 51,6 Mo ; commit `6a4a464` — morph : auto-key visible dans l'éditeur) — VALIDÉE APPAREIL (28/09, via le morphing opérationnel en v0.16.3)
- **Symptôme (retours v0.16.1)** : en changeant les points d'un chemin,
  aucune keyframe n'était ajoutée automatiquement — et en éditant sur une
  pose, la modification restait sans morphing à la lecture.
- **Cause (double)** : ① sans AUCUNE keyframe sur la pièce, le glisser
  édite les points de BASE en silence (comportement v0.16.0) — les
  keyframes visibles sur la timeline étaient celles des OS, pas de la
  pièce, d'où l'attente d'auto-key déçue ; ② une seule pose portant le
  morph fige la forme ailleurs (carry de la dernière pose) — il faut
  DEUX poses pour interpoler, ce qui n'était découvrable nulle part.
- **Fix éditeur** : ① pièce d'un projet SQUELETTE sans aucune keyframe →
  le premier glisser CRÉE la 1ʳᵉ pose au curseur, semée du rendu courant
  (visuellement neutre, base intacte) ; ② bouton ◆ dans la ligne du
  curseur du preview — poser/retirer une pose à n'importe quel instant
  sans retourner au studio (toggle keyframeNear, même sémantique) ;
  ③ snack « Pose à X,XX s enregistrée (morph) » au relâchement quand le
  glisser a écrit une pose ; ④ aide contextuelle dynamique sous le
  curseur : dessin de base (vectoriel sans keyframe) / auto-création
  (pièce squelette) / « une seule pose = forme figée » / morph actif.
- **Chaîne vérifiée de bout en bout** (sonde d'intégration supprimée
  après validation) : ◆ pièce (0 s, 2 s) → sheet ⚙ → éditeur → glisser à
  2000 ms → nuage écrit dans la pose 2000, base intacte, morph à
  1000 ms interpolé (120 → 146,9 px, mi-chemin 133,4) ; modèle+DB+painter
  déjà couverts (repository/point_morph/render_regression).
- Tests : **214/214** (+3 widget), analyze 0 problème.

### v0.16.1 (27/09, CI run #35 verte, release `v0.16.1-build35`, APK 51,6 Mo ; commit `8e11d35` — bugfix : keyframes de pièce incréables en projet squelette) — VALIDÉE APPAREIL (28/09, via la chaîne morph opérationnelle)
- **Symptôme** : dans un projet SQUELETTE, impossible de créer une
  keyframe sur une forme/pièce — le ◆ de la playbar ne faisait rien dès
  qu'une pièce était sélectionnée.
- **Cause** : `_buildPlaybar` routait le ◆ sur `_toggleBoneKeyframe` pour
  TOUT projet squelette ; la sélection étant exclusive (os OU pièce),
  `_selectedBone` était null avec une pièce → no-op. Et la sheet ⚙
  masquait le ◆ de pose pour les pièces (`skeletonPiece` → spacer 48),
  ainsi que la ligne Interpolation et l'astuce ◆ — aucun chemin UI vers
  une pose de pièce (bloquait aussi le workflow morph v0.16.0 sur les
  pièces).
- **Fix** : le ◆ cible l'OS sélectionné s'il y en a un, sinon la PIÈCE
  (`boneSelected = bone != null` — flow analysis promeut `bone`, pas de
  `!` nécessaire) ; la sheet ⚙ affiche le ◆ de pose + Interpolation +
  l'astuce pour les pièces, la note gagne « · aucune keyframe ».
- **Tests** (+2 dans widget_test.dart, 211/211) : ◆ playbar → pose de
  pièce (créée puis retirée, piste d'os intacte) ; sheet ⚙ pièce → ◆
  présent, pose créée, note mise à jour, ligne Interpolation atteinte
  au défilement. **Piège harnais** : `find.text('Interpolation')` ne
  trouve RIEN sans défilement — le ListView `shrinkWrap` de la sheet
  reste paresseux sous `ConstrainedBox(maxHeight)`, les enfants hors
  fenêtre+cacheExtent ne sont PAS construits ; utiliser
  `tester.scrollUntilVisible(..., scrollable: descendant de la sheet)`
  et taper le ◆ AVANT de défiler (sinon l'en-tête sort de l'écran).

### v0.15.0 (livrée + VALIDÉE APPAREIL 27/09, 4/4 tests OK — vasf-3 / Groupe 3 : couleur animée, morph, translation d'os, IK chaînes)
- **Couleur animée** : `ShapeKeyframe.layerColors` (id de couche → ARGB) ;
  sampler `colorAtLayer` — sémantique des poses numériques : valeur RÉSOLUE
  par pose (entrée propre, sinon carry de la dernière posée, sinon base),
  interpolation entre les poses encadrantes avec la courbe d'arrivée, tenue
  hors plage ; painter : `Color(colorAtLayer(...))` ; UI : section « Couleurs
  des couches » dans la sheet ⚙ (une ligne par couche : palette 8 pastilles
  + losange pose/retire l'entrée au curseur) ; callbacks
  `_setLayerColor`/`_toggleLayerColor` (undo coalescé par tag).
- **Morph de points** : `ShapeKeyframe.layerPoints` (id de couche → points
  stockés, même repère que layer.points) ; `pointsAtLayer` lerp point par
  point, nuage court bourré par répétition de son dernier point ; painter :
  les couches path dessinent le nuage échantillonné ; import only.
- **Translation d'os** : `BoneKeyframe.tx/ty` (repère de repos du PARENT) +
  `translationAt` (tenue/interp) ; FK : joint animé = repos + translation
  (les enfants suivent via parentDeltaPos, la pose de repos reste intacte —
  rig maître préservé) ; vasf : `move` [dx, dy] MONDE (conversion par
  `_restWorldAngleRad` du parent, aller-retour testé) ; in-app : ✥ sur os
  animé → translation keyframée au curseur (le glisser d'une PIÈCE liée
  garde le comportement repos + carry — paramètre `keyframed:`).
- **IK chaînes** : `SkeletonRig.ikChain/ikEffectorOf` (descendance en
  enfants uniques, arrêt au branchement) ; `solveChainIk` CCD (16 itérations,
  cible à < 0,5) pour ≥ 3 os / 1 os ; 2 os = solveur analytique v0.10
  conservé (`bend`) ; hit/losange vert sur l'effecteur de CHAÎNE
  (`hitIkEndEffector` chaîne-aware) ; armement ① os racine sélectionné
  (v0.10) ② os = effecteur d'une chaîne (remontée ancêtres) ③ aucune
  sélection (scan) ; pose des angles : `_poseChainAnglesTo` (auto-key par
  os, ré-évaluation mid à chaque étape, carry des pièces).
- **Bug v0.11 corrigé (import chaînes ≥ 3 os)** :
  `worldRestDeg[bone] = somme(parent) + angle` doublait l'angle du parent →
  le 3e niveau (et plus) se posait faux (offset ET restAngle) ;
  auto-cohérent en round-trip export donc invisible depuis v0.11. Fix :
  `worldRestDeg[bone] = angle` (monde déclaré). Les projets déjà importés
  (persistés en interne) restent inchangés ; re-importer un JSON ≥ 3 os
  change (correctement) le rendu.
- **Bonus upsertKeyframe** : écrire sur une pose existante préserve
  désormais son easing custom-bezier ET ses couleurs/morph (v0.13
  réinitialisait en easeInOut → overshoot mort après édition).
- **Format vasf-3** : `version: 3` ; import accepte 1/2/3 ; champs
  keyframes : `color`/`colors`, `points`/`layerPoints` (refus croisé
  explicite hors contexte), `move` (os) ; export v3 si extension utilisée ;
  spec +section VASF-3, exemple `docs/vasf-3-example.json` (ciel couchant +
  flamme morphée en cycle + bras 3 os IK avec move), validateur Python v3
  (alias autorisés dans les couleurs de keyframe, clouds ≥ 2 points,
  ik ≥ 1 enfant + warn multi-enfants).
- **Persistance (leçon v0.13.2 appliquée)** : schéma v6 —
  `shape_keyframes.layer_colors`/`layer_points` (maps JSON, additif,
  onCreate + onUpgrade) ; save/load ; round-trip DB étendu (couleurs,
  points, couleur interpolée reconstruite) ; tx/ty vivent dans le JSON du
  rig (testé).
- Tests : **188/188** — 6 nouveau groupes (couleur/morph modèle, FK+CCD,
  vasf-3 import/export/erreurs, round-trip DB, 2 sondes de rendu mesurées
  couleur+morph, exemple G3 complet, widget sheet couleur) ; analyze 0
  problème.

### v0.14.0 (livrée — option C : import fichier + reciblage + rendu CI)
- **Import par fichier** (`_importJsonFile`) : `FilePicker.pickFiles`
  (file_picker 13.1, `FileType.custom` json) → lecture en mémoire →
  `_parseImportText` (inchangé) → NOUVEAU projet + ouverture ; erreurs =
  dialogue « Import impossible » défilant ; le dialogue de collage et le
  timer différé du controller sont SUPPRIMÉS (piège dispose réglé).
  Fakes de test : `base class` étendant `PlatformFile` (contenu en
  mémoire — dart:io ne progresse pas en fake-async) +
  `FilePickerPlatform.instance` substitué (token OK par héritage,
  restauration via addTearDown).
- **Reciblage sans saut** (`lib/engine/binding_retarget.dart`) :
  `retargetShape` (base + keyframes recalées à leur propre instant, GOND
  `rotationCenterScene()` conservé — PAS la seule origine, sinon le
  contenu pivote) et `retargetLayer` (couches statiques → correction
  unique au curseur) ; `BoneFrame.mapPointInverse` ajouté. Limites
  documentées : os étirés (non-rigide) et interpolation entre keyframes.
- **Tests** : 165/165 — piège debug : un enfant SANS keyframes suit le
  parent avec le MÊME delta → le reciblage parent→enfant est un no-op
  mathématique (donner un delta propre à l'enfant dans les tests) ; la
  zone AVANT la 1re keyframe de la pièce est portée (carry) → monde non
  préservable là (mettre des keyframes à tous les temps de la piste).

### v0.13.2 (livrée — persistance pivot/axes/bézier, schéma v5 — validée appareil 27/09)
- **Retour utilisateur v2** : le pivot de `docs/vasf-2-g2-example.json`
  « pas pris en compte à l'import » — alors que la sonde headless (sans DB)
  montrait un import correct. **Cause réelle trouvée** : la chaîne import →
  save → load perdait les champs — le schéma SQLite `shapes` n'avait ni
  `scale_x`/`scale_y` ni `pivot_dx`/`pivot_dy`, et `shape_keyframes` ne
  stockait pas `bezier_json` : l'app importe, SAUVEGARDE puis recharge le
  projet depuis la DB → pivot retombé à 0 (rotation au centre), export
  sans pivot, overshoot bézier mort au rechargement. Le squash/stretch de
  la balle survivait car les facteurs par keyframe vivent dans
  `values_json`.
- **Corrections** : schéma v5 — 4 colonnes sur `shapes` + `bezier_json`
  sur `shape_keyframes` (ALTER additif dans `_addAxisPivotAndBezierColumns`,
  onCreate + onUpgrade `oldVersion < 5`) ; save() et load() écrivent/lisent
  les 4 champs ; `_decodeKeyframe` parse `bezier_json` (null → defaultBezier,
  garde longueur 4).
- **Tests** : round-trip repository étendu (pivot −120/15, scale_x 0,8,
  scale_y 1,2, keyframe customBezier bezier [0.34, 1.56, 0.64, 1.0]
  vérifiés après save/load) — 157/157, analyze 0 problème, CI run #31
  verte, release `v0.13.2-build31` (`vector-anim-studio-0.13.2.apk`,
  53,8 Mo).
- **Leçon** : un test qui valide le FORMAT ne couvre pas la PERSISTANCE —
  tout nouveau champ de modèle DOIT passer par le schéma DB (v5) et un
  round-trip save/load, sinon il meurt silencieusement à la fermeture de
  l'app. Piège ancres de patch : les blocs CREATE TABLE shapes/layers ont
  des lignes identiques (rotation/scale/opacity) — ancrer avec les lignes
  distinctives au-dessus.

### v0.13.1 (livrée — bugfix pivot : sliders + refus layers[], diagnostic par sondes)
- **Retours utilisateur** : pivot de la porte sans effet (rotation autour
  du centre), sliders Pivot X/Y introuvables, pas de pivot dans le JSON
  exporté — tout le reste (squash/stretch, bezier, liaison de couche,
  export v2) validé OK.
- **Diagnostic par sondes headless** (import du VRAI exemple G2 + rendu
  t=1,7 s + centroid du masque bleu) : l'import/export/painter du pivot
  fonctionnaient DÉJÀ pour un JSON conforme (centroid mesuré (242,0 / 485,1)
  vs prédiction bord gauche (242,5 / 485,7)). Les 3 symptômes correspondent
  à un pivot placé dans `layers[]` (ignoré en silence par l'import ET le
  validateur) et/ou à l'absence des sliders en projet squelette.
- **Corrections** : ① sliders Pivot X/Y affichés dans TOUS les projets
  (garde `!skeletonPiece` retirée — le pivot s'applique aussi aux pièces
  non liées d'un projet squelette, ex. porte de l'exemple G2) ;
  ② `pivot` dans `layers[]` → erreur d'import explicite en français
  (« se règle au niveau de la FORME ») au lieu du silence ; ③ validateur
  Python aligné (même erreur + warning pour tout champ inconnu d'une
  couche) ; ④ spec + skill mis à jour (pivot au niveau forme uniquement).
- **Tests** : 157/157 (153 + unité pivot-en-couche refusé + 2 tests widget
  sheet squelette/vectoriel + test de rendu du vrai exemple G2 : centroid
  bleu attendu ≈ (242, 486), pas (280, 430)) — CI run #30 verte, release
  `v0.13.1-build30` (`vector-anim-studio-0.13.1.apk`, 53,7 Mo).
- **Leçons diagnostics** : un test de rendu mesuré (centroid de masque
  couleur) tranche un débat code-vs-appareil sans installer l'APK ;
  `PictureRecorder.toImage` exige `tester.runAsync` sinon timeout 10 min ;
  les tests widget de sheet doivent défiler (`scrollUntilVisible`) car les
  lignes basses sont hors du viewport (LazyList) ; cibler le slider par
  sa POSITION dans l'arbre (`find.byType(Slider).last` = Pivot Y) plutôt
  que `.first`.

### v0.13.0 (livrée — vasf-2 Groupe 2, moteur léger — pivot resté à valider)
- **scaleX/scaleY par keyframe** : deux nouvelles AnimatableProperty (« Échelle X/Y »)
  ; échelle effective = `scale` × facteur d0027axe (composition au rendu) — la
  keyframe porte le FACTEUR brut (une keyframe à 1 remplace le facteur de base,
  elle ne le restaure pas) ; sliders auto dans la sheet de propriétés ; les
  gestes pinch restent multiplicatifs sur la base (inchangés).
- **Pivot de rotation** : `VectorShape.pivotDx/pivotDy` — offset en unités de
  forme depuis le centre, STATIQUE (non animable) ; gond ancré à sa position
  VISUELLE `centre + S·pivot` (sous échelle non uniforme, le gond reste collé
  au bord visuel) ; chaîne painter = translate(x,y)·translate(S·pivot)·
  rotate·scale(eff)·translate(−pivot) ; lignes pivot dans la sheet + réglage
  via `_setPivot`.
- **Easing cubic-bezier** : `EasingKind.customBezier` + `key.bezier` (forme ET
  os) — chaîne CSS `cubic-bezier(x1, y1, x2, y2)` (x1/x2 bornés [0,1],
  dichotomie 60 itérations) ; identité linéaire = (1/3, 1/3, 2/3, 2/3) ;
  édition des 4 paramètres import-seulement (option « Personnalisé (Bézier) »
  dans les 2 dropdowns).
- **Liaison de couche dans `bind`** (vasf) : clé `« Forme/Couche »` → os ; une
  forme avec liaison de couche est EXPORTÉE en `layers[]` même à une seule
  couche (le nom de couche doit survivre au round-trip) ; import exige une
  couche nommée existante sinon erreur collectée.
- Export `version: 2` dès qu0027une extension G1 **ou** G2 est présente (multi-
  couches, liaison de couche, scaleX/Y ≠ 1, pivot ≠ 0, customBezier).
- Exemple dédié `docs/vasf-2-g2-example.json` (balle squash+stretch bézier,
  porte sur pivot, lampe à couche liée à un os en cycle) ; skill + validateur
  Python étendus (références mises à jour).
- 153/153 tests (146 + 7 G2 dans `test/simple_format_test.dart`),
  `flutter analyze` 0 problème.

### v0.12.0 (livrée — vasf-2 Groupe 1, format seul — VALIDÉE APPAREIL 26/09)
- **Couches multiples** : `shapes[].layers[]` (type/couleur/filled/strokeWidth/
  width/height/points + pose locale `x`/`y`/rotation/scale/opacité par couche) ;
  les champs plats de géométrie sont ignorés quand `layers` est présent, la pose
  forme reste celle du groupe ; export `layers[]` + `version: 2` pour les formes
  multi-couches, à plat + `version: 1` sinon.
- **Palette** : `theme` top-level, couleurs `"$alias"` partout (fond, formes,
  couches, defs) ; alias inconnu → erreur collectée.
- **Cycle** : `cycle.repeat` (forme) et `skeleton.cycle.repeat` (tous les os) —
  duplication du motif de keyframes à l'import, période = dernier − premier
  temps, saut de la 1ʳᵉ keyframe répétée au raccord quand le temps est déjà
  posé (motif bouclé = timeline propre) ; `endMs` étendu ; ignoré sans
  keyframes ; `repeat` invalide → erreur.
- **Defs** : `defs` (géométrie seule) + `ref` au niveau forme, surcharge par
  champ (ex. œil droit rouge) ; ref inconnue → erreur.
- Importeur : version 1 **et** 2 acceptées (3+ → erreur) ; `_parseLayer`
  factorise forme-à-plat / couches ; `_PendingBoneKey` bufferise les keyframes
  d'os (cycle avant insertion) ; `colorRef` résout les alias.
- Spec `docs/vasf-1-format.md` (section VASF-2 + piège path recentré),
  exemples +3ᵉ (multi-couches), skill `generer-animation-json` et validateur
  Python étendus à la v2.

### v0.11.0 (livrée — format d'échange vasf-1 pour agents IA)
- **`lib/engine/simple_animation_format.dart`** : conversion bidirectionnelle
  projet ↔ JSON simple. Secondes/degrés/hex, keyframes partielles portées
  (poses complètes à l'import), squelette en coordonnées MONDE (l'import
  reconstruit offsets relatifs + restAngle, `keyframes[].angle` = absolu),
  liaisons par NOMS, noms de formes uniquifiés, erreurs TOUTES collectées en
  français avec chemins (`shapes[2].keyframes[0].t`), défauts 720×1280/25 fps.
- **UI** : Export ▸ « JSON simple — agents IA (vasf) » (export sparse) et
  ▸ « Importer un JSON… » (dialogue collage, détection auto vasf/complet,
  création d'un NOUVEAU projet puis ouverture, erreurs affichées dans le
  dialogue) ; piège : dispose du TextEditingController DIFFÉRÉ (timer 1 s,
  annulé au dispose de l'écran) sinon assert « used after disposed » pendant
  l'animation de sortie du dialogue.
- **Docs agents** : `docs/vasf-1-format.md` (spec EN complète) +
  `docs/vasf-1-examples.json` (squelette saluant, balle rebondissante).
- Limites v1 : une primitive par forme, pas d'instances, liaisons de couche
  ignorées à l'export.

### v0.12 — extensions du format vasf (validées 26/09, détails PLAN.md § 5 bis)
- Groupe 1 — format seul (l'importeur développe) : couches multiples par
  forme (`layers[]`), palette d'alias, cycles, définitions réutilisables —
  **livré et validé sur appareil en v0.12.0**.
- Groupe 2 — moteur léger : scaleX/scaleY par keyframe, pivot de rotation,
  easing cubic-bezier, liaison de couche exposée dans `bind` —
  **livré en v0.13.0, validé appareil (26/09 ; pivot confirmé en v0.13.2)**.
- Groupe 3 — moteur lourd : morph de points (path animé), couleur animée,
  translation d'os + IK à plus de 2 os.
- Autres options v0.12 : reciblage de binding à la keyframe, test de rendu
  permanent en CI, import par fichier.
- Le skill agent `skills/generer-animation-json/` génère le vasf-1
  (références + validateur `validate_vasf.py`) — à étendre à la v2.

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
