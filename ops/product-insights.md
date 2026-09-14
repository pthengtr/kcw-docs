# Product insights (Spark + local SQLite)

HQ pipeline: **snapshot PARTS9 → Spark analysis → local SQLite → Explorer panel**.

v2 insights are a **14–30 day standing policy** (demand, safe hold, QTYMIN trigger, typical PO pack, SYP target, trends, margin). Snapshot `QTYOH2` is context only and goes stale — **do not** treat the insight as a live “order now” ticket. **No** auto-PO. **No** Supabase this phase.

## Where

| Piece | Location |
|-------|----------|
| Runner | HQ Ubuntu — `kcw-analytic` CLI |
| Inference | `http://spark-3583:8000/v1` (list `/v1/models` at runtime) |
| Insights DB | env `PRODUCT_INSIGHTS_DB` (default under `~/kcw-data/product_insights/insights.sqlite`) |
| Snapshots | `PRODUCT_INSIGHTS_SNAP_DIR` or sibling `snaps/` next to the DB |
| Prompt | `kcw-analytic/prompts/product_insight_v1.yaml` |
| Explorer | `kcw-api` parts9 explorer — product detail panel |

## Flow

1. Snapshot PARTS9 → local snap (`facts_as_of`). For `--site hq`, default sources are **HQ KSS + SYP kss-pc** SI/PI (tagged `src_site`)
2. Worker (or one-shot generate) builds ranked eligibility from `--mover-window`
3. Priority: **never analyzed** → **age ≥ fresh-days** → optional soft refresh
4. Spark → upsert `product_insights`; queue lease `pending` → `running` → `done`
5. Explorer: ready / working / no 5y movement

## Continuous worker (recommended)

24/7 catch-up, then **auto-steady** to weekly movers. Concurrency is **1** (GB10).

```bash
cd ~/projects/kcw-analytic
source .venv/bin/activate

# uses existing latest snap; refreshes snap every 7d; fresh TTL 14d; 5y→7d when never-left=0
python -m src.kcw.pipeline insight-worker --site hq

# smoke: one successful job then exit
python -m src.kcw.pipeline insight-worker --site hq --max-jobs 1
```

| Flag | Default | Purpose |
|------|---------|---------|
| `--mover-window` | `5y` | Eligible movers; **auto-steady** flips to `7d` when no never-analyzed left |
| `--fresh-days` | `14` | Skip if insight younger than this |
| `--soft-refresh` | off | Also claim ages in `[soft-min-days, fresh-days)` |
| `--no-auto-steady` | off | Stay on starting mover-window forever |
| `--snap-every-days` | `7` | New PARTS9 snap on this cadence |
| `--idle-seconds` | `120` | Sleep when nothing due (process stays up) |
| `--lease-minutes` | `90` | Reclaim stuck `running` rows |
| `--max-jobs` | none | Exit after N successes (test) |

**Resume:** `insight_worker_state` stores `mover_window` + last snap time so restarts continue steady mode.

**Phases:**

1. **Backfill** — `mover-window=5y`, high movement first, 24/7 until every SI∪PI BCODE has an insight  
2. **Steady** — auto switch to `7d`; each week only movers that are never / age ≥ 14d (~1–1.5k jobs/week)

## One-shot CLI (bench / manual)

```bash
# dual-site (default for hq): KSS + kss-pc SI/PI
python -m src.kcw.pipeline insight-snapshot --site hq
# HQ only:
python -m src.kcw.pipeline insight-snapshot --site hq --hq-only
# patch latest snap with HQ+SYP QTYOH/QTYMIN + PIMAS suppliers (no SI/PI re-extract)
python -m src.kcw.pipeline insight-snapshot --enrich-latest
python -m src.kcw.pipeline insight-generate --snap latest --window 5y --limit 10 --concurrency 1
python -m src.kcw.pipeline insight-generate --snap latest --window 5y --concurrency 1 --resume
```

| Flag | Purpose |
|------|---------|
| `--snap` | Snapshot id or `latest` (newest by **mtime**) |
| `--window` | Queue lookback from snap time: `5y`, `14d`, `7d`, `2w` |
| `--limit N` | Top-N by movement (bench) |
| `--concurrency` | Parallel Spark calls (1–8; use **1** on GB10) |
| `--resume` | Skip queue rows already `done` (default: on) |
| `--no-resume` | Rebuild pending from window |

Fact history in the prompt prefers **full snap history** for that BCODE (snap holds ~5y), even when the mover window is `7d`.

## Channel mapping (live KSS / kss-pc)

PARTS9 has no `BILLTYPE_STD`. Derive from **billno prefix** + `JOURMODE` (+ snap `src_site`):

| Rule | Channel |
|------|---------|
| `JOURMODE=0` | excluded |
| `TAD*` / `CNTAD*` | **online** |
| `TF*` / `TFV*` / `CNTF*` | **transfer** (HQ↔SYP, not customer sale) |
| `src_site=syp` or billno starts with `3` | **syp_store** |
| else | **hq_store** |

Fact packs expose `sources`, per-line `SRC_SITE`, `sales_qty_by_src_5y`, `stock` (HQ+SYP QTYOH2/QTYMIN), `purchase_summary`, `margin`, and `derived` (formulas the model must cite).

## Queryable columns (`product_insights`)

PK stays `(site, bcode)`. Full Thai JSON remains in `insight_json`. Extra columns are for GROUP BY / filters:

| Column | Meaning |
|--------|---------|
| `order_ok` | `yes` / `caution` / `no` — OK to restock as policy (not “PO today vs snap QTYOH”) |
| `order_ok_reason` | Thai/short origin |
| `dead_stock` / `dead_stock_reason` | `yes` / `no` / `maybe` |
| `safe_holding_qty` / `safe_holding_reason` | company target on-hand (UI1) + formula |
| `suggested_order_qty` / `suggested_order_qty_large` | typical PO when *live* stock ≤ `rec_qtymin` (UI1 / UI2 packs) |
| `last_supplier` / `last_buy_price` / `last_buy_date` | from PIMAS |
| `rec_qtymin` / `check_stock` / `stock_anomaly` | ICMAS trigger (~2 weeks demand); snap anomaly is a hint only |
| `qtyoh_hq` / `qtyoh_syp` / `qtymin_hq` / `qtymin_syp` | snapshot context (`facts_as_of`) — stale |
| `rec_transfer_qty_to_syp` / `rec_transfer_reason` | SYP target / typical HQ→SYP batch (not snap-gap) |
| `sales_qty_30d` / `sales_qty_90d` / `sales_qty_12m` | customer qty (HQ+SYP+Online) |
| `trend_30d` / `trend_90d` / `trend_12m` / `trend_label` | `hot` `growing` `flat` `declining` `dead` `lumpy` `seasonal` `unknown` |
| `margin_pct_list` / `margin_pct_12m` / `margin_delta_pp` | percents |
| `margin_flag` | `healthy` `thin` `weak` `negative` `cost_up_price_lag` `unknown` |

```sql
-- cost up, price not adjusted
SELECT bcode, margin_pct_12m, cost_change_pct_12m, price_change_pct_12m, summary
FROM product_insights WHERE margin_flag = 'cost_up_price_lag';

-- declining last 90 days, still ordering
SELECT bcode, trend_90d, order_ok, sales_qty_90d, sales_qty_12m
FROM product_insights WHERE trend_90d = 'declining' AND order_ok = 'yes';

-- negative stock
SELECT bcode, qtyoh_hq, qtyoh_syp, stock_anomaly FROM product_insights
WHERE stock_anomaly = 'negative';
```

## Explorer UI

| State | UI |
|-------|-----|
| Insight exists | Analysis + `generated_at` + `facts_as_of` |
| Queue `pending` / `running` | กำลังสร้าง insight… |
| Not in movers list | ไม่มีการเคลื่อนไหวใน 5 ปี |

Set `PRODUCT_INSIGHTS_DB` in **both** analytic and `kcw-api` `.env` to the same path.

## Timing (GB10 / qwen3.8-27b)

Heavy movers often **~3–4+ min**/job; quieter SKUs can be faster. Prefer **`--concurrency 1`**. Conc 2 barely helps; conc 8 overloads. Steady ~1k due/week @14d ≈ **1–2 Spark-days/week** after catch-up.

## Counts (HQ KSS, 2026-09-13)

ICMAS ~116k · SI∪PI 5y ~**30,925** · 7d movers ~**2,015**

## Out of scope (this phase)

Supabase mirror · systemd unit (optional later) · separate SYP-labelled insight rows · AR/AP insights

SYP **facts** (kss-pc SI/PI) are included in HQ snaps; generation still upserts `site=hq`.
