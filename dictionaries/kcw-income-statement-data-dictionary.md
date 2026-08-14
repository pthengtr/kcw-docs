# KCW income statement (เฉพาะส่งบัญชี)

Source of truth for `/bi/income-statement` — taxed sales/purchase from VAT books, plus **all company (`ENTRIES`) expenses** from the expense app (same as `/bi/expenses` · บริษัท), then estimated corporate income tax and mid-period run-rate forecast.

**Transition note:** KCW still sells partially non-VAT. Keep `/bi/income` as the **overall** (VAT + non-VAT) margin view.

Status legend: **Confirmed** · **TBD** · **Inferred**

Last reviewed: 2026-08-08

---

## 1. Scope

| Fact | Status |
|------|--------|
| Revenue = VAT sales **before-tax** (`sales_before`) | Confirmed |
| Purchase cost = VAT purchase goods **before-tax** | Confirmed |
| Expense = **all company ENTRIES** from `fn_bi_expense_overview` (`p_source='ENTRIES'`) — not VAT-only expense bases | Confirmed |
| CIT approx **20%** on positive profit only | Confirmed (flat; SME tiers TBD) |
| Trend / year-end forecast = VAT run-rate factor on all lines | Confirmed |
| Label UI as **ประมาณการ** — not statutory filing | Confirmed |

---

## 2. Formulas (Confirmed)

```text
revenue          = sales_before                 -- VAT sales book
purchase_cost    = purchase_before              -- PIDET VAT purchases
expense          = company ENTRIES amount       -- /bi/expenses · บริษัท
total_cost       = purchase_cost + expense
profit_before_tax = revenue − total_cost
income_tax       = max(0, profit_before_tax) × 0.20
net_profit       = profit_before_tax − income_tax
```

Do **not** use `vat.expense_before` (~VAT-taxable expense base only). Company ENTRIES includes all company bills (VAT and non-VAT lines as entered in the app).

Trend: sales/purchase ≈ `vat / 0.07`; expense from expense BI `trend_monthly.entries_amount` (daily = allocate month total across elapsed days).

**Forecast** (same factor as VAT): when `as_of < p_to`,

```text
factor = days_in_range / days_elapsed
forecast_x = actual_x × factor
```

YTD preset uses `Jan 1 → Dec 31` so mid-year forecast targets year-end.

---

## 3. App entry

- UI: `/bi/income-statement`
- API: `GET /api/bi/income-statement/overview?from=&to=&branch=`
- Data: `fn_bi_vat_overview` + `fn_bi_expense_overview(p_source='ENTRIES')` → `deriveIncomeStatement`
- Branch: HQ/SYP map to expense branch UUIDs (`c93efb5f-…` / `4975a5a1-…`)
- Page key: `bi_income_statement` (admin bypass)

---

## 4. Changelog

| Date | Change |
|------|--------|
| 2026-08-08 | Expense line = company ENTRIES total (not VAT expense_before) |
| 2026-08-08 | Clarify taxed-only vs `/bi/income` overall (VAT transition) |
| 2026-08-08 | Initial VAT-based income statement + CIT estimate + forecast |
