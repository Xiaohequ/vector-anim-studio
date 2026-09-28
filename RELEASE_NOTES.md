# Vector Anim Studio 0.16.3

## Correction (le curseur de l'éditeur démarre au playhead du studio)

- **Symptôme** : le snack affichait toujours « Pose à 0,00 s enregistrée
  (morph) », même en éditant à 2 s — et les poses s'accumulaient à 0 s
  au lieu de se répartir sur la timeline.

- **Cause** : le curseur du preview de l'éditeur de forme était initialisé
  au début de la fenêtre de la forme (0 s), indépendamment de la position
  de la tête de lecture du studio. Scrubber le studio à 2 s puis ouvrir
  l'éditeur remettait le curseur à 0 : chaque glisser de point écrivait
  donc sa pose à 0 s. C'était aussi la cause racine du « pas de
  morphing » signalé en 0.16.2.

- **Fix** : l'éditeur démarre maintenant à l'instant affiché par le
  studio (borné à la fenêtre de la forme). Scrubber → ◆ → éditer garde
  le même instant, l'auto-key écrit la pose à CET instant et le snack
  l'affiche correctement (« Pose à 2,00 s »).

- Validation : **215/215 tests** (dont 1 nouveau : pose écrite à 2000 ms
  après scrub studio), `flutter analyze` 0 problème.

Version précédente (0.16.2) : premier glisser de point = première pose
pour une pièce squelette sans keyframe, ◆ dans la ligne du curseur de
l'éditeur, snack de confirmation, aide contextuelle du morph.
