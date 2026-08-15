# KCW notes / payment vouchers data dictionary (`PVMAS` / `RVMAS`)

Source of truth for PARTS9 **โน้ตจ่าย** (notes payable) and **ใบสำคัญจ่าย** (payment vouchers), plus the receipt twin.

There is **no separate note table**. Notes and vouchers are **stages of the same header row** in `dbo.PVMAS` (pay) / `dbo.RVMAS` (receive). There is **no `PVDET`** line table.

Status legend: **Confirmed** · **TBD** · **Inferred**

Last reviewed: 2026-08-16 (HQ `KSS` / `PARTS9` live counts)

**Related:** purchase bills [`PIMAS`](./kcw-purchase-data-dictionary.md); cheque/transfer register [`BPDET`/`BRDET`](./kcw-brdet-bpdet-cheque-transfers-data-dictionary.md); sales bills [`SIMAS`](./kcw-sales-data-dictionary.md) (AR note/voucher columns, same names).

---

## 1. Scope (Confirmed)

| Fact | Status |
|------|--------|
| Grain: 1 `PVMAS` row = 1 pay note and/or 1 payment voucher header | Confirmed |
| Note is issued **before** the voucher (`NOTED` then `VOUCED`) | Confirmed |
| Note-only rows exist (`NOTENO` filled, `VOUCNO` empty) | Confirmed — HQ 2,135 of 14,563 `PVMAS` (2026-08-16) |
| `NOTENO` is the **supplier’s note / bill-ref** (free text), not a PARTS9 document series | Confirmed |
| Related purchase bills live on `PIMAS`, not on `PVMAS` | Confirmed |
| Cheque/transfer instruments for a **vouchered** pay live on `BPDET.VOUCNO` | Confirmed |
| HQ extract: `raw_hq_pvmas_notes_vouchers` / `raw_hq_rvmas_notes_vouchers` | Confirmed |
| Explorer search must match **both** `VOUCNO` and `NOTENO` | Confirmed (2026-08-16) |

`JOURTYPE = 'NP'` on sampled note-only pay rows (Inferred name: note payable).

---

## 2. Stages on `PVMAS` (Confirmed)

| Stage | Flags | Numbers | Amounts (typical) |
|-------|--------|---------|-------------------|
| **Note only** (waiting for voucher) | `NOTED='Y'`, `VOUCED='N'` | `NOTENO` + `NOTEDATE`; `VOUCNO` null | `BILLAMT` filled; `PAYAMT` / `PAID` empty |
| **Voucher only** | `VOUCED='Y'`; `NOTED` blank/`(` | `VOUCNO` + `VOUCDATE`; `NOTENO` often empty | `PAYAMT` used when paid |
| **Note + voucher** | both `Y` (or numbers both filled) | both `NOTENO` and `VOUCNO` | billed then paid |

HQ snapshot 2026-08-16:

| `PVMAS` | Count |
|---------|------:|
| Total | 14,563 |
| Note only (`NOTED='Y'` and not vouchered) | 2,135 |
| Has `NOTENO` | 3,078 |
| Has `VOUCNO` | 12,427 |

Receipt twin `RVMAS` uses the same flag/column names. HQ: 11,714 rows; 1,164 noted and not vouchered.

### Voucher number prefixes (pay)

| Prefix | Role |
|--------|------|
| `KCPN*` | Payment voucher (majority; 7,852 HQ) |
| `P*` + year month (e.g. `P6908-003`) | Payment voucher |
| empty | Note-only row — search by `NOTENO` |

---

## 3. Useful `PVMAS` columns (Confirmed)

| Column | Role |
|--------|------|
| `JOURTYPE` | `NP` on sampled note-only rows |
| `VOUCED`, `VOUCDATE`, `VOUCNO` | Payment voucher issued? date / number |
| `NOTED`, `NOTEDATE`, `NOTENO` | Note issued? date / supplier note number |
| `RCPTNO`, `RCPTDATE` | Receipt ref when filled |
| `ACCTNO`, `ACCTNAME` | AP account (supplier) |
| `BILLCNT`, `BILLAMT` | How many bills / billed amount (present on note-only) |
| `CASHAMT`, `CHKAMT`, `PAYAMT`, `PAID` | Settlement — empty until vouchered/paid |
| `CANCELED`, `DONE`, `POSTED1`, `POSTED2` | Cancel / done / posted |

`RVMAS` column set matches this header shape.

---

## 4. Join to purchase bills (`PIMAS`) (Confirmed)

Do **not** expect a `PVMAS` line table. Bills are `PIMAS` (+ `PIDET` lines).

| Link | Use when | HQ (2026-08-16) |
|------|----------|-----------------|
| `PIMAS.NOTENO = PVMAS.NOTENO` | Note stage (and still after voucher if note kept) | 2,134 of 2,135 note-only `PVMAS` also on `PIMAS`; 2,973 `PVMAS` with `NOTENO` match a bill |
| `PIMAS.VOUCNO2 = PVMAS.VOUCNO` | After voucher issued | **Main voucher link** — 12,422 `PVMAS` hit at least one bill; 70,948 `PIMAS` have `VOUCNO2` |
| `PIMAS.VOUCNO1 = PVMAS.VOUCNO` | Rare second voucher slot | 24 `PIMAS` with `VOUCNO1` |
| `PIMAS.BILLNO = PVMAS.NOTENO` | Sometimes the supplier note **is** the bill number | e.g. `BA25656` |

Example — note only:

- `PVMAS.NOTENO = 103772300`, `VOUCNO` empty, `BILLAMT = 78573.10`, vendor `7STATE`
- `PIMAS.BILLNO = B2607-1080`, same `NOTENO`, unpaid (`PAID='N'`)

Example — vouchered:

- `PVMAS.VOUCNO = KCPN6908-008`, `NOTENO = BO6900997`
- Many `PIMAS` IV bills with `NOTENO = BO6900997` **and** `VOUCNO2 = KCPN6908-008`

A single note/voucher can cover **many** purchase bills (dozens). Lookup UIs should not cap at a handful of bills without saying so.

### `PIMAS` note vs voucher (HQ 2026-08-16)

| | Count |
|--|------:|
| `PIMAS` rows | 88,669 |
| Has `NOTENO` | 15,158 |
| Has `VOUCNO2` | 70,948 |
| Note filled, both voucher slots empty | 52 |

---

## 5. Join to cheque register (Confirmed)

| Direction | Detail | Header |
|-----------|--------|--------|
| Pay | `BPDET.VOUCNO = PVMAS.VOUCNO` | Only after a voucher exists — note-only rows have **no** `BPDET` |
| Receive | `BRDET.VOUCNO` ↔ `RVMAS.VOUCNO` when the receipt voucher was issued | Same idea |

See [BRDET/BPDET dictionary](./kcw-brdet-bpdet-cheque-transfers-data-dictionary.md).

---

## 6. Sales / AR parallel (Inferred from same column names; counts Confirmed)

`SIMAS` has `NOTEDATE` / `NOTENO` / `VOUCDATE1` / `VOUCNO1` / `VOUCDATE2` / `VOUCNO2` like `PIMAS`.

HQ 2026-08-16: 12,786 `SIMAS` with `NOTENO`; `VOUCNO1` unused (0); 65,780 with `VOUCNO2`; 131 note-only (note filled, both voucher slots empty). Treat as **AR notes / receipt vouchers**, not AP pay notes. Confirm joins to `RVMAS` before locking BI.

---

## 7. Lookup rules (Confirmed — PARTS9 explorer)

Search **pay** by:

1. `PVMAS.VOUCNO` (and prefix / `RCPTNO`)
2. `PVMAS.NOTENO` (numeric notes such as `103772300` are valid — they are **not** product `BCODE`s)

Then load related `PIMAS` via `NOTENO` and/or `VOUCNO2` (and `VOUCNO1`). Searching `PIMAS` by the same note or voucher number should find the bills directly.

App `public.expense_*` **PV / 3PV** print numbers are **not** PARTS9 `PVMAS`. Do not match bank lines to `raw_kcw` PVMAS for those.

---

## 8. Pipeline (Confirmed)

| Site | Drive CSV | Supabase |
|------|-----------|----------|
| HQ | `raw_hq_pvmas_notes_vouchers.csv` | `raw_kcw.raw_hq_pvmas_notes_vouchers` |
| HQ | `raw_hq_rvmas_notes_vouchers.csv` | `raw_kcw.raw_hq_rvmas_notes_vouchers` |

Full HQ extract (`TABLE_SPECS`) includes `PVMAS` / `RVMAS`. SYP minimal extract does **not**.

---

## Changelog

| Date | Change |
|------|--------|
| 2026-08-16 | Document note-before-voucher on `PVMAS`/`RVMAS`; no note table / no `PVDET`; `PIMAS.NOTENO` + `VOUCNO2` bill links; explorer search rules |
