# Vector Anim Studio 0.9.4

## Corrections

- **Le déplacement d'os (✥) remis en marche.** Le glisser armé par le bouton « Déplacer l'os » n'avait aucun effet : avec la sélection exclusive, un os sélectionné laisse la forme à `null` et la mise à jour du geste sortait avant la moindre translation (le garde-fou n'exemptait que le geste de rotation). Le déplacement translate maintenant l'ancrage de l'os, la chaîne et les pièces liées suivant le doigt — test widget ajouté (armer, glisser, désarmement automatique).

## Analyse & tests

- `flutter analyze` : 0 problème ; **107 tests verts**.

<!--
Ce fichier est utilisé tel quel comme description de chaque release GitHub.
Il est lu par le workflow .github/workflows/android.yml (body_path), puis complété
d'un pied de page (version · build · commit). Le mettre à jour AVANT chaque push.
-->
