# Vector Anim Studio 0.13.2

## Correction majeure (retours appareil — la vraie cause du pivot « sans effet »)

- **Le pivot (et les facteurs d'axe, et le cubic-bezier) n'étaient PAS
  persistés dans la base SQLite** : l'import plaçait bien le pivot en
  mémoire, mais l'application sauvegarde le projet puis le recharge depuis
  la base — le schéma `shapes` n'avait ni `scale_x`/`scale_y` ni
  `pivot_dx`/`pivot_dy`, et `shape_keyframes` ne stockait pas les 4
  paramètres du cubic-bezier. Résultat : après import, la porte tournait
  autour de son centre « comme avant », l'export ne contenait aucun pivot,
  et l'overshoot du cubic-bezier mourait au premier rechargement.
- **Schéma v5** : 4 colonnes sur `shapes` (scale_x/scale_y/pivot_dx/
  pivot_dy) + `bezier_json` sur `shape_keyframes` — migration ALTER
  additif (les projets existants sont conservés), save/load mis à jour
  dans les deux sens.
- **Round-trip verrouillé par test** : le test d'enregistrement vérifie
  désormais pivot, facteurs d'axe et bezier après save/load (157/157
  tests, analyze 0 problème).

<!--
Ce fichier est utilisé tel quel comme description de chaque release GitHub.
Il est lu par le workflow .github/workflows/android.yml (body_path), puis complété
d'un pied de page (version · build · commit). Le mettre à jour AVANT chaque push,
en le REMPLAÇANT entièrement : uniquement les modifications de la version courante,
jamais un rappel des versions précédentes.
-->
