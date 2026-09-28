# Vector Anim Studio 0.16.1

## Correction (bugfix retours v0.16.0)

- **Projet squelette : les keyframes de pièce étaient incréables.** Avec
  une pièce sélectionnée, le ◆ de la barre de lecture ne faisait rien :
  il visait systématiquement un os, et la sélection étant exclusive
  (os OU pièce), aucun os n'était sélectionné — le bouton no-opait. La
  feuille ⚙ masquait en plus le losange de pose pour les pièces.

- **Le ◆ cible désormais ce qui est sélectionné** : un os sélectionné →
  keyframe d'angle de l'os (comportement inchangé) ; sinon une pièce →
  keyframe de pose complète (position, rotation, échelle, échelle par
  axe, opacité, épaisseur). On peut donc animer la pose d'une pièce dans
  un projet squelette, y compris le morph de points de la v0.16.0 :
  ◆ au studio, glisser les points dans l'éditeur à un autre instant,
  rejouer.

- **Feuille ⚙ d'une pièce** : le losange de pose et la ligne
  « Interpolation » (easings partagés) sont affichés pour les pièces ;
  la note signale « aucune keyframe » tant qu'il n'y en a pas.

- Validation : **211/211 tests** (dont 2 nouveaux : pose de pièce au ◆
  de la playbar, feuille ⚙ d'une pièce), `flutter analyze` 0 problème.

Version précédente (0.16.0) : éditeur de points in-app — poignées de
points sur les couches Chemin, curseur de temps sous le preview, auto-key
du morph, ajout/suppression de points au doigt.
