---
name: atomicnebula-context
description: "Use Atomic Nebula graph-backed context before raw records. Use when a user asks for operational context around a person, thread, deal, or project, or wants to understand how two entities are related. Supports --env <workspace> to target a configured workspace."
metadata:
  {
    "openclaw":
      {
        "emoji": "🕸️",
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

# Context Graph

Use this skill first when the user needs operational understanding rather than raw records.

## Canonical Order

1. Use graph/context endpoints for person, thread, deal, project, and relationship context.
2. Use digest and attention endpoints for priorities and "what matters now".
3. Use domain skills such as Contacts, Tasks, Email, Projects, or Attachments for exact records or writes.

## Helper Script

Run from the repository root:

```bash
skills/atomicnebula-context/scripts/an-context.sh person <contactId>
skills/atomicnebula-context/scripts/an-context.sh thread <threadId>
skills/atomicnebula-context/scripts/an-context.sh deal <dealId>
skills/atomicnebula-context/scripts/an-context.sh project <projectId>
skills/atomicnebula-context/scripts/an-context.sh bridge --from-type contact --from-id <id> --to-type project --to-id <id>
```

## Notes

- The `intention` graph route is intentionally not exposed until the backend route exists.
- If a graph result points to a raw entity that must be inspected or changed, switch to the relevant domain skill.
