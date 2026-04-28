# Atomic Nebula Skills

This repository contains the Atomic Nebula assistant skills for agents that can
load filesystem-based skills, including Codex, Claude Code, and OpenClaw.

The canonical source is the root `skills/` directory. Consumer-specific folders
are included as convenience views so agents can install from the layout they
expect without maintaining separate copies.

## Layout

```text
skills/                 Canonical Atomic Nebula skills and shared helpers
.agents/skills/         Codex-style view, linked to skills/
.claude/skills/         Claude Code-style view, linked to skills/
openclaw-skills/        OpenClaw-style view, linked to skills/
install.sh              Local installer for Codex, Claude Code, or OpenClaw
```

## Install

Clone the repository, then install for the agent you use.

Codex:

```bash
./install.sh --target codex
```

Claude Code:

```bash
./install.sh --target claude
```

OpenClaw:

```bash
./install.sh --target openclaw
```

Install to all default locations:

```bash
./install.sh --target all
```

Replace older installed copies:

```bash
./install.sh --target codex --force
```

Install into a custom skills directory:

```bash
./install.sh --target codex --dest /path/to/skills
```

Restart or reload the target agent after installation.

## Install From A GitHub Path

Agents that can install skills directly from GitHub can use the canonical paths
under `skills/`. For example, install one skill from:

```text
https://github.com/cooksolutions/atomic-nebula-skills/tree/main/skills/atomicnebula-tasks
```

Or install multiple paths from the same repository:

```text
skills/atomicnebula-tasks
skills/atomicnebula-calendar
skills/atomicnebula-email
skills/shared
```

`skills/shared` is required because the shell helpers resolve workspace and API
configuration through `shared/resolve-env.sh`.

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

Use the equivalent installed path for Claude Code or OpenClaw if you installed
there instead.

## Usage

Ask your agent to use an Atomic Nebula skill, for example:

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
