# Keyform Studio 0.38.1

## Timeline : le glisser horizontal est fiable

- Le défilement horizontal de la timeline ne part plus en défilement vertical : l'axe est verrouillé dès les premiers pixels du geste, puis tenu jusqu'au relâchement.
- Un glisser vertical défile les lignes, un glisser horizontal défile le temps — jamais l'un à la place de l'autre.
- La règle de temps reste collée en haut et reste la seule zone qui déplace la tête de lecture.

## Vérifications

- `flutter analyze` sans problème.
- Suite complète : 310 tests réussis, dont deux nouveaux tests qui reproduisent le conflit d'axes (glisser vertical = lignes seules, glisser horizontal = temps seul).
- Build Android et publication de la release par GitHub Actions.
