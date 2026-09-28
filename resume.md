# Résumé du projet — vector_anim_studio

Studio d'animation Flutter (Android) : projets multiples, formes composées de couches,
keyframes « pose », timeline zoomable, undo, export MP4/GIF/PNG/JSON — et depuis la
v0.9.0, l'**animation squelette** (rig maître).

- Repo : https://github.com/Xiaohequ/vector-anim-studio (privé, branche `main`)
- Workspace : `/root/.nanobot/workspace/vector_anim_studio`
- Dernière version : **0.16.1** (bugfix — le ◆ de la playbar anime la
  PIÈCE sélectionnée d'un projet squelette : avant, il visait un os et
  no-opait, aucune pose de pièce n'était créable ; la sheet ⚙ d'une
  pièce retrouve son ◆ de pose + la ligne Interpolation ; 211/211
  tests). v0.16.0 = éditeur de points in-app (poignées, curseur de
  temps, auto-key morph). v0.15.0 (vasf-3 : couleur animée, morph de
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

### v0.16.1 (27/09, bugfix — keyframes de pièce incréables en projet squelette)
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
