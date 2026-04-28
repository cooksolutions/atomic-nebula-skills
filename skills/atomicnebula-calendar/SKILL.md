---
name: atomicnebula-calendar
description: "Query and manage Atomic Nebula calendar events, meetings, and availability through natural language. Use when a user asks about their schedule, upcoming meetings, availability, event details, or wants calendar appointments created/updated/deleted. Supports filtering by date range, status, contact, company, and deal. Use --env <workspace> to target a specific workspace (e.g., --env dev)."
metadata:
  {
    "openclaw":
      {
        "emoji": "📅",
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

# Atomic Nebula Calendar Skill

Query and manage meetings, calendar events, and availability in Atomic Nebula through the HTTP API.

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

- **spider** (default): Real calendar, meetings, availability. Use for all normal operations.
- **dev** (`--env dev`): Testing calendar features, development verification, CI checks. Use when the user asks to "test on dev" or "check dev calendar".

## Helper Script

Use the bundled script for common operations:

```bash
# Today's calendar events from Exchange/Google (PREFERRED for "what's on my calendar")
skills/atomicnebula-calendar/scripts/an-calendar.sh events --today

# List writable calendar targets for explicit mailbox/calendar selection
skills/atomicnebula-calendar/scripts/an-calendar.sh targets

# Upcoming events from now until end of day (calendar + CRM combined)
skills/atomicnebula-calendar/scripts/an-calendar.sh upcoming

# List CRM meetings (manually created, NOT Exchange/Google calendar)
skills/atomicnebula-calendar/scripts/an-calendar.sh list --today

# List CRM meetings for a date range
skills/atomicnebula-calendar/scripts/an-calendar.sh list --start-after 2026-02-20 --start-before 2026-02-27

# Calendar events for a specific date
skills/atomicnebula-calendar/scripts/an-calendar.sh events --date 2026-03-10

# Get CRM meeting details
skills/atomicnebula-calendar/scripts/an-calendar.sh get MEET-0042

# Find availability windows
skills/atomicnebula-calendar/scripts/an-calendar.sh availability --date 2026-02-20

# Create a provider-backed calendar appointment
skills/atomicnebula-calendar/scripts/an-calendar.sh create --subject "1:1" --start 2026-04-22T10:00:00Z --end 2026-04-22T10:30:00Z

# Update a provider-backed calendar appointment
skills/atomicnebula-calendar/scripts/an-calendar.sh update CAL-123 --location "Conference room"

# Delete a provider-backed calendar appointment
skills/atomicnebula-calendar/scripts/an-calendar.sh delete CAL-123 --send-updates
```

**IMPORTANT**: For "what's on my calendar today?" use `events --today` or `upcoming`, NOT `list --today`. The `list` command only shows CRM-created meetings, NOT synced Exchange/Google calendar events. The user's actual calendar is in `events`.

## Operations

### Calendar Events (Provider — Exchange/Google)

**Use this for "what's on my calendar" questions.** Returns events synced from Microsoft Exchange or Google Calendar.

```bash
# Today's events
skills/atomicnebula-calendar/scripts/an-calendar.sh events --today

# Events for a specific date
skills/atomicnebula-calendar/scripts/an-calendar.sh events --date 2026-03-10

# Custom date range
skills/atomicnebula-calendar/scripts/an-calendar.sh events --start 2026-03-06T09:00:00Z --end 2026-03-06T18:00:00Z
```

The `/api/v1/atomicnebula/calendar/events` endpoint returns:
- Subject, start/end times, attendees, Teams join URLs
- Provider info (microsoft/google)
- All-day and cancellation flags

### Calendar Targets

Use this before creating appointments on behalf of a specific mailbox or secondary calendar:

```bash
skills/atomicnebula-calendar/scripts/an-calendar.sh targets
```

This calls `/api/v1/atomicnebula/calendar/targets` and returns:
- Accessible mailbox resources
- Writable calendars under each mailbox
- Saved default target validity

### Create / Update / Delete Calendar Events

Use the new calendar write routes for provider-backed appointments:

```bash
# Create using saved default target
skills/atomicnebula-calendar/scripts/an-calendar.sh create \
  --subject "Project sync" \
  --start 2026-04-22T14:00:00Z \
  --end 2026-04-22T14:30:00Z \
  --attendee alice@example.com \
  --online

# Create on a specific mailbox/calendar
skills/atomicnebula-calendar/scripts/an-calendar.sh create \
  --resource-id mailbox_resource_id \
  --calendar-id provider_calendar_id \
  --subject "Quarterly review" \
  --start 2026-04-23T09:00:00Z \
  --end 2026-04-23T10:00:00Z

# Update a canonical Atomic Nebula calendar event
skills/atomicnebula-calendar/scripts/an-calendar.sh update CAL-123 --location "Board room" --send-updates

# Delete a canonical Atomic Nebula calendar event
skills/atomicnebula-calendar/scripts/an-calendar.sh delete CAL-123 --send-updates
```

If the API returns `CALENDAR_TARGET_REQUIRED`, call `targets` or set a default in Calendar Settings instead of guessing.

### List CRM Meetings

Query manually-created CRM meetings (NOT provider calendar events):

```bash
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/meetings?limit=20" | jq .
```

#### Filter Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `status` | string | Filter by status (scheduled, completed, cancelled) |
| `outcome` | string | Filter by meeting outcome |
| `contactId` | string | Filter by contact |
| `companyId` | string | Filter by company |
| `dealId` | string | Filter by deal |
| `projectId` | string | Filter by project |
| `leadId` | string | Filter by lead |
| `ownerId` | string | Filter by owner |
| `startAfter` | string | ISO date string - meetings starting after this time |
| `startBefore` | string | ISO date string - meetings starting before this time |
| `searchTerm` | string | Search in title/description |
| `limit` | number | Max results (default: 50) |
| `offset` | number | Pagination offset (default: 0) |

#### Example: Meetings this week

```bash
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/meetings?startAfter=2026-02-20&startBefore=2026-02-27&limit=50" | jq '.items[] | {id, title, startsAt, endsAt, location}'
```

### Get Upcoming (Combined Calendar + CRM)

Returns both calendar events from Exchange/Google AND CRM meetings from now until end of day:

```bash
skills/atomicnebula-calendar/scripts/an-calendar.sh upcoming
```

### Get Meeting Details

Retrieve a single meeting by ID with full details:

```bash
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/meetings/{meetingId}" | jq .
```

The response includes: title, description, location, attendees, startsAt, endsAt, status, outcome, contact, company, deal info, and more.

## Pagination

For large result sets, use `limit` and `offset`:

```bash
# First page
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/meetings?limit=50&offset=0" | jq '.items'

# Second page
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/meetings?limit=50&offset=50" | jq '.items'
```

The response includes `totalCount` for calculating total pages.

## Common Use Cases

### "What meetings do I have today?" / "What's on my calendar?"

```bash
skills/atomicnebula-calendar/scripts/an-calendar.sh events --today
```

This returns all Exchange/Google calendar events for today with times, attendees, and join URLs.

### "When am I free today?"

Query canonical calendar availability windows for today:

```bash
skills/atomicnebula-calendar/scripts/an-calendar.sh availability --date $(date +%Y-%m-%d)
```

The availability command uses `/api/v1/atomicnebula/calendar/availability` and returns free slots computed from canonical calendar events.

### "Show me my upcoming client meetings"

```bash
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/meetings/upcoming?limit=20" | jq '.[] | select(.companyId != null) | {id, title, startsAt, company: .companyId}'
```

### "Get the meeting details with attendees"

```bash
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/meetings/MEET-0042" | jq '{title, description, location, startsAt, endsAt, attendees, contactId, companyId, dealId}'
```

## Error Handling

All endpoints return standard HTTP status codes:

- `200` — Success
- `400` — Bad Request (invalid parameters)
- `401` — Unauthorized (missing or invalid API key)
- `403` — Forbidden (API key lacks required permission)
- `404` — Not Found (meeting doesn't exist)
- `500` — Internal Server Error

Error responses have format:

```json
{
  "error": {
    "code": "AUTHORIZATION_DENIED",
    "message": "API key does not have permission: atomicnebula:meetings:read"
  }
}
```

## Write Behaviour

This skill can now create, update, and delete provider-backed calendar events through the assistant calendar API. CRM meetings remain a separate surface under `/meetings`.

The helper script sends `X-Run-Id` on write requests and records approval challenges so OpenClaw webhook correlation still works if approvals are enabled for the workspace/API key.

## Permissions

- `atomicnebula:meetings:read` for CRM meetings
- `atomicnebula:calendar:read` for provider calendar reads and availability
- `atomicnebula:calendar:write` for provider calendar create/update/delete
