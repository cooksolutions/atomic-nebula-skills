---
name: atomicnebula-social
description: "Manage Atomic Nebula social posting through the assistant REST API. Use when a user wants to list connected social accounts, draft posts, edit drafts, schedule, cancel, attach media, generate AI media, or browse swipe-file / templates / snippets. Supports --env <workspace> to target a configured workspace."
metadata:
  {
    "openclaw":
      {
        "emoji": "📣",
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

# Atomic Nebula Social Skill

Drive the Atomic Nebula social posting subsystem from a CLI client (Codex, OpenClaw, scripts). All operations correspond to assistant operation keys registered in `convex/platform/api/http/social.operations.ts` — the same keys that gate Luna's web/WhatsApp tools, so audit trails are unified across surfaces.

## Configuration

Credentials resolve in this order:

1. Environment variables (`ATOMICNEBULA_API_KEY`, `ATOMICNEBULA_BASE_URL`)
2. `~/.config/circeaura/assistant-workspaces.json`
3. Legacy `~/.openclaw/openclaw.json`

Use `--env <workspace>` to target a configured workspace. Run `skills/shared/an-env-list.sh` to inspect configured workspaces.

## Status

**This skill is partially live.** The assistant operation keys are registered (see below) so write requests resolve to the correct approval policy, but the **public Azure REST endpoints under `/api/v1/atomicnebula/social/*` are not yet built** — the Convex `internal*ForAssistant` mutations and queries exist (used by Luna in the web/WhatsApp app), but no HTTP layer routes external requests into them.

Until the external routes ship, the recommended path for ad-hoc social operations is:

1. Use Luna directly in the Atomic Nebula web app (`/assistant`).
2. Or call the Convex internal functions through an existing s2s token via the `convex/products/atomicnebula/social/*` modules.

Run the helper script with `--help` to see the planned commands and current status.

## Supported Operation Keys (Registered)

| Key | Method | Path | Action |
|---|---|---|---|
| `social.posts.create` | POST | `/api/v1/atomicnebula/social/posts` | write |
| `social.posts.publish` | POST | `/api/v1/atomicnebula/social/posts/:postId/publish` | write |
| `social.posts.draft.create` | POST | `/api/v1/atomicnebula/social/posts/drafts` | write |
| `social.posts.draft.update` | PATCH | `/api/v1/atomicnebula/social/posts/:postId` | write |
| `social.posts.schedule` | POST | `/api/v1/atomicnebula/social/posts/:postId/schedule` | write |
| `social.posts.cancel` | POST | `/api/v1/atomicnebula/social/posts/:postId/cancel` | write |
| `social.ai.record_generation` | POST | `/api/v1/atomicnebula/social/ai/generations` | write |
| `social.media.generate` | POST | `/api/v1/atomicnebula/social/ai/media` | write |
| `social.assets.list` | GET | `/api/v1/atomicnebula/social/assets` | read |
| `social.assets.get` | GET | `/api/v1/atomicnebula/social/assets/:assetId` | read |

## Helper Script

```bash
# Show planned commands and current wire-up status
skills/atomicnebula-social/scripts/an-social.sh --help

# Once the public REST routes ship, the planned commands will work as:
skills/atomicnebula-social/scripts/an-social.sh accounts
skills/atomicnebula-social/scripts/an-social.sh posts --status draft
skills/atomicnebula-social/scripts/an-social.sh draft-create \
  --text "Hello world" \
  --account-id LI-123 --account-id IG-456 \
  --tag launch
skills/atomicnebula-social/scripts/an-social.sh schedule POST-ID --at 2026-06-01T09:00:00Z
skills/atomicnebula-social/scripts/an-social.sh cancel POST-ID
skills/atomicnebula-social/scripts/an-social.sh assets --type image
skills/atomicnebula-social/scripts/an-social.sh generate-media \
  --type image --prompt "minimalist hero image of a turquoise wave" --size 1024x1024
```

## Approval Behaviour

Write commands send `X-Run-Id` and surface approval challenges using the shared CLI pattern (the script writes a row to `~/.openclaw/logs/write-runs.log` and prints the challenge id when policy returns `APPROVAL_REQUIRED`). Open the printed `approvalUrl` in the workspace web app to approve.

## Adding Public REST Routes

To finish wiring the CLI skill, add Azure Functions handlers under `api/src/external/social/...` that:

1. Validate the request against the operation key in the catalog (lookup via `resolveAssistantOperationFromMethodAndPath`).
2. Resolve approval policy via the existing `assistantApprovals` helpers.
3. Forward to the matching `internal*ForAssistant` Convex function in `convex/products/atomicnebula/social/*`.

Mirror the pattern used by the notebook external routes (under `api/src/external/notebook/...` if it exists, or by the public-forms routes documented in the root `CLAUDE.md`).
