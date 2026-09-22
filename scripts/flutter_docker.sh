#!/usr/bin/env bash
# Lance la CLI Flutter dans le conteneur officiel cirruslabs, monté sur le projet.
# Usage: scripts/flutter_docker.sh create --platforms=android,ios .
#        scripts/flutter_docker.sh pub get
#        scripts/flutter_docker.sh build apk --debug
set -euo pipefail

IMAGE="${FLUTTER_IMAGE:-ghcr.io/cirruslabs/flutter:stable}"
PROJECT_DIR="${PROJECT_DIR:-/root/.nanobot/workspace/vector_anim_studio}"

exec docker run --rm -i \
  -e GRADLE_OPTS="-Dorg.gradle.jvmargs=-Xmx512m -Dorg.gradle.daemon=false -Dorg.gradle.workers.max=1" \
  -v "${PROJECT_DIR}":/work \
  -w /work/app \
  "${IMAGE}" "$@"