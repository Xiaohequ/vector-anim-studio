# Keyform Studio 0.36.0

## Langue et informations de l’application

- Nouvelle page **Paramètres** accessible depuis l’accueil, avec sélection de la langue : système, français, anglais ou chinois.
- Le choix explicite est mémorisé localement et appliqué immédiatement. En mode système, une langue non prise en charge bascule en anglais.
- Localisation des pages principales, du Studio, des éditeurs, des panneaux de propriétés, des menus, de la timeline et des dialogues en français, anglais et chinois.
- Section **Informations** : version installée de l’application, notice de confidentialité et accès aux licences open source Flutter.
- Notice de confidentialité intégrée et localisée ; elle explique le stockage local des projets, l’import/export et le partage à la demande.

### Vérifications

- `flutter analyze` sans problème.
- `flutter analyze` sans problème ; tests de widgets des paramètres, de la notice et de l’accès aux licences passés. Suite complète : lancée, mais le délai local a expiré à 289 tests ; validation complète à confirmer par la CI GitHub.
