# KCW expense data dictionary (app)

Source of truth for the **in-app expense** BI report (`/bi/expenses`).  
Data lives in schema **`public`** and is entered via the expense app in this repo — **not** `raw_kcw` / PIDET purchases.

Status legend: **Confirmed** · **TBD** · **Inferred**

Last reviewed: 2026-07-26

---

## 1. Schema map

| Object | Grain | Role |
|--------|-------|------|
| `expense_receipt` | 1 company bill / credit note | Header: date, party, branch, VAT%, WH%, discount, `signed_total` |
| `expense_entry` | 1 line on a company bill | Amount, item, line discount |
| `expense_general` | 1 casual expense row | `unit_price * quantity`, item, branch |
| `expense_item` | Item master | → `expense_category` |
| `expense_category` | Category master | Grouping for BI |
| `branch` | Branch master | Filter / split (`สำนักงานใหญ่`, `สี่แยกพัฒนา`) |
| `party` | Supplier / payee on company bills | Optional filter on year RPCs; not required for BI overview |

Staging / KCW upload tables are out of scope for this report.

---

## 2. Amount rules (Confirmed — match year-summary RPCs)

Canonical logic is already encoded in:

- `fn_item_year_summary_all`
- `fn_item_year_summary_entries_fullmonths`
- `fn_item_year_summary_general_fullmonths`

BI RPC `fn_bi_expense_overview` uses the **same formulas** over an arbitrary `from`/`to` date range.

### 2.1 Company (`ENTRIES` = receipt + entry)

```text
entry_net = greatest(entry_amount - entry.discount, 0)
receipt_net_sum = sum(entry_net) over receipt
factor = 1 + (vat - withholding) / 100
sign_factor = -1 if signed_total < 0 else +1   -- credit notes

amount =
  if receipt_net_sum > 0:
    sign_factor
    * (entry_net - entry_net / receipt_net_sum * receipt.discount)
    * factor
  else 0
```

Date: `receipt_date` (Bangkok).

### 2.2 General (`GENERAL`)

```text
amount = unit_price * quantity   -- always positive as stored
```

Date: `entry_date` (Bangkok).

### 2.3 Sources

| `source` | Meaning |
|----------|---------|
| `ENTRIES` | ค่าใช้จ่ายบริษัท (บิล) |
| `GENERAL` | ค่าใช้จ่ายทั่วไป |
| `null` / ALL | ทั้งสองแหล่ง |

---

## 3. BI filters

| Filter | Values | Notes |
|--------|--------|-------|
| Date range | `from`–`to` inclusive | Same period shell as sales BI (เดือนนี้ / YTD / กำหนดเอง) |
| Branch | `branch_uuid` or all | App branches, not HQ/SYP/ONLINE sales codes |
| Source | ALL / ENTRIES / GENERAL | |

Previous-period comparison uses an equal-length window immediately before `from`.

---

## 4. Metrics (Confirmed for BI overview)

| Metric | Definition |
|--------|------------|
| Total amount | `sum(amount)` after source/branch filters |
| Entries amount | Company lines only |
| General amount | General rows only |
| Receipt count | Distinct `receipt_uuid` in ENTRIES |
| General count | Row count in GENERAL |
| Item / category ranking | Sum amount by item or category |
| Monthly trend | Sum by `YYYY-MM` |
| Item × month matrix | `by_item_month` + `month_columns` (for YTD compare table) |
| YTD year | UI year selector → `from=YYYY-01-01` … today or year-end |

---

## 5. Relation to year-summary RPCs

Legacy calendar-year helpers still exist in the DB for reference:

- `fn_item_year_summary_all`
- `fn_item_year_summary_entries_fullmonths`
- `fn_item_year_summary_general_fullmonths`

BI uses `fn_bi_expense_overview` (date range + admin API). The old `/expense/dashboard` UI was removed; use `/bi/expenses`.

---

## 6. Changelog

| Date | Change |
|------|--------|
| 2026-07-26 | Initial dictionary; ship `fn_bi_expense_overview` + `/bi/expenses` |
| 2026-07-26 | Remove `/expense/dashboard` UI; expense analytics live under `/bi/expenses` |
| 2026-07-26 | YTD year selector + item×month compare table (`month_columns` / `by_item_month`) |
| 2026-07-26 | Income BI maps HQ category `ออนไลน์` → reporting branch ONLINE (see income dictionary) |
