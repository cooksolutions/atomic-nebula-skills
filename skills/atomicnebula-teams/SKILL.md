---
name: atomicnebula-teams
description: "Read and reply to Microsoft Teams chats through the Atomic Nebula assistant REST API. Use when a user wants to see their Teams conversations, inspect messages, or reply in an existing chat or channel thread. Supports --env <workspace> to target a specific workspace."
metadata:
  {
    "openclaw":
      {
        "emoji": "💬",
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

# Atomic Nebula Teams Skill

Use the Atomic Nebula Teams REST API through the shared assistant capability layer. This skill is user-scoped: it only exposes chats and messages connected to the authenticated user's Teams credentials.

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

- `GET /api/v1/atomicnebula/channels`
- `GET /api/v1/atomicnebula/teams/chats`
- `GET /api/v1/atomicnebula/teams/chats/:chatId`
- `GET /api/v1/atomicnebula/teams/chats/:chatId/messages`
- `POST /api/v1/atomicnebula/teams/chats/:chatId/messages`

## Helper Script

```bash
# Show whether Teams is connected for the current user
skills/atomicnebula-teams/scripts/an-teams.sh status

# List accessible Teams chats
skills/atomicnebula-teams/scripts/an-teams.sh chats --limit 20

# Filter to meeting chats only
skills/atomicnebula-teams/scripts/an-teams.sh chats --chat-type meeting

# Get one chat
skills/atomicnebula-teams/scripts/an-teams.sh get TC-123

# List recent messages in a chat
skills/atomicnebula-teams/scripts/an-teams.sh messages TC-123 --limit 25

# Reply in a 1:1 or group chat
skills/atomicnebula-teams/scripts/an-teams.sh reply TC-123 --body "I can do 3pm."

# Reply in a channel thread
skills/atomicnebula-teams/scripts/an-teams.sh reply TC-456 --reply-to TM-789 --body "Looks good to me."
```

## Notes

- Channel replies require `--reply-to <messageId>`.
- The write path queues a reply; it does not create a brand-new channel post.
- Write operations send `X-Run-Id` and record approval challenges so OpenClaw webhook correlation still works if approvals are enabled.

## Permissions

- Read: `atomicnebula:teams:read`
- Reply: `atomicnebula:teams:write`
