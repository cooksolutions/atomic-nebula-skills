---
name: atomicnebula-contacts
description: "Read and manage Atomic Nebula contacts through the assistant REST API. Use when a user wants to list contacts, inspect a contact, create a contact, update contact details, or delete a contact. Supports --env <workspace> to target a configured workspace."
metadata:
  {
    "openclaw":
      {
        "emoji": "👤",
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

# Contacts

Use the Atomic Nebula contacts REST API through the shared assistant workspace config.

## Configuration

Credentials resolve in this order:

1. Environment variables such as `ATOMICNEBULA_API_KEY` and `ATOMICNEBULA_BASE_URL`
2. `~/.config/circeaura/assistant-workspaces.json`
3. Legacy `~/.openclaw/openclaw.json`

Use `--env <workspace>` to target a configured workspace.

## Helper Script

Run from the repository root:

```bash
skills/atomicnebula-contacts/scripts/an-contacts.sh list
skills/atomicnebula-contacts/scripts/an-contacts.sh --env dev list --search "Jane"
skills/atomicnebula-contacts/scripts/an-contacts.sh get <contactId>
skills/atomicnebula-contacts/scripts/an-contacts.sh create --email jane@example.com --first-name Jane --confirm yes
skills/atomicnebula-contacts/scripts/an-contacts.sh update <contactId> --job-title "Operations Lead" --confirm yes
```

## Commands

- `list`: List contacts. Options: `--search`, `--page`, `--page-size`.
- `get <contactId>`: Fetch one contact.
- `create`: Create a contact. Requires `--email` and `--confirm yes`.
- `update <contactId>`: Update contact fields. Requires `--confirm yes`.
- `delete <contactId>`: Delete a contact. Requires `--confirm yes`.

Prefer `atomicnebula-context` for person-centered operational context when a contact ID is already known. Use this skill when the user needs raw contact records or contact writes.

## Contact IDs (`<contactId>`)

> **Use the `id` field from list/get responses for every endpoint that takes `<contactId>`. Do not pass HubSpot, Salesforce, or other upstream identifiers — Atomic Nebula only routes its own canonical UUID.**

Every contact object the API returns exposes a single canonical identifier. Foreign-system IDs (HubSpot record IDs, Salesforce IDs, mailing-list rows) may appear inside `metadata.integrations.*` for cross-system reference, but they are NOT valid `<contactId>` path segments.

| Field | Format | Use it for |
|---|---|---|
| `id` | UUID — `9f3e1c7a-1a4b-4c2e-9f01-b0c1d2e3f4a5` | ✅ **All AN endpoints.** This is what `<contactId>` means in every URL path. |
| `metadata.integrations.<source>.recordId` | Provider-side identifier | Direct provider API queries only. Do **not** pass to AN. |
| `email` | Email address | Filtering with `?search=<email>` on the list endpoint. Not a routable ID. |

List results, search results (`GET /contacts?search=…`), and `GET /contacts/:id` responses all include `id`. If you only have an email address, call `GET /api/v1/atomicnebula/contacts?search=<email>` and read the `id` from the matching record before calling get/update/delete.

### What you'll see if you get this wrong

A wrong-format ID returns HTTP 404 with this shape — **read `details.hint` and re-fetch via the list endpoint**:

```json
{
  "success": false,
  "error": {
    "code": "CONTACT_ID_FORMAT_MISMATCH",
    "message": "Contact 'AQMkAD…' was not found for this tenant. This looks like a Microsoft Graph immutable ID (`exchangeId`). Atomic Nebula write endpoints expect the canonical `id` field …",
    "details": {
      "providedId": "AQMkAD…",
      "providedIdLikelyType": "graph_immutable",
      "expectedField": "id",
      "operation": "get contact",
      "hint": "Search/list responses include both `id` (canonical, AN UUID) and provider IDs … Use `id` for every endpoint where the URL contains the contact ID.",
      "recoveryEndpoints": [
        { "method": "GET", "path": "/api/v1/atomicnebula/contacts", "description": "List contacts (returns `id`; supports `?search=`)" }
      ]
    }
  }
}
```

A genuine miss (the `id` is correctly formatted but the contact no longer exists) returns the same shape with `code: "CONTACT_NOT_FOUND"` and `providedIdLikelyType: "an_uuid"` — in that case, re-fetching by the same id won't help. Try the list endpoint with `?search=<emailOrName>` to find the live record.

> **Note**: There is no `POST /contacts/search` endpoint; the list route's `?search=` query parameter is the recovery path.
