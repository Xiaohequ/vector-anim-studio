# Vector Anim Studio 0.20.0

## L'os n'existe plus que par une forme (vague 1 : parcours os/forme)

### Nouvel éditeur d'os

- Boutons **« Ajouter un os… »** et **« Modifier l'os… »** dans la feuille ⚙
  de la forme : ils ouvrent un écran dédié qui contient **la seule forme
  sélectionnée**, **centrée et ancrée au milieu de l'écran** (canvas calé
  sur la boîte englobante ×1,6 pour dessiner précisément).
- **Dessin** : tap ① = articulation, tap ② = extrémité. Un tap ① près d'un
  os existant (poignet ou segment) l'attache → **les chaînes et l'IK restent
  possibles** (D.1).
- **Déplacement** : glisser un os le déplace **sans déplacer la forme**
  (`translateBoneRest`, sans emport des pièces) — la forme reste ancrée au
  centre.
- ✓ renvoie les os **reconvertis en coordonnées projet** ; bouton désactivé
  tant qu'aucun os n'est dessiné.

### Liaison avec effacement contrôlé (D.2)

- Le ✓ lie la forme à l'os **racine** dessiné (sélection exclusive : c'est
  l'os qui porte la pièce désormais).
- **Confirmation AVANT** : si la forme porte des keyframes de
  **TRANSFORMATION**, un dialogue annonce leur suppression avant même
  d'ouvrir l'éditeur. Seules position/rotation/échelle sont effacées —
  **morph, couleurs de couche et opacité sont conservées** ; une keyframe
  devenue vide disparaît.

### « Supprimer l'os »

- Nouveau bouton **« Supprimer l'os »** dans la feuille ⚙ (couleur
  d'avertissement) : dialogue de confirmation annonçant le décompte
  (n os, m keyframes) puis suppression de l'os porteur, de **toute sa
  descendance**, de leurs pistes de keyframes et du lien. La pièce
  redevient libre et sélectionnable.

### Menus (D.4) et studio (D.5)

- **Menu « Squelette » supprimé** (ajout d'os, liaison/délier, renommer ou
  supprimer le rig, liste des os) : le bas de barre garde **Formes +
  Animations** dans les projets squelette.
- Le **mode rig 2-taps sur le canvas du studio** est retiré (remplacé par
  l'éditeur) ; **✦, rotation et IK restent dans le studio** pour animer.
- Les lignes **« Couches liées au rig »** (Lier…/Délier par couche) sortent
  de la feuille : la liaison est au niveau forme.
- Sélection d'os maintenue en tapant dessus sur le canvas.

### Modèle

- `SkeletonRig.chainFrom()` + `removeBoneForShape()` : suppression d'une
  chaîne entière (os, descendance, pistes, liaisons).
- `VectorShape.transformKeyframeCount` / `clearTransformKeyframes()` :
  effacement ciblé des transformations.

### Tests — 253/253, `flutter analyze` 0 problème

- +6 : `test/bone_editor_test.dart` (4 — dessin en 2 taps avec conversion en
  coordonnées projet, chaîne par aimantation au poignet, glisser d'os sans
  bouger la forme, bouton d'enregistrement désactivé) et 2 dans
  `widget_test.dart` (confirmation avant effacement des keyframes,
  suppression complète os + descendance + keyframes + lien).
- **Pièges de harnais rencontrés** : `find.byTooltip` renvoie le `RawTooltip`
  et non l'`IconButton` → `find.widgetWithIcon` ; la liste `const` des os
  refuse l'ajout au premier dessin (`List.of`) ; les taps arrivent en
  coordonnées **canvas** alors que les os vivent en coordonnées **scène**
  (`canvasToScene`) ; le premier move d'un geste est avalé par la slop
  (18 px) — il faut un second move pour voir le déplacement.