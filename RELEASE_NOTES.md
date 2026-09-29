# Vector Anim Studio 0.18.1

## Bugfix retours appareil : le segment par défaut revient sur la timeline

### Segment de rendu par défaut (4 s) pour les formes sans keyframe

- Retour v0.18.0 : ajouter une forme n'affichait **aucun segment** sur la
  timeline (la barre = span de keyframes, vide pour une forme neuve).
- v0.18.1 : **toutes les formes ont une barre** — le segment représente la
  **durée de rendu** de l'élément :
  - avec keyframes → span du contenu (1re → dernière keyframe),
  - sans keyframe (forme statique ou instance) → `[0, 4 s]` par défaut,
    étendu à la durée du projet.
- La fenêtre start/end reste **absente de l'UI** (jamais réintroduite) :
  le segment par défaut n'est pas éditable, il suit le contenu.
- L'appui long sur une barre sans keyframe ne fait plus rien (rien à
  décaler) — surtout pas d'entrée d'undo fantôme.

### Tests

- 227/227 (`flutter analyze` : 0 problème) — +1 test layout (deux formes
  statiques = deux lignes), +1 test view (segment pleine durée + appui
  long inerte), test statique v0.18 réécrit.
