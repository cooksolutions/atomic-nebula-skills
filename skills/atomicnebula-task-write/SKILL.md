---
name: atomicnebula-task-write
description: "Create, update, and complete tasks and projects in Atomic Nebula with human-in-the-loop approval. Use when a user wants to create a new task, update task details, change status, assign tasks, mark tasks complete, create projects, or list projects. Write operations are risk-classified and may require approval. Use --env <workspace> to target a specific workspace (e.g., --env dev)."
metadata:
  {
    "openclaw":
      {
        "emoji": "✏️",
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

# Atomic Nebula Task Write Skill

Create, update, and complete tasks in Atomic Nebula with risk-based approval gates.

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

- **spider** (default): Real task creation and updates for daily work. Use for all normal operations.
- **dev** (`--env dev`): Testing write operations, verifying approval workflows, CI checks. Use when the user asks to "test on dev" or "create a test task on dev".

## Approval Workflow

All write operations go through the **Assistant Gateway** with risk-based approval:

### Risk Classification

| Action | Risk Tier | Approval Status |
|--------|-----------|-----------------|
| `tasks.create` | `low_write` | Auto-accepted |
| `tasks.update` | `low_write` | Auto-accepted |
| `tasks.complete` | `low_write` | Auto-accepted |
| `tasks.delete` | `high_write` | **Requires review** |

### Workflow Steps

1. **Intent Creation** — Skill submits intent to Assistant Gateway
2. **Risk Classification** — Gateway classifies action by risk tier
3. **Approval Decision** — `low_write` auto-accepted; `high_write` requires human review
4. **Execution** — Approved intents are executed against Convex backend
5. **Audit Trail** — All operations logged with correlation IDs

### Approval States

- `accepted` — Operation proceeds immediately
- `requires_review` — Human must approve before execution
- `blocked` — Operation denied (critical operations)

## Operations

### Create Task

Create a new task:

```bash
curl -s -X POST -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  -H "Content-Type: application/json" \
  -H "X-Idempotency-Key: $(uuidgen)" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/tasks" \
  -d '{
    "title": "Review quarterly report",
    "description": "Q4 2025 financial review",
    "category": "review",
    "priority": "high",
    "projectId": "proj_abc123",
    "ownerId": "user_xyz",
    "dueDate": "2026-02-28"
  }' | jq .
```

#### Create Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `title` | string | Yes | Task title |
| `description` | string | No | Detailed description (markdown). Alias: `bodyMarkdown` |
| `category` | string | No | Category (default: "general") |
| `subcategory` | string | No | Free-form subcategory tag |
| `component` | string | No | Free-form component tag |
| `priority` | string | No | Priority: high, medium, low (default: "medium") |
| `projectId` | string | No | Project ID to link |
| `sprintId` | string | No | Sprint ID to link |
| `lifecyclePipelineId` | string | No | Lifecycle pipeline ID. Discover via `GET /lifecycle-pipelines?objectType=task` |
| `lifecycleStageId` | string | No | Lifecycle stage ID within the chosen pipeline |
| `parentTaskId` | string | No | Parent task ID for sub-task hierarchies |
| `ownerId` | string | No | Assignee user ID (defaults to caller) |
| `reporterId` | string | No | Reporter user ID |
| `reviewerId` | string | No | Reviewer user ID |
| `dueDate` | string | No | Due date (ISO format) |
| `startDate` | string | No | Start date (ISO format) |
| `reminderAt` | number\|string | No | Reminder timestamp (epoch ms or ISO datetime) |
| `estimatedHours` | number | No | Estimated effort in hours |
| `effortPoints` | number | No | Story-point style effort estimate |
| `dependencies` | array | No | Task IDs this task depends on |
| `blocks` | array | No | Task IDs this task blocks |
| `acceptanceCriteria` | array | No | Bullet-list of acceptance criteria |
| `contactId` | string | No | Linked contact ID |
| `companyId` | string | No | Linked company ID |
| `dealId` | string | No | Linked deal ID |
| `leadId` | string | No | Linked lead ID |
| `labels` | array | No | Array of label strings |
| `tags` | array | No | Array of tag strings |

### Bulk Create Tasks

Create up to 50 tasks in one request. Use this for imports and migrations so lazy numbering is batched by the backend:

```bash
curl -s -X POST -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  -H "Content-Type: application/json" \
  -H "X-Idempotency-Key: $(uuidgen)" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/tasks" \
  -d '{
    "tasks": [
      {
        "clientRef": "row-1",
        "title": "Import migrated task",
        "description": "Created from import batch",
        "projectId": "proj_abc123"
      }
    ]
  }' | jq .
```

Bulk items accept the same fields as `Create Task`, plus optional `clientRef`. The response maps each `clientRef` to the created task id and allocated `taskId`.

### Update Task

Update an existing task:

```bash
curl -s -X PATCH -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  -H "Content-Type: application/json" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/tasks/TASK-0042" \
  -d '{
    "priority": "high",
    "ownerId": "user_xyz",
    "dueDate": "2026-03-01"
  }' | jq .
```

#### Update Parameters

PATCH accepts the same fields as create (all optional), plus the ability to **clear** linked references by passing `null` for `projectId`, `sprintId`, `ownerId`, `reporterId`, `reviewerId`, `dueDate`, `startDate`, `parentTaskId`, `contactId`, `companyId`, `dealId`, or `leadId`. Pass `completedAt` (epoch ms) to mark complete, or use the `/complete` endpoint.

| Parameter | Type | Description |
|-----------|------|-------------|
| `title` | string | New title |
| `description` | string | New description (markdown). Alias: `bodyMarkdown` |
| `category` | string | New category |
| `subcategory` | string | Free-form subcategory tag |
| `component` | string | Free-form component tag |
| `priority` | string | New priority |
| `projectId` | string\|null | New project (null = unlink) |
| `sprintId` | string\|null | New sprint (null = unlink) |
| `lifecyclePipelineId` | string | New lifecycle pipeline |
| `lifecycleStageId` | string | New lifecycle stage |
| `parentTaskId` | string\|null | New parent task (null = unlink) |
| `ownerId` | string\|null | New assignee (null = unassign) |
| `reporterId` | string\|null | New reporter |
| `reviewerId` | string\|null | New reviewer |
| `dueDate` | string\|null | New due date |
| `startDate` | string\|null | New start date |
| `completedAt` | number | Mark complete (epoch ms) |
| `reminderAt` | number\|string\|null | New reminder timestamp |
| `estimatedHours` | number | Estimated hours |
| `effortPoints` | number | Effort points |
| `dependencies` | array | Replace dependency list |
| `blocks` | array | Replace blocks list |
| `acceptanceCriteria` | array | Replace AC bullets |
| `contactId` | string\|null | New linked contact |
| `companyId` | string\|null | New linked company |
| `dealId` | string\|null | New linked deal |
| `leadId` | string\|null | New linked lead |
| `labels` | array | New labels |
| `tags` | array | New tags |

### Complete Task

Mark a task as completed:

```bash
curl -s -X PATCH -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  -H "Content-Type: application/json" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/tasks/TASK-0042" \
  -d '{"completedAt": '$(date +%s000)'}' | jq .
```

### Delete Task

Soft delete a task (**requires approval** — high_write risk):

```bash
curl -s -X DELETE -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/tasks/TASK-0042" | jq .
```

### List Projects

List all projects for the authenticated tenant:

```bash
curl -s -X GET -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/projects" | jq .
```

### Create Project

Create a new project:

```bash
curl -s -X POST -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  -H "Content-Type: application/json" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/projects" \
  -d '{
    "name": "Content Backlog",
    "key": "content-backlog",
    "description": "Content creation backlog"
  }' | jq .
```

#### Create Project Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `name` | string | Yes | Project name |
| `key` | string | Yes | Project key (auto-generated from name if using helper script) |
| `description` | string | No | Project description |
| `status` | string | No | Project status |
| `startDate` | string | No | Start date (ISO format) |
| `targetEndDate` | string | No | Target end date (ISO format) |

## Helper Script

Use the bundled script for common operations:

```bash
# Create a new task (production)
skills/atomicnebula-task-write/scripts/an-task-write.sh create --title "Review report" --priority high

# Create a test task on dev
skills/atomicnebula-task-write/scripts/an-task-write.sh --env dev create --title "Test task" --priority low

# Update a task
skills/atomicnebula-task-write/scripts/an-task-write.sh update TASK-0042 --priority high --owner user_xyz

# Complete a task
skills/atomicnebula-task-write/scripts/an-task-write.sh complete TASK-0042

# Delete a task (will require approval)
skills/atomicnebula-task-write/scripts/an-task-write.sh delete TASK-0042

# List all projects
skills/atomicnebula-task-write/scripts/an-task-write.sh list-projects

# Create a project (key auto-generated from name)
skills/atomicnebula-task-write/scripts/an-task-write.sh create-project --name "Content Backlog"

# Create a project with explicit key and description
skills/atomicnebula-task-write/scripts/an-task-write.sh create-project --name "Content Backlog" --key "content-backlog" --description "Content creation backlog"
```

## Create Task With Files

Use the attachments skill after task creation:

1. Create the task and capture the returned task ID.
2. Upload each file with `atomicnebula-attachments`:

```bash
skills/atomicnebula-task-write/scripts/an-attachments.sh upload --entity-type task --entity-id TASK-0042 --file ./requirements.pdf
skills/atomicnebula-task-write/scripts/an-attachments.sh upload --entity-type task --entity-id TASK-0042 --file ./wireframe.png
```

3. Verify linked files:

```bash
skills/atomicnebula-task-write/scripts/an-attachments.sh list --entity-type task --entity-id TASK-0042
```

## Idempotency

All create operations support idempotency via the `X-Idempotency-Key` header. If a request with the same key is repeated, the existing task is returned instead of creating a duplicate.

```bash
IDEMPOTENCY_KEY="create-task-review-$(date +%Y%m%d)"
curl -s -X POST -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  -H "X-Idempotency-Key: $IDEMPOTENCY_KEY" \
  ...
```

## Error Handling

All endpoints return standard HTTP status codes:

- `200` — Success (update/delete)
- `201` — Created (create)
- `400` — Bad Request (invalid parameters)
- `401` — Unauthorized (missing or invalid API key)
- `403` — Forbidden (API key lacks required permission)
- `404` — Not Found (task doesn't exist)
- `409` — Conflict (idempotency key collision)
- `500` — Internal Server Error

Error responses have format:

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Missing required field: title"
  }
}
```

## Audit Trail

All write operations are logged with:
- Timestamp
- Actor (user or service)
- Operation type
- Task ID
- Changes made
- Correlation ID for tracing

Query audit logs via the field change audit endpoints (requires appropriate permissions).

## Security

- All write operations require the `atomicnebula:tasks:write` permission
- Operations are scoped to the tenant associated with the API key
- Cross-tenant access is blocked
- Soft delete ensures data recovery is possible
- Delete operations require explicit human approval via the Assistant Gateway

## Related Documentation

- [Skill/Gateway Contract v1](../../docs/products/atomic-nebula/contracts/skill-gateway-v1-contract.md)
