# Keyform Studio 0.31.0

## Barre d’outils dédiée à l’éditeur de forme

- L’éditeur de forme dispose désormais d’une barre d’outils fixe en bas, alignée
  sur le Studio : **Couches**, **Points** et **Aperçu**.
- **Couches** ouvre un panneau contenant la liste/sélection des couches, leur
  visibilité, duplication, réordonnancement, suppression, ajout de primitives
  et réglage de la fenêtre d’affichage.
- **Points** centralise les outils pour les couches Chemin : mode d’ajout par
  toucher d’un segment, déplacement direct des poignées, suppression par appui
  long et aide contextuelle du morph. Les commandes restent disponibles dans
  l’aperçu pour les chemins.
- **Aperçu** regroupe le déplacement de la caméra, zoom avant/arrière,
  recentrage/ajustement et snap de rotation à 90°.
- La liste permanente des couches est retirée de la page principale pour donner
  plus de place au preview ; le preview s’étend à l’espace libéré.
- **Enregistrer** reste dans la barre supérieure ; le curseur temporel et ◆
  restent près du preview.

### Vérifications

- Tests widgets pour les panneaux de l’éditeur, l’ajout de couche, le mode point
  et les commandes de caméra.
- Suite complète des tests et `flutter analyze` requis avant publication.
