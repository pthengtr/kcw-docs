# KCW product movement BI

Report: **`/bi/product-movement`** — sell frequency vs HQ buys + dead-stock aging.

Status legend: **Confirmed** · **TBD** · **Inferred**

Last reviewed: 2026-07-26

---

## 1. Goals (Confirmed)

| Goal | Rule |
|------|------|
| **Stock more** | Rank SKUs by **most move-out** in the period (`sell_qty` desc) |
| **Dead / careful** | Age from **last HQ purchase** with **no subsequent sale** (on-hand > 0) |
| Purchase side | Always **HQ** PIDET |
| Sales side (stock-more) | Optional branch filter HQ / SYP / ONLINE |
| Dead side | As-of end date; **no** period/branch filter on membership |

Aging colors (parts / slow-turn business — start at 6 months):

| Tier | Age since last purchase (no sale after) |
|------|-----------------------------------------|
| Yellow (watch) | ≥ 6 months (180 days) |
| Orange (caution) | ≥ 1 year (365 days) |
| Red (dead) | ≥ 2 years (730 days) |

Membership is **purchase-age only** (`no_move_since_purchase`). Do not flag on “days since last sale” alone — that mixed recent buys into the caution list.

---

## 2. Sources

| Side | Source |
|------|--------|
| Sales | `curated_kcw.fact_sales_*` — same include filters as product BI |
| Purchase | `raw_kcw.raw_hq_pidet_purchase_lines` — see purchase dictionary |
| On-hand | `raw_kcw.raw_hq_icmas_products."QTYOH2"` |

---

## 3. Metrics

### Period block (`from`–`to`)

| Metric | Definition |
|--------|------------|
| `sell_qty` | Sum `QTY×MTP` on filtered sales lines |
| `sell_bills` | Distinct sales bills |
| `sell_days` | Distinct sales dates |
| `buy_qty` | Sum signed purchase `QTY×MTP` for BILLTYPE 1/2/3 + BCODE (HQ) |
| `buy_bills` | Distinct purchase bills (same set) |

### As-of `to` (dead stock)

| Metric | Definition |
|--------|------------|
| `last_purchase_date` | Max `BILLDATE` where `BILLTYPE=1` and BCODE set, ≤ `to` |
| `last_sale_date` | Max sales `BILLDATE` (all branches), ≤ `to` |
| `no_move_since_purchase` | `last_sale_date` is null **or** `last_sale_date < last_purchase_date` |
| `days_since_purchase` | `to − last_purchase_date` |
| `dead_tier` | `red` / `orange` / `yellow` / null — see §1 |

Universe for dead list: has `last_purchase_date`, **`on_hand_qty > 0`**, **`no_move_since_purchase`**, and `days_since_purchase ≥ 180`.

---

## 4. RPC / API

| Piece | Detail |
|-------|--------|
| RPC | `public.fn_bi_product_movement(from, to, branch, stock_limit, dead_limit, dead_offset, dead_sort, mode, dead_tier, category)` |
| Stock-more filters | Period `from`–`to` + optional sales `branch` |
| Dead stock filters | **As-of `to` only** — period/branch do not define membership; `last_sale` is always all-branch |
| Mode | `stock_more` \| `dead` \| `both` — UI loads one side to avoid statement timeouts |
| Dead filters | `dead_tier` = yellow\|orange\|red · `category` = 2-digit ICMAS prefix (one at a time) |
| Dead sort | `value_desc` (default) · `deep` · `recent` · `qty_desc` · `cost_desc` · `value_asc` |
| Dead cost | ICMAS `COSTLAST` → `unit_cost`; `stock_value` = on_hand × cost (blank cost excluded from value) |
| Timeout | Function `statement_timeout = 60s`; API retries once on timeout |
| Pagination | `dead_offset` + `dead_limit` (default 100); UI page jump; `dead_has_more` |
| UI | `/bi/product-movement` — stock-more uses period/branch; dead tab uses as-of + tier/category/sort |
| API | `GET /api/bi/products/movement?...&mode=&dead_tier=&category=&dead_sort=&dead_offset=` |

---

## 5. Changelog

| Date | Change |
|------|--------|
| 2026-07-26 | Dead cost (COSTLAST) + stock value; sort by value/qty/cost/age |
| 2026-07-26 | Dead filters: tier chips + single category + page jump; category narrows RPC scan |
| 2026-07-26 | Fix intermittent load errors: mode split, 60s timeout, light last-sale, client abort/retry |
| 2026-07-26 | Dead tiers → 6m/1y/2y; purchase-age only; UI age in months + default deep sort |
| 2026-07-26 | Dead list: configurable `recent`/`deep` sort; period/branch apply only to stock-more |
| 2026-07-26 | Dead list: yellow-first sort + offset pagination; remove tier filter chips |
| 2026-07-26 | Lock stock-more rank + dead tiers; HQ purchases; ship report |
