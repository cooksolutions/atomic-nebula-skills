---
name: atomicnebula-leads
description: "Read and manage Atomic Nebula leads over the external REST API. Use when a user wants to list leads, inspect a lead, create a new lead, update lead details, or delete a lead. Supports --env <workspace> to target a specific workspace."
metadata:
  {
    "openclaw":
      {
        "emoji": "🎯",
        "requires": { "bins": ["curl", "jq"] },
        "install":
          [
            {
              "id": "brew-jq",
              "kind": "brew",
              "formula": "jq",
              "bins": ["jq"],
              "label": "Install jq (brew)",
            },
          ],
      },
  }
---

# Atomic Nebula Leads Skill

Use the Atomic Nebula leads REST API through the shared assistant capability layer.

## Configuration

Credentials resolve in this order:

1. Environment variables such as `ATOMICNEBULA_API_KEY` and `ATOMICNEBULA_BASE_URL`
2. `~/.config/circeaura/assistant-workspaces.json`
3. Legacy `~/.openclaw/openclaw.json`

Use `--env <workspace>` to target a configured workspace. Run `skills/shared/an-env-list.sh` to inspect configured workspaces.

## Workspace Targeting

All commands accept `--env <workspace>`:

- `spider` by default
- `--env dev`
- `--env circeaurasupport`

Run `skills/shared/an-env-list.sh` to see configured workspaces.

## Supported Endpoints

- `GET /api/v1/atomicnebula/leads`
- `POST /api/v1/atomicnebula/leads`
- `GET /api/v1/atomicnebula/leads/:id`
- `PATCH /api/v1/atomicnebula/leads/:id`
- `DELETE /api/v1/atomicnebula/leads/:id`

## Helper Script

```bash
# List leads
skills/atomicnebula-leads/scripts/an-leads.sh list --search acme --limit 20

# Get one lead
skills/atomicnebula-leads/scripts/an-leads.sh get LEAD-ID

# Create a lead
skills/atomicnebula-leads/scripts/an-leads.sh create --email "prospect@example.com" --first-name "Pat" --last-name "Lee"

# Update a lead
skills/atomicnebula-leads/scripts/an-leads.sh update LEAD-ID --qualification-status sql --score 75 --tag qualified

# Delete a lead
skills/atomicnebula-leads/scripts/an-leads.sh delete LEAD-ID
```

## Common Filters

`list` supports:

- `--pipeline-id <id>`
- `--stage-id <id>`
- `--owner-id <userId>`
- `--team-id <id>`
- `--territory-id <id>`
- `--contact-id <id>`
- `--form-id <id>`
- `--source <value>`
- `--qualification-status <value>`
- `--search <term>`
- `--score-min <n>`
- `--score-max <n>`
- `--sort-by <field>`
- `--sort-order <asc|desc>`
- `--limit <n>`
- `--offset <n>`

## Write Behavior

Write operations can trigger approval if the workspace uses assistant keys with approval gates enabled. The script sends `X-Run-Id` and records approval challenges so webhook correlation still works.

## Permissions

- Read: `atomicnebula:leads:read`
- Write: `atomicnebula:leads:write`
