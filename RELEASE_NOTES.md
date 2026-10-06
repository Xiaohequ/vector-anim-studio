# Keyform Studio 0.32.0

## Retour d’usage : éditeur de forme

- Les couches/« formes » reviennent dans l’écran principal de l’éditeur, sous le
  preview ; elles ne sont plus cachées dans une feuille.
- Le réglage de fenêtre d’affichage est retiré de l’éditeur.
- Les lignes de couche n’affichent plus le type, la taille, la position ni le
  bouton de visibilité ; elles proposent **Propriétés**, duplication et ordre.
- Le bouton inférieur **Couches** devient **Formes** et ouvre une grille de
  primitives à **3 colonnes**.
- **Points** et **Aperçu** restent dans la barre basse. Enregistrer reste en
  haut ; le curseur temporel et la keyframe restent près du preview.

### Vérifications

- Test widget : grille 3 colonnes et ajout d’une primitive.
- Suite complète des tests et `flutter analyze` requis avant publication.
