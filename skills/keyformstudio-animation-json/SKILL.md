---
name: keyformstudio-animation-json
version: 1.0.0
vasf: 6
app: 0.39.0
description: Génère des animations JSON au format VASF-1/2/3/4/5/6 importables dans Keyform Studio (import par fichier). Utiliser quand l'utilisateur demande de générer/créer une animation JSON, un « vasf », une animation pour Keyform Studio / Vector Anim Studio, ou de corriger un JSON refusé par l'import.
---

# Générer animation JSON (VASF-1/2/3/4/5/6)

Créer un FICHIER JSON d'animation 2D que l'utilisateur importe dans l'appli
**Keyform Studio** (accueil ▸ icône « Importer un fichier JSON » ; Studio ▸
Formes ▸ « Importer un VASF comme instance… » pour insérer un squelette dans un
projet existant). L'import crée un NOUVEAU projet (vectoriel ou squelette) et
affiche les erreurs en français.

Ce skill vit DANS le dépôt de l'appli : la spec et les exemples qu'il cite sont
ceux de `docs/`, donc versionnés avec le code qui les implémente. Toute
évolution du format se fait ici et dans `docs/` dans le MÊME commit.

## Démarrer

1. Lire la spec complète : `references/vasf-1-format.md` (tous les champs,
   défauts, extensions v2 — palette, couches multiples, cycles, defs,
   scaleX/Y, pivot, bézier — v3 — couleur animée, morph de points, move
   d'os, IK chaînes — v4 — miroir — v5 — coins de rectangles — v6 — groupes
   d'éléments — et limites).
2. S'inspirer des exemples : `references/vasf-1-examples.json` (balle
   rebondissante + personnage squelette qui salue + personnage multi-couches
   vasf-2). Le recueil contient plusieurs objets — **l'appli importe UN SEUL
   objet par import** : la sortie doit être un unique objet JSON racine.
3. Exemples dédiés : `references/vasf-2-example.json` (G1 : couches/theme/
   defs/cycle), `references/vasf-2-g2-example.json` (G2 : scaleX/scaleY
   animées, pivot, cubic-bezier, liaison de couche),
   `references/vasf-3-example.json` (v3 : couleur animée, morph de points,
   move d'os, IK 3 os), `references/vasf-5-example.json` (rectangles et coins
   personnalisés) et `references/vasf-6-example.json` (groupes d'éléments :
   `groups` + `groupId` par nom).
4. `references/` est un miroir EXACT de `docs/` du dépôt de l'appli (vérifié
   par `scripts/sync_skill.sh --check` côté dépôt) : en cas de doute, `docs/`
   fait foi. Le skill reste ainsi autonome une fois copié dans le workspace de
   l'agent, où `docs/` n'existe pas.

## Règles d'or (résumé)

- Temps en **secondes**, angles en **degrés**, couleurs `#RRGGBB`/`#AARRGGBB`.
- Coordonnées canvas : origine en haut-gauche, y vers le bas ;
  degrés positifs = sens horaire. Défauts : 720×1280, 25 fps, fond `#14161C`.
- Une forme = **une primitive** par défaut (rect, circle, line, path,
  triangle, star, hexagon, cross, heart, arrow). Un personnage = plusieurs
  formes, chacune liée à son os. En **vasf-2**, `"layers": [...]` regroupe
  plusieurs primitives dans UNE forme (yeux, bouche…) avec pose locale par
  couche (`x`/`y` relatifs au centre de forme) ; `x/y/rotation/scale/opacity`
  et `keyframes` restent la pose du GROUPE.
- **vasf-2** (champs optionnels, `version: 2`) : palette `"theme"` + couleurs
  `"$alias"` ; `"cycle": {"repeat": N}` qui répète le motif de keyframes
  (période = dernier − premier temps, motif bouclé pour un raccord propre) ;
  `"defs"` + `"ref"` (géométrie définie une fois, surcharge possible).
- **vasf-2 Groupe 2** : `"scaleX"`/`"scaleY"` facteurs d'axe (base ET
  keyframes — échelle effective = `scale` × facteur ; une keyframe à 1
  remplace le facteur, elle ne le restaure pas) ; `"pivot": [dx, dy]` décalé
  du centre en unités de forme où rotation/échelle tournent (STATIQUE,
  gond ancré à sa position visuelle) — **au niveau de la FORME uniquement,
  JAMAIS dans layers[]** (refusé à l'import, sinon rotation autour du
  centre) ; easing cubic-bezier CSS
  `"cubic-bezier(x1, y1, x2, y2)"` (x1/x2 dans [0,1] ; identité linéaire =
  (0.333, 0.333, 0.667, 0.667) — PAS (0,0,1,1)) ; liaison de couche dans
  `bind` avec la clé `"Forme/Couche"` (la couche doit exister sur la forme ;
  une forme liée par couche est exportée en `layers[]` même à une seule
  couche).
- **vasf-3** (v0.15, `version: 3` — moteur lourd) :
  ① **couleur animée** par keyframe — `"color": "#hex"` (forme à UNE
  couche) ou `"colors": {"NomCouche": "#hex"}` (forme en layers[]) ;
  interpolation entre les poses colorées (tenue hors plage, carry des
  poses sans couleur) ; `color` refusé sur layers[], `colors` refusé à
  plat ; éditable aussi in-app (palette dans la sheet ⚙).
  ② **morph de points** — `"points": [[x,y]…]` (à plat) ou
  `"layerPoints": {"NomCouche": [[x,y]…]}` (layers[]) sur les keyframes :
  le path s'interpole point par point ; nuage plus court bourré par
  répétition de son dernier point ; **repère = celui de la liste `points`
  de base** (le centre bbox de la base, PAS celui de chaque keyframe — sinon
  le morph dérive) ; la PREMIÈRE keyframe doit définir le nuage de départ
  (copier la base à `t: 0`). Édition in-app : possible depuis v0.16
  (éditeur de forme : poignées de points, curseur de temps, auto-key
  morph) — mais les agents posent le morph complet dans le JSON.
  ③ **translation d'os** — `"move": [dx, dy]` MONDE (coords canvas, offset
  depuis la position de repos du joint) sur une keyframe d'os : le joint
  glisse, les enfants et pièces liées suivent rigidement ; combinable avec
  `angle` sur la même keyframe.
  ④ **IK chaînes** — `ik: true` sur la racine d'une chaîne : le glisser de
  l'extrémité du DERNIER os résout toute la chaîne (2 os = solveur exact
  + `bend`, ≥ 3 os = CCD itératif, le côté du coude n'est pas garanti) ;
  la chaîne suit les os à enfant unique et s'arrête au premier branchement.
  In-app : ✥ sur un os ANIMÉ écrit une translation au curseur (auto-key) ;
  sur un os au repos, ✥ garde le comportement historique (repos + emport).
  Un fichier `version: 1` reste valide ; l'import accepte les versions 1 à 6.
- **vasf-4** (v0.19, `version: 4` — miroir) : `"flipH": true` / `"flipV": true`
  PAR COUCHE (ou au niveau forme à plat) — le painter reflète le CONTENU de la
  couche (primitive ou path, points de base comme nuages de morph) autour de
  son origine. L'action in-app « Miroir H/V » (sheet ⚙ de la forme) négue
  aussi x (H) ou y (V) et la rotation de chaque couche : le groupe entier est
  reflété autour de son centre sans bouger ; keyframes intactes. Export :
  champs émis seulement quand true, fichier passé en `version: 4`.
- **vasf-5** (v0.33, `version: 5`) : `cornerRadius` règle le rayon commun des
  rectangles (0 = coins carrés ; absent = rayon automatique historique) ;
  `roundTopLeft`, `roundTopRight`, `roundBottomRight` et `roundBottomLeft`
    activent chaque coin indépendamment. Disponible à plat et dans `layers[]`.
- Ordre Z numérique par forme (interne à l'app, persisté en SQLite) ; il ne
  modifie pas l'ordre de dessin défini par le tableau VASF `shapes`.
- **v0.17 (app + validateur)** : import STRICT — tout champ inconnu
  (racine, canvas, forme, os) est REFUSÉ avec le chemin (avant : ignoré en
  silence → liage perdu / animation immobile). Nouveautés acceptées :
  ① `keyframes` + `cycle` EMBARQUÉS dans un os (sémantique de
  `skeleton.keyframes`, champ `bone` implicite) ; ② `cycle` PAR OS
  (périodes différentes : marche ×9 + rotation lente coexistent ; le cycle
  global épargne les os à cycle propre) ; ③ raccourci `"bone": "Os"` sur
  une forme = bind entier (conflit avec `bind` = erreur).
- **Fenêtres d'affichage `start`/`end` : ACTIVES.** Une forme n'est rendue
  que sur `[start, end]` (secondes). `end` absent = la fin la plus tardive
  des autres formes, sinon 4 s ; `end` doit être > `start` ; une keyframe
  au-delà de `end` PROLONGE `end`. Durée du projet = fin la plus tardive des
  segments (plancher 4 s dès qu'un rig ou une forme existe).
- **Alpha `#AARRGGBB` : REMPLACÉ par l'opacité calculée**, pas multiplié. Le
  rendu fait `Color(colorValue).withValues(alpha: opacity)` : l'alpha propre
  de la couleur est ignoré. Pour un fondu, animer `opacity`.
- **Keyframes d'os : chaque pose porte SA propre valeur.** `opacity` /
  `stretch` / `squash` / `move` omis valent le défaut neutre (1 / 1 / 1 /
  [0,0]) : PAS de carry entre poses d'os (contrairement aux poses de FORME,
  où une propriété omise est portée de la keyframe précédente).
- **`zIndex` est REFUSÉ à l'import** (champ interne à l'app, colonne SQLite) :
  l'ordre de dessin est celui du tableau `shapes`, un point c'est tout.
- **vasf-6 (v0.39, `version: 6`) — groupes d'éléments** : clé racine
  `"groups": [{"name": "Tête", "color": "#FF8800", "visible": true,
  "collapsed": false, "x": 0, "y": 0, "rotation": 0, "scaleX": 1,
  "scaleY": 1}]` et `"groupId": "Tête"` sur chaque forme membre. Le `groupId`
  est le **NOM** du groupe (pas un id) : l'import résout après création, donc
  l'ordre des clés JSON est libre ; un nom inconnu est une erreur. Un groupe
  ne porte ni keyframes ni os (étendue dérivée des fils) ; sa `visible: false`
  masque toutes ses formes. Groupes à plat : pas d'imbrication, une forme dans
  UN groupe au plus. La transformation statique du groupe (`x`/`y`/`rotation`/
  `scaleX`/`scaleY`) EST rendue : elle enveloppe la pose de chaque forme et
  tourne autour du **centre visuel du groupe** (moyenne des positions de repos
  de ses fils), pas de l'origine du canvas ; un groupe neutre rend exactement
  comme des formes non groupées. L'export passe en `version: 6` dès qu'une
  forme a un `groupId` et n'émet que les groupes non vides.
- Piège path dans `layers[]` : les `points` sont recentrés sur l'origine de
  la couche — placer un path avec le `x`/`y` de la couche (ex. sourire →
  `y` = centre vertical de sa bbox).
- Ordre de dessin = ordre du tableau `shapes` (première = fond).
- Keyframes de FORME = poses **partielles** autorisées : une propriété
  absente est portée de la keyframe précédente (ou de la pose de base).
  Les keyframes d'OS ne suivent PAS cette règle (défaut neutre à chaque
  pose). Easing d'une keyframe = courbe du segment qui ARRIVE à cette
  keyframe (linear, easeIn, easeOut, easeInOut, step — défaut easeInOut).
- Keyframe d'os : `angle` = angle **MONDE absolu** en degrés (pas un delta).
- Squelette : os **parents déclarés avant leurs enfants** ; `ik: true`
  démarre une chaîne IK (au moins un enfant ; la chaîne suit les enfants
  uniques) ; liaisons `bind` par **noms** (forme ou `"Forme/Couche"`).
- Limites : pas d'instances imbriquées ; la pose locale d'une couche
  (`x/y/rotation/scale/opacité` dans `layers[]`) reste statique — seuls le
  groupe, les COULEURS de couche et les POINTS de couche (morph, v3)
  s'animent ; `pivot` non animable ; `ref` ne marche qu'au niveau forme (pas
  dans `layers[]`).
- Une keyframe d'os avec seulement `t` remet opacité/étirement/écrasement
  à leur défaut neutre — toujours donner `angle` pour animer un os.

## Workflow

1. **Concevoir** : définir canvas (720×1280 par défaut), durée, formes et
   timeline. Fenêtres `start`/`end` actives : une forme n'apparaît que sur
   son segment ; la durée du projet = fin la plus tardive (plancher 4 s).
   Chute → `easeIn` (accélère),
   montée/relance → `easeOut`, impact → `step` si arrêt net, sinon
   `easeInOut` par défaut.
   Squash & stretch : `scale` (uniforme) ou `scaleX`/`scaleY` indépendants
   (écrasement au sol = `scaleX > 1` + `scaleY < 1`). Rotation autour d'un
   bord → `pivot` sur la forme (ex. porte : pivot `[-width/2, 0]`).
2. **Écrire** le JSON dans `tmp/` (non versionné), nom descriptif
   (`tmp/balle_rebond_v1.json`). Un seul objet racine.
3. **Valider** avant livraison :
   `python3 skills/keyformstudio-animation-json/scripts/validate_vasf.py tmp/<fichier>.json`
   — corriger toutes les erreurs ; les avertissements ⚠ sont à relire
   (renommage auto, échelle/facteurs d'axe hors 0.05–4, pivot démesuré,
   y de bézier élastique, morph démarrant après t ≈ 0).
4. **Aperçu rapide (recommandé)** : rendu FIDÈLE à l'appli sans Docker
   (mêmes formules que `scene_painter.dart`/`skeleton.dart`, vérifié au
   pixel contre le harnais officiel — diff < 1/255) :
   `python3 skills/keyformstudio-animation-json/scripts/preview_vasf.py
   tmp/<fichier>.json [t1 t2 ...] [--bones] [--pick CLE]`
   → `tmp/vasf_preview/<nom>/planche.png` (côte à côte) + `frame_t*.png`
   pleine résolution pour les mesures pixel. Sans instants : 5 échantillons
   sur la durée du contenu ; `--bones` superpose le rig (os orange +
   articulations) ; `--pick` choisit l'objet dans un recueil. Lire la
   planche et vérifier composition/positions/morph. Sorties : 0 = OK,
   1 = erreurs de parsing (à corriger), 2 = fatal.
5. **Vérification exacte (cas douteux)** : le VRAI moteur dans Docker :
   `cp <fichier>.json tmp/preview_input.json &&
   VASF_PREVIEW_INPUT=/work/tmp/preview_input.json
   scripts/flutter_docker.sh test test/vasf_preview_test.dart`
   → `tmp/vasf_preview/planche.png` + frames.
6. **Livrer** : envoyer le FICHIER .json à l'utilisateur (Telegram). L'import
   se fait par fichier : accueil ▸ icône « Importer un fichier JSON » (crée un
   nouveau projet), ou Studio ▸ Formes ▸ « Importer un VASF comme instance… »
   (insère un squelette dans le projet courant). Si l'appli refuse, le dialogue
   « Import impossible » liste les erreurs en français avec le chemin — les
   corriger dans le fichier et redélivrer.

## Conseils d'animation

- Balle qui rebondit : alterner `easeIn` (descente) / `easeOut` (remontée),
  écrasement au sol par `scale` sur 1–2 keyframes.
- Personnage : formes (torse/bras/avant-bras…) posées au repos, os aux
  articulations, `bind` forme → os ; animer par keyframes d'os à angle
  MONDE (ex. coude au repos à 100° → keyframe `angle: 150`).
- IK : activer `ik` sur la RACINE de la chaîne (épaule) — le glisser de
  l'extrémité du dernier os résout toute la chaîne (2 os exacts, ≥ 3 os CCD) ;
  `bend` choisit le côté du coude sur les chaînes de 2 os.
- Rester lisible : peu de formes, durées courtes (2–8 s), 2–4 keyframes par
  propriété.

## Version et synchronisation

- La version du skill est dans le frontmatter (`version`), avec la version
  VASF (`vasf`) et la version d'appli de référence (`app`). Voir
  `CHANGELOG.md` pour l'historique.
- Le skill est versionné avec le code : une évolution du format touche
  `docs/vasf-1-format.md`, `app/lib/engine/simple_animation_format.dart`,
  les tests et ce skill dans le MÊME commit, puis on incrémente `version`.
- `scripts/sync_skill.sh` recopie le skill vers le workspace de l'agent
  (`~/.nanobot/workspace/skills/`) et vérifie que `references/` est identique
  à `docs/`. Lancer `scripts/sync_skill.sh --check` en CI ou avant un commit
  pour détecter une dérive.
