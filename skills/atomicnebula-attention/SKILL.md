---
name: atomicnebula-attention
description: "Query the Atomic Nebula Attention Hub to understand priorities, focus queue, and what needs attention. Use when a user asks 'what should I focus on?', 'what's most important right now?', or wants to see their prioritized inbox. Supports filtering by energy level, bucket (now/next/later), and channel. Use --env <workspace> to target a specific workspace (e.g., --env dev)."
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

# Atomic Nebula Attention Hub Skill

Query and explore the Attention Hub to understand what's most important right now. This skill provides access to the focus queue, which uses a 7-factor scoring algorithm to prioritize threads.

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

- **spider** (default): Real attention queue and priorities. Use for all normal operations.
- **dev** (`--env dev`): Testing attention features, development verification, CI checks. Use when the user asks to "test on dev" or "check dev attention queue".

## Focus Scoring Algorithm

The focus queue uses a deterministic 7-factor scoring system:

1. **Pinned** (+50 points) — User explicitly pinned the thread
2. **Sprint** (+25 points) — Thread is in the active sprint
3. **SLA** (0-45 points) — Time-sensitive response needed
4. **Priority** (5-35 points) — Thread priority (urgent/high/medium/low)
5. **Importance** (0-30 points) — Per-user importance setting
6. **Energy** (-3 to +12 points) — Match with current energy level
7. **Staleness** (0-10 points) — How long since last review

### Buckets

Items are sorted into buckets based on score:
- **Now** (score >= 80) — Action immediately
- **Next** (score >= 55) — Plan for today
- **Later** (score < 55) — Backlog

## Helper Script

Use the bundled script for common operations:

```bash
# Get a summary of what's important (production)
skills/atomicnebula-attention/scripts/an-attention.sh summary

# Get a summary on dev
skills/atomicnebula-attention/scripts/an-attention.sh --env dev summary

# Get a summary for low energy
skills/atomicnebula-attention/scripts/an-attention.sh summary --energy low

# List items in the "now" bucket
skills/atomicnebula-attention/scripts/an-attention.sh focus --bucket now

# List items needing response
skills/atomicnebula-attention/scripts/an-attention.sh focus --needs-response

# Search for specific items
skills/atomicnebula-attention/scripts/an-attention.sh focus --search "invoice"
```

## Operations

### Get Focus Summary

Quick overview of priorities:

```bash
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/attention/summary" | jq .
```

Returns:
- Counts by bucket (now, next, later)
- Count of items needing response
- Top 5 priority items
- Active sprint info

### Get Focus Queue

Full focus queue with optional filters:

```bash
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/attention/focus" | jq .
```

#### Filter Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `energy` | string | Current energy level: low, medium, high |
| `bucket` | string | Filter by bucket: now, next, later |
| `includeSnoozed` | boolean | Include snoozed items (default: false) |
| `maxItems` | number | Max results (default: 50, max: 250) |
| `channel` | string | Filter by channel (email, sms, etc.) |
| `status` | string | Filter by status |
| `priority` | string | Filter by priority |
| `needsResponse` | boolean | Filter items needing response |
| `search` | string | Search in title/preview |

### Example: What should I focus on right now?

```bash
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/attention/summary" | jq '{
    sprint: .sprint.name,
    nowCount: .counts.now,
    needsResponse: .counts.needsResponse,
    topPriority: .topPriority
  }'
```

### Example: Show me "now" items with high energy

```bash
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/attention/focus?bucket=now&energy=high" | jq '.items[] | {
    threadId,
    title,
    score,
    needsResponse,
    scoreBreakdown
  }'
```

### Example: Email threads needing response

```bash
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/attention/focus?channel=email&needsResponse=true" | jq '.items[] | {
    threadId,
    title,
    priority,
    score,
    slaDueAt,
    lastMessageAt
  }'
```

## Response Structure

Each focus item includes:

```json
{
  "threadId": "thread_abc123",
  "title": "Subject line or title",
  "channel": "email",
  "sourceKey": "exchange_sync_123",
  "externalThreadId": "external_id",
  "status": "open",
  "priority": "high",
  "needsResponse": true,
  "slaDueAt": 1738080000000,
  "slaStatus": "at_risk",
  "lastMessageAt": 1737993600000,
  "unreadCount": 2,
  "isPinned": false,
  "importance": "high",
  "energy": "high",
  "snoozedUntil": null,
  "inActiveSprint": true,
  "sprintRank": 3,
  "score": 87,
  "bucket": "now",
  "scoreBreakdown": {
    "pinned": 0,
    "sprint": 25,
    "sla": 22,
    "priority": 22,
    "importance": 30,
    "energy": 12,
    "staleness": 6
  }
}
```

## Error Handling

All endpoints return standard HTTP status codes:

- `200` — Success
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

## Read-Only

This skill only performs read operations. It cannot create, update, or delete focus items or attention state.
