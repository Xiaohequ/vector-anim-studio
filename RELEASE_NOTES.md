# Vector Anim Studio 0.15.0

## Nouveautés (vasf-3 / Groupe 3 — le moteur lourd)

- **Couleur animée** : la couleur d'une couche devient une propriété de pose.
  Dans la sheet ⚙ d'une forme, une section « Couleurs des couches » donne
  une ligne par couche (palette de 8 pastilles + losange) : sans keyframe le
  choix écrit la couleur de base ; avec keyframes, chaque choix pose la
  couleur AU CURSEUR (auto-key) et l'app interpole entre les poses colorées
  (tenue hors plage, courbe de la pose d'arrivée). Coucher de soleil,
  rougeur, pulsation — sans changer la géométrie.

- **Morph de points** : les points d'un chemin (`path`) s'animent entre les
  keyframes, point par point — visages, expressions, flammes. Un nuage plus
  court est bourré par répétition de son dernier point (les nouveaux
  segments poussent depuis lui). Le morph se définit dans le JSON vasf-3
  (`points` / `layerPoints` par couche) ; il suit le repère des points de
  base. Pas encore d'éditeur de points dans l'app : import uniquement.

- **Translation d'os** : `move: [dx, dy]` (monde) sur une keyframe d'os —
  l'articulation glisse, les enfants et les pièces liées suivent
  rigidement, la pose de repos reste intacte. Dans l'app : glisser la
  poignée ✥ d'un os ANIMÉ écrit une translation au curseur (auto-key) ; sur
  un os au repos, ✥ garde le comportement historique (pose du rig + emport
  des pièces).

- **IK à chaînes de N os** : `ik: true` fait maintenant d'un os la racine
  d'une chaîne — le losange vert se pose sur l'extrémité du DERNIER os de
  la chaîne (descendance d'enfants uniques) et son glisser résout toute la
  chaîne : 2 os = solveur analytique exact (coude contrôlé par `bend`),
  3 os et plus = solveur itératif CCD.

- **Compatibilité format** : l'import accepte les vasf 1, 2 ET 3 ; les
  nouveaux champs (`color`/`colors`, `points`/`layerPoints`, `move`) sont
  tous optionnels — un fichier v1 reste valide. L'export écrit `version: 3`
  quand une extension v3 est utilisée. Spec : `docs/vasf-1-format.md`
  (section « VASF-3 extensions »), exemple complet :
  `docs/vasf-3-example.json`.

## Corrections

- **Import vasf des chaînes ≥ 3 os (bug v0.11)** : l'angle de repos d'un
  3e niveau (et plus) était calculé contre un faux angle monde du parent
  (double comptage) — l'os se posait décalé/faux. Corrigé : les joints et
  angles MONDE déclarés sont honorés à tous les niveaux. Les projets déjà
  importés ne bougent pas (persistance interne) ; re-importer un JSON de
  chaîne ≥ 3 os peut légèrement modifier son rendu — vers le conforme.
- **Édition d'une pose custom-bezier** : écrire une propriété sur une pose
  existante préservait mal sa courbe (retour en easeInOut, overshoot mort).
  La pose garde désormais sa bézier, ses couleurs et son morph.

## Technique

- Schéma SQLite **v6** : les couleurs et points de morph par keyframe
  sont persistés (`layer_colors` / `layer_points`, migration additive) —
  round-trip save/load testé (leçon v0.13.2 : tout nouveau champ passe par
  la DB).
- 188/188 tests (dont 2 nouvelles sondes de rendu mesurées : interpolation
  couleur au pixel et morph par centroid ; import + rendu du fichier
  d'exemple v3 vérifiés en CI).
