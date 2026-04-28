# OpenClaw Skills for CirceAura

OpenClaw skills for CirceAura products. Shared-capable skills are canonical in `/skills`; `openclaw-skills/` is the OpenClaw consumer view plus the home for OpenClaw-only skills and packaging artifacts deployed to Lumen.

Atomic Nebula capabilities are no longer OpenClaw-owned. They are shared assistant capabilities for Codex, Claude Code, OpenClaw, and future MCP clients. The skill IDs stay product-prefixed, while consumer labels should stay short: `atomicnebula-contacts` displays as `Contacts`, `atomicnebula-context` displays as `Context Graph`, and so on.

## Skills

| Skill ID | Display Name | Description |
|----------|--------------|-------------|
| `atomicnebula-context` | Context Graph | Graph-first operational context for people, threads, deals, projects, and bridges |
| `atomicnebula-capture` | Capture | Save durable assistant decisions, preferences, corrections, implementation notes, and session summaries |
| `atomicnebula-contacts` | Contacts | List, inspect, create, update, and delete Atomic Nebula contacts |
| `atomicnebula-tasks` | Tasks | Query tasks, projects, subtasks, and comments |
| `atomicnebula-task-write` | Task Write | Create, update, and complete tasks with existing write gates |
| `atomicnebula-projects` | Projects | List, create, update, archive, and inspect project schemas and types |
| `atomicnebula-leads` | Leads | List, inspect, create, update, and delete leads |
| `atomicnebula-email` | Email | Search, read, draft, send, reply, forward, and manage mailbox items |
| `atomicnebula-calendar` | Calendar | Query meetings/events, inspect targets, and create/update/delete appointments |
| `atomicnebula-teams` | Teams | List user-scoped Teams chats/messages and reply in existing conversations |
| `atomicnebula-attention` | Attention | Query focus queue and priorities |
| `atomicnebula-digest` | Digest | Daily briefing, reminders due, and reminder dedupe acknowledgment |
| `atomicnebula-attachments` | Attachments | Upload, list, download, link, and unlink entity attachments |
| `atomicnebula-content` | Content | List, inspect, create, update, and link content items |
| `atomicnebula-forms` | Forms | Create, update, publish, inspect, and query forms and submissions |

## Source Of Truth

- `skills/` is the canonical source of truth for shared-capable skills.
- `openclaw-skills/` contains:
  - symlinks for shared OpenClaw-visible skills
  - real directories for OpenClaw-only skills
  - legacy `.skill` archives and deployment helpers
- Shared operational skills such as `axiom-investigation`, `pulse-debugging`, and `sentry-triage` are exposed here through that symlink view; they are not packaged as OpenClaw-only `.skill` archives.
- `./scripts/deploy-openclaw.sh --skills` derives shared OpenClaw-visible skills from `skills/registry.json`, then combines them with the OpenClaw-only directories in `openclaw-skills/`.
- When you change a shared skill, update it in `skills/`, then run:

```bash
bun run skills:sync
bun run skills:validate
```

## Deployment

### Option 1: Deploy from the shared skill registry

```bash
# From the repo root — deploy skills only
./scripts/deploy-openclaw.sh --skills

# Dry run (show what would happen)
./scripts/deploy-openclaw.sh --skills --dry-run

# Check what's currently deployed
./scripts/deploy-openclaw.sh --status
```

### Option 2: Install from legacy .skill file

1. Copy the `.skill` files to the target machine (Lumen VM)
2. Unzip to the OpenClaw workspace skills directory:

```bash
# On Lumen VM
cd ~/.openclaw/workspace/skills/
unzip /path/to/atomicnebula-tasks.skill
unzip /path/to/atomicnebula-calendar.skill
unzip /path/to/atomicnebula-teams.skill
unzip /path/to/atomicnebula-task-write.skill
unzip /path/to/atomicnebula-attention.skill
unzip /path/to/atomicnebula-attachments.skill
unzip /path/to/atomicnebula-content.skill
unzip /path/to/atomicnebula-forms.skill
unzip /path/to/atomicnebula-leads.skill
unzip /path/to/atomicnebula-projects.skill
unzip /path/to/atomicnebula-digest.skill
```

3. Verify the skills are registered:

```bash
openclaw skills list | grep atomicnebula
```

### Option 3: Clone repo and symlink

```bash
# On Lumen VM
cd ~/code/circeaura  # or wherever the repo is
git pull

# Symlink all skills to OpenClaw workspace
for skill in atomicnebula-context atomicnebula-contacts atomicnebula-tasks atomicnebula-calendar atomicnebula-teams atomicnebula-task-write atomicnebula-attention atomicnebula-attachments atomicnebula-content atomicnebula-forms atomicnebula-leads atomicnebula-projects atomicnebula-digest atomicnebula-email; do
  ln -sf $(pwd)/openclaw-skills/$skill ~/.openclaw/workspace/skills/$skill
done
```

### Option 4: Deploy everything

```bash
# From the repo root — deploy skills only
./scripts/deploy-openclaw.sh --skills

# Deploy everything (extensions + skills)
./scripts/deploy-openclaw.sh

# Dry run (show what would happen)
./scripts/deploy-openclaw.sh --skills --dry-run

# Check what's currently deployed
./scripts/deploy-openclaw.sh --status
```

## Creating/Updating Skills

### Package a skill

Shared Atomic Nebula skills should not be hand-packaged from `openclaw-skills/`.
Update the canonical source in `skills/<skill-name>/`, then use `bun run
skills:sync` and `./scripts/deploy-openclaw.sh --skills`. Existing `.skill`
archives are legacy artifacts for older OpenClaw installs.

### Skill structure

```
skill-name/
├── SKILL.md           # Required: Main skill definition with YAML frontmatter
├── scripts/           # Optional: Helper scripts
└── references/        # Optional: Reference documentation
```

Shared skills follow the same structure, but they should be created in `skills/<skill-name>/` and then exposed to OpenClaw through the `openclaw-skills/` symlink view.

## Configuration

API keys and base URLs are configured per workspace through the shared assistant resolver.

Resolution order:

1. Environment variables such as `ATOMICNEBULA_API_KEY`
2. `~/.config/circeaura/assistant-workspaces.json`
3. Legacy `~/.openclaw/openclaw.json`

Neutral config shape:

```json
{
  "defaultWorkspace": "spider",
  "workspaces": {
    "spider": { "label": "SpiderGroup", "baseUrl": "https://...", "apiKey": "..." },
    "dev": { "label": "Development", "baseUrl": "https://...", "apiKey": "..." }
  }
}
```

Run `an-env-list.sh` on Lumen to see available workspaces:

```bash
~/.openclaw/workspace/skills/shared/an-env-list.sh
```

Fallback: skills also check these environment variables (used when workspace not in config):

```bash
export ATOMICNEBULA_API_KEY="atom_..."       # production
export ATOMICNEBULA_DEV_API_KEY="atom_..."   # dev
```

### Required Permissions

| Skill | Permissions Required |
|-------|---------------------|
| `atomicnebula-context` | Graph endpoint permissions vary by target: contacts, projects, deals, or attention read |
| `atomicnebula-capture` | `atomicnebula:context:read` for reads, `atomicnebula:context:write` for durable capture writes |
| `atomicnebula-contacts` | `atomicnebula:contacts:read` for reads, `atomicnebula:contacts:write` for create/update/delete |
| `atomicnebula-tasks` | `atomicnebula:tasks:read`, `atomicnebula:projects:read` |
| `atomicnebula-calendar` | `atomicnebula:meetings:read`, `atomicnebula:calendar:read`, `atomicnebula:calendar:write` for create/update/delete |
| `atomicnebula-teams` | `atomicnebula:teams:read` for reads, `atomicnebula:teams:write` for replies |
| `atomicnebula-task-write` | `atomicnebula:tasks:write` |
| `atomicnebula-attention` | `atomicnebula:attention:read` |
| `atomicnebula-attachments` | Entity-scoped read/write permissions for the target object (for task attachments: `atomicnebula:tasks:read` + `atomicnebula:tasks:write`) |
| `atomicnebula-content` | `atomicnebula:content:read` for reads, `atomicnebula:content:write` for create/update/markdown/link writes |
| `atomicnebula-forms` | `atomicnebula:form_designer:read` for reads, `atomicnebula:form_designer:write` for create/update/publish/unpublish |
| `atomicnebula-leads` | `atomicnebula:leads:read` for reads, `atomicnebula:leads:write` for create/update/delete |
| `atomicnebula-projects` | `atomicnebula:projects:read` for list/types/schema, `atomicnebula:projects:write` for create/update/archive |
| `atomicnebula-digest` | `atomicnebula:attention:read` (digest + due), `atomicnebula:attention:write` (mark reminders notified) |
| `atomicnebula-email` | Mailbox read/write permissions by operation |

## Lumen Checklist

Use this after any skill update to ensure Lumen is current:

```bash
# 1) Preview changes
./scripts/deploy-openclaw.sh --skills --dry-run

# 2) Deploy skills
./scripts/deploy-openclaw.sh --skills

# 3) Verify what's on Lumen
./scripts/deploy-openclaw.sh --status

# 4) Validate skill registry from Lumen
ssh lumen-ts "ls -1 ~/.openclaw/workspace/skills | grep atomicnebula"
```

## Skill Details

### atomicnebula-tasks (CIR-536)

Read-only task querying. Supports:
- List tasks with filters (project, assignee, status, priority, date range)
- Get task details including subtasks and comments
- List projects

```bash
# CLI usage
./scripts/an-tasks.sh list --priority high --limit 20
./scripts/an-tasks.sh get f7388c6a-c718-4584-bfe3-c5b6b4a8fe41  # Use UUID from list
./scripts/an-tasks.sh subtasks f7388c6a-c718-4584-bfe3-c5b6b4a8fe41
./scripts/an-tasks.sh comments f7388c6a-c718-4584-bfe3-c5b6b4a8fe41
```

### atomicnebula-calendar (CIR-538)

Calendar and meeting access. Supports:
- List provider-backed calendar events
- List accessible calendar targets
- Create, update, and delete provider-backed appointments
- List CRM meetings with filters
- Get meeting details
- Find availability windows
- Get upcoming meetings

```bash
# CLI usage
./scripts/an-calendar.sh upcoming
./scripts/an-calendar.sh events --today
./scripts/an-calendar.sh targets
./scripts/an-calendar.sh create --subject "Planning" --start 2026-04-22T09:00:00Z --end 2026-04-22T09:30:00Z
./scripts/an-calendar.sh availability --date 2026-02-20
./scripts/an-calendar.sh get MEET-0042
```

### atomicnebula-teams (—)

Teams chat access and replies. Supports:
- Show whether Teams is connected for the current user
- List user-scoped chats
- Inspect a chat
- List messages in a chat
- Reply in existing chats and channel threads

```bash
# CLI usage
./scripts/an-teams.sh status
./scripts/an-teams.sh chats --limit 20
./scripts/an-teams.sh get TC-123
./scripts/an-teams.sh messages TC-123 --limit 25
./scripts/an-teams.sh reply TC-123 --body "I can do 3pm."
./scripts/an-teams.sh reply TC-456 --reply-to TM-789 --body "Looks good to me."
```

### atomicnebula-task-write (CIR-537)

Task creation and updates with approval gates. Supports:
- Create tasks (title, description, project, assignee, priority, due date)
- Update tasks (status, assignee, priority, due date, description)
- Complete tasks
- Delete tasks (soft delete)

**Note**: All write operations require human approval via the Skill/Gateway workflow.

```bash
# CLI usage
./scripts/an-task-write.sh create --title "Review report" --priority high
./scripts/an-task-write.sh update TASK-0042 --priority high --owner user_xyz
./scripts/an-task-write.sh complete TASK-0042
./scripts/an-task-write.sh delete TASK-0042
```

### atomicnebula-attention (CIR-543)

Read-only focus queue and priority access. Supports:
- Get focus queue summary (counts by bucket, top priorities)
- List focus items by bucket (now, next, later)
- Filter by energy level, channel, status, priority
- Search for specific items
- Show items needing response

```bash
# CLI usage
./scripts/an-attention.sh summary
./scripts/an-attention.sh summary --energy low
./scripts/an-attention.sh focus --bucket now
./scripts/an-attention.sh focus --needs-response
./scripts/an-attention.sh focus --search "invoice"
```

### atomicnebula-attachments (TBD)

Entity attachment operations. Supports:
- Upload + confirm attachment bytes via SAS URL
- List attachments for a specific entity
- Generate download URLs
- Link/unlink existing attachments

```bash
# CLI usage
./scripts/an-attachments.sh list --entity-type task --entity-id TASK-123
./scripts/an-attachments.sh upload --entity-type task --entity-id TASK-123 --file ./spec.pdf
./scripts/an-attachments.sh download-url ATT-123 --entity-type task --entity-id TASK-123
./scripts/an-attachments.sh link ATT-123 --entity-type deal --entity-id DEAL-42
./scripts/an-attachments.sh unlink ATT-123 --entity-type task --entity-id TASK-123
```

### atomicnebula-content (—)

External content-item access. Supports:
- List content items with filters, sorting, and pagination
- Get content item details
- Create document-backed or allowlisted bodyless content items
- Update content metadata
- Read and replace markdown for document-backed items
- Link content items to contacts, companies, deals, and leads

```bash
# CLI usage
./scripts/an-content.sh list --type content_idea --page 1 --page-size 20
./scripts/an-content.sh get CONTENT-ID
./scripts/an-content.sh markdown CONTENT-ID
./scripts/an-content.sh create --title "Launch memo" --markdown-file ./memo.md
./scripts/an-content.sh update CONTENT-ID --status archived --tag launch
./scripts/an-content.sh set-markdown CONTENT-ID --file ./updated.md --expected-version 3
./scripts/an-content.sh link-entity CONTENT-ID --entity-type contact --entity-id CONTACT-ID
```

### atomicnebula-leads (—)

External lead access. Supports:
- List leads with filters, sorting, and pagination
- Get lead details
- Create leads
- Update lead metadata and qualification state
- Delete leads

```bash
# CLI usage
./scripts/an-leads.sh list --search acme --limit 20
./scripts/an-leads.sh get LEAD-ID
./scripts/an-leads.sh create --email "prospect@example.com" --first-name "Pat" --last-name "Lee"
./scripts/an-leads.sh update LEAD-ID --qualification-status sql --score 75 --tag qualified
./scripts/an-leads.sh delete LEAD-ID
```

### atomicnebula-projects (—)

External project access. Supports:
- List projects with basic filters
- Create, update, and archive projects
- Get project type definitions
- Get project custom-field schema

```bash
# CLI usage
./scripts/an-projects.sh list --status active
./scripts/an-projects.sh types
./scripts/an-projects.sh custom-fields
./scripts/an-projects.sh create --name "Content Backlog" --key "content-backlog"
./scripts/an-projects.sh update PROJECT-ID --status active --description "Current work backlog"
./scripts/an-projects.sh archive PROJECT-ID --reason "Completed"
```
