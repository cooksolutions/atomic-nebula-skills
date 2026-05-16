# Maintainers

This repository is the public/shareable packaging repo for Atomic Nebula agent
skills. It is not the primary product repository.

## Purpose

The repo lets external users install Atomic Nebula skills into filesystem-based
agents without cloning the full CirceAura product repository.

Supported consumers:

- Codex
- Claude Code
- OpenClaw

## Source Of Truth

The canonical skill sources currently live in the private CirceAura repository:

```text
/Users/jamescook/code/circeaura/skills/atomicnebula-*
/Users/jamescook/code/circeaura/skills/shared
```

This repository contains a copied release bundle under:

```text
skills/
```

The consumer folders are views over that bundle:

```text
.agents/skills/     Codex-style view
.claude/skills/     Claude Code-style view
openclaw-skills/    OpenClaw-style view
```

Do not edit the same skill independently in multiple places. Make product skill
changes in the CirceAura repository first, then sync this repo.

## Update Workflow

Run this whenever an Atomic Nebula assistant skill changes in CirceAura:

```bash
cd /Users/jamescook/code/atomic-nebula-skills
scripts/sync-from-circeaura.sh /Users/jamescook/code/circeaura
```

Then review the diff:

```bash
git status --short
git diff --stat
git diff
```

If a new `atomicnebula-*` skill was added, expose it in each consumer view:

```bash
ln -sfn ../../skills/<skill-name> .agents/skills/<skill-name>
ln -sfn ../../skills/<skill-name> .claude/skills/<skill-name>
ln -sfn ../skills/<skill-name> openclaw-skills/<skill-name>
```

Also add it to the included-skill list in `README.md`.

## Validation Checklist

Before pushing, run:

```bash
tmp="$(mktemp -d)"
./install.sh --dest "$tmp/codex-skills"
find "$tmp/codex-skills" -maxdepth 2 -name SKILL.md | wc -l
test -f "$tmp/codex-skills/shared/resolve-env.sh"
"$tmp/codex-skills/atomicnebula-tasks/scripts/an-tasks.sh" --help
"$tmp/codex-skills/atomicnebula-teams/scripts/an-teams.sh" --help
```

OpenClaw install smoke test:

```bash
tmp="$(mktemp -d)"
./install.sh --target openclaw --dest "$tmp/openclaw-skills"
find "$tmp/openclaw-skills" -maxdepth 2 -name SKILL.md | wc -l
test -f "$tmp/openclaw-skills/shared/resolve-env.sh"
```

Expected current count: `20` skills.

Check executable modes:

```bash
find skills -path '*/scripts/*.sh' -type f ! -perm -111 -print
```

If that command prints any script paths, fix them with `chmod +x`.

## Commit And Publish

Use a normal commit after validation:

```bash
git add README.md MAINTAINERS.md install.sh scripts skills .agents .claude openclaw-skills
git commit -m "Sync Atomic Nebula skills"
git push
```

## Credential Notes

Do not commit credentials, workspace config files, API keys, OAuth tokens, or
tenant-specific secrets.

The public bundle should only contain:

- skill instructions
- helper scripts
- safe examples
- install and maintenance docs

Users configure access locally through environment variables or:

```text
~/.config/circeaura/assistant-workspaces.json
```
