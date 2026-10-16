# Keyform Studio 0.37.0

## Sélection des keyframes sur la timeline

- Zone de sélection d’environ 10 px de part et d’autre du marqueur, quelle que soit l’échelle de zoom.
- Clic sur une keyframe distante : la tête de lecture rejoint la keyframe ; clic à proximité de la tête de lecture : la keyframe est supprimée.

## Vérifications

- `flutter analyze` sans problème.
- Tests de la timeline réussis aux différents niveaux de zoom.
- Build Android et publication de la release par GitHub Actions.
