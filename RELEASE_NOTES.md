# Keyform Studio 0.38.4

## Timeline : le défilement ne reconstruit plus tout le Studio

- Le zoom et le défilement de la timeline ne déclenchent plus de reconstruction de l'écran entier : la timeline se redessine seule. Le preview, les barres d'outils et les panneaux ne sont plus reconstruits à chaque pixel de défilement.
- Pendant un appui long sur un segment, le glisser déplace le segment sans faire défiler la timeline en même temps.

## Vérifications

- `flutter analyze` sans problème.
- Suite complète : 312 tests réussis.
- Build Android et publication de la release par GitHub Actions.
