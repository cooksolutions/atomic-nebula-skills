---
name: atomicnebula-notebook
description: "Read and manage Atomic Nebula notebook items over the external REST API. Use when a user wants to list notebook items, inspect a notebook item, read or update markdown, create a new notebook item, or link a notebook item to a contact, company, deal, or lead. Supports --env <workspace> to target a specific workspace."
metadata:
  {
    "openclaw":
      {
        "emoji": "📓",
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

# Atomic Nebula Notebook Skill

Use the Atomic Nebula notebook REST API through the shared assistant capability layer. This skill treats notebook items (backed by `an_content_items` rows) as the public resource model and exposes document-backed markdown access through notebook-item subroutes.

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

- `GET /api/v1/atomicnebula/notebook/items`
- `POST /api/v1/atomicnebula/notebook/items`
- `GET /api/v1/atomicnebula/notebook/items/:id`
- `PATCH /api/v1/atomicnebula/notebook/items/:id`
- `GET /api/v1/atomicnebula/notebook/items/:id/markdown`
- `PUT /api/v1/atomicnebula/notebook/items/:id/markdown`
- `POST /api/v1/atomicnebula/notebook/items/:id/entity-links`

## Helper Script

```bash
# List notebook items
skills/atomicnebula-notebook/scripts/an-notebook.sh list --type content_idea --page 1 --page-size 20

# Get one notebook item
skills/atomicnebula-notebook/scripts/an-notebook.sh get NOTEBOOK-ID

# Read markdown
skills/atomicnebula-notebook/scripts/an-notebook.sh markdown NOTEBOOK-ID

# Create a bodyless idea
skills/atomicnebula-notebook/scripts/an-notebook.sh create --title "March social idea" --content-type content_idea

# Create a document-backed item from markdown
skills/atomicnebula-notebook/scripts/an-notebook.sh create --title "Launch memo" --markdown-file ./memo.md

# Update metadata
skills/atomicnebula-notebook/scripts/an-notebook.sh update NOTEBOOK-ID --title "Updated title" --status archived --tag launch

# Replace markdown
skills/atomicnebula-notebook/scripts/an-notebook.sh set-markdown NOTEBOOK-ID --file ./updated.md --expected-version 3 --conflict-strategy reject

# Link to a CRM entity
skills/atomicnebula-notebook/scripts/an-notebook.sh link-entity NOTEBOOK-ID --entity-type contact --entity-id CONTACT-ID
```

## Common Filters

`list` supports:

- `--type <contentType>`
- `--status <status>`
- `--owner-id <userId>`
- `--stage-id <stageId>`
- `--search <term>`
- `--page <n>`
- `--page-size <n>`
- `--sort-by <title|createdAt|updatedAt|status|contentType>`
- `--sort-order <asc|desc>`

## Write Behavior

Write operations can trigger approval if the workspace uses assistant keys with approval gates enabled. The script sends `X-Run-Id` and records approval challenges so webhook correlation still works.

## Permissions

- Read: `atomicnebula:content:read`
- Write: `atomicnebula:content:write`

The stored permission strings are intentionally retained as `atomicnebula:content:*` to keep deployed role grants stable across the rename. User-facing labels and the API surface are Notebook.

## Notes

- Markdown routes only work for document-backed notebook items.
- Bodyless creates are currently limited to allowlisted notebook content types such as `content_idea`.
- Markdown write conflict handling supports `overwrite` and `reject`.
