# Vector Anim Studio 0.9.2

Studio d'animation vectorielle pour Android : projets multiples, formes composées de couches, keyframes « pose », timeline zoomable, undo, export MP4 et GIF, animation squelette. Cette version affine le rigging suite aux retours de la v0.9.1 : os 2 attaché automatiquement à l'os 1, liaison os↔pièce uniquement manuelle, sélection exclusive et boutons dédiés pour l'os.

## Nouveautés

- **Os 2 attaché automatiquement à l'os 1.** Au premier tap du mode rig, le parent du nouvel os est détecté par priorité : extrémité d'os touchée (l'articulation s'y accroche exactement — le poignet), sinon segment d'os touché, sinon pièce touchée → l'os qui la porte, sinon l'os sélectionné. L'ancrage posé suit ensuite tout mouvement de l'os parent (rotation, déplacement) — plus jamais de décalage entre l'endroit cliqué et l'articulation (bug v0.9.1 : elle était placée au deuxième tap).
- **Bouton ⚙ propriétés de l'os sur le preview** : quand un os est sélectionné, un bouton apparaît ancré à son segment (comme le bouton des formes) et ouvre la sheet os (longueur, parent, renommer, supprimer, keyframe, easing). À côté, un bouton ✥ **Déplacer l'os** : mode où tout glisser translate l'ancrage de l'os — la chaîne descendante ET les pièces liées suivent le doigt.
- **Sélection exclusive os / forme** : sélectionner un os désélectionne la forme (et inversement). L'utilisateur manipule soit une forme, soit un os — jamais les deux.
- **Le bouton ⚙ des formes suit le rig** : ancré à la pièce transformée par son os (plus de bouton flottant à l'écart quand l'os a tourné).

## Changement de comportement

- **La création d'os ne lie plus la pièce touchée.** À partir des retours : le nouvel os naît attaché à un os (parent), mais la liaison pièce → os reste un geste volontaire (Squelettes ▸ Lier la pièce à un os…). Délier : Squelettes ▸ Délier la pièce.

## Corrections

- Déplacer une pièce liée au repos fait suivre l'os **et la pièce suit le doigt** (emport des pièces collées à l'os : la pièce traînée ne reste plus en arrière pendant que l'os glisse).

## Analyse & tests

- `flutter analyze` : 0 problème ; **104 tests verts** (FK, round-trip, persistance v4, durée squelette, translation d'ancrage, emport de pièces, création d'os attaché au poignet y compris sur os animé).

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
