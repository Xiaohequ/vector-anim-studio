# Keyform Studio 0.38.2

## Timeline : défilement fluide sur les projets chargés

- Les keyframes ne sont plus des widgets : elles sont peintes en une seule passe. Une timeline de 40 pièces × 20 poses construisait plus de 800 widgets interactifs par frame ; elle en construit désormais un nombre constant.
- Seuls les segments visibles sont construits : un projet de plusieurs dizaines de pièces ne paie plus le prix des segments hors du cadre.
- L'empilement des lignes est mémoïsé : il n'est plus recalculé à chaque frame de défilement.
- Les poignées de redimensionnement n'apparaissent que sur le segment sélectionné.
- La sélection des keyframes garde sa zone cliquable d'environ 10 px, quel que soit le zoom.

## Vérifications

- `flutter analyze` sans problème.
- Suite complète : 312 tests réussis, dont deux garde-fous de performance (le nombre de widgets ne dépend plus du nombre de keyframes ; les segments hors vue ne sont pas construits).
- Build Android et publication de la release par GitHub Actions.
