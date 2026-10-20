# Keyform Studio 0.39.0

## Groupes d'éléments dans le format VASF (version 6)

- Le format d'échange VASF accepte désormais les **groupes d'éléments** : une clé racine `groups` déclare les groupes (nom, couleur de piste, visibilité, repliage, transformation statique) et chaque forme s'y rattache par `groupId`.
- Le `groupId` d'une forme est le **nom** du groupe, pas un identifiant interne : l'import résout le rattachement après la création des groupes, donc l'ordre des clés JSON n'a pas d'importance. Un nom inconnu produit une erreur explicite en français.
- Un groupe ne porte ni keyframes ni os : son étendue temporelle se déduit de ses formes. Un groupe masqué (`visible: false`) cache toutes ses formes.
- L'export passe en `version: 6` dès qu'une forme appartient à un groupe, et n'émet que les groupes qui contiennent au moins une forme. Les champs restés à leur valeur par défaut sont omis.
- Les groupes restent à plat : pas d'imbrication, une forme dans un seul groupe.

## Transformation des groupes

- Les réglages **Décalage X/Y, Rotation, Échelle X/Y** d'un groupe sont désormais **appliqués au rendu** : ils enveloppent la pose de chaque forme du groupe.
- La rotation et l'échelle tournent autour du **centre visuel du groupe** (moyenne des positions de repos de ses formes), pas de l'origine du canvas : un groupe se transforme là où il est.
- Un groupe laissé aux valeurs par défaut rend exactement comme des formes non groupées.
- Les cinq réglages sont accessibles dans **Éléments ▸ Transformation du groupe**, avec annulation et sauvegarde différée.

## Vérifications

- `flutter analyze` sans problème.
- Suite complète : 322 tests réussis, dont sept nouveaux tests sur les groupes (round-trip par nom, groupe inconnu, groupe vide non exporté, et quatre sondes pixel sur la transformation : décalage, rotation, échelle, neutralité, masquage).
- Validateur Python et aperçu headless alignés sur la version 6.
