# Vector Anim Studio 0.3.0

Studio d'animation vectorielle complet pour Android : projets multiples, formes composées de couches, keyframes « pose », timeline à rectangles d'affichage, export MP4 et GIF.

## Nouveautés

- **Keyframes « pose »** : une keyframe porte désormais **toutes les propriétés** de la forme (position, rotation, échelle, opacité, épaisseur) au lieu d'une seule. L'interpolation entre deux keyframes s'applique à toutes les propriétés et est immédiatement visible dans l'aperçu.
- **Auto-key** : dès qu'une forme possède au moins une keyframe, toute modification de propriété écrit une keyframe à la position du curseur (plus besoin de créer la keyframe à part).
- **Aperçu réactif** : au repos, bouger un réglage repeint immédiatement le canvas (le comparateur de repaint comparait un objet mutable partagé et ignorait les changements de valeur).
- **Bouton de suppression contextuel** : quand la tête de lecture passe près d'une keyframe sur la timeline, celle-ci affiche un bouton ✕ rouge pour la supprimer.
- **Snap des keyframes** : l'ajout d'une keyframe à proximité d'une existante (≈ 8 px) la remplace au lieu d'en créer une seconde à quelques millisecondes d'écart.
- **Sélecteur d'interpolation** : la courbe du segment (linéaire, entrée, sortie, entrée/sortie, palier) se règle dans l'inspecteur pour la keyframe sous le curseur.
- **Inspecteur simplifié** : les curseurs affichent la valeur interpolée à la tête de lecture ; une seule keyframe (losange) est gérée par forme, et les propriétés réellement animées sont marquées d'un losange jaune.

## Corrections

- Interpolation invisible dans l'aperçu : cause identifiée (repaint du canvas ignoré lorsque seule une valeur changeait, et écriture des curseurs dans la valeur de base plutôt que dans les keyframes).
- Analyse statique : plus aucun avertissement (`flutter analyze` propre), 27 tests verts.

## Migration

- La base locale passe en **schéma v2** : les anciennes pistes par propriété sont automatiquement regroupées en poses complètes au premier lancement. Aucune perte de projet.

## Installation

1. Télécharge le fichier `.apk` ci-dessous.
2. Transfère-le sur ton téléphone Android.
3. Ouvre-le et autorise « Installer des applications inconnues » si Android le demande.

## À savoir

- Build **signé avec la clé debug** de Flutter : destiné aux tests, refusé par le Play Store.
- La CI ne produit que l'APK (pas d'App Bundle `.aab`).
- L'export MP4 utilise l'encodeur natif du téléphone : le rendu peut varier selon l'appareil.

<!--
Ce fichier est utilisé tel quel comme description de chaque release GitHub.
Il est lu par le workflow .github/workflows/android.yml (body_path), puis complété
automatiquement par un pied de page avec la version et le SHA du build.
Les expressions GitHub (${{ ... }}) ne sont PAS évaluées ici : ce fichier est statique.
-->
