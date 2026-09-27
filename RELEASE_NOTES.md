# Vector Anim Studio 0.14.0

## Nouveautés (option C — petits ajouts rapides)

- **Import par fichier** : « Export ▸ Importer un fichier JSON… » ouvre le
  sélecteur système (SAF sous Android, aucune permission à déclarer) —
  fini le collage dans le presse-papiers. Un JSON vasf (agents IA) ou un
  projet complet est accepté ; un fichier refusé affiche la liste des
  problèmes dans un dialogue défilant, et aucun projet n'est créé.

- **Reciblage « sans saut »** : re-lier une pièce (ou une couche) déjà
  liée à un autre os réécrit ses poses pour que sa position MONDE reste
  identique au moment du changement — la pièce ne saute pas, elle passe
  juste sous le nouvel os. La pose de base est recalée au curseur ; les
  keyframes existantes sont recalées à leur propre instant. Exact tant
  que les os ne sont pas étirés (stretch 1).

- **Tests de rendu permanents en CI** : la sonde v0.13.1 devient une
  suite de régression exécutée à chaque build — chaque scène de référence
  est rendue en headless et vérifiée par mesure pixel (centroid d'un
  masque couleur) : pièce liée suit l'os animé, couche liée suit son os,
  reciblage sans saut (rendu avant/après identique), pivot de la porte
  (test existant conservé). 165/165 tests, analyze 0 problème.

<!--
Ce fichier est utilisé tel quel comme description de chaque release GitHub.
Il est lu par le workflow .github/workflows/android.yml (body_path), puis complété
d'un pied de page (version · build · commit). Le mettre à jour AVANT chaque push,
en le REMPLAÇANT entièrement : uniquement les modifications de la version courante,
jamais un rappel des versions précédentes.
-->
