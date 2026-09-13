# Product insights (Spark + local SQLite)

HQ pipeline: **snapshot PARTS9 → Spark analysis → local SQLite → Explorer panel**.

Analysis-only (trend, channel mix, anomalies, dead/slow, demand/cover). **No** live QTYOH advice. **No** Supabase this phase. **No** recurring timer yet.

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

1. `insight-snapshot --site hq` → ICMAS + SIDET + SIMAS fields + PIDET → stamp `facts_as_of`
2. Build queue: BCODEs with SI/PI inside `--window` from snap time; score = SI+PI lines; **sort DESC**
3. `insight-generate --snap latest --window 5y [--limit N] [--concurrency 2] [--resume]`
4. Per BCODE: fact pack (no QTYOH*) + channel legend → Spark → upsert insights; mark queue `done`
5. Explorer: ready / working / no 5y movement

## CLI

```bash
cd ~/projects/kcw-analytic
source .venv/bin/activate   # or .venv/bin/python

# create snap (always first)
python -m src.kcw.pipeline insight-snapshot --site hq

# bench top 10 (predict full runtime)
python -m src.kcw.pipeline insight-generate --snap latest --window 5y --limit 10 --concurrency 2

# full first generation (resume-safe)
python -m src.kcw.pipeline insight-generate --snap latest --window 5y --concurrency 2 --resume

# later manual delta
python -m src.kcw.pipeline insight-generate --snap latest --window 14d --resume
```

| Flag | Purpose |
|------|---------|
| `--snap` | Snapshot id or `latest` |
| `--window` | Queue lookback from snap time: `5y`, `14d`, `2w` |
| `--limit N` | Top-N by movement (bench) |
| `--concurrency` | Parallel Spark calls (1–3) |
| `--resume` | Skip queue rows already `done` (default: on) |
| `--no-resume` | Rebuild pending from window |

Fact history in the prompt prefers **full snap history** for that BCODE (snap holds ~5y), even when `--window` is `14d`.

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
| In queue, pending | กำลังสร้าง insight… |
| Not in movers list | ไม่มีการเคลื่อนไหวใน 5 ปี |

Set `PRODUCT_INSIGHTS_DB` in **both** analytic and `kcw-api` `.env` to the same path.

## Timing (samples on qwen3.8-27b)

~40–70s+ per product. Conc 2–3. Full ~31k SI∪PI ≈ **1–2 weeks** 24/7. Always bench with `--limit 10` first.

## Counts (HQ KSS, 2026-09-13)

ICMAS ~116k · SI∪PI 5y ~**30,925**

## Out of scope (this phase)

Supabase mirror · systemd schedule · auto daily delta · SYP generation · AR/AP insights
