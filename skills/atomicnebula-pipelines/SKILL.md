---
name: atomicnebula-pipelines
description: "Manage Atomic Nebula lifecycle pipelines and stages over the external REST API — list, create, update, delete pipelines and stages, plus reorder. Use when an agent needs to discover existing pipelines, set up a new staged workflow (e.g. a Software Development pipeline for tasks), or look up stage IDs for assigning tasks to a stage on create/update. Supports --env <workspace> to target a specific workspace."
metadata:
  {
    "openclaw":
      {
        "emoji": "🛤️",
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

# Atomic Nebula Lifecycle Pipelines Skill

Read lifecycle pipelines (and their stages) through the Atomic Nebula external REST API.

Pipelines model staged workflows for any tracked object type — `task`, `deal`, `contact`, `company`, `lead`, etc. Each pipeline has an ordered set of stages (e.g. `Backlog → Todo → In Progress → In Review → Complete → Cancelled` for a task pipeline). To set a task to a particular stage on create or update, the caller needs both the `lifecyclePipelineId` and the `lifecycleStageId` — this skill is how you discover them.

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

## Supported Endpoints

Read:
- `GET /api/v1/atomicnebula/lifecycle-pipelines` — list pipelines + their stages (optional `?objectType=task`)
- `GET /api/v1/atomicnebula/lifecycle-pipelines/:pipelineId` — single pipeline metadata (no stages; use `list` for stages)

Pipeline writes:
- `POST /api/v1/atomicnebula/lifecycle-pipelines` — create
- `PATCH /api/v1/atomicnebula/lifecycle-pipelines/:pipelineId` — update
- `DELETE /api/v1/atomicnebula/lifecycle-pipelines/:pipelineId` — soft-delete (also soft-deletes stages)

Stage writes:
- `POST /api/v1/atomicnebula/lifecycle-pipelines/:pipelineId/stages` — create
- `PATCH /api/v1/atomicnebula/lifecycle-pipelines/:pipelineId/stages/:stageId` — update
- `DELETE /api/v1/atomicnebula/lifecycle-pipelines/:pipelineId/stages/:stageId` — soft-delete (compacts remaining `displayOrder`)
- `POST /api/v1/atomicnebula/lifecycle-pipelines/:pipelineId/stages/reorder` — reorder by stage IDs

## Helper Script

```bash
# Read
skills/atomicnebula-pipelines/scripts/an-pipelines.sh list --object-type task
skills/atomicnebula-pipelines/scripts/an-pipelines.sh get <pipelineId>
skills/atomicnebula-pipelines/scripts/an-pipelines.sh stages <pipelineId>
skills/atomicnebula-pipelines/scripts/an-pipelines.sh stage-id <pipelineId> "In Progress"

# Pipeline write
skills/atomicnebula-pipelines/scripts/an-pipelines.sh create-pipeline \
  --object-type task --name "Software Development" --transition-mode open
skills/atomicnebula-pipelines/scripts/an-pipelines.sh update-pipeline <pipelineId> \
  --name "Software Dev (renamed)" --is-default
skills/atomicnebula-pipelines/scripts/an-pipelines.sh delete-pipeline <pipelineId>

# Stage write
skills/atomicnebula-pipelines/scripts/an-pipelines.sh create-stage <pipelineId> \
  --name "Backlog" --color "#fab"
skills/atomicnebula-pipelines/scripts/an-pipelines.sh update-stage <pipelineId> <stageId> \
  --color "#abc" --closed
skills/atomicnebula-pipelines/scripts/an-pipelines.sh delete-stage <pipelineId> <stageId>
skills/atomicnebula-pipelines/scripts/an-pipelines.sh reorder-stages <pipelineId> \
  <stageId-backlog> <stageId-todo> <stageId-in-progress> <stageId-complete>
```

## Response shape (list)

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "abc-123",
        "name": "Software Development",
        "description": null,
        "objectType": "task",
        "isDefault": false,
        "displayOrder": 0,
        "transitionMode": "open",
        "allowBackwardMoves": true,
        "transitionCount": 0,
        "stages": [
          { "id": "stage-1", "name": "Backlog", "displayOrder": 1, "isClosed": false, "isWon": null, "color": "#yellow", "probability": null, "reservesStock": false },
          { "id": "stage-2", "name": "Todo", "displayOrder": 2, "isClosed": false, "isWon": null, "color": "#grey", "probability": null, "reservesStock": false }
        ]
      }
    ]
  }
}
```

## Permissions

- Read: `atomicnebula:lifecycle:read`

## Common workflow: setting a task's stage

```bash
# 1. Find the pipeline
PIPELINE=$(skills/atomicnebula-pipelines/scripts/an-pipelines.sh list --object-type task \
  | jq -r '.data.items[] | select(.name == "Software Development")')
PIPELINE_ID=$(echo "$PIPELINE" | jq -r '.id')

# 2. Find the stage
STAGE_ID=$(echo "$PIPELINE" | jq -r '.stages[] | select(.name == "In Progress") | .id')

# 3. Create a task pinned to that stage
skills/atomicnebula-task-write/scripts/an-task-write.sh create \
  --title "Reproduce auth bug" \
  --priority high \
  --raw-json "{\"lifecyclePipelineId\": \"$PIPELINE_ID\", \"lifecycleStageId\": \"$STAGE_ID\"}"
```

## Notes

- The list endpoint returns full pipelines + stages in a single round trip — prefer it over multiple `get` calls.
- `transitionMode` of a pipeline can be `open` (any stage to any), `sequential` (forward by `displayOrder`), or `explicit` (only allowed transition pairs). For migration writes, `open` is the easiest target.
- A pipeline created via the UI may show `transitionMode: "open"` even if the UI labels it "Open transitions" — semantics are the same.
