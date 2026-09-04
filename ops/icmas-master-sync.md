# HQ → SYP ICMAS product-master sync

Push product catalog fields from **HQ PARTS9** (`KSS`) to **SYP PARTS9** (`kss-pc`), without touching branch stock or bins.

## Architecture (live + weekly safety)

```text
HQ ICMAS INSERT / master-col UPDATE
  → trigger → dbo.ICMAS_MASTER_SYNC_QUEUE on KSS
  → hq-ubuntu poller every 2 min → INSERT/UPDATE SYP ICMAS
Weekly Sunday 05:30 → full dry-run drift report (no writes)
```

| Path | Role |
|------|------|
| **Queue + poller** | Near-real-time for changed / new SKUs |
| **Weekly dry-run** | Safety net + proof of alignment (`added=0 updated=0`) |

HQ POS never waits on SYP: the trigger only writes a local queue row.

## Rules

| Direction | Behavior |
|-----------|----------|
| HQ → SYP | Master fields: `DESCR`, codes, packs (`UI*`/`MTP*`), prices, costs list (`COSTNET`/`COSTSET*`), `CANCELED`, … |
| Never overwrite on SYP | All `QTY*`, `LOCATION1`/`LOCATION2`, `STOCKNO`, sale/audit dates, `COSTAVG`/`COSTLAST` |
| SYP-only BCODE | Leave untouched; listed in report as `syp_only` |
| New HQ SKU | INSERT on SYP with qty/locations zeroed/blank (not HQ on-hand) |

HQ is the product master for catalog attrs on the same `BCODE`.

## One-time setup on KSS (HQ)

Run as SQL admin on **KSS** / `PARTS9` (from hq-ubuntu this is `KSS_SMB_USER=Administrator` via WinRM + `sqlcmd -E`, or SSMS on the box):

[`kcw-analytic/scripts/sql/icmas_master_sync_queue.sql`](../../kcw-analytic/scripts/sql/icmas_master_sync_queue.sql)

(also copied under `kcw-api/scripts/sql/`).

Creates:

- `dbo.ICMAS_MASTER_SYNC_QUEUE`
- trigger `dbo.trg_ICMAS_master_sync_queue` (skips QTY*/LOCATION*-only updates)
- grants for `python_writer` on the queue

On **kss-pc** (already done for full sync):

```sql
GRANT SELECT, INSERT, UPDATE ON dbo.ICMAS TO [python_writer];
```

## Where it runs

**Only on `hq-ubuntu-server`.** Do not schedule on SYP Ubuntu.

## Commands

```bash
# Live path — drain queue (timer runs this every 2 min)
python -m src.kcw.pipeline sync-icmas-master-queue
python -m src.kcw.pipeline sync-icmas-master-queue --limit 500

# Full catalog dry-run / apply (manual or weekly timer)
python -m src.kcw.pipeline sync-icmas-master
python -m src.kcw.pipeline sync-icmas-master --apply
```

Shell wrappers:

```bash
worker_tasks/linux/sync_icmas_master_queue.sh
worker_tasks/linux/sync_icmas_master.sh
```

## Schedulers (systemd user units on HQ)

```bash
cp ~/projects/kcw-analytic/scripts/kcw-icmas-master-queue.{service,timer} ~/.config/systemd/user/
cp ~/projects/kcw-analytic/scripts/kcw-icmas-master-sync.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now kcw-icmas-master-queue.timer   # every 2 min
systemctl --user enable --now kcw-icmas-master-sync.timer    # Sun 05:30 dry-run
systemctl --user list-timers | grep icmas
```

| Unit | When | Action |
|------|------|--------|
| `kcw-icmas-master-queue.timer` | every 2 min | Drain queue → SYP |
| `kcw-icmas-master-sync.timer` | Sunday 05:30 | Full dry-run report |

## Reports / history

Full sync runs write under `logs/icmas_master_sync/` (+ Drive `KCW-Data/ops/icmas_master_sync/`). Queue polls skip Drive mirror by default (high frequency).

## Credentials

- Readers: `PARTS9_HQ_*` / `PARTS9_SYP_*`
- Writers: `POS_MSSQL_WRITER_USERNAME` / `PASSWORD` (HQ queue mark-done + SYP apply)

## Verify after trigger install

1. On HQ, change a master field (e.g. `DESCR`) on a test `BCODE` in KACC/SSMS.
2. `SELECT TOP 5 * FROM dbo.ICMAS_MASTER_SYNC_QUEUE ORDER BY queue_id DESC` — should show `pending`.
3. Wait ≤2 min (or run `sync-icmas-master-queue` once) — row → `done`, SYP matches.
4. Confirm SYP `QTYOH2` / `LOCATION*` unchanged.
5. Weekly dry-run should stay `added=0 updated=0` (aside from intentional SYP-only SKUs).
