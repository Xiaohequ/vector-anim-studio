# Vector Anim Studio 0.19.0

## Miroir : symétrie horizontale / verticale d'un groupe de couches

### Le geste

- Deux nouveaux boutons **Miroir H** et **Miroir V** dans la feuille de
  propriétés de la forme (⚙) : un appui retourne tout le groupe de
  couches autour du centre de la forme, qui reste en place.
- Par couche : le contenu dessiné (primitive ou path) est réfléchi autour
  de l'origine de la couche (drapeaux `flipH`/`flipV`), la position `x`
  (resp. `y`) et la rotation sont négées — la double réflexion
  (action ∘ flip de rendu) est l'identité sur le contenu : **les points de
  base, les nuages de morph et toutes les keyframes de la forme restent
  intacts**.
- Auto-inverse : un second appui sur le même bouton redonne la forme
  d'origine.
- Une pression = une entrée d'annulation (undo), sauvegarde différée
  habituelle. Pas proposé pour les instances imbriquées (aucune couche).
- Les poignées de points de l'éditeur suivent le rendu reflété, et les
  glisser/insertions reconvertissent le delta dans le repère des données
  — on édite un chemin miroir exactement comme un chemin normal.

### Persistance

- Schéma SQLite **v7** : colonnes `flip_h` / `flip_v` sur `layers`
  (migration additive `ALTER TABLE`, onCreate + onUpgrade) — sans elles
  le flip mourrait silencieusement au rechargement (leçon v0.13.2).
- Format **vasf-4** : `flipH`/`flipV` acceptés à plat (forme à une
  couche) et dans `layers[]`, émis seulement quand vrais, fichier passé en
  `version: 4` dès qu'un flip est présent ; l'import accepte les versions
  1 à 4 (5 → message « version : 1, 2, 3 ou 4 attendu »).
- Spec `docs/vasf-1-format.md` (section « Mirror — flipH / flipV »),
  skill `generer-animation-json` + validateur Python et preview headless
  `preview_vasf.py` alignés.

### Tests

- Nouveau `test/mirror_test.dart` (12 tests) : modèle (négations +
  auto-inverse, keyframes intactes), poignées reflétées, round-trip base,
  export/import vasf v4, 3 sondes de rendu mesurées par centroid de masque
  (miroir H, miroir V, morph à travers le flip) et sheet ⚙.
- Suite complète verte, `flutter analyze` 0 problème.