#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_root="${1:-/Users/jamescook/code/circeaura}"
source_skills="$source_root/skills"

if [[ ! -d "$source_skills" ]]; then
  echo "Error: source skills directory not found: $source_skills" >&2
  echo "Usage: scripts/sync-from-circeaura.sh [path-to-circeaura-repo]" >&2
  exit 2
fi

shopt -s nullglob
atomic_sources=("$source_skills"/atomicnebula-*)
if [[ ${#atomic_sources[@]} -eq 0 ]]; then
  echo "Error: no atomicnebula-* skills found in $source_skills" >&2
  exit 2
fi

rm -rf "$repo_root"/skills/atomicnebula-* "$repo_root/skills/shared"
mkdir -p "$repo_root/skills"

for skill_dir in "${atomic_sources[@]}"; do
  cp -R "$skill_dir" "$repo_root/skills/"
done

cp -R "$source_skills/shared" "$repo_root/skills/shared"

chmod +x "$repo_root"/skills/atomicnebula-*/scripts/*.sh "$repo_root"/skills/shared/*.sh

echo "Synced ${#atomic_sources[@]} Atomic Nebula skills from $source_root"
echo "Next: review git diff, run install smoke tests, commit, and push."
