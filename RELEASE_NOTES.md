# Keyform Studio 0.28.0

## Projets squelette imbriqués en tant que groupes

- Dans un projet squelette, **Formes → Insérer un projet squelette…** ajoute un
  sous-projet existant comme élément de groupe animé. Le source reste un projet
  distinct et peut être ouvert depuis les propriétés du groupe.
- **Importer un VASF comme groupe…** importe un fichier JSON VASF squelette et
  l'enregistre comme nouveau sous-projet avant de l'insérer ; le JSON doit
  contenir une section `skeleton`.
- Le groupe conserve sa transformation, ses keyframes de pose, ses pivots,
  miroirs horizontal/vertical et peut être attaché à un os du rig hôte. Le
  binding pilote le groupe par le rig sans perdre les transformations de groupe.
- Le groupe squelette apparaît sur la timeline comme un seul élément, avec
  segment orange et icône 🦴 ; ses keyframes de groupe restent éditables.
- Les propriétés de groupe (type d'instance et miroirs) sont persistées en base
  (schéma v8). La prévisualisation recentre et adapte le sous-projet dans le
  cadre du groupe.

## Import de fichier à l'accueil

- L'import JSON reste disponible depuis l'écran d'accueil, crée un projet neuf
  et ne remplace jamais un projet existant, même si l'ID apparaît dans le JSON.

### Vérifications

- Tests ciblés : import de groupe VASF, insertion et keyframes de groupe,
  persistance de l'instance squelette et timeline : passés.
- La CI doit confirmer `flutter analyze`, la suite complète et le build APK sur
  la PR avant publication de la release.
