---
name: atomicnebula-projects
description: "Read and manage Atomic Nebula projects over the external REST API. Use when a user wants to list projects, create a project, update project details, archive a project, inspect project type definitions, or inspect the project custom-fields schema. Supports --env <workspace> to target a specific workspace."
metadata:
  {
    "openclaw":
      {
        "emoji": "📁",
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

# Atomic Nebula Projects Skill

Use the Atomic Nebula projects REST API through the shared assistant capability layer.

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

- `GET /api/v1/atomicnebula/projects`
- `POST /api/v1/atomicnebula/projects`
- `PATCH /api/v1/atomicnebula/projects/:id`
- `POST /api/v1/atomicnebula/projects/:id/archive`
- `GET /api/v1/atomicnebula/projects/types`
- `GET /api/v1/atomicnebula/projects/custom-fields/schema`

## Helper Script

```bash
# List projects
skills/atomicnebula-projects/scripts/an-projects.sh list --status active

# Get project types for AI/project categorization
skills/atomicnebula-projects/scripts/an-projects.sh types

# Get project custom-field schema
skills/atomicnebula-projects/scripts/an-projects.sh custom-fields

# Create a project
skills/atomicnebula-projects/scripts/an-projects.sh create --name "Content Backlog" --key "content-backlog"

# Update a project
skills/atomicnebula-projects/scripts/an-projects.sh update PROJECT-ID --status active --description "Current work backlog"

# Archive a project
skills/atomicnebula-projects/scripts/an-projects.sh archive PROJECT-ID --reason "Completed"
```

## Notes

- The current external REST surface does not expose `GET /projects/:id`, so this skill cannot fetch one project directly by ID.
- Use `list` filters to narrow to a specific project until a detail endpoint exists.

## Common Filters

`list` supports:

- `--status <value>`
- `--owner-id <userId>`

## Write Behavior

Write operations can trigger approval if the workspace uses assistant keys with approval gates enabled. The script sends `X-Run-Id` and records approval challenges so webhook correlation still works.

## Permissions

- Read: `atomicnebula:projects:read`
- Write: `atomicnebula:projects:write`
