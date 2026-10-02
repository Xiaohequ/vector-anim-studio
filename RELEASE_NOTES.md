# Vector Anim Studio 0.22.0

## Bugfix preview

- Sélectionner une forme dont toutes les couches sont masquées ne réduit plus
  le `Stack` et ne fait plus disparaître le preview ni les autres formes.

## Miroir de chaîne d'os

- Les propriétés de l'os proposent **Miroir H** et **Miroir V**.
- Le miroir transforme l'os sélectionné et toute sa descendance autour du
  centre de la première forme liée, ainsi que les formes/couches portées.
- Les keyframes d'angle et de translation d'os et les poses de transformation
  des formes sont réfléchies à tous les instants ; un miroir est une action
  annulable unique.

### Tests

- **262/262 tests** passés ; `flutter analyze` : aucun problème.
- Régression du preview avec la seule couche masquée : vérifiée.
- Miroir des os, keyframes de formes et d'os, chaîne et undo : vérifiés.
