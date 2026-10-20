#!/usr/bin/env bash
# Synchronise le skill keyformstudio-animation-json entre le dépôt (source de
# vérité) et le workspace de l'agent nanobot.
#
#   scripts/sync_skill.sh            copie dépôt -> workspace
#   scripts/sync_skill.sh --check    vérifie seulement (code retour 1 si dérive)
#   scripts/sync_skill.sh --pull     copie workspace -> dépôt (édition faite
#                                    côté agent, à relire avant commit)
#
# Vérifie aussi que references/ est identique à docs/ (miroir de contrôle).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="keyformstudio-animation-json"
SRC="$ROOT/skills/$NAME"
WORKSPACE="${NANOBOT_WORKDIR:-$HOME/.nanobot/workspace}"
DST="$WORKSPACE/skills/$NAME"

MODE="push"
case "${1:-}" in
  --check) MODE="check" ;;
  --pull) MODE="pull" ;;
  "") ;;
  *) printf 'Usage: %s [--check|--pull]\n' "$0" >&2; exit 2 ;;
esac

fail=0

# Copie récursive sans rsync (absent de l'image nanobot) : remplace la cible
# et ignore les caches Python.
copy_tree() {
  local from="$1" to="$2"
  rm -rf "$to"
  mkdir -p "$to"
  (cd "$from" && tar -cf - --exclude='__pycache__' --exclude='*.pyc' .) \
    | (cd "$to" && tar -xf -)
}

# 1. references/ doit refléter docs/ (mêmes fichiers, même contenu).
for f in "$SRC"/references/*; do
  base="$(basename "$f")"
  if [ ! -f "$ROOT/docs/$base" ]; then
    printf '✘ docs/%s manquant (présent dans references/)\n' "$base" >&2
    fail=1
  elif ! diff -q "$f" "$ROOT/docs/$base" >/dev/null; then
    printf '✘ references/%s diffère de docs/%s\n' "$base" "$base" >&2
    fail=1
  fi
done

# 2. Le frontmatter doit déclarer version / vasf / app.
for key in version vasf app; do
  if ! grep -q "^$key:" "$SRC/SKILL.md"; then
    printf '✘ frontmatter : clé « %s » absente de SKILL.md\n' "$key" >&2
    fail=1
  fi
done

# 3. Les scripts doivent être exécutables et valider un exemple.
if ! python3 "$SRC/scripts/validate_vasf.py" "$ROOT/docs/vasf-6-example.json" >/dev/null; then
  printf '✘ validate_vasf.py refuse docs/vasf-6-example.json\n' >&2
  fail=1
fi

if [ "$MODE" = "check" ]; then
  if [ "$fail" -eq 0 ]; then
    printf '✔ skill %s cohérent (references/ = docs/, frontmatter complet)\n' "$NAME"
  fi
  exit "$fail"
fi

if [ "$fail" -ne 0 ]; then
  printf 'Synchronisation annulée : corriger les écarts ci-dessus.\n' >&2
  exit 1
fi

if [ "$MODE" = "pull" ]; then
  if [ ! -d "$DST" ]; then
    printf '✘ %s introuvable : rien à rapatrier\n' "$DST" >&2
    exit 1
  fi
  copy_tree "$DST" "$SRC"
  printf '✔ skill rapatrié depuis %s — relire puis committer\n' "$DST"
  exit 0
fi

mkdir -p "$WORKSPACE/skills"
copy_tree "$SRC" "$DST"
printf '✔ skill copié vers %s\n' "$DST"
