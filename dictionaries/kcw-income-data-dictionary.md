# KCW income / margin data dictionary

Source of truth for the **overall** gross + net income BI report (`/bi/income`).  
Combines curated sales lines (**VAT + non-VAT**) with **app operating expenses** (not a full accounting P&L).

During the VAT transition, use this page for whole-business margin. Taxed-only P&L + CIT estimate lives at `/bi/income-statement`.

Status legend: **Confirmed** · **TBD** · **Inferred**

Last reviewed: 2026-07-26

---

## 1. Scope (Confirmed)

| Layer | Source | Role |
|-------|--------|------|
| Revenue / COGS / Gross | `curated_kcw.fact_sales_*` | Line grain after sales filters + bill-gap alloc |
| OpEx | `public.expense_*` | Same amount rules as expense BI |
| Net (approx) | Gross − OpEx only | No interest, tax, depreciation, etc. |

Label in UI as **ประมาณการ** — not statutory net profit.

---

## 2. Gross profit (Confirmed — §8.5 sales dictionary)

```text
revenue_net = line amount after:
  - bill DISCOUNT/DEDUCT gap allocation (§6.7)
  - /1.07 only when ISVAT='Y' AND TAXIC='Y'

cogs = qty_base × LAST_PURCHASE_COST
qty_base = QTY × coalesce(nullif(MTP, 0), 1)   -- purchase/base units

-- Lines with blank/missing LAST_PURCHASE_COST:
--   excluded from revenue_net / cogs / gross / net totals
--   still counted in blank_cost_line_count + drilldown list

gross_profit = revenue_net − cogs
gross_margin_pct = gross_profit / revenue_net   -- null if revenue_net = 0
```

| Rule | Status |
|------|--------|
| Ignore `XPRICE` for COGS | Confirmed |
| Blank / missing `LAST_PURCHASE_COST` | **Exclude from margin totals**; keep drilldown list (Confirmed) |
| Allocate bill gap onto lines before margin | Confirmed |
| Sales filters = revenue include set (`fn_bi_sales_bill_excluded_from_revenue`; no SA/3SA stock-check; `JOURMODE≠0`; etc.) | Confirmed |
| Reporting branch HQ / SYP / ONLINE (TAD/CNTAD) | Confirmed |

---

## 3. Net income (Confirmed)

```text
opex = sum(app expense amounts)   -- ENTRIES + GENERAL, expense dictionary §2
net_income ≈ gross_profit − opex
net_margin_pct = net_income / revenue_net
```

Only operating expenses from the expense app. No other P&L lines.

---

## 4. Expense → sales reporting branch (Confirmed)

App expenses use `branch` (`สำนักงานใหญ่`, `สี่แยกพัฒนา`). Map to sales BI codes:

| Expense branch | Category (`btrim`) | Reporting branch |
|----------------|--------------------|------------------|
| สำนักงานใหญ่ | `ออนไลน์` | **ONLINE** |
| สำนักงานใหญ่ | other | **HQ** |
| สี่แยกพัฒนา | any | **SYP** |
| other | any | OTHER (shown only when filter = ALL) |

Note: category name in DB may have a trailing space (`ออนไลน์ `) — always `btrim`.

---

## 5. RPC / API

| Piece | Detail |
|-------|--------|
| RPC | `public.fn_bi_income_overview(from, to, branch, timezone)` |
| Blank-cost RPC | `public.fn_bi_income_blank_costs(from, to, branch, limit)` |
| UI | `/bi/income` |
| API | `GET /api/bi/income/overview?from=&to=&branch=` |
| Blank-cost API | `GET /api/bi/income/blank-costs?from=&to=&branch=&limit=` |
| Branch filter | `HQ` \| `SYP` \| `ONLINE` \| omit = ALL |

Previous-period window = equal length immediately before `from` (same as other BI reports).

### 5.1 Blank cost drilldown

Lines where `LAST_PURCHASE_COST` is blank/null are **excluded from income totals** (revenue/COGS/gross/net) so missing cost does not inflate margin.  
They remain available in the drilldown list for data cleanup.

UI: click **ต้นทุนว่าง N บรรทัด** on the COGS KPI → dialog with:

`bill_date`, `bill_no`, reporting/store branch, `BCODE`, `DETAIL`, `QTY` (+ `MTP`), line `AMOUNT`, `COST_STATUS`.

Default API limit 500 (max 2000); response includes `truncated` when capped.

---

## 6. Changelog

| Date | Change |
|------|--------|
| 2026-08-08 | Label as overall (VAT + non-VAT); taxed-only P&L is `/bi/income-statement` |
| 2026-07-26 | Lock gross/net formulas; HQ category ออนไลน์ → ONLINE; ship `fn_bi_income_overview` + `/bi/income` |
| 2026-07-26 | Blank-cost line drilldown (`fn_bi_income_blank_costs` + dialog on COGS KPI) |
| 2026-07-26 | Blank-cost lines excluded from income totals; list retained for drilldown |
