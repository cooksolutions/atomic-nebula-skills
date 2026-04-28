---
name: atomicnebula-content
description: "Read and manage Atomic Nebula content items over the external REST API. Use when a user wants to list content, inspect a content item, read or update markdown, create a new content item, or link content to a contact, company, deal, or lead. Supports --env <workspace> to target a specific workspace."
metadata:
  {
    "openclaw":
      {
        "emoji": "📝",
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

# Atomic Nebula Content Skill

Use the Atomic Nebula content REST API through the shared assistant capability layer. This skill treats `an_content_items` as the public resource model and exposes document-backed markdown access through content-item subroutes.

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

- `GET /api/v1/atomicnebula/content/items`
- `POST /api/v1/atomicnebula/content/items`
- `GET /api/v1/atomicnebula/content/items/:id`
- `PATCH /api/v1/atomicnebula/content/items/:id`
- `GET /api/v1/atomicnebula/content/items/:id/markdown`
- `PUT /api/v1/atomicnebula/content/items/:id/markdown`
- `POST /api/v1/atomicnebula/content/items/:id/entity-links`

## Helper Script

```bash
# List content items
skills/atomicnebula-content/scripts/an-content.sh list --type content_idea --page 1 --page-size 20

# Get one content item
skills/atomicnebula-content/scripts/an-content.sh get CONTENT-ID

# Read markdown
skills/atomicnebula-content/scripts/an-content.sh markdown CONTENT-ID

# Create a bodyless idea
skills/atomicnebula-content/scripts/an-content.sh create --title "March social idea" --content-type content_idea

# Create a document-backed item from markdown
skills/atomicnebula-content/scripts/an-content.sh create --title "Launch memo" --markdown-file ./memo.md

# Update metadata
skills/atomicnebula-content/scripts/an-content.sh update CONTENT-ID --title "Updated title" --status archived --tag launch

# Replace markdown
skills/atomicnebula-content/scripts/an-content.sh set-markdown CONTENT-ID --file ./updated.md --expected-version 3 --conflict-strategy reject

# Link to a CRM entity
skills/atomicnebula-content/scripts/an-content.sh link-entity CONTENT-ID --entity-type contact --entity-id CONTACT-ID
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

## Notes

- Markdown routes only work for document-backed content items.
- Bodyless creates are currently limited to allowlisted content types such as `content_idea`.
- Markdown write conflict handling supports `overwrite` and `reject`.
