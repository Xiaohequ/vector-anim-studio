# Vector Anim Studio 0.8.0

Studio d'animation vectorielle pour Android : projets multiples, formes composées de couches, keyframes « pose », timeline zoomable à rectangles d'affichage, undo, export MP4 et GIF.

## Nouveautés (depuis 0.7.0)

- **Déplacement de segment sans limite** : appui long + glisser horizontal peut maintenant dépasser la fin du projet — la durée s'étend automatiquement. Des espaces vides entre deux segments restent possibles (ils tiennent sur la même ligne).
- **Défilement automatique pendant le geste** : quand le segment déplacé ou étiré dépasse le bord droit de l'écran, la timeline défile sous le doigt (bord épinglé à 95 % de la vue, même règle que le suivi de la tête de lecture) — on peut viser loin au-delà de l'écran en un seul geste.
- **Poignée droite sans limite** : étirer la fin d'un segment au-delà de la fin du projet étend la durée de l'animation. Le bouton « ajuster » cadre désormais un projet plus long que 30 minutes.
- **Undo complet sur les formes et instances** : l'ajout d'une forme et l'insertion d'une instance d'animation sont maintenant annulables (⎌) — la suppression l'était déjà. Toute la vie d'une forme (ajout, duplication, modification, suppression) passe par la pile des 20 dernières actions.

## Corrections

- Analyse statique propre ; **78 tests verts** (extension de durée dérivée, défilement automatique, undo d'ajout/suppression).

## Migration

- Aucune migration : la durée reste dérivée du contenu ; les projets existants restent inchangés.

## Installation

1. Télécharge le fichier `.apk` ci-dessous.
2. Transfère-le sur ton téléphone Android.
3. Ouvre-le et autorise « Installer des applications inconnues » si Android le demande.

## À savoir

- Build **signé avec la clé debug** de Flutter : destiné aux tests, refusé par le Play Store.
- La CI ne produit que l'APK (pas d'App Bundle `.aab`).
- L'export MP4 utilise l'encodeur natif du téléphone : le rendu peut varier selon l'appareil.
- L'annulation vit en mémoire de session : elle n'est pas restaurée après fermeture de l'application.

<!--
Ce fichier est utilisé tel quel comme description de chaque release GitHub.
Il est lu par le workflow .github/workflows/android.yml (body_path), puis complété
d'un pied de page (version · build · commit). Le mettre à jour AVANT chaque push.
-->
