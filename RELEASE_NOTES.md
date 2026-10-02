# Vector Anim Studio 0.23.0

## Zoom et plein écran du preview

- L’éditeur de forme et le Studio proposent **Zoom arrière**, **Zoom avant** et
  **Ajuster** sur le preview. Le zoom est centré et indépendant des données
  d’animation ; plage de 50 % à 400 %.
- Le Studio propose un mode **plein écran** : AppBar, timeline, playbar et barre
  d’outils sont masquées ; les barres système sont cachées. La forme et l’os
  sélectionnés sont désélectionnés à l’entrée et les overlays de sélection sont
  masqués. Le bouton de sortie et le bouton Retour quittent le mode.
- Le playhead et la lecture restent inchangés. Les gestes de transformation sont
  désactivés en plein écran afin que l’aperçu serve uniquement au visionnage.

### Tests

- Tests ciblés de géométrie du zoom, preview éditeur et mode plein écran Studio.
- Suite complète **265/265 tests** passée ; `flutter analyze` sans problème.
