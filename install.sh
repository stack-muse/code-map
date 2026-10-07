#!/usr/bin/env bash
# install.sh <claude|codex|cursor|agents|all> [--link] [--project <dir>]
#
# Installs the code-map skill as <skills-dir>/code-map/{SKILL.md, assets/, references/},
# where SKILL.md comes from adapters/<adapter>/ and assets/ + references/ are shared.
#   claude                 -> adapters/claude into ~/.claude/skills
#   codex | cursor | agents -> adapters/agents into ~/.agents/skills, the shared Agent
#                             Skills folder that both Codex and Cursor read
#   all                    -> both of the above
#
#   --link            symlink instead of copying, so edits and `git pull` in this
#                     checkout take effect without reinstalling
#   --project <dir>   install into <dir>/.claude/skills/ or <dir>/.agents/skills/
#                     instead of your home directory
#
# Safe to re-run: it replaces only the three entries it owns.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  echo "usage: ./install.sh <claude|codex|cursor|agents|all> [--link] [--project <dir>]" >&2
  exit 1
}

TARGET="${1:-}"
[[ -n "$TARGET" ]] || usage
shift

LINK=0
PROJECT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --link) LINK=1; shift ;;
    --project)
      [[ -n "${2:-}" ]] || usage
      PROJECT="$(cd "$2" && pwd)" || { echo "install.sh: no such directory '$2'" >&2; exit 1; }
      shift 2
      ;;
    *) usage ;;
  esac
done

case "$TARGET" in
  all) SELECTED=(claude agents) ;;
  claude) SELECTED=(claude) ;;
  codex|cursor|agents) SELECTED=(agents) ;;
  *) usage ;;
esac

skills_dir() {
  # skills_dir <adapter> — claude -> .claude/skills, agents -> .agents/skills
  local adapter="$1" base
  if [[ -n "$PROJECT" ]]; then
    base="$PROJECT"
  else
    base="$HOME"
  fi
  printf '%s/.%s/skills' "$base" "$adapter"
}

place() {
  # place <source> <dest> — copy or symlink one entry, replacing what was there.
  local src="$1" dst="$2"
  rm -rf "$dst" || return 1
  if [[ "$LINK" -eq 1 ]]; then
    ln -s "$src" "$dst"
  else
    cp -R "$src" "$dst"
  fi
}

install_one() {
  local adapter="$1" label
  local dest
  dest="$(skills_dir "$adapter")/code-map"
  label="$adapter"
  [[ "$adapter" == "agents" ]] && label="codex + cursor"

  # An old install was a full clone of this repo (or a symlink to one) — never overwrite it.
  if [[ -L "$dest" || -d "$dest/.git" ]]; then
    echo "install.sh: $dest is an older clone-style install of code-map." >&2
    echo "  Remove it first, then re-run:  rm -rf \"$dest\" && ./install.sh $TARGET" >&2
    return 1
  fi

  # Called from an `||` list, so set -e is off in here: check each step explicitly.
  mkdir -p "$dest" || return 1
  place "$REPO/adapters/$adapter/SKILL.md" "$dest/SKILL.md" || return 1
  place "$REPO/assets" "$dest/assets" || return 1
  place "$REPO/references" "$dest/references" || return 1
  chmod +x "$dest"/assets/*.sh || return 1

  local how="copied"
  [[ "$LINK" -eq 1 ]] && how="linked"
  echo "code-map for $label: $how into $dest"
}

status=0
for adapter in "${SELECTED[@]}"; do
  install_one "$adapter" || status=1
done

if [[ "$status" -eq 0 ]]; then
  echo "Done. Start a new session in your agent to pick up the skill."
fi
exit "$status"
