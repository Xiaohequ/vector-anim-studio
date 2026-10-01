# Vector Anim Studio 0.20.2

## Retours v0.20.1 : pivot de l'os, sélecteur masqué, accès depuis la feuille d'os

### 1. L'os se pivote dans l'éditeur

- **Glisser l'EXTRÉMITÉ** d'un os = le **pivoter** autour de son
  articulation (longueur inchangée ; les descendants suivent en FK, le
  repère du parent est respecté).
- **Glisser le MILIEU** d'un os = le **déplacer** (comportement précédent :
  la forme reste ancrée au milieu de l'écran).
- Delta incrémental d'angle (normalisé ±π) : aucun saut de ±200° au
  passage de la coupure.
- Indice sous le preview mis à jour : *« glisser au MILIEU d'un os = le
  déplacer, sur son EXTRÉMITÉ = le pivoter »*.

### 2. Plus de sélecteur de forme dans l'éditeur d'os

- Le cadre de sélection de la pièce n'est plus affiché : on dessine
  **sur** la forme, le cadre ne faisait que gêner.

### 3. Bouton « Ouvrir l'éditeur d'os… » dans les propriétés de l'os

- La feuille **Propriétés de l'os** (⚙ de l'os sélectionné sur le
  preview) gagne un bouton qui ouvre directement le même éditeur, sur la
  forme portée par cet os (racine **ou** descendance).
- Aucune forme liée → message explicite au lieu d'un écran vide.

### Tests

- +3 (aucun sélecteur de forme, pivot avec articulation fixe + forme
  immobile, bouton de la feuille d'os qui ouvre l'éditeur) — **257/257**,
  `flutter analyze` 0 problème.

## Ce qui n'a pas bougé (validé v0.20.1)

- Accès à l'éditeur depuis la feuille ⚙ de la forme : **ok**.
- Glisser un os sans bouger la forme : **ok**.