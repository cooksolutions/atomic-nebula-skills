---
name: atomicnebula-email
description: "Read, search, send, reply, forward, and draft emails across all connected mailboxes (Exchange + Gmail). Drafts created via this skill are persisted in Atomic Nebula AND pushed to the user's Outlook/Gmail Drafts folder, with a shareable AN deep-link the user can open on desktop or mobile. Use when an assistant needs to compose, queue, or schedule outbound email, prepare drafts for human review, search inboxes, or perform mailbox operations like marking-read or deleting. Use --env <workspace> to target a specific workspace (e.g., --env dev)."
metadata:
  {
    "openclaw":
      {
        "emoji": "📧",
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

# Atomic Nebula Email Skill

Full email feature parity with the Atomic Nebula web UI. Use this skill to:

- **Read**: list / search / get-content / threads / unread counts across all mailboxes
- **Write**: send, reply, forward, mark-read, flag, delete
- **Drafts**: create drafts that appear in **both** the user's Outlook/Gmail Drafts folder **and** in Atomic Nebula, with a deep-link the user can open from desktop or mobile to review and send

This replaces the old `atomicnebula-email-search` skill (read-only). All previous search functionality is still available — see [Search](#how-search-works) below.

## Configuration

Credentials resolve in this order:

1. Environment variables such as `ATOMICNEBULA_API_KEY` and `ATOMICNEBULA_BASE_URL`
2. `~/.config/circeaura/assistant-workspaces.json`
3. Legacy `~/.openclaw/openclaw.json`

Use `--env <workspace>` to target a configured workspace. Run `skills/shared/an-env-list.sh` to inspect configured workspaces.

| Workspace | Default | Flag |
|---|---|---|
| `spider` (SpiderGroup production) | yes | `--env spider` |
| `dev` (James's dev workspace) | no | `--env dev` |

## Permissions

| Operation | Required permission |
|---|---|
| Read (list / get / search / threads / unread) | `atomicnebula:emails:read` |
| Write (send / reply / forward / mark / flag / delete / drafts) | `atomicnebula:emails:write` |
| Promote sender to contact | `atomicnebula:contacts:write` |

If your API key was created before this skill update, request a new one with `atomicnebula:emails:write` to use the write/draft operations.

## Quick Start

```bash
# ── DISCOVERY ──────────────────────────────────────────────────────────────
# Always run this first if you don't already know the mailbox address. The
# `address` value returned here is what you pass as --mailbox / mailboxAddress
# everywhere else.
skills/atomicnebula-email/scripts/an-email.sh mailboxes

# ── READ ───────────────────────────────────────────────────────────────────
skills/atomicnebula-email/scripts/an-email.sh search "invoice from Acme"
skills/atomicnebula-email/scripts/an-email.sh search --from "billing@acme.com" --has-attachments
skills/atomicnebula-email/scripts/an-email.sh list --mailbox james@company.com --limit 25
skills/atomicnebula-email/scripts/an-email.sh get <emailId>
skills/atomicnebula-email/scripts/an-email.sh content <emailId>
skills/atomicnebula-email/scripts/an-email.sh thread <conversationId>
skills/atomicnebula-email/scripts/an-email.sh unread

# ── SEND / REPLY / FORWARD ─────────────────────────────────────────────────
skills/atomicnebula-email/scripts/an-email.sh send --mailbox you@co.com --to alice@co.com --subject "Hi" --body "Hello"
skills/atomicnebula-email/scripts/an-email.sh reply <emailId> --mailbox you@co.com --body "Thanks!"
skills/atomicnebula-email/scripts/an-email.sh forward <emailId> --mailbox you@co.com --to bob@co.com --body "FYI"

# Multiple recipients use ';' (semicolon) as separator — comma is unsafe
# because email display names like "Cook, James" legitimately contain commas.
skills/atomicnebula-email/scripts/an-email.sh send --mailbox you@co.com \
  --to "alice@co.com;bob@co.com" --cc "manager@co.com" \
  --subject "Heads up" --body "Hello"

# ── DRAFTS (synced to provider + AN deep-link) ─────────────────────────────
skills/atomicnebula-email/scripts/an-email.sh draft create --mailbox you@co.com --to alice@co.com --subject "Proposal" --body "<p>Hi Alice…</p>" --body-type html
skills/atomicnebula-email/scripts/an-email.sh draft reply <emailId> --mailbox you@co.com --body "Thanks for the update — here's my response…"
skills/atomicnebula-email/scripts/an-email.sh draft forward <emailId> --mailbox you@co.com --to bob@co.com --body "FYI"
skills/atomicnebula-email/scripts/an-email.sh draft list
skills/atomicnebula-email/scripts/an-email.sh draft get <draftId>
skills/atomicnebula-email/scripts/an-email.sh draft update <draftId> --subject "Updated subject"
skills/atomicnebula-email/scripts/an-email.sh draft send <draftId>
skills/atomicnebula-email/scripts/an-email.sh draft delete <draftId>

# ── MAILBOX OPERATIONS ─────────────────────────────────────────────────────
skills/atomicnebula-email/scripts/an-email.sh mark-read <emailId>
skills/atomicnebula-email/scripts/an-email.sh mark-unread <emailId>
skills/atomicnebula-email/scripts/an-email.sh flag <emailId> --flag flagged   # or notFlagged | complete
skills/atomicnebula-email/scripts/an-email.sh delete <emailId>
skills/atomicnebula-email/scripts/an-email.sh delete-thread <conversationId>
skills/atomicnebula-email/scripts/an-email.sh promote-contact <emailId> --first-name "Jane" --last-name "Doe"
```

## Drafts

Drafts are the headline addition. When you create a draft via this skill:

1. AN persists the draft locally (table `an_email_drafts`) and schedules an async sync to the user's Outlook (Microsoft Graph) or Gmail Drafts folder.
2. **The skill script auto-polls** the draft after the create call until `syncStatus` reaches `synced` or `failed`, so the JSON the assistant sees on stdout reflects the real provider outcome — not an optimistic "pending". On `failed` the script exits non-zero and prints `syncError` to stderr.
3. If the supplied `mailboxAddress` isn't connected at all (no Convex `core_integration_oauth_resources` row), the create call returns `400 MAILBOX_NOT_CONNECTED` immediately — call `GET /api/v1/atomicnebula/mailboxes` to discover valid addresses and retry.
4. On success, the response includes:
   - `draftId` — AN's local identifier.
   - `appLink` — deep-link the user can open on **desktop or mobile** (`https://app.atomicnebula.com/workspace/{tenantId}/email/drafts/{draftId}`). The web app is responsive and the desktop Tauri build loads the same URL.
   - `syncStatus` — `synced` once the provider confirms. The skill script blocks until this is reached.
   - `providerDraftId` and `providerWebLink` — populated once synced.
   - `syncError` — populated when the provider rejects the draft for a non-discovery reason (the local draft is preserved so the user can fix and retry).

### Draft as reply

When a user asks an assistant to "draft a reply for me," call `draft reply <originalEmailId>` rather than `reply`. This produces a draft in the user's Drafts folder and a clickable AN link, but does **not** send. The user clicks the link, reviews, and sends.

```bash
skills/atomicnebula-email/scripts/an-email.sh draft reply 9f3e1c7a... \
  --mailbox james@company.com \
  --body "<p>Hi Sarah,</p><p>Thanks for the brief. A few questions:</p><ul><li>…</li></ul>"
# Script auto-polls until syncStatus is terminal. Returns (typical success):
# {
#   "data": {
#     "id": "...",
#     "syncStatus": "synced",
#     "appLink": "https://app.atomicnebula.com/workspace/{tenantId}/email/drafts/{draftId}",
#     "providerDraftId": "AAMkAD...",
#     "providerWebLink": "https://outlook.office.com/mail/drafts/id/..."
#   }
# }
```

The user then receives both the AN deep-link (where they can edit and send from Atomic Nebula) **and** sees the draft in their Outlook/Gmail Drafts folder (where they can also edit and send).

### Provider support

| Provider | Status |
|---|---|
| Microsoft Exchange / Outlook (via Microsoft Graph) | ✅ Fully implemented |
| Gmail | ✅ Fully implemented (drafts appear in Gmail's Drafts folder; `providerWebLink` opens the draft directly in the Gmail web UI) |
| IMAP | ❌ Not yet supported. |

## Email IDs (`<emailId>`)

> **Use the `id` field from search/list/get responses for every endpoint that takes `<emailId>`. Do not pass `exchangeId`, `gmailId`, or `internetMessageId`.**

Every email object the API returns exposes several identifiers. Only `id` is canonical for Atomic Nebula endpoints — the others are provider-side identifiers exposed for cross-system reference, not as routing keys for AN.

| Field | Format | Use it for |
|---|---|---|
| `id` | UUID — `9f3e1c7a-1a4b-4c2e-9f01-b0c1d2e3f4a5` | ✅ **All AN endpoints.** This is what `<emailId>` means in every URL path. |
| `exchangeId` | Microsoft Graph immutable ID — long base64 string starting with `AQMk`, `AAMk`, or `AAAk` | Direct Microsoft Graph queries only. Do **not** pass to AN. |
| `gmailId` | Gmail message ID — short hex string (≈16 chars) | Direct Gmail API queries only. Do **not** pass to AN. |
| `internetMessageId` | RFC 2822 — `<abc@example.com>` | Threading / references. Not routable. |

Search results, list results, and `GET /emails/:id` responses all include `id`. If a fresh search returns an item with no `id`, that email has not yet been ingested into Atomic Nebula — wait a few seconds, search again, then proceed.

### What you'll see if you get this wrong

If you call (e.g.) `POST /emails/AQMkAD…/draft-reply`, the response is HTTP 404 with this shape — **read the `details.hint` and re-fetch via search/list to obtain the correct `id`**:

```json
{
  "success": false,
  "error": {
    "code": "EMAIL_ID_FORMAT_MISMATCH",
    "message": "Email 'AQMkAD…' was not found for this tenant. This looks like a Microsoft Graph immutable ID (`exchangeId`). Atomic Nebula write endpoints expect the canonical `id` field …",
    "details": {
      "providedId": "AQMkAD…",
      "providedIdLikelyType": "graph_immutable",
      "expectedField": "id",
      "operation": "draft reply",
      "hint": "Search/list responses include both `id` (canonical, AN UUID) and provider IDs (`exchangeId`, `gmailId`). Use `id` for every endpoint where the URL contains `<emailId>`.",
      "recoveryEndpoints": [
        { "method": "GET", "path": "/api/v1/atomicnebula/emails", "description": "List emails (returns `id`)" },
        { "method": "POST", "path": "/api/v1/atomicnebula/emails/search", "description": "Provider-native search (returns `id` once ingested)" }
      ]
    }
  }
}
```

A genuine miss (the `id` is correctly formatted but the email no longer exists or was never ingested) returns the same shape with `code: "EMAIL_NOT_FOUND"` and `providedIdLikelyType: "an_uuid"` — in that case, re-fetching usually won't help.

## API Reference

Endpoints are under `https://convex-actions.circeaura.com/api/v1/atomicnebula/`. Most live under `/emails/`; mailbox discovery is the one sibling endpoint.

### Mailbox discovery

| Method | Path | Description |
|---|---|---|
| GET | `/mailboxes` | List the connected mailbox addresses the authenticated user can act on |

Response shape:

```json
{
  "success": true,
  "data": {
    "mailboxes": [
      {
        "address": "james@company.com",
        "name": "James Cook",
        "provider": "exchange",
        "isPrimary": true,
        "isActive": true,
        "syncEnabled": true,
        "isDelegated": false,
        "canSendAs": true
      }
    ]
  }
}
```

Always use the returned `address` value verbatim as `mailboxAddress` in send/reply/forward/draft calls. Other addresses (aliases, "send-as" addresses surfaced by the provider but never connected to AN) are rejected with `MAILBOX_NOT_CONNECTED`.

### Read

| Method | Path | Body / Params | Description |
|---|---|---|---|
| GET | `/emails` | query: `mailboxAddress`, `folderId`, `contactId`, `dealId`, `isRead`, `importance`, `hasAttachments`, `search`, `limit`, `cursor` | List emails with filters |
| GET | `/emails/:id` | — | Get single email metadata |
| GET | `/emails/:id/content` | — | Get full email body (resolved from blob storage) |
| GET | `/emails/thread/:conversationId` | query: `mailboxAddress`, `limit` | Get conversation thread |
| GET | `/emails/unread` | query: `folderId`, `mailboxAddress` | Unread count |
| POST | `/emails/search` | `{query, from, to, hasAttachments, after, before, mailboxAddress, limit}` | Provider-native deep search across all mailboxes |

### Write

| Method | Path | Body | Description |
|---|---|---|---|
| POST | `/emails/send` | `{mailboxAddress, to, cc?, bcc?, subject, body, bodyType?, importance?, attachmentIds?, contactId?, dealId?}` | Queue a new email to send |
| POST | `/emails/:id/reply` | `{mailboxAddress, body, bodyType?, replyAll?, attachmentIds?}` | Queue a reply |
| POST | `/emails/:id/forward` | `{mailboxAddress, to, cc?, body?, attachmentIds?}` | Queue a forward |
| POST | `/emails/:id/read` | `{isRead: boolean}` | Mark read/unread |
| POST | `/emails/:id/flag` | `{flag: "notFlagged"\|"flagged"\|"complete"}` | Set flag |
| DELETE | `/emails/:id` | — | Soft-delete |
| DELETE | `/emails/thread/:conversationId` | query: `mailboxAddress?` | Soft-delete entire thread |
| POST | `/emails/:id/promote-contact` | `{contactEmail?, firstName?, lastName?, primaryCompanyId?, jobTitle?, phone?, source?}` | Create CRM contact from sender |

### Drafts

| Method | Path | Body | Description |
|---|---|---|---|
| POST | `/emails/draft` | `{mailboxAddress, to?, cc?, bcc?, subject?, body?, bodyType?, contactId?, dealId?, attachmentIds?}` | Create new draft. Returns immediately with `syncStatus: "pending"`. Skill script auto-polls. `400 MAILBOX_NOT_CONNECTED` when no oauth resource exists for the mailbox. |
| POST | `/emails/:id/draft-reply` | `{mailboxAddress, body?, bodyType?, replyAll?, attachmentIds?}` | Create draft reply. Same async contract as `/emails/draft`. |
| POST | `/emails/:id/draft-forward` | `{mailboxAddress, to?, cc?, body?, bodyType?, attachmentIds?}` | Create draft forward. Same async contract as `/emails/draft`. |
| GET | `/emails/drafts` | query: `limit?` | List the authenticated user's drafts |
| GET | `/emails/drafts/:draftId` | — | Get draft (poll until `syncStatus` is `synced` or `failed`) |
| PATCH | `/emails/drafts/:draftId` | `{subject?, body?, bodyType?, to?, cc?, bcc?}` | Update draft (re-syncs to provider) |
| DELETE | `/emails/drafts/:draftId` | — | Delete draft locally + on provider |
| POST | `/emails/drafts/:draftId/send` | — | Dispatch a synced draft via provider |

## Assistant approval gate

All **write** operations (`emails:write` permission) are gated by Atomic Nebula's
assistant-approval system. The first time an API-keyed assistant calls a write
endpoint (send, reply, forward, mark-read, flag, delete, draft-create, etc.),
the response is **HTTP 403** with code `APPROVAL_REQUIRED` and an
`approvalUrl` the user must click to authorise.

Sample response:

```json
{
  "success": false,
  "error": {
    "code": "APPROVAL_REQUIRED",
    "message": "Human approval is required for this assistant action",
    "details": {
      "challengeId": "<uuid>",
      "actionType": "write",
      "operationKey": "emails.draftReply",
      "requiredPermission": "atomicnebula:emails:write",
      "approvalUrl": "https://app.atomicnebula.com/a/<challengeId>"
    }
  }
}
```

After the user clicks the approval URL and confirms, the assistant retries the
same call and the action proceeds. Read operations (`emails:read`) are not
gated.

The `approvalUrl` host varies per environment (resolved server-side from the
Atomic Nebula product domain table) — `dev.atomicnebula.com` on dev, the staging
host on staging, `app.atomicnebula.com` on production. Always present the URL
verbatim; do not rewrite the host.

## Send semantics

`POST /emails/send`, `/emails/:id/reply`, and `/emails/:id/forward` are **queued** (HTTP 202). They return:

```json
{
  "queued": true,
  "queueId": "<uuid>",
  "status": "pending",
  "resolvedSenderIdentityAddress": "james@company.com",
  "resolvedSenderIdentitySource": "user_default",
  "fallbackReason": null
}
```

The Convex outbound queue dispatches the email asynchronously with retry/backoff. If you need to confirm it actually went out, query the email by `mailboxAddress` and look for the new sent item, or watch the AN inbox UI.

`POST /emails/drafts/:draftId/send` is also async — the provider draft is dispatched server-side.

Draft bodies default to HTML when `bodyType` is omitted. Pass `--body-type text` only when the body should be treated as literal plain text.

## Error responses

```json
{ "error": { "code": "AUTHORIZATION_DENIED", "message": "API key does not have permission: atomicnebula:emails:write" } }
```

Common codes:
- `400` — bad request, missing field
- `400 MAILBOX_NOT_CONNECTED` — the supplied `mailboxAddress` is not a mailbox AN syncs for this user. Call `GET /api/v1/atomicnebula/mailboxes` to discover valid `address` values, then retry with one of them. The error `details.triedAddress` echoes back what you sent so you can correlate logs; `details.discoveryEndpoint` names the discovery route.
- `401` — missing/invalid API key
- `403` — wrong permission scope
- `404` — email or draft not found
- `409 DRAFT_NOT_SYNCED` — tried to send a draft before provider sync completed (poll `GET /emails/drafts/:draftId` first)
- `409 DUPLICATE_EMAIL` — promote-contact found existing contact with same email
- `429` — rate limited (mailbox-level; back off)
- `500` — internal error

### `MAILBOX_NOT_CONNECTED` example

A draft / send / reply / forward call where `mailboxAddress` does not match a mailbox AN currently syncs for the user returns:

```json
{
  "success": false,
  "error": {
    "code": "MAILBOX_NOT_CONNECTED",
    "message": "Mailbox 'james.cook@spidergroup.com' is not connected to Atomic Nebula. Call GET /api/v1/atomicnebula/mailboxes to discover the addresses you can use, then retry with one of the returned 'address' values as 'mailboxAddress'.",
    "details": {
      "triedAddress": "james.cook@spidergroup.com",
      "discoveryEndpoint": {
        "method": "GET",
        "path": "/api/v1/atomicnebula/mailboxes"
      }
    }
  }
}
```

Recovery flow for an assistant: call `GET /api/v1/atomicnebula/mailboxes` (or `skills/atomicnebula-email/scripts/an-email.sh mailboxes`), pick a row whose `address` matches what the user asked for (or whose `isPrimary` is `true` if the user did not specify), and retry the original call with that `address` as `mailboxAddress`.

## Curl examples

### Create a draft reply

```bash
curl -s -X POST \
  -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "mailboxAddress": "james@company.com",
    "body": "<p>Hi Sarah, thanks for the brief — here are my thoughts...</p>",
    "bodyType": "html",
    "replyAll": false
  }' \
  "https://convex-actions.circeaura.com/api/v1/atomicnebula/emails/9f3e1c7a-.../draft-reply" | jq .
```

### Poll until provider sync completes

The skill script's `draft create` / `draft reply` / `draft forward` commands
already auto-poll and only print the final terminal state, so you don't
need to do this yourself. If you call the HTTP endpoint directly via
curl, this is the loop:

```bash
DRAFT_ID="..."
while true; do
  STATUS=$(curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
    "https://convex-actions.circeaura.com/api/v1/atomicnebula/emails/drafts/$DRAFT_ID" \
    | jq -r '.data.syncStatus')
  echo "syncStatus=$STATUS"
  [ "$STATUS" = "synced" ] || [ "$STATUS" = "failed" ] && break
  sleep 1
done
```

### Send a previously-created draft

```bash
curl -s -X POST \
  -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "https://convex-actions.circeaura.com/api/v1/atomicnebula/emails/drafts/$DRAFT_ID/send" | jq .
```

## How search works

Search hits `POST /emails/search` and proxies to provider-native full-text search:
- **Exchange**: `$search` (KQL) across subject/body/sender/recipients via `/users/{email}/messages`. Supports `from`/`to`/`hasAttachments`/`after`/`before`.
- **Gmail**: maps to the `q` parameter with operators (`from:`, `to:`, `has:attachment`, `after:`, `before:`).

Results across mailboxes are returned in parallel; per-mailbox failures (e.g. expired tokens) are returned in `metadata.errors` without failing the whole call. See `convex/products/atomicnebula/email/mailbox/search.ts` for full provider mapping.

## Limitations

- Search results capped at 50 across all mailboxes
- Send and draft-send are queued (not synchronous) — confirm via UI/polling
- IMAP drafts not implemented
- Attachments must already exist in AN attachment storage; pass `attachmentIds`
- The `appLink` route requires the AN web app — the desktop Tauri build loads the same URL

## Implementation pointers

For engineers extending this skill:
- HTTP routes: `convex/platform/api/http/emails.ts` + `emails.operations.ts`
- Convex draft sync: `convex/products/atomicnebula/email/mailbox/draftSync.ts`
- Convex outbound queue (send/reply/forward): `convex/products/atomicnebula/email/mailbox/outboundQueue.ts`
- Microsoft Graph draft client: `api/src/integrations/microsoft/graph-client-email.ts` (search for `createDraft`, `createReplyDraft`, `createForwardDraft`)
- Microsoft Graph S2S handlers: `api/src/s2s/v1/email/email.handlers.ts` + `email.http.ts`
- Gmail draft service: `api/src/integrations/email/providers/gmail/gmail-drafts.service.ts`
- Gmail draft S2S handlers: `api/src/s2s/v1/integrations/gmail-drafts.handlers.ts` + `integrations.http.ts`
- Schema: `convex/schema/email.ts` — `an_email_drafts` table
- Frontend draft route: `apps/web/src/experiences/atomicnebula/routes/app/workspace/email/drafts/[draftId]/`
