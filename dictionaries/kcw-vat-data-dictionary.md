# KCW VAT sales / purchase BI (รายงานภาษีขาย·ซื้อ)

Source of truth for `/bi/vat` — replicates **kcw-analytics** Excel tax books (notebooks `30` / `31` / `32`) as a BI dashboard, plus a mid-period **run-rate forecast**.

Upstream reference: [kcw-analytics `docs/vat_sales_purchase_reports.md`](https://github.com/pthengtr/kcw-analytics/blob/master/docs/vat_sales_purchase_reports.md)

Status legend: **Confirmed** · **TBD** · **Inferred**

Last reviewed: 2026-08-05

---

## 1. Scope

| Fact | Status |
|------|--------|
| Formal Thai VAT books = ภาษีขาย + ภาษีซื้อ (PARTS9 + TAR + app expense) | Confirmed |
| Tax rate **7%** (`/1.07` when inclusive) | Confirmed |
| Purchases HQ-only in PARTS9 | Confirmed |
| BI route `/bi/vat` · RPC `fn_bi_vat_overview` | Confirmed |
| Does **not** replace Excel filing packs — dashboard totals for ops | Confirmed |

---

## 2. Sales VAT (ภาษีขาย)

| Source | Doc types | Amount rule |
|--------|-----------|-------------|
| `curated_kcw.fact_sales_bills_all` | TD, TAD, TR, CN, CNTAD (+ SYP `3*`) | Bill `BEFORETAX` / `TAX` / `AFTERTAX` |
| `billgen.fin_tar_lines` | TAR (HQ) | Per-bill `sum(amount)/1.07` rounded |
| `billgen.fin_3tar_lines` | 3TAR (SYP) | same |
| `billgen.fin_cntar_lines` | CNTAR (HQ) | Group by `new_billno`; inclusive |
| `billgen.fin_3cntar_lines` | 3CNTAR (SYP) | same |

**Filters (Confirmed):**

- Drop bills whose `BILLNO` contains `TF` (excludes `TF`/`TFV` transfers and `CNTF`/`CNTFV`/`3CNTF` transfer credit notes)
- `CANCELED = N` on curated bills
- CNTAD split from CN by billno prefix

Branch: HQ vs SYP (TAD/CNTAD sit on HQ tax entity, same as Excel HQ workbook).

---

## 3. Purchase VAT (ภาษีซื้อสินค้า)

| Source | Rule |
|--------|------|
| `raw_hq_pidet_purchase_lines` ⋈ `raw_hq_pimas_purchase_bills` | `ISVAT = Y`; one row per bill |
| Amounts | Prefer PIMAS `BEFORETAX` / `TAX` / `AFTERTAX` |
| Book sheets | `BOOKNO` `1`/`1_0`=เครดิต, `2`=สด, `5`=ลดหนี้ซื้อ, `6`=เพิ่มหนี้ซื้อ |

When BI branch filter = SYP, purchase VAT = 0 (no SYP PIDET).

---

## 4. Expense VAT (ภาษีซื้อค่าใช้จ่าย)

| Source | Rule |
|--------|------|
| `public.vw_expense_entry_flat_tax` | Keep `vat <> 0` |
| Grain | Aggregate per `receipt_uuid` |
| Math | `vat = signed_entry_amount × 0.07` (base treated exclusive) |
| Date | `receipt_day` in selected range (**BI**) |

**Note:** Excel notebook `31_` filters expense by `created_at` window starting on the 10th of the reporting month. BI uses `receipt_day` for date-range consistency with sales/purchase.

HQ branch uuid = `c93efb5f-07c9-4229-b6b3-568ce1c0a9ab`.

---

## 5. Net VAT + forecast

```text
net_vat = sales_vat − purchase_vat − expense_vat
```

**Forecast (Confirmed):** when `as_of < p_to` (incomplete period):

```text
factor = days_in_range / days_elapsed
forecast_x = actual_x × factor
```

`as_of` defaults to today (Asia/Bangkok), clamped into `[p_from, p_to]`. Complete periods set `forecast.enabled = false`.

UI presets **เดือนนี้ / YTD / custom-month** pass the **full calendar end** as `p_to` (not capped at today) so mid-month forecast has a real target; actuals stop at `as_of`.

---

## 6. App entry

- UI: `/bi/vat`
- API: `GET /api/bi/vat/overview?from=&to=&branch=`
- SQL: [sql/fn_bi_vat_overview.sql](./sql/fn_bi_vat_overview.sql)
- Page key: `bi_vat` (admin bypass)

---

## 7. Changelog

| Date | Change |
|------|--------|
| 2026-08-05 | Initial BI VAT report + run-rate forecast from kcw-analytics 30–32 |
