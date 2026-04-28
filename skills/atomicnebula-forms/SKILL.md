---
name: atomicnebula-forms
description: "Create, manage, publish, and query forms and submissions in Atomic Nebula. Use when a user wants to create a new form, list existing forms, check form submissions, publish or unpublish a form, or build a form for a specific purpose (e.g., feedback, lead capture, event registration). Supports multi-step forms with field configuration, conditional logic, and CRM field mapping. Use --env <workspace> to target a specific workspace (e.g., --env dev)."
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

# Atomic Nebula Forms Skill

Create, manage, publish, and query forms and submissions in Atomic Nebula through the HTTP API.

## Configuration

Credentials resolve in this order:

1. Environment variables such as `ATOMICNEBULA_API_KEY` and `ATOMICNEBULA_BASE_URL`
2. `~/.config/circeaura/assistant-workspaces.json`
3. Legacy `~/.openclaw/openclaw.json`

Use `--env <workspace>` to target a configured workspace. Run `skills/shared/an-env-list.sh` to inspect configured workspaces.

## Workspace Targeting

All commands accept `--env <workspace>` to target a specific workspace:

- **spider** (default, no flag needed) — SpiderGroup production workspace
- `--env dev` — James's development workspace
- `--env circeaurasupport` — CirceAura Support production workspace

Each workspace has its own API key in the shared assistant workspace config.

## Helper Script

Use the bundled script for common operations:

```bash
# List all forms
skills/atomicnebula-forms/scripts/an-forms.sh list

# List published forms only
skills/atomicnebula-forms/scripts/an-forms.sh list --published

# Get form details (use UUID from list output)
skills/atomicnebula-forms/scripts/an-forms.sh get <form-uuid>

# Create a simple one-step form
skills/atomicnebula-forms/scripts/an-forms.sh create --name "Feedback Form" --steps-json '[{"id":"step1","title":"Your Feedback","position":0,"fields":[{"id":"name","type":"text","label":"Your Name","required":true},{"id":"email","type":"email","label":"Email","required":true},{"id":"message","type":"textarea","label":"Message","required":true}]}]'

# Create a form from a JSON file
skills/atomicnebula-forms/scripts/an-forms.sh create --name "Event Registration" --steps-file ./my-form-steps.json

# Update a form
skills/atomicnebula-forms/scripts/an-forms.sh update <form-uuid> --name "Updated Form Name"

# Publish a form (makes it publicly accessible)
skills/atomicnebula-forms/scripts/an-forms.sh publish <form-uuid>

# Unpublish a form
skills/atomicnebula-forms/scripts/an-forms.sh unpublish <form-uuid>

# Delete a form (soft delete)
skills/atomicnebula-forms/scripts/an-forms.sh delete <form-uuid>

# List submissions for a form
skills/atomicnebula-forms/scripts/an-forms.sh responses <form-uuid>

# Get a single submission
skills/atomicnebula-forms/scripts/an-forms.sh response <response-uuid>

# All commands support --env for workspace targeting
skills/atomicnebula-forms/scripts/an-forms.sh --env dev list
skills/atomicnebula-forms/scripts/an-forms.sh --env dev create --name "Test Form" --steps-file ./steps.json
```

## Operations

### List Forms

Query forms with optional filters:

```bash
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/forms?limit=20" | jq .
```

#### Filter Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `isActive` | boolean | Filter by active status (`true` or `false`) |
| `isPublished` | boolean | Filter by published status (`true` or `false`) |
| `limit` | number | Max results (default: 50) |
| `cursor` | string | Pagination cursor from previous response |

### Get Form Details

Retrieve a single form with full configuration and backend-owned delivery metadata:

```bash
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/forms/{uuid}" | jq .
```

Key blocks returned by `get <form-uuid>`:

- `publication`
  - `isPublished`
  - `publishedVersion`
  - `publishedAt`
- `delivery`
  - `livePath`
  - `publishedPreviewPath`
  - `draftPreviewPath`
  - `embedPath`
  - `iframeEmbedCode`
- `submission`
  - `hosted.endpointPath`
  - `staticSite.endpointPath`
- `schema`
  - normalized `steps`
  - normalized `options`
  - explicit `storageMode`
  - `storage.writesToCrm`
- `submissionBehavior`
  - validation, navigation, confirmation, consent, and messaging rules

Legacy aliases are still present for compatibility:

- `publicUrl` = `delivery.livePath`
- `embedCode` = `delivery.iframeEmbedCode`

Use these API-owned blocks instead of reconstructing live URLs, embed code, submit endpoints, or field storage semantics in prompts or follow-up shell commands.

Examples:

```bash
skills/atomicnebula-forms/scripts/an-forms.sh get <form-uuid> | jq '.delivery'
skills/atomicnebula-forms/scripts/an-forms.sh get <form-uuid> | jq '.submission'
skills/atomicnebula-forms/scripts/an-forms.sh get <form-uuid> | jq '.publication'
skills/atomicnebula-forms/scripts/an-forms.sh get <form-uuid> | jq '.schema.steps[].fields[] | {id, label, storageMode}'
```

### Create Form

Create a new form with multi-step configuration:

```bash
curl -s -X POST -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  -H "Content-Type: application/json" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/forms" \
  -d '{
    "name": "Customer Feedback",
    "description": "Collect customer feedback",
    "type": "multi-step",
    "steps": [
      {
        "id": "step1",
        "title": "About You",
        "position": 0,
        "fields": [
          {
            "id": "name",
            "type": "text",
            "label": "Full Name",
            "required": true,
            "placeholder": "Enter your name"
          },
          {
            "id": "email",
            "type": "email",
            "label": "Email Address",
            "required": true
          }
        ]
      },
      {
        "id": "step2",
        "title": "Your Feedback",
        "position": 1,
        "fields": [
          {
            "id": "rating",
            "type": "select",
            "label": "How would you rate us?",
            "required": true,
            "options": ["Excellent", "Good", "Average", "Poor"]
          },
          {
            "id": "comments",
            "type": "textarea",
            "label": "Additional Comments",
            "required": false,
            "placeholder": "Tell us more..."
          }
        ]
      }
    ]
  }' | jq .
```

#### Create Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `name` | string | Yes | Form name |
| `description` | string | No | Form description |
| `type` | string | No | Form type (default: "multi-step") |
| `steps` | array | Yes | Array of step objects (see Step Schema below) |
| `layout` | object | No | Layout config (type, maxWidth, padding, etc.) |
| `settings` | object | No | Form settings (see Settings Schema below) |

#### Step Schema

```json
{
  "id": "unique-step-id",
  "title": "Step Title",
  "description": "Optional step description",
  "position": 0,
  "fields": [ /* field objects */ ],
  "imageLayout": null,
  "nextStepLogic": null,
  "conditionalFields": null
}
```

#### Field Schema

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `id` | string | Yes | Unique field identifier |
| `type` | string | Yes | Field type (see types below) |
| `label` | string | Yes | Display label |
| `placeholder` | string | No | Placeholder text |
| `required` | boolean | No | Whether field is required |
| `helpText` | string | No | Help text shown below field |
| `options` | string[] | No | Options for select/radio/checkbox fields |
| `width` | string | No | Field width (e.g., "full", "half") |
| `minLength` | number | No | Minimum text length |
| `maxLength` | number | No | Maximum text length |
| `min` | number | No | Minimum number value |
| `max` | number | No | Maximum number value |
| `storageMode` | string | No | "crm" (maps to CRM field) or "response_only" |
| `crmMapping` | object | No | CRM field mapping (when storageMode is "crm") |

#### Field Types

- `text` — Single-line text input
- `email` — Email address input
- `phone` — Phone number input
- `textarea` — Multi-line text input
- `number` — Numeric input
- `select` — Dropdown select (requires `options`)
- `radio` — Radio button group (requires `options`)
- `checkbox` — Checkbox group (requires `options`)
- `date` — Date picker
- `url` — URL input
- `currency` — Currency input (supports `currency` property)
- `consent` — Consent/GDPR checkbox

#### Settings Schema

```json
{
  "enableAutoSave": false,
  "allowBackNavigation": true,
  "showProgressIndicator": true,
  "enableConditionalLogic": true,
  "requireConfirmation": false,
  "submitButtonText": "Submit",
  "successMessage": "Thank you for your submission!",
  "errorMessage": "Something went wrong. Please try again.",
  "allowedOrigins": ["https://example.com"]
}
```

### Update Form

Update an existing form (partial update):

```bash
curl -s -X PATCH -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  -H "Content-Type: application/json" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/forms/{uuid}" \
  -d '{
    "name": "Updated Form Name",
    "description": "Updated description"
  }' | jq .
```

#### Update Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | string | New form name |
| `description` | string | New description |
| `type` | string | New form type |
| `steps` | array | Replace all steps |
| `layout` | object | New layout config |
| `settings` | object | New settings |
| `isActive` | boolean | Activate or deactivate |

### Publish Form

Make a form publicly accessible. Increments the version number and syncs to Azure for public hosting:

```bash
curl -s -X POST -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/forms/{uuid}/publish" | jq .
```

Returns: `{ id, version, publishedAt }`

### Unpublish Form

Remove public access for a form:

```bash
curl -s -X POST -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/forms/{uuid}/unpublish" | jq .
```

Returns: `{ id, isPublished: false }`

### Delete Form

Soft delete a form:

```bash
curl -s -X DELETE -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/forms/{uuid}" | jq .
```

### List Form Responses

Query submissions for a form:

```bash
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/forms/{uuid}/responses?limit=20" | jq .
```

#### Response Filter Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `fromDate` | string | Filter from date (ISO format) |
| `toDate` | string | Filter to date (ISO format) |
| `limit` | number | Max results (default: 50) |
| `cursor` | string | Pagination cursor |

### Get Form Response

Retrieve a single submission with full detail:

```bash
curl -s -H "Authorization: Bearer $ATOMICNEBULA_API_KEY" \
  "${ATOMICNEBULA_BASE_URL:-https://convex-actions.circeaura.com}/api/v1/atomicnebula/forms/{formUuid}/responses/{responseUuid}" | jq .
```

Returns: responseData, responseBreakdown, stepResponses, UTM data, referrer, contact/lead linkage, etc.

## Approval Workflow

Write operations go through the Assistant Gateway with risk-based approval:

| Action | Risk Tier | Approval Status |
|--------|-----------|-----------------|
| `forms.list` | read | Auto-accepted |
| `forms.get` | read | Auto-accepted |
| `forms.responses.list` | read | Auto-accepted |
| `forms.responses.get` | read | Auto-accepted |
| `forms.create` | `low_write` | Auto-accepted |
| `forms.update` | `low_write` | Auto-accepted |
| `forms.publish` | `low_write` | Auto-accepted |
| `forms.unpublish` | `low_write` | Auto-accepted |
| `forms.delete` | `high_write` | **Requires review** |

## Common Use Cases

### "Build me a feedback form"

1. Create the form with appropriate fields
2. Publish it to make it accessible

```bash
# Create
skills/atomicnebula-forms/scripts/an-forms.sh create --name "Customer Feedback" --steps-json '[{"id":"s1","title":"Feedback","position":0,"fields":[{"id":"name","type":"text","label":"Name","required":true},{"id":"email","type":"email","label":"Email","required":true},{"id":"rating","type":"select","label":"Rating","required":true,"options":["5 - Excellent","4 - Good","3 - Average","2 - Poor","1 - Terrible"]},{"id":"feedback","type":"textarea","label":"Comments","required":false}]}]'

# Publish (use the returned form ID)
skills/atomicnebula-forms/scripts/an-forms.sh publish <form-uuid>
```

### "What forms do we have?"

```bash
skills/atomicnebula-forms/scripts/an-forms.sh list
skills/atomicnebula-forms/scripts/an-forms.sh list --published  # Only published forms
```

### "How many submissions did the contact form get?"

```bash
skills/atomicnebula-forms/scripts/an-forms.sh responses <form-uuid>
```

### "Create an event registration form"

```bash
skills/atomicnebula-forms/scripts/an-forms.sh create --name "Event Registration" --steps-json '[
  {"id":"s1","title":"Personal Details","position":0,"fields":[
    {"id":"name","type":"text","label":"Full Name","required":true},
    {"id":"email","type":"email","label":"Email","required":true},
    {"id":"phone","type":"phone","label":"Phone Number","required":false}
  ]},
  {"id":"s2","title":"Event Details","position":1,"fields":[
    {"id":"session","type":"select","label":"Which session?","required":true,"options":["Morning Workshop","Afternoon Workshop","Full Day"]},
    {"id":"dietary","type":"select","label":"Dietary Requirements","required":false,"options":["None","Vegetarian","Vegan","Gluten-free","Other"]},
    {"id":"notes","type":"textarea","label":"Anything else we should know?","required":false}
  ]}
]'
```

## Error Handling

All endpoints return standard HTTP status codes:

- `200` — Success
- `201` — Created
- `204` — Deleted
- `400` — Bad Request (invalid parameters or field storage consistency error)
- `401` — Unauthorized (missing or invalid API key)
- `403` — Forbidden (API key lacks required permission)
- `404` — Not Found (form/response doesn't exist)
- `500` — Internal Server Error

Error responses have format:

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Missing required field: name"
  }
}
```

## Security

- Read operations require the `atomicnebula:forms:read` permission
- Write operations require the `atomicnebula:forms:write` permission
- Operations are scoped to the tenant associated with the API key
- Cross-tenant access is blocked
- Delete is soft delete — data recovery is possible
