# Keyform Studio 0.38.3

## Timeline : défilement fluide quand c'est zoomé

- Les segments sont découpés à la vue : à fort zoom, un segment peut mesurer des dizaines de milliers de pixels de large, et Flutter peignait alors son fond arrondi et son nom sur toute cette largeur, même hors écran. Seule la portion visible est désormais dessinée.
- Le fond, le liseré de groupe, le nom et les keyframes d'un segment sont peints en une seule passe, au lieu d'empiler un conteneur décoré, un texte et un painter.
- Le nom d'un segment n'est plus peint quand on a défilé loin à l'intérieur : il n'apparaît qu'à son début.

## Vérifications

- `flutter analyze` sans problème.
- Suite complète : 312 tests réussis, dont les garde-fous de performance et les tests de gestes de la timeline.
- Build Android et publication de la release par GitHub Actions.
