# Vector Anim Studio 0.24.0

## Caméra des previews

- Zoom maximum porté à **800 %** dans l’éditeur de forme et le Studio.
- Ajout d’un mode **Déplacer la vue** dans les deux previews : le glisser déplace
  la caméra sans déplacer les formes ou les os. Le mode se désactive en retapant
  l’icône main.
- **Ajuster** réinitialise le zoom à 100 % et recentre le cadrage.
- Le pan est appliqué à la scène et à ses overlays ; sélection et géométrie
  restent alignées dans l’éditeur comme dans le Studio.

## Plein écran Studio

- Le mode plein écran de la version précédente reste disponible ; la caméra
  (zoom et pan) est partagée avec le preview normal.

### Vérifications

- Tests ciblés caméra, géométrie et gestes : passés.
- Suite complète : **266/266 tests** ; `flutter analyze` : aucun problème.
