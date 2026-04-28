---
name: atomicnebula-digest
description: "Get a comprehensive daily briefing and context overview for Atomic Nebula. Use when a user asks 'what's my day look like?', 'give me a briefing', 'what's due today?', or wants a summary of completed work, pending attention items, upcoming events, and strategic context. Supports today, briefing, due, upcoming, and notified modes. Use --env <workspace> to target a specific workspace (e.g., --env dev for development)."
metadata:
  {
    "openclaw":
      {
        "emoji": "📰",
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

# Atomic Nebula Digest Skill

Get a comprehensive, layered workspace digest for AI assistants. This skill provides four views: Completed (what happened), Pending (what needs attention), Upcoming (what's coming), and Strategic (project context).

## Configuration

Credentials resolve in this order:

1. Environment variables such as `ATOMICNEBULA_API_KEY` and `ATOMICNEBULA_BASE_URL`
2. `~/.config/circeaura/assistant-workspaces.json`
3. Legacy `~/.openclaw/openclaw.json`

Use `--env <workspace>` to target a configured workspace. Run `skills/shared/an-env-list.sh` to inspect configured workspaces.

To see available workspaces: `skills/shared/an-env-list.sh`

## Workspace Targeting

All commands accept `--env <workspace>` to target a specific workspace:

- **spider** (default, no flag needed) — SpiderGroup production workspace
- `--env dev` — James's development workspace
- `--env circeaurasupport` — CirceAura Support production workspace

Each workspace has its own API key, base URL, and webhook credentials configured in the `atomicnebula-webhook` plugin config.

### When to Use Which Workspace

- **spider** (default): SpiderGroup production data. Use for all normal operations.
- **dev** (`--env dev`): Development workspace for testing and verification. Use when the user asks to "test on dev" or "check dev digest".
- **circeaurasupport** (`--env circeaurasupport`): CirceAura Support production data.

## Helper Script

Use the bundled script for common operations:

```bash
# Get full daily digest (production)
skills/atomicnebula-digest/scripts/an-digest.sh today

# Get briefing on dev
skills/atomicnebula-digest/scripts/an-digest.sh --env dev briefing

# Get due items within 30 minutes
skills/atomicnebula-digest/scripts/an-digest.sh due --within 30

# Get upcoming horizon for next 7 days
skills/atomicnebula-digest/scripts/an-digest.sh upcoming --days 7

# Mark reminder keys as notified (dedupe)
skills/atomicnebula-digest/scripts/an-digest.sh notified --keys "task:abc,meeting:def" --channel openclaw
```

## Commands

### today

Get the full daily digest with all four layers:

```bash
skills/atomicnebula-digest/scripts/an-digest.sh today
```

Returns:
- **Completed**: Tasks completed, meetings held, messages received
- **Pending**: Attention queue items by urgency
- **Upcoming**: Horizon view of tasks, meetings, and deadlines
- **Strategic**: Active projects and week overview

Options:
- `--date <YYYY-MM-DD>` — Target date (default: today)
- `--channels <list>` — Filter channels (e.g., "email,sms" or "all")
- `--details` — Include full item lists instead of counts

### briefing

Get a concise briefing summary:

```bash
skills/atomicnebula-digest/scripts/an-digest.sh briefing
```

Returns a condensed view with:
- Top 5 attention items
- Today's meetings and tasks due
- Critical/overdue items

### due

Get items due within a time window:

```bash
skills/atomicnebula-digest/scripts/an-digest.sh due --within 30
```

Returns items (tasks, meetings, SLAs) due within the specified minutes.

Options:
- `--within <minutes>` — Time window (default: 15, max: 120)
- `--types <list>` — Item types: task, meeting, sla, reminder, or all (default: all)
- `--min-urgency <level>` — Minimum urgency: now, soon, upcoming (default: soon)

### upcoming

Get the upcoming horizon view:

```bash
skills/atomicnebula-digest/scripts/an-digest.sh upcoming --days 7
```

Returns a day-by-day view of upcoming tasks, meetings, and flagged days.

Options:
- `--days <n>` — Days to include (default: 5, max: 14)

### notified

Mark reminder notification keys as delivered so future `due` calls can exclude already-sent items.

```bash
skills/atomicnebula-digest/scripts/an-digest.sh notified --keys "task:abc,meeting:def" --channel openclaw
```

Options:
- `--keys <csv>` — Comma-separated notification keys (required)
- `--channel <value>` — Channel label (default: `openclaw`)
- `--expires-after <ms>` — TTL for dedupe entry (default handled by API: 24h)
- `--notified-at <ms>` — Epoch milliseconds for delivery time (default: now)

## Operations

### Get Full Digest

```bash
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/digest" | jq .
```

#### Query Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `date` | string | ISO date for digest (YYYY-MM-DD), defaults to today |
| `daysAhead` | number | Days to include in upcoming horizon (default: 5, max: 14) |
| `channels` | string | Comma-separated channel types or "all" (default: "all") |
| `includeDetails` | boolean | Include full item lists vs counts only (default: false) |

### Get Due Items

```bash
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/reminders/due?withinMinutes=30" | jq .
```

#### Query Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `withinMinutes` | number | Time window in minutes (default: 15, max: 120) |
| `includeTypes` | string | Comma-separated types: task, meeting, sla, reminder, or all |
| `minUrgency` | string | Minimum urgency: now, soon, upcoming (default: soon) |
| `excludeNotified` | boolean | Exclude notification keys already marked via `/reminders/notified` |

### Mark Notification Keys as Notified

```bash
curl -s -X POST -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  -H "Content-Type: application/json" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/reminders/notified" \
  -d '{
    "notificationKeys": ["task:abc", "meeting:def"],
    "channel": "openclaw",
    "expiresAfter": 86400000
  }' | jq .
```

#### Request Fields

| Field | Type | Description |
|-------|------|-------------|
| `notificationKeys` | string[] | Required dedupe keys to record as delivered |
| `channel` | string | Delivery channel label (`openclaw`, `email`, `sms`, etc.) |
| `notifiedAt` | number | Epoch milliseconds for delivery timestamp |
| `expiresAfter` | number | TTL in milliseconds before key expires |

### Example: What's my day look like?

```bash
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/digest?includeDetails=true" | jq '{
    completed: .data.completed.summary,
    pending: .data.pending.byUrgency,
    today: .data.upcoming.horizon[0],
    projects: .data.strategic.activeProjects | length
  }'
```

### Example: What's due in the next hour?

```bash
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/reminders/due?withinMinutes=60&minUrgency=soon" | jq '.data.items[] | {
    type,
    title,
    minutesUntil,
    urgency,
    notificationText
  }'
```

## Response Structure

All responses follow the standard API wrapper format with `success`, `data`, and `meta` top-level fields:

```json
{
  "success": true,
  "data": { /* response payload */ },
  "meta": {
    "timestamp": "2024-01-15T10:30:00.000Z",
    "requestId": "req_abc123"
  }
}
```

### Digest Response

```json
{
  "success": true,
  "data": {
    "meta": {
      "date": "2024-01-15",
      "requestedChannels": ["all"],
      "generatedAt": 1705312800000
    },
    "completed": {
      "summary": {
        "tasksCompleted": 5,
        "meetingsHeld": 3,
        "messagesReceived": 12
      },
      "byChannel": { "email": { "received": 8, "pending": 3 } }
    },
    "pending": {
      "attention": { "items": [...] },
      "byUrgency": {
        "critical": [...],
        "high": [...],
        "medium": [...],
        "low": [...]
      }
    },
    "upcoming": {
      "horizon": [...],
      "byProject": [...]
    },
    "strategic": {
      "activeProjects": [...],
      "weekOverview": { ... }
    }
  },
  "meta": {
    "timestamp": "2024-01-15T10:30:00.000Z"
  }
}
```

### Due Items Response

```json
{
  "success": true,
  "data": {
    "query": {
      "withinMinutes": 30,
      "checkedAt": 1705312800000
    },
    "items": [
      {
        "type": "meeting",
        "id": "mtg_123",
        "title": "Team standup",
        "dueAt": 1705313100000,
        "minutesUntil": 5,
        "urgency": "now",
        "notificationText": "Meeting in 5 min: Team standup",
        "deepLink": "https://app.atomicnebula.com/workspace/.../meetings/mtg_123"
      }
    ],
    "summary": {
      "total": 3,
      "now": 1,
      "soon": 2,
      "upcoming": 0,
      "overdue": 0
    }
  },
  "meta": {
    "timestamp": "2024-01-15T10:30:00.000Z"
  }
}
```

## Error Handling

All endpoints return standard HTTP status codes:

- `200` — Success
- `201` — Created (used by `/reminders/notified`)
- `400` — Bad Request (invalid parameters)
- `401` — Unauthorized (missing or invalid API key)
- `403` — Forbidden (API key lacks required permission)
- `500` — Internal Server Error

Error responses have format:

```json
{
  "error": {
    "code": "AUTHORIZATION_DENIED",
    "message": "API key does not have permission: atomicnebula:attention:read"
  }
}
```

## Safety Scope

This skill is mostly read-only (`digest`, `briefing`, `due`, `upcoming`).  
The `notified` command performs a bounded write to reminder-dedupe state only (no task, meeting, or project mutations).
