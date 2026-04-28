---
name: atomicnebula-capture
description: "Save and retrieve durable Atomic Nebula assistant context captures. Use when an agent learns a durable decision, correction, preference, implementation note, unresolved follow-up, or session summary that should be available to Codex, Claude Code, OpenClaw, and future MCP clients. Supports --env <workspace> to target a configured workspace."
metadata:
  {
    "openclaw":
      {
        "emoji": "🧠",
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

# Atomic Nebula Capture Skill

Use this skill to write durable learnings back into Atomic Nebula's shared context layer. Captures are tenant-scoped, deduplicated by normalized content, linkable to known entities, and queued for future graph enrichment.

## Configuration

Credentials resolve in this order:

1. Environment variables such as `ATOMICNEBULA_API_KEY` and `ATOMICNEBULA_BASE_URL`
2. `~/.config/circeaura/assistant-workspaces.json`
3. Legacy `~/.openclaw/openclaw.json`

Use `--env <workspace>` to target a configured workspace.

## Supported Endpoints

- `POST /api/v1/atomicnebula/context/captures`
- `GET /api/v1/atomicnebula/context/captures`
- `GET /api/v1/atomicnebula/context/captures/:id`

## Helper Script

```bash
# Capture a decision
skills/atomicnebula-capture/scripts/an-capture.sh create --type decision --text "Use dedicated context capture tables for assistant memory."

# Capture a session summary from a file
skills/atomicnebula-capture/scripts/an-capture.sh create --type session_summary --file ./summary.md

# Link a capture to an entity
skills/atomicnebula-capture/scripts/an-capture.sh create --type correction --text "The primary contact prefers email." --entity-type contact --entity-id CONTACT-ID

# List and inspect captures
skills/atomicnebula-capture/scripts/an-capture.sh list --type decision --limit 20
skills/atomicnebula-capture/scripts/an-capture.sh get CAPTURE-ID
```

The helper intentionally omits `captureType` unless `--type` is supplied. This
prevents duplicate replays from downgrading an existing decision, preference, or
session summary into a generic thought.

## Capture Types

- `thought`
- `decision`
- `session_summary`
- `correction`
- `preference`
- `implementation_note`

## Auto-Capture Protocol

When a session produces durable value, capture only the highest-signal items:

- decisions made
- durable user or project preferences
- corrections to existing context
- unresolved follow-ups or ACT NOW items
- implementation notes likely to matter in future sessions
- one concise final session summary

Skip:

- secrets, credentials, or sensitive raw payloads
- raw transcripts or low-value conversation logs
- temporary debugging noise
- obvious duplicates
- facts that are already in canonical product records unless the capture adds interpretation

Each capture should be self-contained enough to be useful months later without reopening the original chat.

## Session-Close Examples

Codex:

```bash
skills/atomicnebula-capture/scripts/an-capture.sh create --type session_summary --text "Implemented the context capture permission boundary tests and retrieval ordering. Follow-up: run the read-only audit before staging."
```

Claude Code:

```bash
skills/atomicnebula-capture/scripts/an-capture.sh create --type implementation_note --text "Context capture writes do not imply read access; duplicate writes from write-only keys return only captureId."
```

OpenClaw:

```bash
skills/atomicnebula-capture/scripts/an-capture.sh create --type correction --text "Use context.captures.create for durable assistant memory, not content notes." --entity-type project --entity-id PROJECT-ID
```

## Permissions

- Read: `atomicnebula:context:read`
- Write: `atomicnebula:context:write`

Create operations are assistant write operations and can trigger the existing
Atomic Nebula approval gate. `atomicnebula:context:write` does not imply
`atomicnebula:context:read`; duplicate creates made by write-only keys return a
minimal acknowledgement instead of the full existing capture.

Entity links are checked before storage. A capture-create request that links to an
entity must use an API key with `atomicnebula:context:write`, the relevant entity
read permission, and access to an existing entity. Linked captures are only
surfaced from entity-context reads when the API key has both the relevant entity
read permission and `atomicnebula:context:read`.
