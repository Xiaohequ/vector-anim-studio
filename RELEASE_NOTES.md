# Vector Anim Studio 0.19.1

## Pièce liée à un os : plus aucune manipulation au doigt

### Au canvas

- **Non sélectionnable** : taper une pièce portée par un os ne la
  sélectionne plus (aucun bouton ⚙, aucun geste possible). Le message
  nomme l'os porteur et rappelle la passerelle : menu Formes (pour ouvrir
  la sheet ⚙ ou la délier).
- **Tous les gestes de transformation bloqués** quand une telle pièce est
  sélectionnée via le menu : déplacement, **rotation** ET **échelle**
  (pincement). La garde est posée AVANT les branches de geste — un seul
  point de contrôle. Message « transformations bloquées » si le doigt est
  posé sur la pièce (ailleurs : geste ignoré en silence, comme avant).
- **Restent libres** : les gestes d'os (poignée ✥, rotation d'os, IK) —
  c'est le seul moyen de la déplacer, avec la dissociation
  (menu Squelettes ▸ Délier la pièce).

### Feuille de propriétés ⚙

- Sliders **Position X/Y, Rotation, Échelle, Échelle X/Y désactivés** pour
  une pièce liée, avec un rappel en ambre placé au-dessus des sliders.
- **Opacité** et **Épaisseur** restent libres : elles ne déplacent pas la
  pièce. Pièce non liée : aucun verrou, aucun avertissement.

### Modèle

- `SkeletonRig.isAttached(shapeId)` + `carrierBoneId(shapeId)` : détecte
  la liaison de la forme **entière**, sinon la première **couche** liée de
  cette forme.

### Changement de comportement

- Le glisser d'une pièce liée **au repos** ne déplace plus l'ancrage de
  l'os (comportement v0.9.5 « l'os suit la pièce ») : le verrou a la
  priorité. Déplacer l'ancrage se fait par la poignée ✥ de l'os.

### Tests

- **247/247**, `flutter analyze` 0 problème. +11 tests :
  `test/bound_shape_lock_test.dart` (7 : 3 modèle, 4 sheet ⚙) et
  `widget_test.dart` (4 : glisser bloqué + témoin non lié, tap non
  sélectionnable, pincement bloqué, rotation par poignée bloquée).
- **Pièges de harnais rencontrés** :
  - la preview du studio est clamped à ~200 px en fenêtre 800×600
    (échelle 0,159) : un test de glisser doit donner au canvas une fenêtre
    haute (800×1400 → ~366 px, échelle 0,286) ET une pièce assez grande
    (400×300) pour que le pointeur reste dedans pendant la slop du
    recognizer (18 px) — sinon `SelectionGeometry.hit` est faux et « rien
    ne se passe » sans aucun message d'erreur ;
  - `_load()` **auto-sélectionne la dernière forme** au chargement : un
    test de « non sélectionnable » doit d'abord désélectionner (tap sur
    l'os, sélection exclusive) ;
  - le **SnackBar** apparaît en bas et recouvre la barre d'outils : le
    laisser se fermer (pomper 5 s) avant d'utiliser un menu ;
  - l'os de test doit être **loin** de la pièce : `segmentTouchSlop` 13 px
    et `tipTouchSlop` 26 px font que le tap sur la pièce est absorbé par
    l'os s'il est trop proche.