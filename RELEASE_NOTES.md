# Vector Anim Studio 0.9.1

Studio d'animation vectorielle pour Android : projets multiples, formes composées de couches, keyframes « pose », timeline zoomable, undo, export MP4 et GIF, animation squelette. Cette version corrige les cinq bugs de la v0.9.0 signalés en test sur appareil réel — aucune nouvelle fonctionnalité, que des corrections.

## Corrections (retours v0.9.0)

- **Timeline : les pièces ne disparaissent plus dès qu'un os existe.** En mode squelette, v0.9.0 remplaçait les barres de pièces par les barres d'os animés. Les barres de pièces sont de retour, les barres d'os animés se posent en dessous.
- **Os ancré à la pièce.** Au premier tap du mode rig, si le tap tombe sur une pièce, le nouvel os naît **lié** à cette pièce (confirmé par un message). Déplacer la pièce au repos déplace désormais l'ancrage de l'os : l'os (et sa chaîne) suit la pièce, qui reste collée à l'os.
- **Liaison os → pièce qui marche.** Au repos, tourner un os emporte les pièces liées (et celles liées aux os descendants) : la pose de repos du rig entraîne les pièces au lieu de les laisser en place. Avec keyframes d'os, le comportement auto-key est inchangé.
- **Rotation d'os fluide.** Le glisser d'os déclenchait des repaints erratiques (sauts visuels) : le canvas et la timeline se repeignent maintenant à chaque mise à jour du geste.
- **Playback remis en marche.** La durée d'un projet squelette valait 0 tant qu'aucune keyframe d'os n'existait (affichage « 0 s / 0 s », lecture impossible) même avec des pièces de 4 s posées. La durée tient compte des pièces ET des keyframes d'os, avec le plancher de 4 s.

## Corrections annexes

- Instances d'animation imbriquées : les poses du sous-projet sont échantillonnées à son temps de boucle propre (v0.9.0 les figeait au temps de la scène hôte).

## Analyse & tests

- `flutter analyze` : 0 problème ; **101 tests verts** (FK, échantillonnage, round-trip JSON, persistance v4, durée dérivée squelette, translation d'ancrage, emport de pièces lors d'une pose du rig).

## Migration

- Aucune : la base reste en v4, aucune donnée touchée.

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
