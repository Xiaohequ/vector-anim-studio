# Vector Anim Studio 0.18.2

## Bugfix retours appareil : le segment garde sa durée quand on ajoute une keyframe

### La barre = durée de rendu, indépendante des keyframes

- Retour v0.18.1 : ajouter une keyframe **rétrécissait le segment** de la
  timeline (la barre se repliait sur le span des keyframes — une seule
  keyframe → un segment de 24 px).
- v0.18.2 : la barre de **toutes** les formes = leur **durée de rendu**
  `[0, max(durée du projet, 4 s)]` — identique avec ou sans keyframes,
  comme le segment par défaut de v0.17. Ajouter ou déplacer une keyframe
  ne change plus la taille ni la position du segment (sauf si la keyframe
  étend la durée du projet).
- Les **losanges de keyframes** se déplacent sur la barre ; l'appui long +
  glisser décale toujours les keyframes d'une forme animée (la barre
  reste pleine durée, les losanges suivent le doigt).
- Une ligne par forme, triées par nom (toutes les barres couvrent la même
  plage : l'empilement par span n'a plus lieu d'être).

### Fix au passage : barres invisibles au zoom

- v0.18.0 bornait la largeur de barre à la vue tout en ancrant la barre à
  sa vraie position : au zoom avant, une barre plus large que la vue était
  ancrée à x négatif → **entièrement invisible**. Désormais une barre
  plus large que la vue couvre tout le viewport (intersection avec la
  fenêtre visible) et les losanges se positionnent sur la plage visible.
- Même fix appliqué aux barres d'os (piste hors vue → barre vide).
- La règle graduée est traversée par les taps (IgnorePointer) : le tap
  sur la règle scrubbe la tête de lecture, le tap sur une barre
  sélectionne la forme.

### Tests

- 223/223 (`flutter analyze` : 0 problème) — tests d'empilement par span
  réécrits pour la nouvelle sémantique ; +2 tests view (le segment couvre
  la durée de rendu même zoomé, une keyframe ajoutée ne rétrécit pas le
  segment).
