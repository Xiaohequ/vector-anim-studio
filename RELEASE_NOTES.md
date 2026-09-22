# Vector Anim Studio

Studio d'animation vectorielle pour Android (et iOS à venir) : formes vectorielles, keyframes par propriété, timeline scrubbable.

## Nouveautés

- Première version publique du studio : scène, formes (rectangle, cercle, ligne, chemin), inspecteur complet.
- Animation par keyframes : position, taille, rotation, échelle, opacité, épaisseur de trait — interpolation linéaire, easeIn, easeOut, easeInOut, step.
- Timeline avec tête de lecture déplaçable, lecture/pause, boucle, affichage des keyframes.
- Export du projet en JSON (fichier ou presse-papier) et export PNG de la frame courante.

## Installation

1. Télécharge le fichier `.apk` ci-dessous.
2. Transfère-le sur ton téléphone Android.
3. Ouvre-le et autorise « Installer des applications inconnues » si Android le demande.

## À savoir

- Build **signé avec la clé debug** de Flutter : destiné aux tests, refusé par le Play Store.
- Le fichier `.aab` est fourni pour un futur envoi sur le Play Store.

<!--
Ce fichier est utilisé tel quel comme description de chaque release GitHub.
Il est lu par le workflow .github/workflows/android.yml (body_path), puis complété
automatiquement par un pied de page avec la version et le SHA du build.
Les expressions GitHub (${{ ... }}) ne sont PAS évaluées ici : ce fichier est statique.
-->