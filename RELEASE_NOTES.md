# Vector Anim Studio 0.9.0

Studio d'animation vectorielle pour Android : projets multiples, formes composées de couches, keyframes « pose », timeline zoomable à rectangles d'affichage, undo, export MP4 et GIF — et maintenant l'**animation squelette**.

## Nouveautés (depuis 0.8.0)

- **Type de projet « Animation squelette »** : à la création d'un projet, on choisit entre *Vectorielle* (comportement historique) et *Squelette*. Un projet squelette = un personnage riggé : on dessine des pièces, on construit un rig d'os, et ce sont les os qui portent toute l'animation (rig maître, façon cut-out).
- **Rig d'os hiérarchique** : création au toucher (articulation puis extrémité, l'os se parente à l'os sélectionné — les chaînes se construisent naturellement). Glisser l'extrémité d'un os = rotation FK, les os enfants suivent. Les sliders de la pièce liée restent utilisables comme offset de repos dans le repère de l'os.
- **Keyframes d'angle par os** : bouton ◆ au curseur (mêmes sémantiques que les poses de forme : toggle, auto-key dès la première keyframe, snap à ~8 px, easings linéaire/entrée/sortie/entrée-sortie/palier). La timeline affiche une **barre verte par os animé** — appui long pour décaler toute la piste, losanges supprimables près de la tête de lecture.
- **Durée dérivée avec plancher** : la durée d'un projet squelette suit la dernière keyframe (plancher de 4 s tant qu'un rig existe, pour garder le curseur déplaçable avant la première pose).
- **Undo complet sur le rig** : création/suppression d'os, liaison/déliaison, keyframes, glissements — tout passe par la pile des 20 dernières actions.
- **Export** : MP4, GIF, PNG et JSON fonctionnent sur les deux types de projet (le rig est évalué à chaque frame).

## Hors périmètre (à venir)

- Liaison au niveau **couche** (0.9.1) : une couche précise d'une pièce liée à un os.
- **Import d'une animation squelette dans un projet vectoriel** (0.9.1) : le personnage riggé devient un acteur posable dans une scène.
- IK 2 os, ordre de dessin par os, squash/stretch par os (0.10+).

## Corrections

- Analyse statique propre ; **95 tests verts** (FK : chaînes statiques/animées, échantillonnage, round-trip JSON, persistance v4, barres d'os, dialogue de création).

## Migration

- Base v3 → v4 : deux colonnes ajoutées sur `projects` (`type`, `skeleton`). Additif et silencieux : les projets existants restent des projets vectoriels, aucune donnée touchée.

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
