# KCW cheque / transfer register data dictionary (`BRDET` / `BPDET`)

Source of truth for PARTS9 **ทะเบียนเช็ครับ** / **ทะเบียนเช็คจ่าย** — bank instrument lines (real cheques **or** transfers / other methods).

Upstream analytic docs: [`kcw-analytics/docs/parts9_cheque_transfers.md`](https://github.com/pthengtr/kcw-analytics/blob/main/docs/parts9_cheque_transfers.md).

Status legend: **Confirmed** · **TBD** · **Inferred**

Last reviewed: 2026-08-03

**Related:** bank statement upload ([worker-jobs](https://github.com/pthengtr/kcw-v2/blob/master/docs/worker-jobs.md#bank-statement-upload-from-bank-statement-sync-kcw-v2--not-a-pc-worker-job)); payment vouchers `PVMAS` / receipt vouchers `RVMAS`; purchase bills [`PIMAS`](./kcw-purchase-data-dictionary.md).

---

## 1. Source (Confirmed)

| Report | Excel (example) | PARTS9 table |
|--------|-----------------|--------------|
| ทะเบียนเช็ครับ | `07_temp/ทะเบียนเช็ครับ.xls` | **`dbo.BRDET`** |
| ทะเบียนเช็คจ่าย | `07_temp/ทะเบียนเช็คจ่าย.xls` | **`dbo.BPDET`** |

Sheet: `Report`. Export period is in the title row (e.g. ประจำเดือน กรกฎาคม 2569).

Despite the Thai name “เช็ค”, each row is a **bank instrument line**: either a real **cheque**, or a **transfer / other method**. Discriminate with `CHKNO` (§3).

**HQ only** — not in the SYP minimal extract. Connection: PARTS9 on KSS via `mssql_engine("hq")` (`.env` `KSS_*` / `PARTS9_HQ_*`).

Ingested tables:

| Direction | Drive CSV | Supabase |
|-----------|-----------|----------|
| In (รับ) | `raw_hq_brdet_cheques_received.csv` | `raw_kcw.raw_hq_brdet_cheques_received` (+ `_stg`) |
| Out (จ่าย) | `raw_hq_bpdet_cheques_paid.csv` | `raw_kcw.raw_hq_bpdet_cheques_paid` (+ `_stg`) |

DDL reference: [`sql/create_raw_hq_brdet_bpdet.sql`](./sql/create_raw_hq_brdet_bpdet.sql).

---

## 2. Not the same as voucher headers

These registers are **not** `RVMAS` / `PVMAS` alone.

| Direction | Detail table | Typical voucher headers |
|-----------|--------------|-------------------------|
| In (รับ) | `BRDET` | Often `TR*` / sales-linked; not always present as `RVMAS.VOUCNO` |
| Out (จ่าย) | `BPDET` | Often linked to `PVMAS.VOUCNO` (e.g. `KCPN*`) |

Related but different:

| Table | Role |
|-------|------|
| `PVMAS` / `RVMAS` | Payment / receipt voucher **headers** (totals, AP/AR account) |
| `BKTRNS` | Bank statement / reconciliation lines (PARTS9) |
| `CHMAS` | Chart / bank **account master** (`TASK='BK'`, accounts like `2101.x`) — not register lines |
| `bank.statement_*` | Drive bank Excel import (KBANK/KTB) used by `/bank-statement-sync` |

### Validation (July 2026 export)

Against Drive Excel vs HQ PARTS9:

- ทะเบียนเช็ครับ ↔ `BRDET` on `VOUCNO` + `CHKAMT`: **exact match** (after dropping repeated header rows in the xls)
- ทะเบียนเช็คจ่าย ↔ `BPDET` on `VOUCNO` + `CHKAMT`: **exact match**

---

## 3. Cheque vs transfer (`CHKNO`) (Confirmed)

`CHKNO` is free text. There is **no reliable separate “is_cheque” flag**; use the value itself:

| `CHKNO` looks like… | Treat as | Examples |
|---------------------|----------|----------|
| Numeric / cheque-style id | **Cheque number** | `10102934`, `8033176` |
| Method / channel label | **Not a cheque** (transfer, shop, cash, …) | `โอน`, `KSHOP`, `จ่ายสด(กรรมการ)` |

`PAYTYPE` exists (`1` / `2`) but does **not** cleanly mean cheque vs transfer — both methods appear under both values. Prefer `CHKNO` for classification.

---

## 4. Useful columns (Confirmed shape)

BRDET and BPDET share the same shape:

| Column | Role |
|--------|------|
| `VOUCDATE`, `VOUCNO` | Voucher date / number (Excel “วันที่” / “เลขที่ใบสำคัญ…”) |
| `ACCTNO` | Bank / GL account when filled (e.g. `2101.1`) |
| `CARDNAME` | On receive rows often holds the bank account code (e.g. `2101.4`) when `ACCTNO` is blank |
| `PAYTYPE` | Internal pay-type code (do not use alone for cheque vs transfer) |
| **`CHKNO`** | Cheque number **or** method label (`โอน`, `KSHOP`, …) |
| `CHKDATE` | Instrument date (“ลงวันที่”) |
| `CHKAMT` | Amount |
| `BANKNAME` | Bank description (often includes account #) |
| `JOURTYPE` | e.g. `SJ`/`CR` (receive), `CP`/`PJ` (pay) |
| `STATUS` | Clearing-ish marker when set (e.g. `=`) |
| `CANCELED`, `DONE` | Cancel / done flags |

### Excel ↔ DB map

| Excel | DB |
|-------|-----|
| วันที่ | `VOUCDATE` |
| เลขที่ใบสำคัญรับ / จ่าย | `VOUCNO` |
| รหัสบัญชี | `ACCTNO` (or `CARDNAME` on some receive rows) |
| หมายเลขเช็ค | `CHKNO` |
| ลงวันที่ | `CHKDATE` |
| ชื่อธนาคาร | `BANKNAME` |
| จำนวนเงิน | `CHKAMT` |

---

## 5. Examples

Outbound cheque:

- `BPDET.VOUCNO = KCPN6907-011`, `CHKNO = 10102934`, `CHKAMT = 287426.30`
- Header also in `PVMAS` (same `VOUCNO`, `CHKAMT`)

Inbound transfer-style:

- `BRDET.VOUCNO = TR6907-004`, `CHKNO = KSHOP`, `BANKNAME = KBANK … #0648917236`, `CHKAMT = 2400`

---

## 6. Pipeline / worker sync (Confirmed)

### Daily HQ A pipeline

Included in full HQ extract (`TABLE_SPECS`) and `upload-daily-raw` (analytic CLI):

```bash
python -m src.kcw.pipeline extract --site hq
python -m src.kcw.pipeline upload-daily-raw
```

### Focused sync

```bash
python -m src.kcw.pipeline sync-brdet-bpdet
python -m src.kcw.pipeline upload-brdet-bpdet
```

### Daily bank sync (`bank_statement_import` — HQ-PC only)

[`run_bank_statement_import.bat`](https://github.com/pthengtr/kcw-analytics/blob/main/worker_tasks/run_bank_statement_import.bat) on **HQ** does:

1. HQ BRDET/BPDET → Drive + `raw_kcw` (via `run_hq_brdet_bpdet_sync.bat`)
2. Drive `01_raw/statement` Excel (KBANK + KTB) → `bank.statement_*`

kcw-v2 **อัปโหลด Statement** calls Edge Function `import-bank-statement` in this repo (`auto_v2` fingerprints, RBAC `bank_statement_sync` or service-role for Drive bulk; no `ops.job_queue`). The daily HQ BAT refreshes BRDET/BPDET then uploads Drive Excel via the same Edge Function — see [worker-jobs](https://github.com/pthengtr/kcw-v2/blob/master/docs/worker-jobs.md#bank-statement-upload-from-bank-statement-sync-kcw-v2--not-a-pc-worker-job).

Focused cheque-only BAT (no statement Excel): `run_hq_brdet_bpdet_sync.bat` (not exposed as a separate web button yet).

---

## 7. App usage (TBD / Inferred)

| Consumer | Status |
|----------|--------|
| `/bank-statement-sync` statement lines + chat-agent match prompts | Use `bank.statement_*`; match prompts may later join BRDET/BPDET for cheque clears |
| BI dashboards | No dedicated BRDET/BPDET report yet |
| Expense / payroll match (account 6184) | Currently prefers `PIMAS` / PVMAS paths — BRDET/BPDET are the PARTS9 register grain for the same instruments |

---

## Changelog

| Date | Change | Who |
|------|--------|-----|
| 2026-08-03 | Integrate analytic `parts9_cheque_transfers` + bank BAT includes BRDET/BPDET; HQ-only enqueue | Agent |
