# Vector Anim Studio 0.7.0

Studio d'animation vectorielle pour Android : projets multiples, formes composées de couches, keyframes « pose », timeline zoomable à rectangles d'affichage, undo, export MP4 et GIF.

## Nouveautés (depuis 0.5.0)

- **Timeline zoomable** : pincement à deux doigts = zoom ancré (le temps sous le doigt reste immobile), glisser à deux doigts = défilement horizontal, boutons ＋ / － / ajuster dans l'en-tête. Échelle de temps de 500 ms (≈ 15 images) à 30 minutes en pleine largeur ; règle graduée adaptative (50 ms → 30 min) ; la tête de lecture reste visible pendant la lecture.
- **Déplacement de segment** : appui long sur un rectangle de la timeline puis glisser horizontal — durée intacte et keyframes décalées du même delta. Déposé sur un temps occupé, le segment atterrit automatiquement sur une nouvelle ligne. Tap = sélection, glisser = scrub, poignées = redimensionnement (inchangés).
- **Duplication de forme** : menu Formes ▸ « Dupliquer (avec ses keyframes) » — couches et keyframes copiées à l'identique, même fenêtre (le clone atterrit sur la ligne en dessous). Instances d'animation incluses.
- **Annuler (⎌) les 20 dernières actions** : pile de snapshots en session dans la barre de lecture. Couvre formes (ajout/suppression/duplication/renommage/ordre/visibilité), couches, keyframes (ajout/retrait/preset/courbe), déplacement et redimensionnement de segment, gestes canvas — un geste = une annulation. La lecture, le scrub, le zoom et la sélection ne consomment pas d'annulation. Pas de redo (volontaire).
- **Durée du projet dérivée du contenu** : plus de durée à la création (nom + format seulement). La durée = fin du dernier segment de la timeline : poser/déplacer/allonger une forme l'étend, supprimer la dernière forme la raccourcit. Seek, boucle, zoom et export suivent en direct.
- **FPS réglé à l'export** : plus de fps à la création. L'export MP4 ouvre un dialogue de choix (15/24/25/30/60, défaut 30) ; GIF (10/12/15/25, défaut 12). Le dernier choix est proposé comme défaut à l'export suivant.

## Corrections

- **Barres de timeline déformées au zoom** : la largeur des rectangles était calculée en sens inverse (durée × ms/pixel) — chaque forme occupait tout l'écran et bloquait le défilement/zoom. Corrigé : largeur = durée × (pleine largeur / temps affiché).
- **Scrub sur les barres** : le glisser déplace maintenant la tête de lecture même au-dessus d'un rectangle, et un pincement interrompt proprement un déplacement de forme en cours.
- **Nom des clones** : « null (copie) » s'affichait à la duplication (nom masqué par un paramètre).
- Analyse statique propre ; **71 tests verts**.

## Migration

- Aucune migration : la durée n'est plus stockée en dur, elle est recalculée du contenu ; la colonne `duration_ms` de la base est réécrite à chaque sauvegarde. Les projets existants restent inchangés.

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
automatiquement par un pied de page avec la version et le SHA du build.
Les expressions GitHub (${{ ... }}) ne sont PAS évaluées ici : ce fichier est statique.
À CHAQUE RELEASE : mettre à jour ce fichier AVANT le push.
-->
