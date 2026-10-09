# Keyform Studio 0.35.0

## Groupes d’éléments

- Création de groupes nommés depuis **Éléments**, avec sélection de couleur de timeline, renommage et dissolution en conservant les formes.
- Appartenance de formes aux groupes depuis les propriétés de la forme ou de l’os porteur ; forme libre possible avec « Aucun ».
- Timeline : ligne de groupe colorée, repliage/dépliage, visibilité, fils indentés avec liseré de 3 px et déplacement temporel commun. La durée du groupe est dérivée de ses fils.
- Les groupes et appartenances sont sauvegardés (migration SQLite v10), sérialisés en JSON et préservés lors de la duplication de projet.
- Les actions de groupe sont annulables ; sa visibilité s’applique à ses formes et à leurs os dans le preview.
- Les réglages de position, rotation et échelle du groupe sont enregistrés ; leur manipulation par le sélecteur preview est prévue en v0.35.1.

### Vérifications

- `flutter analyze` sans problème.
- Suite complète des tests Flutter : 303 tests passés.
