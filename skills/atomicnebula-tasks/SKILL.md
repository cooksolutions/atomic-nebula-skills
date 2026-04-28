---
name: atomicnebula-tasks
description: "Query Atomic Nebula tasks, projects, subtasks, and comments through natural language. Use when a user asks about their tasks, project status, what's due, task details, subtasks, or comments. Supports filtering by project, status, assignee, priority, and date range. Use --env <workspace> to target a specific workspace (e.g., --env dev)."
metadata:
  {
    "openclaw":
      {
        "emoji": "📋",
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

# Atomic Nebula Tasks Skill

Query and explore tasks, projects, subtasks, and comments in Atomic Nebula through the HTTP API.

## Configuration

Credentials resolve in this order:

1. Environment variables such as `ATOMICNEBULA_API_KEY` and `ATOMICNEBULA_BASE_URL`
2. `~/.config/circeaura/assistant-workspaces.json`
3. Legacy `~/.openclaw/openclaw.json`

Use `--env <workspace>` to target a configured workspace. Run `skills/shared/an-env-list.sh` to inspect configured workspaces.

## Workspace Targeting

All commands accept `--env <workspace>` to target a specific workspace:

- **spider** (default, no flag needed) — SpiderGroup production workspace
- `--env dev` — James's development workspace
- `--env circeaurasupport` — CirceAura Support production workspace

Each workspace has its own API key in the shared assistant workspace config.

### When to Use Which Workspace

- **spider** (default): Real tasks and projects for daily work. Use for all normal operations.
- **dev** (`--env dev`): Testing new features, development verification, CI checks. Use when the user asks to "test on dev" or "check the dev workspace".

## Helper Script

Use the bundled script for common operations:

```bash
# List all tasks (production)
skills/atomicnebula-tasks/scripts/an-tasks.sh list

# List high priority tasks on dev
skills/atomicnebula-tasks/scripts/an-tasks.sh --env dev list --priority high

# Get task details (use UUID from list output)
skills/atomicnebula-tasks/scripts/an-tasks.sh get f7388c6a-c718-4584-bfe3-c5b6b4a8fe41

# Get subtasks
skills/atomicnebula-tasks/scripts/an-tasks.sh subtasks f7388c6a-c718-4584-bfe3-c5b6b4a8fe41

# Get comments
skills/atomicnebula-tasks/scripts/an-tasks.sh comments f7388c6a-c718-4584-bfe3-c5b6b4a8fe41

# List projects
skills/atomicnebula-tasks/scripts/an-tasks.sh projects
```

## Operations

### List Projects

Query projects with optional filters:

```bash
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/projects" | jq .
```

#### Project Filter Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `status` | string | Filter by status (e.g., `active`, `completed`) |
| `ownerId` | string | Filter by owner |

### List Tasks

Query tasks with optional filters:

```bash
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/tasks?limit=20" | jq .
```

#### Task Filter Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `projectId` | string | Filter by project ID |
| `ownerId` | string | Filter by assignee (owner) |
| `reporterId` | string | Filter by reporter |
| `category` | string | Filter by category |
| `priority` | string | Filter by priority (e.g., `high`, `medium`, `low`) |
| `lifecycleStageId` | string | Filter by status/stage ID |
| `contactId` | string | Filter by contact |
| `companyId` | string | Filter by company |
| `dealId` | string | Filter by deal |
| `dueBefore` | string | ISO date string |
| `dueAfter` | string | ISO date string |
| `searchTerm` | string | Search in title/description |
| `limit` | number | Max results (default: 50) |
| `offset` | number | Pagination offset |

#### Example: High priority tasks due this week

```bash
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/tasks?priority=high&limit=10" | jq '.items[] | {id, title, priority, dueDate}'
```

### Get Task Details

Retrieve a single task by UUID with full details:

```bash
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/tasks/{uuid}" | jq .
```

**Note:** Use the task's `id` field (UUID), not the `taskId` field (e.g., TASK-0042). List tasks first to get the UUID.

The response includes all task fields: title, description, project, priority, owner, dates, dependencies, acceptance criteria, labels, tags, and more.

### Get Subtasks

Retrieve all subtasks for a parent task:

```bash
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/tasks/{uuid}/subtasks" | jq .
```

**Note:** Use the task's `id` field (UUID), not the `taskId` field.

Returns array of subtasks with: id, taskId, title, lifecycleStageId, priority, ownerId, dueDate, completedAt.

### Get Task Comments

Retrieve all comments on a task:

```bash
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/tasks/{uuid}/comments" | jq .
```

**Note:** Use the task's `id` field (UUID), not the `taskId` field.

Returns array of comments with: id, commentId, author, content, type, metadata, createdAt, updatedAt.

## Pagination

For large result sets, use `limit` and `offset`:

```bash
# First page
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/tasks?limit=50&offset=0" | jq '.items'

# Second page
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/tasks?limit=50&offset=50" | jq '.items'
```

The response includes `totalCount` for calculating total pages.

## Common Use Cases

### "What tasks do I have due today?"

```bash
TODAY=$(date +%Y-%m-%d)
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/tasks?dueBefore=${TODAY}T23:59:59Z&limit=20" | jq '.items[] | {id, title, dueDate, priority}'
```

### "Show me all tasks in project X"

```bash
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/tasks?projectId={projectId}&limit=50" | jq '.items[] | {id, taskId, title, status: .lifecycleStageId}'
```

### "Get the full details and comments for a task"

```bash
# First, find the task UUID by listing tasks
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/tasks?searchTerm=task+title&limit=5" | jq '.items[] | {id, taskId, title}'

# Then use the UUID (id field) for detailed operations
TASK_UUID="f7388c6a-c718-4584-bfe3-c5b6b4a8fe41"

# Get task details
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/tasks/${TASK_UUID}" | jq .

# Get comments
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/tasks/${TASK_UUID}/comments" | jq .

# Get subtasks
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/tasks/${TASK_UUID}/subtasks" | jq .
```

## Error Handling

All endpoints return standard HTTP status codes:

- `200` — Success
- `400` — Bad Request (invalid parameters)
- `401` — Unauthorized (missing or invalid API key)
- `403` — Forbidden (API key lacks required permission)
- `404` — Not Found (resource doesn't exist)
- `500` — Internal Server Error

Error responses have format:

```json
{
  "error": {
    "code": "AUTHORIZATION_DENIED",
    "message": "API key does not have permission: atomicnebula:tasks:read"
  }
}
```

## Read-Only

This skill only performs read operations. It cannot create, update, or delete tasks, subtasks, or comments.

For task file workflows, pair this skill with `atomicnebula-attachments` to list/upload/download task attachments.
