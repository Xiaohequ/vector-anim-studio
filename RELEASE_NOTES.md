# Keyform Studio 0.28.4

## Groupes squelette liés : timeline pilotée par l’os

- Le segment d’un groupe squelette lié affiche désormais les keyframes de son os
  porteur ; toucher le segment sélectionne l’os, pas le groupe.
- À la liaison, toutes les keyframes propres au groupe sont supprimées ; sa
  transformation suit ensuite le comportement d’une forme liée à un os.
- Un groupe squelette lié utilise le style vert des éléments portés par un os.

### Vérifications

- Tests de timeline couvrant les losanges de l’os et la sélection de l’os depuis
  le segment d’un groupe importé.
- Test widget vérifiant la suppression des keyframes de groupe à la liaison.
- La CI doit confirmer l’analyse, la suite complète et le build APK avant
  publication.
