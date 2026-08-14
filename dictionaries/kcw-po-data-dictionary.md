# KCW purchase-order data dictionary (POMAS / PODET)

Naming and join rules for **purchase orders** in KACC PARTS9 (HQ / KSS).

Status legend: **Confirmed** · **TBD** · **Inferred**

Last reviewed: 2026-07-28

---

## 1. Source

| Fact | Status |
|------|--------|
| System DB: SQL Server `KSS` → database **`PARTS9`** (HQ) | Confirmed |
| PO header table: `dbo.POMAS` | Confirmed |
| PO line table: `dbo.PODET` | Confirmed |
| Related receive/invoice: `dbo.PIMAS` / `dbo.PIDET` (not PO) | Confirmed |
| `dbo.SAPOS` = cash-register POS — **unrelated**, empty | Confirmed |
| Ingested into Supabase `raw_kcw` via worker job `sync_pomas_podet` (HQ-PC + SYP-PC) | Confirmed (2026-07-27) |
| HQ tables: `raw_hq_pomas_purchase_orders`, `raw_hq_podet_purchase_order_lines` (+ `_stg`) | Confirmed |
| SYP tables: `raw_syp_pomas_purchase_orders`, `raw_syp_podet_purchase_order_lines` (+ `_stg`) | Confirmed |
| Last sync signal: `max(_ingested_at)` on each header table | Confirmed |
| SYP open POs are HQ→SYP transfers (vendor = HQ / เกียรติชัย) | Confirmed |

Row counts (local PARTS9 as of 2026-07-28):

| Table | Role | Rows |
|-------|------|-----:|
| `POMAS` | PO header | 64,213 |
| `PODET` | PO lines | 250,865 |
| `PIMAS` | Purchase invoice header | 88,026 |
| `PIDET` | Purchase invoice lines | 264,468 |

`POMAS.DOCDATE` range observed: **2016-04-20 → 2026-07-27**.

---

## 2. Grain & joins (Confirmed)

| Object | Grain |
|--------|-------|
| `POMAS` | 1 row ≈ 1 purchase order |
| `PODET` | 1 row ≈ 1 PO line |

```text
POMAS  ←→  PODET   on  DOCNO
POMAS  ←→  PIMAS   on  PIMAS.PO = POMAS.DOCNO   (when billed / received)
PIMAS  ←→  PIDET   on  BILLNO (purchase invoice — see purchase dictionary)
```

### Critical naming

| Field | Meaning | Status |
|-------|---------|--------|
| **`POMAS.DOCNO`** | **The PO number** | Confirmed |
| `POMAS.PO` | Always empty in PARTS9 — **do not use** as PO id | Confirmed |
| `POMAS.BILLNO` / `BILLDATE` | Linked purchase-invoice ref when billed | Confirmed |
| `PIMAS.PO` | Points back to **`POMAS.DOCNO`** | Confirmed |

Notes:

- One PO can map to **multiple** purchase invoices (`PIMAS.PO = POMAS.DOCNO`).
- All billed POs (`BILLED='Y'`, n≈7,810) have non-empty `BILLNO` and join to `PIMAS`.
- Integrity: ~25 headers with no lines; **0** orphan detail rows.
- Slight `DOCNO` duplication in headers (~64,213 rows vs ~63,975 distinct `DOCNO`) — prefer latest / de-dupe before reporting.

---

## 3. `DOCNO` format (Confirmed)

Dominant pattern: **`POYYMM-NNN`** with **Buddhist year** (BE).

| Example | Meaning |
|---------|---------|
| `PO6907-927` | July **2026** (BE 2569 → `69`), sequence 927 |

Almost all active rows use `PO6…` prefix (~62.7k of 64k). Older/noisy prefixes exist from 2016–2017.

```sql
-- BE year in positions 3–4 of DOCNO (after 'PO')
-- CE year ≈ BE + 543 only when converting calendars; here YY is already BE century digits
```

---

## 4. Status flags — `POMAS` (Confirmed)

| Flag | Values in practice | BI meaning |
|------|--------------------|------------|
| **`BILLED`** | `Y` ≈ 7,810 · `N` ≈ 56,395 | **`Y`** = received/invoiced (has `BILLNO`); **`N`** = open / not yet billed |
| `CANCELED` | effectively all `N` | Unused in practice |
| `DONE` | effectively all `N` | Unused in practice |
| `JOURMODE` | almost all `1` | Little variation on POs (unlike PIDET 1/2 VAT split) |

Open PO working set:

```text
open_po = ISNULL(CANCELED,'') <> 'Y' AND BILLED = 'N'
```

---

## 5. Column map

### 5.1 `POMAS` (header)

| Group | Columns | Notes |
|-------|---------|-------|
| Identity | `ID` (PK), `JOURMODE`, `DOCDATE`, `DOCNO`, `LINES` | PO id = `DOCNO` |
| Amounts | `TAXIC`, `DISCOUNT`, `DEDUCT`, `BEFORETAX`, `VAT`, `TAX`, `AFTERTAX`, `EXEMPT` | Same naming family as sales/PI bills; VAT rules TBD for PO |
| Vendor | `ACCTNO`, `ACCTNAME`, `ADDR1`, `ADDR2`, `ATTN` | Join AP master on `ACCTNO` |
| Meta | `SUBJECT`, `PO` (**empty**), `SALE`, `SANAME`, `SATITLE`, `RE`, `TERM`, `STAND`, `DELIVER`, `COVER`, `REMARKS`, `LANG` | |
| Fulfillment | `BILLDATE`, `BILLNO`, `BILLED` | Invoice link when `BILLED=Y` |
| Flags | `CANCELED`, `DONE` | Unused in practice |

### 5.2 `PODET` (lines)

| Group | Columns | Notes |
|-------|---------|-------|
| Keys | `ID` (PK), `JOURMODE`, `DOCDATE`, `DOCNO`, `LINE`, `ITEMNO` | Join header on `DOCNO` |
| Product | `BCODE`, `PCODE`, `MCODE`, `DETAIL`, `WHNUMBER`, `LOCATION1` | Same product codes as ICMAS / PIDET |
| Qty / price | `QTY`, `UI`, `MTP`, `PRICE`, `XPRICE`, `DISCNT1–4`, `DED`, `AMOUNT` | MTP = pack→small-unit multiplier (same family as sales/PIDET) |
| Tax / status | `STATUS`, `SERIAL`, `TAXIC`, `EXMPT`, `ACCT_NO`, `CANCELED`, `DONE` | Line `ACCT_NO` role TBD (cf. sales line `ACCT_NO`) |

Avg ~3.9 lines per PO (min 1, max 304).

---

## 6. Indexes / performance (Confirmed)

| Table | Indexes |
|-------|---------|
| `POMAS` | PK on `ID`; nonunique `(DOCDATE, DOCNO, CANCELED, DONE)` |
| `PODET` | PK on `ID`; nonunique on `ACCT_NO` only — **no index on `DOCNO`** |

PO header↔line joins on `DOCNO` can be slow at full scan; consider ingest + index in Supabase if used heavily.

---

## 7. Practical query (source SQL Server)

```sql
SELECT h.DOCNO, h.DOCDATE, h.ACCTNO, h.ACCTNAME,
       h.BEFORETAX, h.TAX, h.AFTERTAX, h.BILLED, h.BILLNO, h.BILLDATE,
       d.LINE, d.ITEMNO, d.BCODE, d.DETAIL, d.QTY, d.UI, d.MTP, d.PRICE, d.AMOUNT
FROM dbo.POMAS h
JOIN dbo.PODET d ON d.DOCNO = h.DOCNO
WHERE ISNULL(h.CANCELED, '') <> 'Y';
```

---

## 8. Relation to purchase invoices (PIDET) & BI

| Topic | Rule | Status |
|-------|------|--------|
| PO vs PI | **PO** = order (`POMAS`/`PODET`); **PI** = received bill (`PIMAS`/`PIDET`) | Confirmed |
| Stock / last purchase | Product-movement BI uses **PIDET** receive lines, not open POs | Confirmed (see [purchase dictionary](./kcw-purchase-data-dictionary.md)) |
| Open commitments (header) | Use `POMAS`/`PODET` where `BILLED='N'` for “open PO” lists — **not** the same as line ค้างรับ | Confirmed pattern |
| Vendor | `POMAS.ACCTNO` → APMAS / `party` supplier | Inferred |
| Supabase raw | `raw_kcw.raw_{hq\|syp}_pomas_purchase_orders` + `raw_{hq\|syp}_podet_purchase_order_lines` | Confirmed |
| Sync job | `sync_pomas_podet` — see [worker-jobs.md](https://github.com/pthengtr/kcw-v2/blob/master/docs/worker-jobs.md); enqueue via `ops.job_queue` | Confirmed |
| App list API | `fn_po_list` / `fn_po_last_ingested_at` (service-role); open partial indexes on POMAS | Confirmed |
| **Pending receive (ค้างรับ)** | **`ICLOW`** — `ORDERED='Y'` AND `RECEIVED='N'` AND `CANCELED='N'`. See [ICLOW dictionary](./kcw-iclow-pending-receive-data-dictionary.md) | Confirmed |
| App prepare overlay (SYP only) | `public.po_syp_prepare` — webapp marks prepared for HQ→SYP transfer; not PARTS9 | Confirmed |
| HQ vs SYP product meaning | **HQ** = open POs to external vendors; **SYP** = orders on HQ (transfer prep) | Confirmed |

Do **not** confuse sales-bill column `"PO"` (CN original bill / TAD txn id — sales dictionary §6.8) with PARTS9 purchase-order `DOCNO`.

---

## 9. Open questions

- [x] PO number = `DOCNO` (not `POMAS.PO`) — Confirmed
- [x] Header↔line join = `DOCNO`; PI link = `PIMAS.PO = POMAS.DOCNO` — Confirmed
- [x] `BILLED` Y/N = invoiced vs open — Confirmed
- [x] Ingest path into `raw_kcw` via `sync_pomas_podet` — Confirmed
- [ ] How to de-dupe rare duplicate `DOCNO` headers
- [ ] PO-level VAT/`TAXIC`/`BEFORETAX` rules (mirror PIDET/sales or different?)
- [ ] Whether open-PO qty should use `QTY*MTP` like sales/PIDET
- [ ] Curated open-PO fact (optional; v1 reads raw)
- [x] Line ค้างรับ source = `ICLOW` — Confirmed 2026-08-01
- [x] Ingest `ICLOW` → `raw_kcw.raw_{hq|syp}_iclow_stock_orders` — Confirmed
- [x] Wire `/po` pending-receive UI to ICLOW four-status list (`fn_po_pending_receive`)

---

## 10. Changelog

| Date | Change | By |
|------|--------|----|
| 2026-07-28 | Start PO dictionary from PARTS9 `POMAS`/`PODET` inspection | Owner |
| 2026-07-28 | Mark `raw_kcw` ingest Confirmed (`sync_pomas_podet`); SYP = HQ→SYP transfer; note `po_syp_prepare` | Owner |
| 2026-08-01 | Pending receive (ค้างรับ) = `ICLOW`; link [ICLOW dictionary](./kcw-iclow-pending-receive-data-dictionary.md) | Owner |
| 2026-08-01 | Confirm ICLOW ingest tables; `/po` pending tab uses four ICLOW statuses | Agent |
