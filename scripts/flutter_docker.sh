#!/usr/bin/env bash
# Lance la CLI Flutter dans le conteneur officiel cirruslabs, monté sur le projet.
# Usage: scripts/flutter_docker.sh create --platforms=android,ios .
#        scripts/flutter_docker.sh pub get
#        scripts/flutter_docker.sh build apk --debug
set -euo pipefail

IMAGE="${FLUTTER_IMAGE:-ghcr.io/cirruslabs/flutter:stable}"
PROJECT_DIR="${PROJECT_DIR:-/root/.nanobot/workspace/vector_anim_studio}"
# Cache pub persistant sur l'hote : le conteneur est lance avec --rm, donc sans
# ce montage chaque `flutter pub get` retélécharge tous les paquets (et un
# `flutter analyze` sans pub get échoue en "name isn't defined" sur les
# dépendances : la config de paquets pointerait vers un cache disparu).
PUB_CACHE_DIR="${PUB_CACHE_DIR:-$PROJECT_DIR/tmp/pub-cache}"
mkdir -p "$PUB_CACHE_DIR"

exec docker run --rm -i \
  -e GRADLE_OPTS="-Dorg.gradle.jvmargs=-Xmx512m -Dorg.gradle.daemon=false -Dorg.gradle.workers.max=1" \
  -v "${PROJECT_DIR}":/work \
  -v "${PUB_CACHE_DIR}":/root/.pub-cache \
  -w /work/app \
  "${IMAGE}" "$@"
