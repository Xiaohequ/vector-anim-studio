# Vector Anim Studio 0.17.0

## Pipeline agents : aperçu headless officiel, import strict, cycles par os

### Aperçu headless officiel (le VRAI moteur, sans appareil)

- Nouveau `test/vasf_preview_test.dart` : rend un JSON vasf avec le vrai
  `ScenePainter` et écrit une planche PNG + les frames pleine résolution.
  À la demande par variables d'environnement (la CI normale le saute) :
  `VASF_PREVIEW_INPUT=/work/tmp/preview_input.json
  scripts/flutter_docker.sh test test/vasf_preview_test.dart`
  (+ `VASF_PREVIEW_OUT`, `VASF_PREVIEW_TIMES`, `VASF_PREVIEW_SCALE`).
- `scripts/flutter_docker.sh` transmet ces variables au conteneur.
- Un import qui échoue fait échouer le test avec la liste française des
  erreurs — même diagnostic que le dialogue « Import impossible ».

### Import strict

- Tout champ inconnu (racine, `canvas`, forme, os) est REFUSÉ avec un
  message français nommant le champ et son chemin — auparavant il était
  ignoré en silence (liage perdu, animation immobile, sans avertissement).
- Champ `bone` sur une forme = raccourci de liage (bind de la forme
  entière) : conflit avec `skeleton.bind` → erreur explicite ; `bone`
  sans section `skeleton` → erreur claire.

### Keyframes/cycle embarqués dans un os + cycle par os

- Un os peut porter ses `keyframes` (angles monde, poses partielles,
  `move`, easing — sémantique de `skeleton.keyframes`, champ `bone`
  implicite) et son `cycle` : auparavant ignorés en silence (une planète
  ne tournait pas).
- `cycle` PAR OS : chaque os répète SON propre motif (période = dernier −
  premier temps de ses keyframes) ; `skeleton.cycle.repeat` reste le
  cycle global et épargne les os à cycle propre → une marche ×9 et une
  rotation lente coexistent (42 keyframes au lieu de 330 sur l'exemple
  Petit Prince).
- Spec `docs/vasf-1-format.md` (section v0.17) et validateur Python du
  skill `generer-animation-json` alignés (champs inconnus refusés,
  nouvelles formes acceptées — exemples officiels revalidés).

### Tests

- +8 tests (import strict, raccourci `bone`, fusion embarquée, cycle par
  os, cohabitation cycle par os / global) — 224/224, analyze 0 problème.
