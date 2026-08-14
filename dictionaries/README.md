# KCW data dictionaries

Canonical business meaning for tables and metrics used by **kcw-api**, **kcw-v2**, and **kcw-analytics**.

Status legend in each file: **Confirmed** · **TBD** · **Inferred**. When a rule changes, add a **Changelog** row with the effective date.

| File | Purpose |
|------|---------|
| [kcw-sales-data-dictionary.md](./kcw-sales-data-dictionary.md) | Sales naming, grain, joins, codes, billing rules; customer `ACCTNO` / party |
| [kcw-icmas-data-dictionary.md](./kcw-icmas-data-dictionary.md) | Product master (ICMAS): `BCODE`, `CODE1`, categories |
| [kcw-ar-ap-data-dictionary.md](./kcw-ar-ap-data-dictionary.md) | AR/AP masters (ARMAS/APMAS); **`MOBILE` = tax id** |
| [kcw-expense-data-dictionary.md](./kcw-expense-data-dictionary.md) | App expense tables + amount rules (company + general) |
| [kcw-income-data-dictionary.md](./kcw-income-data-dictionary.md) | Overall gross / net (VAT + non-VAT sales − opex) |
| [kcw-income-statement-data-dictionary.md](./kcw-income-statement-data-dictionary.md) | Taxed-only VAT-book P&L + CIT + year-end forecast |
| [kcw-vat-data-dictionary.md](./kcw-vat-data-dictionary.md) | VAT sales/purchase tax books + mid-period forecast |
| [kcw-purchase-data-dictionary.md](./kcw-purchase-data-dictionary.md) | HQ PIDET purchase **invoice** lines (JOURMODE / BILLTYPE) |
| [kcw-po-data-dictionary.md](./kcw-po-data-dictionary.md) | Purchase **orders** in `raw_kcw` (HQ+SYP); PO id = `DOCNO`; SYP prepare = `po_syp_prepare` |
| [kcw-iclow-pending-receive-data-dictionary.md](./kcw-iclow-pending-receive-data-dictionary.md) | PARTS9 **ค้างรับ** = `ICLOW` (`ORDERED`/`RECEIVED`/`CANCELED`) |
| [kcw-brdet-bpdet-cheque-transfers-data-dictionary.md](./kcw-brdet-bpdet-cheque-transfers-data-dictionary.md) | PARTS9 **ทะเบียนเช็ครับ/จ่าย** = `BRDET`/`BPDET` (`CHKNO` = cheque # or method label) |
| [kcw-product-movement-data-dictionary.md](./kcw-product-movement-data-dictionary.md) | Stock-more + dead-stock aging rules |

v2 BI pages and RPC SQL remain in [kcw-v2/docs/bi](https://github.com/pthengtr/kcw-v2/blob/master/docs/bi/README.md). Analytics extract notes remain in [kcw-analytics/docs](https://github.com/pthengtr/kcw-analytics/tree/main/docs).
