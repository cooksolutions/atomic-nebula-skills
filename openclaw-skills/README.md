# Atomic Nebula Skills For OpenClaw

This directory is the OpenClaw-facing view of the shared Atomic Nebula skills.
The canonical skill sources live in `../skills/`.

## Install

From the repository root:

```bash
./install.sh --target openclaw
```

If your OpenClaw skills directory is not the default, set it explicitly:

```bash
OPENCLAW_SKILLS_DIR="$HOME/.openclaw/workspace/skills" ./install.sh --target openclaw
```

Replace an older install:

```bash
./install.sh --target openclaw --force
```

Reload OpenClaw after installation.

## Layout

- `openclaw-skills/atomicnebula-*` entries are symlinks to `../skills/atomicnebula-*`.
- `openclaw-skills/shared` is a symlink to `../skills/shared`.
- `.skill` archives are legacy compatibility artifacts. Prefer installing from
  the canonical `skills/` directories with `install.sh`.

## Required Shared Helper

Every Atomic Nebula shell helper sources:

```text
shared/resolve-env.sh
```

If you manually copy or install individual skills, copy `skills/shared` as well.

## Configure Access

The skills resolve credentials in this order:

1. Environment variables such as `ATOMICNEBULA_API_KEY` and `ATOMICNEBULA_BASE_URL`
2. `~/.config/circeaura/assistant-workspaces.json`
3. Legacy `~/.openclaw/openclaw.json`

List configured workspaces after installation:

```bash
~/.openclaw/skills/shared/an-env-list.sh
```

Use `$OPENCLAW_SKILLS_DIR/shared/an-env-list.sh` instead if you installed into a
custom OpenClaw skills directory.
