# Product insights (Spark + local SQLite)

HQ pipeline: **snapshot PARTS9 → Spark analysis → local SQLite → Explorer panel**.

Analysis-only (trend, channel mix, anomalies, dead/slow, demand/cover). **No** live QTYOH advice. **No** Supabase this phase.

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

1. Snapshot PARTS9 → local snap (`facts_as_of`)
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
python -m src.kcw.pipeline insight-snapshot --site hq
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

## Channel mapping (live KSS)

PARTS9 has no `BILLTYPE_STD`. Derive from **billno prefix** + `JOURMODE`:

| Rule | Channel |
|------|---------|
| `JOURMODE=0` | excluded |
| `TAD*` / `CNTAD*` | **online** |
| `TF*` / `TFV*` / `CNTF*` | **transfer** (HQ↔SYP, not customer sale) |
| else | **hq_store** (or syp-ish if billno starts with `3`) |

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

Supabase mirror · systemd unit (optional later) · SYP generation · AR/AP insights
