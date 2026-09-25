# Vector Anim Studio 0.10.1

## Corrigé

- **Le glisser IK ne faisait rien depuis certaines sélections (v0.10.0).** Deux causes :
  - Le geste IK n'était armé que si l'os PARENT (épaule) était sélectionné — or on tape naturellement le poignet pour le saisir, ce qui sélectionne l'ENFANT : le glisser tombait alors dans le vide. Désormais le losange vert est une vraie poignée : le glisser IK démarre que le parent ou l'enfant soit sélectionné, voire SANS aucune sélection.
  - Le bouton ✥ (déplacer l'os), ancré près de l'enfant sélectionné, recouvait l'effecteur et avalait le press. Quand l'os sélectionné est l'enfant d'une chaîne IK, les boutons ⚙/✥ se rangent maintenant au joint du PARENT (le coude), loin du poignet.
- Reproduction corrigée par 3 tests widget (enfant sélectionné / sans sélection / parent sélectionné) qui pilotent de vrais glissers sur le canvas.

## Analyse & tests

- `flutter analyze` : 0 problème ; **123 tests verts** (120 + solveur/samplers/FK stretch/z de v0.10.0 déjà comptés, + 3 tests widget IK).

<!--
Ce fichier est utilisé tel quel comme description de chaque release GitHub.
Il est lu par le workflow .github/workflows/android.yml (body_path), puis complété
d'un pied de page (version · build · commit). Le mettre à jour AVANT chaque push.
-->
