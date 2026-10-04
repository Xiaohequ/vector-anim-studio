# Keyform Studio 0.28.3

## Groupes squelette : transport par l'os sans keyframe

- Lorsqu'un os hôte bouge ou pivote en pose de repos, le groupe squelette lié
  est maintenant transporté avec lui, comme une forme normale.
- Les keyframes propres au groupe restent conservées ; l'auto-key de l'os
  continue d'utiliser son chemin d'animation distinct.
- Le nom du groupe sur la timeline reste sans emoji.

### Vérifications

- Test de rendu mesurant le déplacement du groupe après le déplacement de repos
  d'un os, sans créer de keyframe sur le groupe.
- La CI doit confirmer l'analyse, la suite complète et le build APK avant
  publication.
