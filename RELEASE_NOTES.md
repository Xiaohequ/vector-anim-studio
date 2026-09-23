# Vector Anim Studio 0.2.0

Studio d'animation vectorielle complet pour Android : projets multiples, formes composées de couches, keyframes, timeline à rectangles d'affichage, export MP4 et GIF.

## Nouveautés

- **Écran d'accueil** : liste des projets enregistrés (nom, format, durée, fps, nombre de formes, date), création d'un projet (nom, format portrait / paysage / carré, durée, fps), projet d'exemple, renommage, duplication, suppression.
- **Menus de l'éditeur** : Formes, Animations, Calques, Export.
- **Formes et couches** : une forme est un ensemble de couches (rectangle, cercle, ligne, chemin) ; l'écran de création affiche l'aperçu en haut et la liste des couches en bas, avec ajout de formes basiques, changement de couche, taille, position, couleur, rotation, opacité, épaisseur.
- **Animations** : six presets (apparition, disparition, déplacement, rotation, pulsation, fondu) + gestion des keyframes par propriété avec courbes linéaire, easeIn, easeOut, easeInOut, step.
- **Timeline** : chaque forme est un rectangle (bord gauche = début d'affichage, bord droit = fin, poignées déplaçables) ; les formes qui se chevauchent occupent automatiquement des lignes parallèles.
- **Export vidéo** : MP4 (H.264, encodeur natif du téléphone, sans ffmpeg embarqué) et GIF animé, plus PNG de la frame courante et JSON du projet, puis partage système.
- **Persistance** : les projets sont enregistrés localement (sqflite) et rechargés au démarrage.

## Corrections

- Le ticker de l'éditeur ne tourne plus en permanence : il ne produit des frames que pendant la lecture (batterie, fluidité).
- Analyse statique : plus aucun avertissement (`flutter analyze` propre), 25 tests verts.

## Installation

1. Télécharge le fichier `.apk` ci-dessous.
2. Transfère-le sur ton téléphone Android.
3. Ouvre-le et autorise « Installer des applications inconnues » si Android le demande.

## À savoir

- Build **signé avec la clé debug** de Flutter : destiné aux tests, refusé par le Play Store.
- Le fichier `.aab` est fourni pour un futur envoi sur le Play Store.
- L'export MP4 utilise l'encodeur natif du téléphone : le rendu peut varier selon l'appareil.

<!--
Ce fichier est utilisé tel quel comme description de chaque release GitHub.
Il est lu par le workflow .github/workflows/android.yml (body_path), puis complété
automatiquement par un pied de page avec la version et le SHA du build.
Les expressions GitHub (${{ ... }}) ne sont PAS évaluées ici : ce fichier est statique.
-->
