# Vector Anim Studio 0.20.1

## Bugfix : le bouton « Ajouter un os… » était introuvable

### Cause

- La section « os » de la feuille ⚙ n'était affichée **que si le projet
  avait déjà un rig** (`skeletonRig != null`) — or sur un **projet squelette
  neuf**, `project.skeleton` est `null` : le rig naît seulement à la
  validation (✓) de l'éditeur d'os.
- Résultat : aucun bouton pour ajouter un os sur une forme, donc parcours
  bloqué dès la première utilisation.

### Correction

- La section est désormais conditionnée au **type de projet** (squelette),
  plus à l'existence du rig : elle affiche **« Aucun os » + « Ajouter un
  os… »** dès l'ouverture de la feuille.
- « Modifier l'os… » et « Supprimer l'os » n'apparaissent toujours que si
  la forme porte réellement un os.
- Le rig est créé à la validation de l'éditeur (inchangé).

### Tests

- +1 test de non-régression : projet squelette neuf (sans rig) → feuille ⚙
  → « Ajouter un os… » présent → l'éditeur s'ouvre, le rig naît au ✓.
  **254/254**, `flutter analyze` 0 problème.

## Note — le bouton « Squelette » a bien été remplacé par « Animations »

C'est **normal** (choix validé, D.4 du plan v0.20.0) : le menu « Squelette »
a été supprimé, donc le bas de barre affiche **Formes + Animations** dans
les projets squelette aussi (ce qui rend enfin accessible le menu
Animations — effacer les animations, presets — auparavant masqué).

Les actions sur les os ont changé d'endroit :

- **Feuille ⚙ de la forme** : Ajouter / Modifier / Supprimer l'os.
- **Canvas** : tap sur un os = le sélectionner (⚙ et ✥ apparaissent),
  ✥ / rotation / IK pour l'animer.
- **Playbar** : ◆ cible l'os sélectionné.