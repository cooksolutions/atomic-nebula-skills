#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest_root="${CODEX_HOME:-$HOME/.codex}/skills"
force="false"

usage() {
  cat <<'EOF'
Usage: ./install.sh [--force] [--dest <skills-dir>]

Installs the Atomic Nebula skills into Codex.

Options:
  --force             Replace existing installed Atomic Nebula skills.
  --dest <skills-dir> Install into a custom skills directory.
                      Defaults to $CODEX_HOME/skills or ~/.codex/skills.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      force="true"
      shift
      ;;
    --dest)
      if [[ $# -lt 2 ]]; then
        echo "Error: --dest requires a path." >&2
        exit 2
      fi
      dest_root="$2"
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

mkdir -p "$dest_root"

for source_dir in "$repo_root"/skills/atomicnebula-* "$repo_root"/skills/shared; do
  name="$(basename "$source_dir")"
  dest_dir="$dest_root/$name"

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

echo
echo "Done. Restart Codex to pick up the Atomic Nebula skills."
