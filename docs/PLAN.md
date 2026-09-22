# Plan technique — vector_anim_studio

## 1. Environnement d'exécution

Le projet vit dans le workspace nanobot (`/root/.nanobot/workspace/vector_anim_studio`), bind-monté depuis l'hôte Docker au même chemin. Le conteneur Flutter y accède donc directement via `-v /root/.nanobot/workspace/vector_anim_studio:/work`.

Toolchain :
- Image `ghcr.io/cirruslabs/flutter:stable` (Flutter + Dart + Android SDK + JDK embarqués)
- Daemon Docker de l'hôte (Engine 28.0.1) atteint via `/var/run/docker.sock` monté dans le conteneur nanobot
- Helper : `scripts/flutter_docker.sh`

## 2. Modèle de données

```
Project
 ├─ Scene { width, height, background, durationMs, fps }
 ├─ List<Layer>       # ordre de rendu, visibilité, verrouillage
 │   └─ Shape { type, path/params, style, transform de base }
 └─ List<Track>       # une par (layer, propriété)
     └─ List<Keyframe { timeMs, value, easing }>
```

Propriétés animables : `x`, `y`, `rotation`, `scale`, `opacity`, `color`, `strokeWidth`, `path` (morphing simple).

## 3. Moteur

- `Timeline.tick(dtMs)` → temps courant, boucle, lecture/pause
- Échantillonnage : pour chaque track, recherche du segment encadrant + interpolation selon l'easing (linéaire, easeIn/Out/InOut, step)
- `Painter` : construit un `Path` par forme, applique la matrice (translate/rotate/scale), dessine via `Canvas`
- Rendu offscreen pour l'export : `PictureRecorder` → `Picture.toImage(w,h)` → PNG

## 4. Interface

1. **Écran studio** : canvas au centre (pinch zoom / pan), barre d'outils d'ajout de forme, timeline en bas (règle + pistes + tête de lecture), inspecteur à droite/en bas selon l'orientation.
2. **Panneau calques** : réordonnancement, visibilité, suppression.
3. **Barre de lecture** : play/pause, reset, durée, fps, boucle.
4. **Export** : sheet avec choix (JSON / PNG / GIF), gestion `share_plus` pour partager l'artefact.

## 5. Livrables

- APK debug + release (Android)
- Projet Xcode configuré (iOS) — build délégué à un runner macOS
- Workflow GitHub Actions : job Android (ubuntu) + job iOS (macos) produisant les artefacts