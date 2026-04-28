---
name: atomicnebula-attachments
description: "Manage Atomic Nebula entity attachments with upload/list/download/link/unlink operations. Use when a user wants to attach files to tasks or any supported object, fetch attachment lists, or generate download URLs. Write operations are approval-gated and correlated with X-Run-Id. Use --env dev to target development."
metadata:
  {
    "openclaw":
      {
        "emoji": "📎",
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

# Atomic Nebula Attachments Skill

Manage attachments for Atomic Nebula entities through the generic attachments API.

## Configuration

Credentials resolve in this order:

1. Environment variables such as `ATOMICNEBULA_API_KEY` and `ATOMICNEBULA_BASE_URL`
2. `~/.config/circeaura/assistant-workspaces.json`
3. Legacy `~/.openclaw/openclaw.json`

Use `--env <workspace>` to target a configured workspace. Run `skills/shared/an-env-list.sh` to inspect configured workspaces.

## Supported Operations

- `list`
- `upload` (create upload session, upload bytes to SAS URL, confirm)
- `download-url`
- `link`
- `unlink`

All write operations include `X-Run-Id` correlation and participate in approval-gated assistant workflows.

## Helper Script

```bash
# List task attachments
skills/atomicnebula-attachments/scripts/an-attachments.sh list --entity-type task --entity-id TASK-123

# Upload a local file to a task
skills/atomicnebula-attachments/scripts/an-attachments.sh upload --entity-type task --entity-id TASK-123 --file ./proposal.pdf

# Get a signed download URL
skills/atomicnebula-attachments/scripts/an-attachments.sh download-url ATTACHMENT-ID --entity-type task --entity-id TASK-123

# Link an existing attachment to a deal
skills/atomicnebula-attachments/scripts/an-attachments.sh link ATTACHMENT-ID --entity-type deal --entity-id DEAL-42 --relationship reference

# Unlink and hard-delete if orphaned
skills/atomicnebula-attachments/scripts/an-attachments.sh unlink ATTACHMENT-ID --entity-type task --entity-id TASK-123 --hard-delete-if-orphan true
```

## API Endpoints

Base path: `/api/v1/atomicnebula/attachments`

- `POST /upload-url`
- `POST /:attachmentId/confirm`
- `GET /?entityType=...&entityId=...`
- `POST /:attachmentId/download-url`
- `POST /:attachmentId/link`
- `DELETE /:attachmentId/link`

## Task + Files Workflow

When a user asks to "create a task with files", do this in order:

1. Create the task (`atomicnebula-task-write`).
2. Upload files to that task (`atomicnebula-attachments upload --entity-type task --entity-id <taskId>`).
3. Confirm with `list` that attachments are present.

## Common Errors

- `UNSUPPORTED_ENTITY_TYPE`
- `ENTITY_NOT_FOUND`
- `ATTACHMENT_TOO_LARGE`
- `ATTACHMENT_EXTENSION_BLOCKED`
- `ENTITY_ATTACHMENT_LIMIT_REACHED`
- `APPROVAL_REQUIRED`
