# Keyform Studio 0.33.0

## Studio simplifié et propriétés des éléments

- Barre Studio simplifiée : **Éléments** et **Animation** ; les actions d’un élément sont regroupées dans sa feuille de propriétés. L’accès Os dédié disparaît de la barre.
- La keyframe au curseur est placée dans l’en-tête de la timeline ; l’aperçu de l’éditeur de forme isole la forme en cours d’édition.
- Depuis les propriétés d’un os, accès direct à l’édition de la forme qu’il porte.
- Sélecteur de couleur personnalisée ajouté aux propriétés des couches.

## Ordre Z et coins arrondis

- Ordre Z numérique réglable par forme ; il est persisté (migration SQLite v9) et départage l’ordre d’affichage.
- Rayon commun réglable et sélection indépendante des quatre coins des rectangles. Les rectangles existants conservent leur arrondi automatique historique ; un rayon nul explicite donne un rectangle carré.
- VASF-5 prend en charge ces réglages dans les formes à plat et `layers[]`.

### Vérifications

- `flutter analyze` sans problème.
- Suite complète des tests Flutter : 290 tests passés.
