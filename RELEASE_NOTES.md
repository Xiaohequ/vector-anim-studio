# Keyform Studio 0.29.0

## Projets unifiés et rig disponible partout

- Suppression du choix « vectoriel / squelette » à la création : un projet neuf
  utilise le type historique vectoriel, mais propose dès le départ les outils de
  rig et de liaison des formes aux os.
- Les projets existants conservent leurs données et leurs rigs ; l'ancien champ
  de type est maintenu pour compatibilité, sans restreindre les fonctions.
- Tous les projets peuvent désormais imbriquer des animations, dessiner et
  sélectionner des os, utiliser l'IK et transporter les éléments liés.
- Export VASF : un rig présent est exporté même si le projet a été créé comme
  projet vectoriel ; les projets VASF avec squelette gardent leur représentation.
- Suppression de la ligne « temps actuel / durée totale · fps » au-dessus de la
  timeline, sans changement des commandes de lecture ni des options d'export.

### Vérifications

- Tests couvrant création unifiée, disponibilité du rig dans un ancien projet
  vectoriel, keyframes d'os et durée avec rig.
- Suite complète, analyse statique et build APK CI requis avant publication.
