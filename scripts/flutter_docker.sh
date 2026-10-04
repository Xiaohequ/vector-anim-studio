#!/usr/bin/env bash
# Lance la CLI Flutter dans le conteneur officiel cirruslabs, monté sur le projet.
# Usage: scripts/flutter_docker.sh create --platforms=android,ios .
#        scripts/flutter_docker.sh pub get
#        scripts/flutter_docker.sh build apk --debug
# L'image n'a pas d'ENTRYPOINT (Cmd: /bin/bash) : « flutter » est préfixé
# automatiquement. Passer « flutter » en premier argument reste accepté
# (idempotent). Pour autre chose que flutter (dart, bash…), lancer
# docker run directement.
set -euo pipefail

IMAGE="${FLUTTER_IMAGE:-ghcr.io/cirruslabs/flutter:stable}"
PROJECT_DIR="${PROJECT_DIR:-/root/.nanobot/workspace/vector_anim_studio}"
# Cache pub persistant sur l'hote : le conteneur est lance avec --rm, donc sans
# ce montage chaque `flutter pub get` retélécharge tous les paquets (et un
# `flutter analyze` sans pub get échoue en "name isn't defined" sur les
# dépendances : la config de paquets pointerait vers un cache disparu).
PUB_CACHE_DIR="${PUB_CACHE_DIR:-$PROJECT_DIR/tmp/pub-cache}"
mkdir -p "$PUB_CACHE_DIR"
# Idem pour Gradle (~200 Mo de distribution + caches AGP) : sans ce montage,
# chaque invocation de gradlew retélécharge la distribution complète.
GRADLE_CACHE_DIR="${GRADLE_CACHE_DIR:-$PROJECT_DIR/tmp/gradle-cache}"
mkdir -p "$GRADLE_CACHE_DIR"

# Préfixe « flutter » sauf s'il est déjà présent en premier argument.
if [ "${1:-}" = "flutter" ]; then
  CMD=("$@")
else
  CMD=(flutter "$@")
fi

# Variables de l'aperçu headless (test/vasf_preview_test.dart) : passées au
# conteneur seulement quand elles sont définies (chemins CONTENEUR, /work =
# racine du projet).
ENV_FLAGS=()
for var in VASF_PREVIEW_INPUT VASF_PREVIEW_OUT VASF_PREVIEW_TIMES VASF_PREVIEW_SCALE; do
  if [ -n "${!var:-}" ]; then
    ENV_FLAGS+=(-e "$var=${!var}")
  fi
done

# Un verrou hôte partagé sérialise les appels Flutter de ce projet. Sans cela,
# plusieurs tests lancés en parallèle créent chacun un conteneur et plusieurs
# VM Dart, ce qui surcharge fortement le serveur.
FLUTTER_LOCK="${FLUTTER_LOCK:-/tmp/vector_anim_studio_flutter.lock}"
FLUTTER_CONTAINER="vector-anim-studio-flutter"
# Nettoie un éventuel conteneur orphelin laissé si le processus appelant a été
# tué brutalement. Le verrou garantit qu'aucun autre appel du script ne tourne.
flock --exclusive "$FLUTTER_LOCK" bash -c '
  docker rm -f "$1" >/dev/null 2>&1 || true
  exec docker run --rm --name "$1" -i "${@:2}"
' _ "$FLUTTER_CONTAINER" \
  -e GRADLE_OPTS="-Dorg.gradle.jvmargs=-Xmx512m -Dorg.gradle.daemon=false -Dorg.gradle.workers.max=1" \
  "${ENV_FLAGS[@]}" \
  -v "${PROJECT_DIR}":/work \
  -v "${PUB_CACHE_DIR}":/root/.pub-cache \
  -v "${GRADLE_CACHE_DIR}":/root/.gradle \
  -w /work/app \
  "${IMAGE}" "${CMD[@]}"
