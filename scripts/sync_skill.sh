#!/usr/bin/env bash
# Synchronise le skill keyformstudio-animation-json, qui vit désormais dans son
# PROPRE dépôt public (Xiaohequ/keyformstudio-animation-json, publié sur
# ClawHub). Ce dépôt-ci reste la source de vérité de la spec et des exemples.
#
#   scripts/sync_skill.sh            copie docs/ -> dépôt du skill, puis
#                                    dépôt du skill -> workspace de l'agent
#   scripts/sync_skill.sh --check    vérifie seulement (code retour 1 si dérive)
#   scripts/sync_skill.sh --pull     copie dépôt du skill -> docs/ (édition faite
#                                    côté skill, à relire avant commit)
#
# Le dépôt du skill est cherché dans $SKILL_REPO, sinon dans un dossier voisin
# du projet (../keyformstudio-animation-json).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="keyformstudio-animation-json"
SKILL_REPO="${SKILL_REPO:-$ROOT/../$NAME}"
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

if [ ! -d "$SKILL_REPO" ]; then
  printf '✘ dépôt du skill introuvable : %s\n' "$SKILL_REPO" >&2
  printf '  cloner https://github.com/Xiaohequ/%s à côté du projet,\n' "$NAME" >&2
  printf '  ou définir SKILL_REPO=/chemin/vers/%s\n' "$NAME" >&2
  exit 2
fi

# Copie récursive sans rsync (absent de l'image nanobot).
copy_tree() {
  local from="$1" to="$2"
  rm -rf "$to"
  mkdir -p "$to"
  (cd "$from" && tar -cf - --exclude='__pycache__' --exclude='*.pyc' .) \
    | (cd "$to" && tar -xf -)
}

# 1. references/ du dépôt du skill doit refléter docs/ : c'est le miroir publié
#    de la spec. Le skill ne publie QUE la spec et l'exemple complet ; les
#    fichiers d'exemples séparés de docs/ restent des fixtures des tests Flutter.
PUBLISHED="vasf-1-format.md vasf-example.json"
for base in $PUBLISHED; do
  if [ ! -f "$ROOT/docs/$base" ]; then
    printf '✘ docs/%s manquant\n' "$base" >&2
    fail=1
  elif [ ! -f "$SKILL_REPO/references/$base" ]; then
    printf '✘ references/%s manquant dans le dépôt du skill\n' "$base" >&2
    fail=1
  elif ! diff -q "$ROOT/docs/$base" "$SKILL_REPO/references/$base" >/dev/null; then
    printf '✘ references/%s diffère de docs/%s\n' "$base" "$base" >&2
    fail=1
  fi
done

# 2. Le frontmatter du skill doit déclarer version / vasf / app.
for key in version vasf app; do
  if ! grep -q "^$key:" "$SKILL_REPO/SKILL.md"; then
    printf '✘ frontmatter : clé « %s » absente de SKILL.md\n' "$key" >&2
    fail=1
  fi
done

# 3. Le validateur du skill doit accepter l'exemple publié.
if ! python3 "$SKILL_REPO/scripts/validate_vasf.py" \
    "$ROOT/docs/vasf-example.json" >/dev/null; then
  printf '✘ validate_vasf.py refuse docs/vasf-example.json\n' >&2
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
  for base in $PUBLISHED; do
    cp "$SKILL_REPO/references/$base" "$ROOT/docs/$base"
  done
  printf '✔ docs/ rapatrié depuis %s — relire puis committer\n' "$SKILL_REPO"
  exit 0
fi

# push : docs/ -> dépôt du skill, puis dépôt du skill -> workspace de l'agent.
for base in $PUBLISHED; do
  cp "$ROOT/docs/$base" "$SKILL_REPO/references/$base"
done
printf '✔ docs/ copié vers %s/references\n' "$SKILL_REPO"

mkdir -p "$WORKSPACE/skills"
copy_tree "$SKILL_REPO" "$DST"
printf '✔ skill copié vers %s\n' "$DST"
