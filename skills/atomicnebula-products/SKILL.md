---
name: atomicnebula-products
description: "Look up Atomic Nebula products over the external REST API. Use when a user asks whether a product exists, how many are in stock, what is available to sell, or what the current price is. Supports --env <workspace> to target a configured workspace."
metadata:
  {
    "openclaw":
      {
        "emoji": "📦",
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

# Atomic Nebula Products

Use the Atomic Nebula product catalogue REST API through the shared assistant workspace config.

## Configuration

Credentials resolve in this order:

1. Environment variables such as `ATOMICNEBULA_API_KEY` and `ATOMICNEBULA_BASE_URL`
2. `~/.config/circeaura/assistant-workspaces.json`
3. Legacy `~/.openclaw/openclaw.json`

Use `--env <workspace>` to target a configured workspace. Run `skills/shared/an-env-list.sh` to inspect configured workspaces.

## Helper Script

Run from the repository root:

```bash
skills/atomicnebula-products/scripts/an-products.sh lookup --query "printer cartridge"
skills/atomicnebula-products/scripts/an-products.sh lookup --sku "SKU-123"
skills/atomicnebula-products/scripts/an-products.sh stock --query "printer cartridge"
skills/atomicnebula-products/scripts/an-products.sh price --sku "SKU-123"
skills/atomicnebula-products/scripts/an-products.sh list --search "support" --limit 20
skills/atomicnebula-products/scripts/an-products.sh get <productId>
```

## Commands

- `lookup`: Search by name, description, SKU, or product id. Options: `--query`, `--sku`, `--product-id`, `--limit`.
- `stock`: Same lookup surface, trimmed to stock-relevant fields.
- `price`: Same lookup surface, trimmed to price-relevant fields.
- `list`: List catalogue entries. Options: `--search`, `--category`, `--limit`, `--cursor`, `--sort-by`, `--sort-order`.
- `get <productId>`: Fetch one product by canonical Atomic Nebula product id.

## Interpreting Stock

- Use `availableQty` for "how many can we sell?"
- Use `qtyOnHand` for physical stock.
- Use `allocatedQty` and `reservedQty` for committed stock.
- Check `stockUpdatedAt` or `stockAgeMins` before implying live inventory freshness.

## Permissions

- Read: `atomicnebula:products:read`

The skill is read-only. Product creation, update, deletion, and external stock sync remain outside this assistant helper.
