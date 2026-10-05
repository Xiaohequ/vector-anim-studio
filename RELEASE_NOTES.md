# Keyform Studio 0.30.0

## Outils du Studio regroupés et projets unifiés

- Nouvelle barre d’outils fixe en bas avec trois accès nommés : **Éléments**,
  **Animation** et **Os**. Les actions fréquentes sont regroupées dans des
  panneaux organisés et défilants ; l’export reste dans la barre supérieure.
- **Éléments** : ajout/sélection, visibilité, ordre d’affichage, propriétés,
  modification des couches, duplication, renommage et suppression ; insertion
  d’animations et import VASF comme groupe.
- **Animation** : presets et suppression des animations de l’élément sélectionné.
  La pose/keyframe au curseur reste dans la barre de lecture.
- **Os** : création/modification et liaison à l’élément sélectionné, sélection
  des os du projet et accès rapide à leurs propriétés ; disponible sur les
  projets historiques vectoriels comme sur les projets avec rig.
- Suppression des anciens menus redondants « Formes », « Animations » et
  « Calques ».
- Les projets sont unifiés : le choix « vectoriel / squelette » n’est plus
  demandé à la création. Le type historique reste conservé pour compatibilité,
  sans restreindre les fonctions de rig.
- Les projets existants conservent leurs données et rigs ; les projets peuvent
  imbriquer des animations, dessiner/sélectionner des os, utiliser l’IK et
  transporter les éléments liés.
- Export VASF : un rig présent est exporté même si le projet a été créé avec le
  type historique vectoriel.

### Vérifications

- Tests de widgets pour les trois panneaux, les actions de sélection et le
  maintien de l’export en haut.
- Suite complète des tests et `flutter analyze` requis avant publication.
