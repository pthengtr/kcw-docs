# KCW pending-receive data dictionary (`ICLOW`)

Source of truth for PARTS9 **ค้างรับ** (pending receive) — the legacy report / operator list.

Upstream analytic docs: [`kcw-analytics/docs/parts9_pending_receive.md`](https://github.com/pthengtr/kcw-analytics/blob/main/docs/parts9_pending_receive.md).

Status legend: **Confirmed** · **TBD** · **Inferred**

Last reviewed: 2026-08-03

**Related:** purchase **orders** [`POMAS`/`PODET`](./kcw-po-data-dictionary.md); purchase **invoices** [`PIMAS`/`PIDET`](./kcw-purchase-data-dictionary.md).

---

## 1. Source (Confirmed)

Pending receive comes from **`dbo.ICLOW`** (PARTS9 / KSS HQ).

**Separate from the PO list:** `/po` **รายการ PO** reads `POMAS`/`PODET`; `/po` ICLOW tabs (**รอสั่งซื้อ** / **ค้างรับ** / **รับบางส่วน** / **รับแล้ว**) read `ICLOW` only. Same page, two sources — do not mix membership logic.

It is **not** driven by flags on `POMAS` / `PODET`, and **not** by `PODET.QTY − PIDET.QTY`.

Validated against operator Excel: the filter below returns **616 rows** with matching dates, BCODEs, and qtys (ingested HQ snapshot ≈ **603** — sync lag).

Ingested tables:

| Site | Table |
|------|--------|
| HQ | `raw_kcw.raw_hq_iclow_stock_orders` |
| SYP | `raw_kcw.raw_syp_iclow_stock_orders` |

---

## 2. How PARTS9 marks ค้างรับ

| Field | Pending value | Meaning |
|-------|---------------|---------|
| `ORDERED` | `'Y'` | Ordered against the PO |
| `RECEIVED` | `'N'` (treat null as `'N'`) | Not yet received |
| `CANCELED` | `'N'` (treat null as `'N'`) | Not canceled |

When goods arrive, the app sets:

- `RECEIVED = 'Y'`
- fills `RCVDDATE` / `RCVDNO`

### Canonical pending filter

```sql
SELECT *
FROM dbo.ICLOW
WHERE ORDERED = 'Y'
  AND ISNULL(RECEIVED, 'N') = 'N'
  AND ISNULL(CANCELED, 'N') = 'N';
```

Postgres / Supabase equivalent:

```sql
WHERE "ORDERED" = 'Y'
  AND coalesce("RECEIVED", 'N') = 'N'
  AND coalesce("CANCELED", 'N') = 'N'
```

---

## 3. Do not use as receive indicators

| Field | Why |
|-------|-----|
| `PODET.DONE` / `POMAS.DONE` | Always `'N'` in this DB — unused for receive |
| `PODET.STATUS` | Product status (≈ `ICMAS.STATUS`), not receive state |
| `POMAS.BILLED` / `BILLNO` | Header “billed at least once”; partial bills can still leave other lines pending in `ICLOW` |
| `PODET.QTY − PIDET.QTY` | **Wrong** for ค้างรับ — does not match PARTS9 / operator list |

`BILLED = 'Y'` can coexist with remaining `ICLOW` pending rows on the same PO.

---

## 4. Useful columns on `ICLOW` (Confirmed shape)

Same grain as the legacy report. Observed / used fields include:

| Group | Columns | Notes |
|-------|---------|-------|
| Identity | `ID` | PARTS9 row id (stable key for app list) |
| PO link | `DOCNO`, `DOCDATE` | PO identity when ordered; **null** while still “to be ordered” |
| Vendor | `VENDOR` | Supplier code; join **APMAS** for name (not POMAS) |
| Product | `BCODE`, `DESCR`, `MCODE`, `PCODE` | Match / display |
| Qty | `QTY`, `UI`, `MTP` | Qty on the ICLOW row |
| Order flags | `ORDERED`, `RECEIVED`, `CANCELED` | Receive lifecycle |
| Receive fill | `RCVDDATE`, `RCVDNO` | Set when `RECEIVED = 'Y'` |
| Other | `DONE` | Rare (`X` on a few draft rows) — not used for UI status |

---

## 5. Grain & joins

| Object | Grain |
|--------|-------|
| `ICLOW` row | 1 row ≈ 1 stock-order / receive-tracking line in PARTS9 |

```text
ICLOW  →  APMAS   on  VENDOR = ACCTNO   (vendor name only)
ICLOW  →  product on  BCODE  (ICMAS)     (optional display)
```

Do **not** join `POMAS`/`PODET` for pending-receive membership or list status.

- **ค้างรับ membership** = `ICLOW` alone (§2).
- **`DOCNO` on ICLOW** is the PO number string (same format as `POMAS.DOCNO`) but the pending-receive feature does not read POMAS. Pending rows have no `RCVDNO`.
- **Received link to PI** (when `RECEIVED='Y'`):

```text
Primary (1:1 / left-12):
  ICLOW.RCVDNO   ↔ left(btrim(PIMAS.BILLNO),12)
  PIMAS          → PIDET on BILLNO (BILLTYPE in 1/2/3, not canceled)

Implied BILLNO (not 1:1 — UI: “จับคู่แบบ implied”):
  when primary miss: left(BILLNO,12) equals RCVDNO after stripping spaces
  (e.g. A219623 ↔ "A 219623"). match_method='pattern'.

Fallback PO fingerprint (also implied / not 1:1):
  when still miss: same AP (ICLOW.VENDOR = PIMAS.ACCTNO)
    + PIMAS.PO matches ICLOW.DOCNO via fn_po_docno_key
      (PO6907-579 and 6907-579 are the same key; slash-split multi-PO ok)
    + exact BCODE/qty fingerprint of that RCVDNO on the DOCNO
    + unique best date proximity (RCVDDATE ↔ BILLDATE)
  UI marks these as implied (operator often keys a delivery note
  into PIMAS first, then renames BILLNO to the invoice).
```

Do **not** use `PIMAS.PO` alone for membership/qty — only as this secondary remap signal with AP + line fingerprint.

---

## 6. App status model (`/po` pending tab) — Confirmed design

Operators filter by one of four statuses.

### 6.1 Status rules

Exclude from all buckets:

- `coalesce(CANCELED,'N') = 'Y'`
- `ORDERED = 'X'` (**TBD** — hidden until confirmed)

**Ordered grain = `DOCNO + BCODE`** (sum ICLOW `QTY`).  
**HQ received qty** = sum `PIDET.QTY` joined on distinct `ICLOW.RCVDNO` → `PIDET.BILLNO` + same `BCODE`.  
Legacy PARTS9 truncates `ICLOW.RCVDNO` to **12 chars**; `PIMAS.BILLNO` can be longer and/or padded with spaces.  
Join key: `left(btrim(BILLNO),12) = left(btrim(RCVDNO),12)` (prefer exact `btrim(BILLNO)=RCVDNO` when multiple bills share a key).  
Do **not** use `PIMAS.PO` (unreliable).  
`RECEIVED='Y'` alone is not “fully received” — it means complete **or** partial after the PIDET qty check.

| Status key | Thai (UI) | Grain | Predicate |
|------------|-----------|-------|-----------|
| `to_be_ordered` | รอสั่งซื้อ | line | `ORDERED=N`. `DOCNO` null in practice. |
| `pending_receive` | ค้างรับ | bcode | `ORDERED=Y` and **no** ICLOW row for that DOCNO+BCODE has `RECEIVED='Y'`. |
| `partially_received` | รับบางส่วน | bcode | Any `RECEIVED='Y'` on DOCNO+BCODE; received qty from bill lines **&lt;** ordered qty. HQ: `PIMAS`/`PIDET` via `RCVDNO`. SYP: HQ TF `SIMas`/`SIDet` via `RCVDNO` **∪** REMARKS-matched follow-up TF/TFV. Do **not** use `PIMAS.PO`. |
| `complete` | รับแล้ว | bcode | Any `RECEIVED='Y'` and received qty **≥** ordered qty. |

**SYP `received_qty`** = sum distinct `SIDet.QTY` for that `BCODE` over the union of:

1. TF bills from `ICLOW.RCVDNO` → `left(btrim(SIMas.BILLNO),12)` (first receive)
2. HQ TF/TFV bills whose `REMARKS` match the SYP `DOCNO` via `fn_po_syp_tf_bills_by_docno()` (same pattern as prepare — e.g. `1PO6906-388##…`)

Membership still requires any ICLOW `RECEIVED='Y'` (a REMARKS-only TF does not invent rows). Same complete/partial/pending split as HQ; do **not** use ICLOW `RECEIVED` qty alone or `PIMAS.PO`.

**Clear SYP รับบางส่วน (backorder):** HQ opens a follow-up TF/TFV for the same SYP PO (`DOCNO` in `REMARKS`) covering the missing BCODE qty → sync (`อัปเดตข้อมูล`) → when summed SIDet ≥ ordered, the line becomes `complete` and drops off รับบางส่วน. Will-not-ship remainder: cancel/reduce that ICLOW line in PARTS9, then sync.

### 6.2 Document links (UI)

No mixed missing/received breakdown dialog. On ICLOW tabs:

| Click | Opens |
|-------|--------|
| **DOCNO** (SYP) | Same as รายการ PO — `PoSypDetailDialog` via `GET /api/po/syp/[docno]` (prepare badges, TF billnos, print) |
| **DOCNO** (HQ) | PO lines — `GET /api/po/hq/[docno]` |
| **RCVDNO** (HQ, exact / left-12) | Purchase invoice — `GET /api/po/pi/[billno]` |
| **RCVDNO** with `(จับคู่แบบ implied ไม่ใช่ 1:1 → {BILLNO})` | Implied remap (space-normalized BILLNO or AP+PO key+fingerprint); click opens resolved invoice |
| **RCVDNO** with `(ไม่พบลิงก์ PIMAS)` | Not clickable |

Legacy RPC `fn_po_pending_receive_detail` / `GET /api/po/pending-receive/[docno]` may still exist but is unused by the simplified UI.

### 6.3 Notes

- Do **not** use mixed-DOCNO sibling logic for รับบางส่วน.
- Do **not** use `PIMAS.PO` or `PODET.QTY − PIDET.QTY` for membership.
- Default UI filter: **`pending_receive`**.
- `complete` / `partially_received` / `pending_receive` keep a date window on `DOCDATE` (UI default: **last 30 days**; quick presets: 60d / 3m / 6m / 1y).
- `to_be_ordered` has **no** date filter (`DOCDATE` is usually null on those ICLOW rows).
- รายการ PO (HQ/SYP) uses the same lookback presets on `POMAS.DOCDATE`.

### 6.4 Observed HQ counts (ingested snapshot 2026-08-01)

| Bucket | ≈ |
|--------|--:|
| `to_be_ordered` (lines) | 274 |
| `pending_receive` (bcode) | (no RECEIVED=Y) |
| `partially_received` (bcode) | RECEIVED=Y and PIDET via RCVDNO incomplete |
| `complete` (bcode) | RECEIVED=Y and PIDET via RCVDNO covers ordered qty |
| `ORDERED='X'` (hidden) | 60 |

### 6.5 API / RPC

| Piece | Contract |
|-------|----------|
| List RPC | `public.fn_po_pending_receive` (SYP: BCODE-level `prepare_status` / `prepared_qty` / `prepare_tf_billnos`; optional `p_prepare` filter) |
| List API | `GET /api/po/pending-receive?site=&status=` |
| PO lines API | `GET /api/po/hq/[docno]` · `GET /api/po/syp/[docno]` |
| PI detail API | `GET /api/po/pi/[billno]` (RCVDNO → PIMAS/PIDET) |
| SYP TF bills by DOCNO | `public.fn_po_syp_tf_bills_by_docno()` (REMARKS → DOCNO; shared with prepare) |
| PO / DOCNO key | `public.fn_po_docno_key(text)` — `PO6907-579` ≡ `6907-579` for implied PO match |
| Legacy detail RPC | `public.fn_po_pending_receive_detail` (unused by UI) |
| SQL | [`sql/fn_po_pending_receive.sql`](./sql/fn_po_pending_receive.sql) |

---

## 7. Supabase / app status

| Topic | Status |
|-------|--------|
| Source | PARTS9 `dbo.ICLOW` (HQ / KSS) — Confirmed |
| SYP `ICLOW` | Confirmed ingested (`raw_syp_iclow_stock_orders`) |
| Ingest into `raw_kcw` | Confirmed — `raw_{hq\|syp}_iclow_stock_orders` |
| App list | Wire `/po` pending tab to ICLOW + §6 statuses |
| `ORDERED='X'` meaning | TBD |

---

## 8. Changelog

| Date | Change | By |
|------|--------|-----|
| 2026-08-03 | Link upstream `kcw-analytics/docs/parts9_pending_receive.md` | Agent |
| 2026-08-02 | HQ implied match: space-normalized BILLNO + `fn_po_docno_key` (PO6907-579 ≡ 6907-579); UI “จับคู่แบบ implied” | Agent |
| 2026-08-02 | SYP รับบางส่วน: union RCVDNO TF + REMARKS follow-up TF (`fn_po_syp_tf_bills_by_docno`); clear backorder when SIDet covers ordered | Agent |
| 2026-08-02 | HQ fallback: pattern remap RCVDNO→PIMAS via AP+PO+BCODE/qty; UI remark “ไม่ใช่ 1:1” | Agent |
| 2026-08-01 | Perf: date-filter ICLOW early; skip PIDET for ค้างรับ; resolve RCVDNO→BILLNO once + indexes | Agent |
| 2026-08-01 | Normalize PIMAS BILLNO with `btrim` + `left(...,12)` before RCVDNO join (leading spaces) | Agent |
| 2026-08-01 | Default ICLOW dated tabs to last 30 days (avoid 12‑month statement timeouts) | Agent |
| 2026-08-01 | Simplify UI: DOCNO→POMAS/PODET, RCVDNO→PIMAS/PIDET; drop partial missing/received dialog | Agent |
| 2026-08-01 | Match truncated RCVDNO via `left(PIMAS.BILLNO,12)` (legacy 12-char ICLOW field) | Agent |
| 2026-08-01 | UI shows `(ไม่พบลิงก์ PIMAS)` when ICLOW.RCVDNO has no matching ingested PIMAS bill | Agent |
| 2026-08-01 | BCODE grain: RECEIVED=Y → complete/partial via RCVDNO→PIDET qty; drop mixed DOCNO + PIMAS.PO | Agent |
| 2026-08-01 | `partially_received` = ICLOW line rows on mixed DOCNO with receive_state + PIMAS BILLNO | Agent |
| 2026-08-01 | Document PARTS9 ค้างรับ = `ICLOW` (`ORDERED=Y`, `RECEIVED=N`, `CANCELED=N`); match Excel 616 rows | Owner |
| 2026-08-01 | Confirm ingest tables; define `/po` four-status design; reject PODET−PIDET for membership | Agent |
| 2026-08-01 | รับบางส่วน = ICLOW DOCNO group with mixed receive; detail via `RCVDNO→PIDET`; no POMAS join | Agent |
