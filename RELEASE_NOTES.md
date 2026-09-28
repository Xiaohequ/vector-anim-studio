# Vector Anim Studio 0.16.2

## Correction (morph de points dans l'éditeur)

- **Le morph de points ne s'enregistrait pas au doigt.** Deux causes
  combinées : sans aucune keyframe sur la pièce, le glisser d'un point
  éditait les points de BASE en silence (aucun ◆ n'apparaissait sur la
  timeline — les keyframes visibles étaient celles des os, pas de la
  pièce) ; et une seule pose portant le morph fige la forme partout
  ailleurs : il faut deux poses pour animer, ce qui n'était indiqué
  nulle part.

- **Le premier glisser crée la première pose** : en projet squelette,
  une pièce sans aucune keyframe enregistre désormais son premier
  glisser de point comme pose au curseur (semée du rendu courant, donc
  visuellement neutre ; le dessin de base reste intact).

- **◆ dans l'éditeur** : la ligne du curseur du preview gagne un losange
  poser/retirer une keyframe à l'instant affiché — plus besoin de
  retourner au studio pour poser le second instant du morph.

- **Retour visuel** : au relâchement d'un glisser qui a écrit une pose,
  un message « Pose à X,XX s enregistrée (morph) » confirme l'auto-key ;
  l'aide sous le curseur s'adapte à l'état (base / auto-création / une
  seule pose / morph actif).

- **Workflow morph** (projet squelette) : ◆ à l'instant A → déplace les
  points → scrub l'autre instant → ◆ → déplace les points → Lecture :
  le chemin s'interpole entre les deux poses.

- Validation : **214/214 tests** (dont 3 nouveaux), `flutter analyze`
  0 problème.

Version précédente (0.16.1) : le ◆ de la barre de lecture anime la pièce
sélectionnée d'un projet squelette ; feuille ⚙ des pièces avec losange de
pose et Interpolation.
