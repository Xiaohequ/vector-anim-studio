# Vector Anim Studio 0.20.3

## Un seul os par forme dans l'éditeur

- **Retour v0.20.2** : « Éditeur os : ne pas autoriser d'ajouter plusieurs
  os ».
- Dès qu'un os existe, **les taps ne créent plus rien** dans l'éditeur :
  l'indice sous le preview devient *« La forme a déjà son os — glisser au
  MILIEU = le déplacer, sur son EXTRÉMITÉ = le pivoter »*.
- **Déplacement et pivot restent pleinement actifs** sur l'os (et sur
  chaque os d'un projet importé qui porte une chaîne).
- L'enregistrement (✓) porte toujours l'**unique** os de la forme, déjà
  lié automatiquement.

### Conséquence à connaître

- On ne **crée** plus de chaîne d'os depuis l'éditeur : la règle « 1 forme
  = 1 os » prime (D.1 revu par ce retour). Un fichier importé qui contient
  déjà une chaîne reste entièrement modifiable (déplacer / pivoter chaque
  os) ; la création d'os enfants est à redéfinir si tu en as besoin.

### Tests

- Le test « chaîne : tap sur le poignet → os 2 » devient **« un seul os :
  dessiné, les taps n'en ajoutent plus »** (2ᵉ tentative refusée + indice,
  résultat = 1 os lié). **257/257**, `flutter analyze` 0 problème.