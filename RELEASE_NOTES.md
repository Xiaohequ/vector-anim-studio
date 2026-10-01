# Vector Anim Studio 0.21.1

## Corrections timeline, preview et sélection

- La visibilité d'une pièce respecte désormais toujours son rectangle
  `startMs → endMs`, y compris dans un projet squelette : des keyframes d'os
  situées après la fin du segment ne prolongent plus l'affichage de la pièce.
- Hors de cette fenêtre, la pièce n'est plus sélectionnable dans le preview et
  son bouton ⚙ n'est plus affiché.
- La sélection d'une forme depuis la timeline désélectionne l'os
  précédemment sélectionné ; la sélection d'un segment lié continue de
  sélectionner son os.

### Tests

- **257/257 tests** passés.
- `flutter analyze` : aucun problème.
