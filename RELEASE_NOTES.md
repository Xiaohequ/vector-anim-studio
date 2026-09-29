# Vector Anim Studio 0.18.0

## Fenêtres start/end supprimées, alpha honoré, carry des keyframes d'os

### Fenêtres d'affichage start/end SUPPRIMÉES (code + UI + format vasf)

- Une forme s'affiche pendant **tout le projet** — l'œil `visible` est le
  seul interrupteur d'affichage. Les champs `startMs`/`endMs` sont retirés
  du modèle, de la base (colonnes conservées, écrites à 0, jamais relues),
  de l'UI (RangeSlider « Fenêtre d'affichage » supprimé, curseur de
  l'éditeur borné à la durée du projet) et du format vasf.
- vasf : `start`/`end` restent **acceptés** (nombres ≥ 0, validés) mais sont
  **ignorés** à l'import ; l'export ne les émet plus. La durée du projet
  dérive du contenu : dernière keyframe (plancher 4 s ; une forme statique
  compte pour 4 s).
- Timeline : la barre d'une forme = le **span de son contenu** (1re →
  dernière keyframe, largeur min 24 px, bornée à la vue). Une instance sans
  keyframe garde une barre **pleine durée** (elle s'anime en boucle) ; une
  forme statique sans keyframe n'a plus de barre (sélection au canvas).
  Le déplacement par appui long décale les keyframes.
- Fix au passage : le scrub au-dessus d'une barre (forme ou os) utilise
  désormais la position en espace vue — avant, il dépendait de la position
  de la barre (scrub faux dès que la barre n'était plus à x = 0).

### Alpha `#AARRGGBB` honoré

- L'alpha PROPRE de la couleur **multiplie** l'opacité calculée (avant : il
  était remplacé par l'opacité, donc l'alpha du JSON était ignoré).
  `#80FF5C5C` à opacité 1 se rend à 50 % ; à opacité 0,5, à 25 %.

### Carry des keyframes d'os (sémantique des poses de forme)

- `opacity`/`stretch`/`squash`/`tx`/`ty` deviennent nullables : une
  propriété absente est **portée** de la dernière keyframe qui la pose
  (base 1/1/1/0) — avant, chaque keyframe d'os portait des défauts
  indépendants (une opacité posée à t=0 retombait à 1 à la keyframe
  suivante). La 1re valeur posée est **tenue avant son temps**.
- `upsertKeyframe` fusionne sans écraser par null ; la persistance JSON du
  rig n'écrit que les valeurs posées (une valeur posée 1.0/0.0 surcharge
  bien un carry antérieur).
- vasf : import sparse (propriétés absentes = portées) ; export sparse —
  une propriété d'os n'est émise que si sa valeur RÉSOLUE change, donc le
  re-import reproduit exactement le même rendu.

### Docs & outils agents

- Spec `docs/vasf-1-format.md` : section « v0.18 » (fenêtres supprimées,
  alpha honoré, carry d'os + tenue arrière), exemples sans `end`, champ
  `start`/`end` marqué supprimé.
- `resume.md` réorganisé : historique détaillé sous « ✅ Ce qui est fait »,
  roadmap (v0.18 à valider appareil, reciblage, backlog) séparée.

### Tests

- 224/224 (`flutter analyze` : 0 problème). Nouveaux/ajustés : carry
  d'os (modèle + round-trip), export sans start/end, barres = span de
  contenu, scrub de barre en espace vue, undo sur formes statiques (état
  du projet), barre d'instance pleine durée.
