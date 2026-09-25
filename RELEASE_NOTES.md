# Vector Anim Studio 0.9.5

## Changement de comportement

- **Le bouton ✥ devient la poignée de déplacement.** Plus de « mode déplacement » : appuyer sur le bouton ✥ et glisser déplace directement l'os — il suit le doigt en direct, la chaîne descendante et les pièces liées sont emportées. Le bouton, ancré à l'os, colle au doigt pendant le glisser. Un tap simple sur ✥ ne fait plus rien ; la poignée de rotation (cercle au bout de l'os sélectionné) reste inchangée.

## Analyse & tests

- `flutter analyze` : 0 problème ; **107 tests verts** (nouveau test widget : glisser le bouton ✥ translate l'ancrage, un tap ne fait rien).

<!--
Ce fichier est utilisé tel quel comme description de chaque release GitHub.
Il est lu par le workflow .github/workflows/android.yml (body_path), puis complété
d'un pied de page (version · build · commit). Le mettre à jour AVANT chaque push.
-->
