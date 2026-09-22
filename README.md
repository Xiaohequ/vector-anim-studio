# vector_anim_studio

Application Flutter (Android + iOS) pour **créer des animations vectorielles** : scène, formes vectorielles, timeline à keyframes, lecture et export.

## Objectif

Un studio d'animation vectorielle mobile : on dessine des formes, on les anime dans le temps avec des keyframes, on prévisualise en boucle, puis on exporte (projet JSON, séquence d'images, GIF).

## Périmètre MVP

1. **Scène** : canvas 2D avec zoom/pan, grille optionnelle, fond couleur/dégradé.
2. **Formes vectorielles** : cercle, rectangle, ligne, chemin (multi-points), groupe.
3. **Propriétés animables** : position, rotation, échelle, opacité, couleur, épaisseur de trait.
4. **Timeline** : durée, lecture/pause/scrub, keyframes par propriété, interpolation linéaire puis easing.
5. **Lecture** : aperçu temps réel, boucle, onglet calques.
6. **Export** : sauvegarde/chargement de projet (JSON), export PNG par frame, export GIF.

Hors MVP (backlog) : import SVG, édition de courbes de Bézier, export SVG animé, partage cloud, calques imbriqués.

## Pile technique

- Flutter stable / Dart 3 — cibles `android` et `ios`
- Rendu vectoriel via `CustomPainter` (pas d'assets images)
- État : `ChangeNotifier` + `InheritedNotifier` (dépendances minimales)
- Export : rendu offscreen `ui.PictureRecorder` → PNG ; assemblage GIF via package dédié
- Organisation cible : `lib/models` (scène, forme, keyframe), `lib/engine` (timeline, interpolation, renderer), `lib/ui` (canvas, timeline, inspecteur)

## Contraintes d'environnement (importantes)

- Le projet est généré et compilé **dans le conteneur officiel Flutter** `ghcr.io/cirruslabs/flutter:stable`, lancé sur l'hôte Docker via le socket monté dans le conteneur nanobot.
- Hôte : Ubuntu 24.04, 2 vCPU, **~954 Mo de RAM** → build Android bridé (Gradle `-Xmx512m`, `-j1`, `--no-daemon`) ou déporté sur GitHub Actions.
- **Pas de macOS** disponible : l'app est configurée pour iOS (`ios/`, bundle id), mais la compilation iOS doit passer par un runner macOS (GitHub Actions / Codemagic).

## Structure

```
vector_anim_studio/
├── app/        # projet Flutter (généré dans le conteneur Flutter)
├── docs/       # plan, décisions techniques
├── scripts/    # helpers de build/run via Docker
└── tmp/        # artefacts temporaires (non versionnés)
```

## Statut

- [x] Workspace créé
- [x] Accès Docker externe validé (Engine 28.0.1 via socket monté)
- [ ] Scaffold Flutter (`flutter create --platforms=android,ios`) dans le conteneur
- [ ] Implémentation MVP
- [ ] Build Android de validation
- [ ] Push repo public