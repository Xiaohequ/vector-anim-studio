# Vector Anim Studio 0.21.0

## Vague 2 — la timeline

### Les pistes d'os séparées ont disparu

- Les **barres d'os vertes** sous les pièces sont supprimées
  (`packBoneLanes`, `_BoneBar`, le déplacement de piste par appui long) :
  la timeline compte **une ligne par pièce**, rien de plus.
- Un os n'a plus de « segment » à lui — ses keyframes vivent sur le segment
  de la forme qu'il porte.

### Keyframes de l'os sur le segment de la forme liée

- Sur le segment d'une pièce **liée**, les losanges affichent les
  **keyframes de l'OS** ; les keyframes de la forme ne sont plus prises en
  compte pour une pièce liée.
- La suppression près de la tête de lecture (cercle rouge) supprime une
  **keyframe d'os** sur un segment lié — et une keyframe de forme sur un
  segment libre (comportement inchangé pour les pièces sans os).

### Couleur distincte

- Segment **lié à un os** : **vert** `#3ECF8E`
- Pièce **libre** : bleu primaire du thème
- **Instance** d'animation : violet

### Sélection : le segment sélectionne l'os

- Cliquer le segment d'une pièce liée sélectionne **l'OS dans le preview**
  (sélection exclusive) : cadre de sélection de la pièce disparu, boutons
  ⚙ et ✥ de l'os affichés, ◆ de la playbar qui cible l'os.
- À l'inverse, le segment se surligne quand **son os** est sélectionné.

### Conséquence à connaître

- Les keyframes de **morph / couleur / opacité** d'une pièce liée restent
  bien dans le modèle (conservées à la liaison) mais ne sont **plus
  affichées ni supprimables depuis la timeline** : elles s'écoutent via la
  feuille ⚙ (◆ + sliders) et l'éditeur de forme (curseur de temps).

### Tests — 255/255, `flutter analyze` 0 problème

- −2 tests (`packBoneLanes` supprimé avec la fonction).
- Le test « un projet squelette affiche une barre d'os » devient
  **« segment lié : keyframes de l'os, couleur, clic = os sélectionné »**
  et vérifie les 4 exigences : plus de piste 🦴, losanges = keyframes de
  l'os (2) et non de la forme (1), fond vert `#3ECF8E`, clic → ⚙ de l'os
  présent et ⚙ de la forme absent.