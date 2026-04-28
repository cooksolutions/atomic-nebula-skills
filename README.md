# Atomic Nebula Codex Skills

This repository contains the Atomic Nebula skills for Codex.

It is intentionally small: it only packages the skills and their shared helper
scripts so another user can install them into Codex and use Atomic Nebula from
their agent.

## Install

Clone the repository, then run:

```bash
./install.sh
```

Restart Codex after installation.

If you already have older copies installed, replace them with:

```bash
./install.sh --force
```

The installer copies these directories into `~/.codex/skills` by default:

- `skills/atomicnebula-*`
- `skills/shared`

You can install into a custom skills directory:

```bash
./install.sh --dest /path/to/skills
```

## Configure Access

The skills call the Atomic Nebula assistant API. Configure credentials by either
setting environment variables or creating a workspace config file.

Environment variables:

```bash
export ATOMICNEBULA_API_KEY="..."
export ATOMICNEBULA_BASE_URL="https://convex-actions.circeaura.com"
```

Workspace config:

```text
~/.config/circeaura/assistant-workspaces.json
```

After credentials are configured, list available workspaces with:

```bash
~/.codex/skills/shared/an-env-list.sh
```

## Usage

Ask Codex to use an Atomic Nebula skill, for example:

- "Use Atomic Nebula to show my tasks."
- "Use Atomic Nebula to draft an email."
- "Use Atomic Nebula to show my calendar tomorrow."

Most scripts accept `--env <workspace>` to target a configured workspace:

```bash
~/.codex/skills/atomicnebula-tasks/scripts/an-tasks.sh --env dev list
```

## Included Skills

- `atomicnebula-attachments`
- `atomicnebula-attention`
- `atomicnebula-calendar`
- `atomicnebula-capture`
- `atomicnebula-contacts`
- `atomicnebula-content`
- `atomicnebula-context`
- `atomicnebula-digest`
- `atomicnebula-email`
- `atomicnebula-forms`
- `atomicnebula-leads`
- `atomicnebula-projects`
- `atomicnebula-task-write`
- `atomicnebula-tasks`
- `atomicnebula-teams`
