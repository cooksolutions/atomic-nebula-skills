---
name: atomicnebula-meetings
description: "Read and manage Atomic Nebula CRM meetings — including AI-recorder transcripts (Read.ai, Otter, Plaud, Wave, Granola, etc.) — and act on the open loops they produce. Use when a user wants to record a meeting, attach a transcript, list CRM meetings, or promote/resolve/snooze/dismiss the loops derived from a meeting. Supports --env <workspace> to target a configured workspace."
metadata:
  {
    "openclaw":
      {
        "emoji": "🤝",
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

# CRM Meetings

This skill manages **CRM meetings** (`an_meetings`) — the records that capture the business significance of a conversation: subject, transcript, action items emitted by AI recorders, CRM links to contacts/companies/deals/projects, outcome, and the open loops detected from the transcript.

## CRM meetings vs calendar events

These are two different things and Luna must keep them straight:

- **Calendar events** (`an_calendar_events`) — the user's diary, synced from Exchange/Google. Read-only. **Use the `atomicnebula-calendar` skill.** Answers *"what's on my calendar?"*.
- **CRM meetings** (`an_meetings`) — a record that a meeting had business significance, often produced from an AI recorder webhook (Read.ai today; future: Otter, Plaud, Wave, Granola, Fireflies). Has the transcript, action items, links to contacts/deals/etc. Can exist with or without a calendar event. **This skill.**

The two are linked when both exist:
- `an_meetings.calendarEventId` → points to the calendar event.
- `an_calendar_events.crmEnabled` (bool) + `crmMeetingId` → back-pointer.

A CRM meeting can exist:
- **Linked to a calendar event** (typical when promoting a diary entry to CRM).
- **Standalone** (Read.ai webhook for an ad-hoc Zoom call, a phone call, or a meeting Luna recorded post-hoc).

## Action items vs tasks (terminology)

This is the most important distinction in this skill. Get it wrong and the data model gets corrupted.

- **Action items / suggestions / next steps** — what AI recorders (Read.ai, Otter, Plaud, Wave, Granola, Fireflies, etc.) emit. Each vendor uses different wording. They are **evidence — proposals — never commitments.** They live in `meeting.metadata.<vendor>.actionItems` (e.g. `metadata.readai.actionItems`).
- **Open loops** — Atomic Nebula's normalized representation of "something that might need to happen." Action items get auto-promoted into open loops by the meeting-processing pipeline. This is where the actionable lifecycle lives: `open | snoozed | promoted | dismissed | resolved`. **The "checkbox tick that makes a row disappear" in the meeting triage UI is operating on the open loop, not the action item.**
- **Tasks** — canonical AN tasks. A task means "someone has agreed to do this." Tasks are the only commitments.

**Luna must never write to action items.** Vendor-emitted action items are immutable evidence. If Luna decides something needs doing, she:

1. Calls `meetings loops <meetingId>` to see what's been suggested and whether each is open / promoted / resolved / dismissed / snoozed.
2. Acts on the loops via `loops promote|resolve|snooze|dismiss`.
3. `promote` creates a real task linked to the meeting + loop. The other verbs change the loop status without creating a task.

Use `atomicnebula-task-write` if Luna needs to author a task that isn't derived from an existing open loop.

## Configuration

Credentials resolve in this order:

1. Environment variables such as `ATOMICNEBULA_API_KEY` and `ATOMICNEBULA_BASE_URL`
2. `~/.config/circeaura/assistant-workspaces.json`
3. Legacy `~/.openclaw/openclaw.json`

Use `--env <workspace>` to target a configured workspace.

## Helper Script

Run from the repository root:

```bash
# Read CRM meetings
skills/atomicnebula-meetings/scripts/an-meetings.sh list
skills/atomicnebula-meetings/scripts/an-meetings.sh list --start-after 2026-05-01 --start-before 2026-05-08
skills/atomicnebula-meetings/scripts/an-meetings.sh upcoming
skills/atomicnebula-meetings/scripts/an-meetings.sh get <meetingId>
skills/atomicnebula-meetings/scripts/an-meetings.sh loops list <meetingId>

# Write CRM meetings (--confirm yes required)
skills/atomicnebula-meetings/scripts/an-meetings.sh create \
  --subject "Acme intro call" --start 2026-05-09T14:00:00Z --end 2026-05-09T14:30:00Z \
  --transcript "James: ...\nAcme: ..." --company-id <id> --confirm yes
skills/atomicnebula-meetings/scripts/an-meetings.sh attach-transcript <meetingId> --transcript-file ./call.txt --confirm yes
skills/atomicnebula-meetings/scripts/an-meetings.sh update <meetingId> --outcome "held" --confirm yes
skills/atomicnebula-meetings/scripts/an-meetings.sh cancel <meetingId> --confirm yes
skills/atomicnebula-meetings/scripts/an-meetings.sh delete <meetingId> --confirm yes

# Open loop verbs (--confirm yes required)
skills/atomicnebula-meetings/scripts/an-meetings.sh loops promote <loopId> --confirm yes
skills/atomicnebula-meetings/scripts/an-meetings.sh loops resolve <loopId> --confirm yes
skills/atomicnebula-meetings/scripts/an-meetings.sh loops snooze <loopId> --until 2026-05-15T09:00:00Z --confirm yes
skills/atomicnebula-meetings/scripts/an-meetings.sh loops dismiss <loopId> --confirm yes
```

## Endpoints

### Read

| Method | Path | Notes |
|---|---|---|
| GET | `/api/v1/atomicnebula/meetings` | Filters: `status`, `outcome`, `contactId`, `companyId`, `dealId`, `projectId`, `leadId`, `ownerId`, `startAfter`, `startBefore`, `searchTerm`, `limit`, `cursor` |
| GET | `/api/v1/atomicnebula/meetings/upcoming` | `?limit`, `?ownerId` |
| GET | `/api/v1/atomicnebula/meetings/:id` | Full record incl. `body` (transcript) and `metadata` (vendor action items) |
| GET | `/api/v1/atomicnebula/meetings/:id/loops` | Open loops derived from this meeting, with `status`, `promotedToTaskId`, `actionIndex`, `actionText` |

### Write

| Method | Path | Notes |
|---|---|---|
| POST | `/api/v1/atomicnebula/meetings` | Body accepts `subject`/`title`, `startTime`/`startAt`, `endTime`/`endAt`, `body`/`description` (transcript), `bodyHtml`, `location`, `meetingUrl`, `outcome`, `calendarEventId`, `contactId`/`companyId`/`dealId`/`projectId`/`leadId`, `ownerId`, `priority`, `tags`, `metadata`, `source` (default `"api"` — the skill sends `"luna"`), `externalId`. Setting `calendarEventId` on create flips the back-pointer (`crmEnabled` + `crmMeetingId`) on the matching calendar event. |
| PATCH | `/api/v1/atomicnebula/meetings/:id` | Same fields. Updates that change `body` or `metadata` re-trigger the meeting downstream processing pipeline (open-loop detection from transcript and from action items). |
| POST | `/api/v1/atomicnebula/meetings/:id/cancel` | Body: `{ reason? }`. Sets status to `cancelled`. |
| DELETE | `/api/v1/atomicnebula/meetings/:id` | Soft delete. |

### Open loops

| Method | Path | Notes |
|---|---|---|
| POST | `/api/v1/atomicnebula/openloops/:loopId/promote` | Body: `{ title?, dueDate?, priority?, category?, projectId?, assigneeUserId? }`. Creates a canonical task linked back to the loop; loop status becomes `promoted`. Idempotent if already promoted. |
| POST | `/api/v1/atomicnebula/openloops/:loopId/resolve` | Body: `{ reason? }`. Marks loop `resolved` (done, no task needed). |
| POST | `/api/v1/atomicnebula/openloops/:loopId/snooze` | Body: `{ until }` (epoch ms or ISO datetime). Marks loop `snoozed`. |
| POST | `/api/v1/atomicnebula/openloops/:loopId/dismiss` | No body. Marks loop `dismissed` (false positive / not relevant). |

## Meeting IDs

Use the `id` UUID returned in list/get responses for the path `<meetingId>`. The human-readable `meetingId` (e.g. `MTG-1715000000000`) is for display. Don't pass vendor-side IDs (Read.ai sessionId, Outlook event GUID) into the AN URL.

## Permissions

- `atomicnebula:meetings:read` — list / get / upcoming / loops
- `atomicnebula:meetings:write` — create / update / cancel / delete
- `atomicnebula:attention:read` — listing the meeting's loops
- `atomicnebula:attention:write` — promote / resolve / snooze / dismiss

When `promote` creates a task, the API key must additionally have access to the underlying task creation path — `requireAtomicNebulaTenantAccessForUserId` enforces tenant membership; standard task permissions are not separately required.
