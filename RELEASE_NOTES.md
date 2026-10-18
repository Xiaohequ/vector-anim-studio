# Keyform Studio 0.38.0

## Timeline : règle collante et gestes clarifiés

- La règle de temps reste visible en haut de la timeline quand les lignes défilent verticalement.
- La tête de lecture ne se déplace plus que sur la règle : un tap ou un glisser horizontal sur la règle positionne le curseur.
- Partout ailleurs (fond des lignes et segments), un glisser horizontal fait défiler la timeline au lieu de déplacer le curseur.
- L'appui long sur un segment continue de déplacer le segment avec ses keyframes.

## Vérifications

- `flutter analyze` sans problème.
- Suite complète : 308 tests réussis, dont les tests de la timeline réécrits pour les nouveaux gestes.
- Build Android et publication de la release par GitHub Actions.
