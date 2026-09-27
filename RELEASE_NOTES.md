# Vector Anim Studio 0.16.0

## Nouveautés (éditeur de points in-app — le morph sans JSON)

- **Poignées de points** : dans l'éditeur de forme (Modifier une forme), une
  couche « Chemin » sélectionnée affiche désormais ses points sur le preview
  (cercles blancs en espace écran, taille constante). On les attrape au
  doigt : chaque glisser déplace le point — la géométrie suit le doigt
  exactement, y compris sous rotation et squash & stretch de la forme.

- **Curseur de temps dans l'éditeur** : un slider sous le preview
  (pas de 50 ms, borné à la fenêtre de la forme) choisit l'instant affiché ;
  toutes les poignées échantillonnent le nuage RENDU à cet instant.

- **Auto-key du morph** : sans keyframe, glisser un point édite les points
  de base (dessin). Dès que la forme a des keyframes (créées au ◆ du
  studio), glisser un point écrit le nuage de morph dans la pose au
  curseur : le nuage est SEMÉ du rendu courant (visuellement neutre — seul
  le point déplacé bouge, l'interpolation vers les poses voisines reste
  continue), la pose numérique, les easings, les couleurs et le morph des
  autres couches sont préservés. Le curseur snappe à la keyframe proche
  (tolérance de la timeline, ~80 ms pour 4 s) comme dans le studio.

- **Ajouter un point** : bouton ✚ en haut à gauche du preview — puis toucher
  un segment du chemin (à moins de 28 px écran) insère un point à cet
  endroit, dans la base ET dans chaque nuage de morph existant au même
  index (la correspondance positionnelle des nuages est préservée : le
  morph reste continu, le nouveau point diverge dès qu'on le déplace par
  pose). Une activation = une insertion.

- **Supprimer un point** : appui long sur une poignée — le point disparaît
  de la base et des nuages au même index.

- **Robustesse** : `ShapeLayer.points` est désormais toujours une liste
  modifiable (les points fournis constants — littéraux par défaut, import
  — sont copiés) : l'insertion/suppression structurelle ne peut plus
  casser sur une liste figée.

## Limites (volontaires pour cette version)

- Les poses numériques (x/y, rotation, échelle…) ne s'auto-keyent toujours
  pas dans l'éditeur : elles s'éditent au ◆/sliders du studio ; dans
  l'éditeur, seuls les POINTS de chemin auto-keyent au curseur.
- L'éditeur de forme n'a pas d'undo interne (inchangé) : l'enregistrement
  remplace la forme en une seule entrée d'annulation dans le studio.
- Un point de morph ne peut pas être supprimé d'un nuage plus court que
  son index (nuages de longueurs différentes : règle du padding v0.15).

## Technique

- `VectorShape.applyLayerPoints` (écriture base/pose au curseur, même
  sémantique que `applyLayerColor`), `insertLayerPoint` /
  `removeLayerPoint` (structurel base + nuages alignés).
- `SelectionGeometry.canvasToLocal` (inverse exact de `localToCanvas`,
  pivot inclus) + `pointHandlePositions` / `hitPointIndex` /
  `nearestClosedSegment` / `distanceToSegment` ; hit des poignées sur la
  position BRUTE du doigt (la reconnaissance du geste arrive le foyer déjà
  déplacé — piège connu).
- `ScenePainter.showLayerPoints` + `activePointIndex` : dessin des
  poignées, éditeur seulement (jamais en export).
- Tests : **209/209** (+15 unitaires modèle/géométrie/vasf round-trip,
  +5 widget : glisser auto-key, base sans keyframe, appui long, mode ✚,
  légende). `flutter analyze` 0 problème.
