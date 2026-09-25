# Vector Anim Studio 0.9.3

## Corrections

- **Re-parentage « racine » sans disparition.** Dans Propriétés de l'os, choisir « Racine (aucun) » faisait sauter l'os et ses fils hors du preview (l'offset restait dans le repère de l'ancien parent, réinterprété en coordonnées projet). Le re-parentage préserve maintenant la géométrie de repos : l'os reste **ancré sur place** et visible, sa descendance aussi, et l'ancien parent n'a plus aucun effet dessus.

## Nouveautés

- **Confirmation d'attachement.** À la création d'un os 2 qui se rattacherait à un os 1 (tap sur son poignet, son segment, ou sur une pièce qu'il porte), une fenêtre demande confirmation. « Attacher » → l'ancrage suivra l'os 1 ; « Non, sans parent » → l'os 2 est créé racine, ancré sur place.
- **Poignée de rotation dédiée.** Quand un os est sélectionné, une poignée sort de son extrémité (dans le prolongement) : la glisser pivote l'os. La rotation via le deuxième point de l'os est désactivée — toucher l'extrémité sélectionne, ne pivote plus.
- **Déplacement sans mode.** Plus de « mode déplacement » collant : appuyer sur ✥ puis glisser n'importe où sur l'écran translate l'ancrage de l'os sélectionné (chaîne et pièces liées suivent) ; le relâchement désarme le bouton.

## Analyse & tests

- `flutter analyze` : 0 problème ; **106 tests verts** (FK, round-trip, persistance v4, durée squelette, translation d'ancrage, emport de pièces, création d'os attaché, re-parentage sans saut racine/autre os).

<!--
Ce fichier est utilisé tel quel comme description de chaque release GitHub.
Il est lu par le workflow .github/workflows/android.yml (body_path), puis complété
d'un pied de page (version · build · commit). Le mettre à jour AVANT chaque push.
-->
