---
name: atomicnebula-companies
description: "Read and manage Atomic Nebula companies through the assistant REST API. Use when a user wants to list companies, inspect a company, create a company, update company details, or delete a company. Supports --env <workspace> to target a configured workspace."
metadata:
  {
    "openclaw":
      {
        "emoji": "🏢",
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

# Companies

Use the Atomic Nebula companies REST API through the shared assistant workspace config.

## Configuration

Credentials resolve in this order:

1. Environment variables such as `ATOMICNEBULA_API_KEY` and `ATOMICNEBULA_BASE_URL`
2. `~/.config/circeaura/assistant-workspaces.json`
3. Legacy `~/.openclaw/openclaw.json`

Use `--env <workspace>` to target a configured workspace.

## Helper Script

Run from the repository root:

```bash
skills/atomicnebula-companies/scripts/an-companies.sh list
skills/atomicnebula-companies/scripts/an-companies.sh --env dev list --search "Acme"
skills/atomicnebula-companies/scripts/an-companies.sh get <companyId>
skills/atomicnebula-companies/scripts/an-companies.sh create --name "Acme Ltd" --domain acme.com --confirm yes
skills/atomicnebula-companies/scripts/an-companies.sh update <companyId> --industry "Manufacturing" --confirm yes
skills/atomicnebula-companies/scripts/an-companies.sh delete <companyId> --confirm yes
```

## Commands

- `list`: List companies. Options: `--search`, `--limit`, `--cursor`.
- `get <companyId>`: Fetch one company.
- `create`: Create a company. Requires `--name` and `--confirm yes`.
- `update <companyId>`: Update company fields. Requires `--confirm yes`.
- `delete <companyId>`: Delete a company. Requires `--confirm yes`.

## Company IDs (`<companyId>`)

> **Use the `id` field from list/get responses for every endpoint that takes `<companyId>`. Do not pass HubSpot, Xero, Salesforce, or other upstream identifiers — Atomic Nebula only routes its own canonical UUID.**

Every company object the API returns exposes a single canonical identifier. Foreign-system IDs (HubSpot record IDs, Xero ContactIDs, mailing-list rows) may appear inside `metadata.integrations.*` for cross-system reference, but they are NOT valid `<companyId>` path segments.

| Field | Format | Use it for |
|---|---|---|
| `id` | UUID — `9f3e1c7a-1a4b-4c2e-9f01-b0c1d2e3f4a5` | ✅ **All AN endpoints.** This is what `<companyId>` means in every URL path. |
| `metadata.integrations.<source>.recordId` | Provider-side identifier | Direct provider API queries only. Do **not** pass to AN. |
| `domain` | Domain string | Filtering with `?search=<domain>` on the list endpoint. Not a routable ID. |

If you only have a domain or name, call `GET /api/v1/atomicnebula/companies?search=<term>` and read the `id` from the matching record before calling get/update/delete.

## Write Fields

Create accepts:

- `--name` (required)
- `--domain`
- `--website`
- `--phone`
- `--email`
- `--industry`
- `--city`
- `--state`
- `--country`
- `--tag <value>` (repeatable to set multiple tags)

Update accepts the same fields plus omits `--name` requirement; only the fields you pass are changed.

## Permissions

- `atomicnebula:companies:read`
- `atomicnebula:companies:write` (create / update / delete)
