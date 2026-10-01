# Vector Anim Studio 0.21.2

## Éditeur d'os

- La forme sélectionnée est désormais **toujours centrée au milieu du
  preview**, même lorsqu'elle porte des keyframes de transformation : les
  keyframes de position ne décalent plus la pièce dans l'éditeur.
- La pièce reste visible dans l'éditeur même si le playhead du studio est
  hors de sa fenêtre d'affichage.

## Visibilité des os

- Seul l'**os sélectionné** est affiché sur le preview : à la désélection,
  l'overlay d'os disparaît.
- Un os lié à une forme est **masqué lorsque le playhead sort de la fenêtre
  `startMs → endMs`** de cette forme, comme la pièce elle-même.
- Un os masqué ne peut plus être sélectionné, pivoté ni manipulé par IK.

## Keyframes d'os

- Une keyframe d'os ne peut être posée ou modifiée que lorsque le **curseur
  de lecture est dans le rectangle** de la forme liée sur la timeline :
  le ◆ de la playbar, les sliders opacité/étirement/écrasement et les
  gestes de rotation / IK / translation keyframée sont bloqués hors segment.

### Tests

- **259/259 tests** passés.
- `flutter analyze` : aucun problème.
