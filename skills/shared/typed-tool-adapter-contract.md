# Atomic Nebula Typed Tool Adapter Contract

This contract describes the shared direction for Atomic Nebula assistant tools across Codex, Claude Code, OpenClaw, and future assistant clients.

The goal is not to expose one large always-on MCP server. The goal is to give agents narrow, typed, domain-scoped tool groups that can be loaded only when the matching skill or user intent requires them.

## Principles

- Domain scoped: expose small groups such as `atomicnebula_email`, `atomicnebula_calendar`, `atomicnebula_tasks`, `atomicnebula_context`, and `pulse_halo_ops` instead of one broad Atomic Nebula surface.
- Lazy by default: a client should load a tool group when a skill is invoked or a task clearly belongs to that domain.
- Transport neutral: MCP is one valid transport, but the durable contract is the typed schema, safety metadata, operation identity, and result semantics.
- Multi-agent usable: avoid Codex-only, Claude-only, or OpenClaw-only assumptions in shared tool definitions. Consumer-specific packaging may live beside the shared contract.
- Catalog backed: use the assistant operation catalog in `convex/platform/api/http/*operations.ts` for method, path, permission, action type, policy, and operation key metadata.
- Description rich: reuse or mirror the best native assistant tool descriptions from `convex/products/atomicnebula/assistant/tools/*`, especially disambiguators such as calendar event vs CRM meeting recording.

## Tool Group Shape

Each domain adapter should publish a small manifest with:

- `name`: stable domain tool group id, for example `atomicnebula_email`.
- `version`: semantic adapter contract version.
- `sourceOperations`: assistant operation keys covered by the group.
- `workspace`: how the adapter resolves `--env <workspace>` or equivalent config.
- `tools`: callable tools with schemas, descriptions, annotations, and examples.

Each tool should include:

- stable tool name
- human-readable title
- selection description
- near-neighbor disambiguation
- JSON Schema or Zod-equivalent input schema
- read/write/delete annotations
- approval behavior and operation key
- idempotency notes where applicable
- expected result shape, including IDs, cursors, approval challenge details, and provider sync state

## Safety Metadata

Use these annotations consistently, regardless of transport:

- `readOnly`: true for pure reads.
- `destructive`: true for deletes, hard unlinks, cancels, and irreversible provider operations.
- `idempotent`: true only when repeat calls are intended to be safe.
- `approval`: `none`, `may_require`, or `required`.
- `operationKey`: the Atomic Nebula assistant operation key, for example `emails.drafts.create`.
- `requiredPermission`: permission from the operation catalog.
- `workspaceScoped`: true for tenant-scoped Atomic Nebula calls.

## Preferred Domain Groups

Start with these groups:

- `atomicnebula_context`: context captures, entity context, domain context packs, graph bridge.
- `atomicnebula_tasks`: task/project reads, task writes, stage lookup handoff.
- `atomicnebula_calendar`: calendar events, targets, availability, calendar writes.
- `atomicnebula_email`: mailbox discovery, search, hydrate/content/thread reads, drafts, send/reply/forward, mailbox operations.
- `atomicnebula_crm`: contacts, companies, leads, products, projects, pipelines.
- `atomicnebula_forms`: form schemas, validation, publish/unpublish, responses.
- `atomicnebula_meetings`: CRM meeting records, transcripts, meeting open loops.
- `atomicnebula_files`: attachment upload/list/download/link/unlink.
- `atomicnebula_teams`: Teams conversations, messages, guarded replies.
- `pulse_halo_ops`: Halo ticket inspection, write previews, confirmed apply operations.

## CLI Compatibility

Existing shell helpers remain supported. They are useful for agents that cannot load typed tools and for humans debugging locally.

Typed adapters should call the same REST endpoints or lower-level domain functions as the CLI helpers and should preserve:

- workspace resolution through the neutral assistant workspace config
- `X-Run-Id` correlation for writes
- approval challenge recording
- permission and tenant scoping
- preview-before-apply behavior for high-risk domains

## What Not To Do

- Do not expose all Atomic Nebula operations to every prompt by default.
- Do not hide safety semantics in prose-only skill instructions.
- Do not make MCP the source of truth; keep operation metadata in the product catalog and generate or mirror adapters from that.
- Do not create separate approval systems per agent. Approval policy belongs to the shared assistant operation model.
