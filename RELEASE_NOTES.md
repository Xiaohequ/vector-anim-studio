# Vector Anim Studio 0.11.0

## Nouveautés

- **Format d'échange simple « vasf-1 » pour agents IA** : un JSON compact (secondes, degrés, couleurs `#RRGGBB`, noms au lieu d'ids) décrivant une animation complète — formes primitives, keyframes (poses partielles permises, les propriétés absentes sont portées) et **squelette complet** (os avec `joint`/`angle` en monde, liaisons par noms, keyframes d'os avec angle absolu + opacité/étirement/écrasement, z, IK).
- **Import dans l'app** : menu Export ▸ « Importer un JSON… » → collage (presse-papiers) dans un dialogue. Les DEUX formats sont détectés automatiquement (vasf si champ `version`, sinon le projet complet). L'import crée un NOUVEAU projet et l'ouvre. Les erreurs sont TOUTES collectées, affichées en français avec leur chemin (`shapes[2].keyframes[0].t : …`) — l'agent IA corrige et retente.
- **Export vasf** : menu Export ▸ « JSON simple — agents IA (vasf) » (fichier partagé via Telegram/partage). Les propriétés identiques à la keyframe précédente sont omises (sparse) pour rester lisible.
- **Spec + exemples livrés** : `docs/vasf-1-format.md` (spécification complète en anglais, pour les agents) et `docs/vasf-1-examples.json` (squelette saluant + balle rebondissante). Canvas par défaut vasf : 720×1280, 25 fps, fond `#14161C`.

## Limites v1 (documentées)

- Une primitive par forme ; pas d'instances imbriquées ; liaisons de couche ignorées à l'export.

## Analyse & tests

- `flutter analyze` : 0 problème ; **136 tests verts** — 11 nouveaux sur le format (round-trips vectoriel et squelette avec poses évaluées à 5 instants, keyframes partielles portées, défauts, path/bbox, noms uniquifiés, collecte d'erreurs avec chemins) + 2 tests widget (import réussi → nouveau projet ouvert et sauvegardé ; import invalide → erreurs affichées dans le dialogue qui reste ouvert).

<!--
Ce fichier est utilisé tel quel comme description de chaque release GitHub.
Il est lu par le workflow .github/workflows/android.yml (body_path), puis complété
d'un pied de page (version · build · commit). Le mettre à jour AVANT chaque push.
-->
