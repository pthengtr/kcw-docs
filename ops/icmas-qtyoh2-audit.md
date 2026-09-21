# ICMAS QTYOH2 audit (KSS)

Forensic log of every **real** `ICMAS.QTYOH2` change on HQ `PARTS9`, with SQL session source metadata. Built to catch unexplained on-hand drift during stock-check (live OH moves with no SA/SIDET/PIDET).

## Objects (KSS only)

| Object | Role |
|--------|------|
| `dbo.ICMAS_QTYOH2_AUDIT` | Append-only rows: bcode, old/new/delta, login, host, app, program, session |
| `dbo.trg_ICMAS_qtyoh2_audit` | `AFTER UPDATE` on `ICMAS`; fires only when `QTYOH2` is in the SET list **and** the value actually changes |

Does **not** run on SYP. Does **not** enqueue master-sync (that trigger still skips QTY-only updates).

## Install

As SQL admin on KSS:

```bash
cd ~/projects/kcw-api
python scripts/apply_icmas_qtyoh2_audit.py
```

Or manual: `scripts/sql/icmas_qtyoh2_audit.sql` via SSMS / `sqlcmd -E`.

## Source attribution

| Column | Meaning |
|--------|---------|
| `login_name` / `original_login` | SQL principal (`python_writer`, Windows login, …) |
| `host_name` | Client host (`HOST_NAME()`) |
| `app_name` | ODBC `APP=` / `APP_NAME()` — our writers set `kcw-stock-check` / `kcw-transfer` |
| `program_name` / `client_interface` | From `sys.dm_exec_sessions` |
| `also_updated` | Related cols in the same UPDATE (`DATEUPDATE`, `LOCATION*`, …) |

Legacy KACC / other tools usually leave a generic `app_name` (e.g. client exe); login + host still identify the box.

## Query examples

```sql
-- Recent QTYOH2 changes for one barcode
SELECT TOP 50 *
FROM dbo.ICMAS_QTYOH2_AUDIT
WHERE bcode = N'03051277'
ORDER BY changed_at_utc DESC;

-- Unexplained writers: not our tagged apps
SELECT TOP 100 *
FROM dbo.ICMAS_QTYOH2_AUDIT
WHERE changed_at_utc >= DATEADD(day, -7, SYSUTCDATETIME())
  AND (app_name IS NULL OR app_name NOT IN (N'kcw-stock-check', N'kcw-transfer'))
ORDER BY changed_at_utc DESC;
```

## Retention

Table grows with every sale/PO/SA/transfer that touches OH. Purge when needed, e.g. keep 90 days:

```sql
DELETE FROM dbo.ICMAS_QTYOH2_AUDIT
WHERE changed_at_utc < DATEADD(day, -90, SYSUTCDATETIME());
```

## Related

- Stock-check drift / unexplained outcome: [`kcw-api/docs/stock-check.md`](../../kcw-api/docs/stock-check.md)
- Master sync trigger (skips QTY-only): [icmas-master-sync.md](./icmas-master-sync.md)
