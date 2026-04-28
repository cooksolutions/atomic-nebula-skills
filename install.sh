#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
force="false"
target="codex"
custom_dest=""

usage() {
  cat <<'EOF'
Usage: ./install.sh [--target codex|claude|openclaw|all] [--force] [--dest <skills-dir>]

Installs the Atomic Nebula skills into a local agent skills directory.

Options:
  --target <name>     Target agent. Defaults to codex.
                      codex    -> $CODEX_HOME/skills or ~/.codex/skills
                      claude   -> $CLAUDE_HOME/skills or ~/.claude/skills
                      openclaw -> $OPENCLAW_SKILLS_DIR or $OPENCLAW_HOME/skills or ~/.openclaw/skills
                      all      -> install to all default locations
  --force             Replace existing installed Atomic Nebula skills.
  --dest <skills-dir> Install into a custom skills directory.
                      Only valid with a single target, not --target all.
EOF
}

default_dest_for_target() {
  case "$1" in
    codex)
      printf '%s\n' "${CODEX_HOME:-$HOME/.codex}/skills"
      ;;
    claude)
      printf '%s\n' "${CLAUDE_HOME:-$HOME/.claude}/skills"
      ;;
    openclaw)
      if [[ -n "${OPENCLAW_SKILLS_DIR:-}" ]]; then
        printf '%s\n' "$OPENCLAW_SKILLS_DIR"
      else
        printf '%s\n' "${OPENCLAW_HOME:-$HOME/.openclaw}/skills"
      fi
      ;;
    *)
      echo "Error: unsupported target '$1'." >&2
      exit 2
      ;;
  esac
}

install_to_dest() {
  local dest_root="$1"
  mkdir -p "$dest_root"

  for source_dir in "$repo_root"/skills/atomicnebula-* "$repo_root"/skills/shared; do
    local name
    name="$(basename "$source_dir")"
    local dest_dir="$dest_root/$name"

    if [[ -e "$dest_dir" ]]; then
      if [[ "$force" != "true" ]]; then
        echo "Error: $dest_dir already exists. Re-run with --force to replace it." >&2
        exit 1
      fi
      rm -rf "$dest_dir"
    fi

    cp -R "$source_dir" "$dest_dir"
    echo "Installed $name -> $dest_dir"
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      if [[ $# -lt 2 ]]; then
        echo "Error: --target requires codex, claude, openclaw, or all." >&2
        exit 2
      fi
      target="$2"
      shift 2
      ;;
    --force)
      force="true"
      shift
      ;;
    --dest)
      if [[ $# -lt 2 ]]; then
        echo "Error: --dest requires a path." >&2
        exit 2
      fi
      custom_dest="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$target" in
  codex|claude|openclaw|all)
    ;;
  *)
    echo "Error: unsupported target '$target'." >&2
    usage >&2
    exit 2
    ;;
esac

if [[ "$target" == "all" && -n "$custom_dest" ]]; then
  echo "Error: --dest cannot be used with --target all." >&2
  exit 2
fi

if [[ "$target" == "all" ]]; then
  install_to_dest "$(default_dest_for_target codex)"
  install_to_dest "$(default_dest_for_target claude)"
  install_to_dest "$(default_dest_for_target openclaw)"
else
  install_to_dest "${custom_dest:-$(default_dest_for_target "$target")}"
fi

echo
echo "Done. Restart or reload the target agent to pick up the Atomic Nebula skills."
