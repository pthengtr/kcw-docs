# Product substitutes (สินค้าทดแทน)

Operator + engineer runbook. App code: kcw-api `docs/substitutes/plan.md` and `src/substitutes/`.

| Item | Value |
|------|--------|
| Live suggestions | ICMAS signals — REMARKS, CODE1+SIZE, PCODE, MCODE (`suggest.py`) |
| Catalog DB | Supabase `catalog.substitute_groups` / `catalog.substitute_members` |
| Manage UI | PARTS9 Explorer `:8788` → `/parts9/substitutes` |
| Transfer UI | `kcw-transfer` `:8792` — แนะนำทดแทน + prepare **ส่งแทน** |
| Suggest API | `GET /parts9/api/substitutes/suggest/{bcode}` |

---

## Glossary (locked)

| Operator says | Means here | Not |
|---------------|------------|-----|
| L-1 / qtylo -1 / ไม่สั่งซ้ำ / ไม่สต็อก | `ICMAS.QTYMIN < 0` (usually `-1`), **per branch** | Out of stock (`QTYOH2 = 0`) |
| **แนะนำทดแทน / suggestion** | Live ICMAS hints (REMARKS, รหัส+ขนาด, PCODE, MCODE) | Confirmed catalog / ส่งแทน |
| สินค้าทดแทน / กลุ่มทดแทน / catalog | Operator-**confirmed** mutual peer SKUs | Auto-import from Phase 0 dump |
| ส่งแทน | Prepare ships a **catalog peer** against the request line | Shipping a live-only suggestion |

See also [ICMAS dictionary §6](../dictionaries/kcw-icmas-data-dictionary.md) (`QTYMIN`), §4 (PCODE/MCODE), §7 (CODE1+SIZE), and [transfer.md](./transfer.md).

---

## Two layers (do not mix)

```text
Live suggestion  →  hint only on Transfer / Explorer
Catalog group    →  intentional confirm  →  can ส่งแทน
```

1. **Suggestion** — when ship-from is L-1 or stock &lt; need, UI shows peers from live ICMAS (badges: REMARKS / รหัส+ขนาด / PCODE / MCODE). Does **not** authorize ส่งแทน.
2. **Catalog** — operator creates/edits groups in Explorer (or promotes a suggestion). Only catalog peers can be chosen for **ส่งแทน**.

Do **not** bulk-seed Phase 0 candidates into catalog without human approval. Prefer create/promote in Explorer.

---

## Manage groups (Explorer)

1. Open Explorer (`:8788`) → product detail (แนะนำ + กลุ่ม) or **`/parts9/substitutes`**.
2. Review live suggestions; **เพิ่มเข้ากลุ่ม** to confirm, or create a group manually.
3. Add/remove peer BCODEs (must exist on HQ and/or SYP ICMAS). Optional name/note.

Auth: same LINE cookie / Tailscale gate as other `/parts9/api/*` routes.

API: `/parts9/api/substitutes` — `suggest/{bcode}`, `by-bcode`, groups CRUD. See kcw-api `docs/substitutes/plan.md`.

---

## Transfer: hints + ส่งแทน

### Suggest / prepare hints (read-only)

When ship-from has `QTYMIN < 0` or insufficient `QTYOH2`, transfer UI shows **แนะนำทดแทน** with dual stock + source badge. No ship change yet.

### Prepare ส่งแทน (catalog only)

1. Confirm the peer in a catalog group (Explorer).
2. On prepare, type **รหัสส่งแทน** (peer must be in the same catalog group as the request BCODE). Empty = ship request BCODE.
3. TF/SIDET deducts **peer** stock; request line `qty_prepared` still bumps on the **original** line.
4. Receive sees shipped peer with note that it substituted the request SKU.

`ship_as_bcode` that is only a live suggestion (not in catalog) is **rejected**.

### Prepare API contract

`POST /transfer/api/requests/{id}/prepare` line items:

| Field | Meaning |
|-------|---------|
| `line_id` | Request line (fulfillment bumps this line) |
| `qty_ship` | Qty on this wave |
| `ship_as_bcode` | Optional **catalog** peer BCODE; omit/null/same = no substitute |

Persistence:

- `shipment_lines.bcode` = shipped SKU
- `shipment_lines.requested_bcode` = original request BCODE (when ส่งแทน)
- Event `substitute_ship` `{line_id, from_bcode, to_bcode, qty}`

**Clash (v1):** reject if `ship_as_bcode` equals another request line’s `bcode` on the same transfer.

---

## Migrations

| Migration | Purpose |
|-----------|---------|
| `20260910120000_catalog_substitutes.sql` | `catalog.substitute_*` |
| `20260910130000_transfer_shipment_requested_bcode.sql` | `transfer.shipment_lines.requested_bcode` |

Apply on Supabase before staging E2E for ส่งแทน.

---

## Optional seed import

Phase 0 dump (`initial-seed-candidates.md`) is **review material only**. If ops ever exports an approved CSV:

```bash
cd /home/hqadmin/projects/kcw-api
.venv/bin/python scripts/load_substitute_seed.py docs/substitutes/approved-seed.csv
.venv/bin/python scripts/load_substitute_seed.py docs/substitutes/approved-seed.csv --apply
```

Default preference: confirm peers via Explorer promote, not bulk seed.

---

## Non-goals

- Relaxing ส่งแทน to accept live-only peers
- Auto-import Phase 0 CSV
- Fuzzy PCODE/MCODE match
- Writing substitutes back into `ICMAS.REMARKS`
- Multi-group membership per BCODE
- Silent auto-pick without preparer confirmation

---

## Changelog

| Date | Change |
|------|--------|
| 2026-09-11 | Split live suggestions vs confirmed catalog; ส่งแทน catalog-gated |
| 2026-09-10 | Initial runbook |
