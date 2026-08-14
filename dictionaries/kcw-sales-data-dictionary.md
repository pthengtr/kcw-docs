# KCW sales data dictionary

Source of truth for naming, grain, joins, codes, and billing rules used by the sales BI dashboard.

Schemas: `raw_kcw` (source) · `curated_kcw` (BI-ready)

Status legend:

- **Confirmed** — verified from data inspection and/or business owner
- **TBD** — needs owner confirmation before using in metrics
- **Inferred** — looks true from data patterns; not yet locked

Last reviewed: 2026-07-26

---

## 1. Schema map (sales)

| Object | Kind | Grain | Branches (as of 2026-07-25) | Approx rows | Role in BI |
|--------|------|-------|-----------------------------|------------:|------------|
| `curated_kcw.fact_sales_all` | table | **1 row = 1 bill line item** | HQ, SYP | ~533k | Product qty, unit price, line amount, cost |
| `curated_kcw.fact_sales_bills_all` | table | **1 row = 1 bill header** | HQ, SYP | ~195k | Bill totals, payment, customer, salesman |
| `curated_kcw.fact_sales_all_stg` | staging | same as line fact | — | — | Upload/staging twin; not for reporting |
| `curated_kcw.fact_sales_bills_all_stg` | staging | same as bill fact | — | — | Upload/staging twin; not for reporting |

**Confirmed:** Use final tables (`fact_sales_all`, `fact_sales_bills_all`) for dashboards, not `_stg`.

**Customer master:** `public.party` (+ tax/bank/contact) — see [§6.9](#69-acctno-acct_no--customer-party-confirmed).  
**TBD:** Full inventory of other `curated_kcw` / `raw_kcw` objects relevant to BI (purchases, etc.).

---

## 2. Relationship & join keys

```
fact_sales_bills_all          fact_sales_all
(1 bill header)   1 ──< N     (line items)
```

| Key | Tables | Notes |
|-----|--------|-------|
| `("BRANCH", "BILLNO")` | bills ↔ lines | **Confirmed** primary join |
| `"BRANCH_BILLNO"` | lines only | Composite helper like `HQ-8K69-0013225` |

### Join coverage (rechecked after SYP bill upload fix, 2026-07-25)

| Branch | Line bills | Matched headers | Line-only missing |
|--------|----------:|----------------:|------------------:|
| HQ | 174,757 | 174,757 | 0 |
| SYP | 20,567 | 20,567 | 0 |
| **All** | **195,324** | **195,324** | **0** |

Bill headers with **no** matching lines: **29** (all HQ). Mostly odd headers — see [§7 Gotchas](#7-gotchas--data-quality).

**Confirmed:** Date span for both facts roughly **2023-07-25 → 2026-07-25** (SYP bill headers start **2025-06-23**).

---

## 3. Global conventions

| Topic | Rule | Status |
|-------|------|--------|
| Column casing | Business columns are **UPPERCASE**; quote in SQL: `"BILLNO"` | Confirmed |
| Data types | Nearly all business fields stored as **`text`** (including amounts) | Confirmed |
| Numeric use | Cast with care, e.g. `"AMOUNT"::numeric`; prefer `"AMOUNT_NUM"` / `"PRICE_NUM"` on lines when present | Confirmed / prefer |
| Branches (source) | Stored values: `HQ`, `SYP` | Confirmed |
| Branches (BI reporting) | `HQ`, `SYP`, **`ONLINE`** | Confirmed — see [§6.2.2](#622-reporting-branch-online-vs-hq) |
| Staging vs prod | Report from non-`_stg` tables | Confirmed |
| RLS | Currently **disabled** on curated sales tables — treat as private BI data | Confirmed (security follow-up TBD) |

---

## 4. `fact_sales_all` — line items

### 4.1 Purpose

One row per product (or charge line) on a sales bill. Use for product mix, quantity, line revenue, and cost/margin at line level.

### 4.2 Column glossary

| Column | Meaning | Status | Notes |
|--------|---------|--------|-------|
| `_ingested_at` | Row load timestamp | Confirmed | Pipeline metadata |
| `_source_file` | Source file name | Confirmed | Pipeline metadata |
| `BRANCH` | Branch code | Confirmed | `HQ`, `SYP` |
| `BILLDATE` | Bill date | Confirmed | Text `YYYY-MM-DD` |
| `BILLNO` | Bill number | Confirmed | Part of join key |
| `BRANCH_BILLNO` | `BRANCH` + bill no helper | Confirmed | e.g. `HQ-8K69-0013225` |
| `BILLTYPE` | Raw bill type code | TBD | Seen: `0`, `1`, `2` (and rare others on bills) |
| `BILLTYPE_STD` | Standardized bill type | TBD | Seen: `TAR`, `TF`, `TFV`, `TAD`, `TD`, `TR`, `DN`, `CN`, `UNKNOWN` — meanings TBD |
| `JOURMODE` | Journal / posting mode | TBD | Seen: `0`, `1`, `2` |
| `BCODE` | Product / item code | Confirmed (name) | Item SKU-like code. First 2 digits = category; see [ICMAS dictionary](./kcw-icmas-data-dictionary.md) for `CODE1` part-type letters |
| `DETAIL` | Product description | Confirmed | Thai/English text |
| `QTY` | Quantity sold | Confirmed | Text numeric |
| `UI` | Unit of measure (as sold on the bill) | Confirmed | e.g. `หน่วย`, `ชุด`. Master pack names live on ICMAS `UI1`/`UI2` — see [ICMAS §5](./kcw-icmas-data-dictionary.md) |
| `MTP` | Pack multiplier → count of **smallest units** per sold UI | Confirmed | e.g. box of 10 ⇒ `MTP=10`. Related to ICMAS `MTP2` (master). See note below |
| `PRICE` | Unit selling price | Confirmed (name) | Text; also `PRICE_NUM` |
| `XPRICE` | Appears related to cost/ref price | Inferred | Often close to `LAST_PURCHASE_COST` |
| `DISCNT1`…`DISCNT4` | Line discounts | Confirmed (DISCNT1) | `DISCNT1` is **percent off**. Already baked into `AMOUNT` (`AMOUNT ≈ QTY*PRICE*(1-DISCNT1/100)`). `DISCNT2–4` almost unused |
| `DED` | Line deduction (baht?) | Inferred | Sparse (~2k lines). Owner: line-level adjustments are already reflected in `AMOUNT` — safe for revenue |
| `VAT` | VAT amount on line | TBD | Often null on samples |
| `AMOUNT` | Line extended amount as keyed | Confirmed | Prefer `AMOUNT_NUM`. Almost always `QTY * PRICE`. Incl/excl VAT depends on `TAXIC` — see [§6.0](#60-vat--taxic--isvat-rules-confirmed) |
| `PRICE_NUM` | Numeric price helper | Confirmed | Text still; curated helper |
| `AMOUNT_NUM` | Numeric amount helper | Confirmed | Text still; curated helper |
| `TAXIC` | How operator keyed the amount | Confirmed | `Y` = line amount **includes** VAT; `N` = line amount **excludes** VAT. Not the VAT-sales classifier |
| `ISVAT` | Whether this is a **VAT sale** line | Confirmed | `Y` = VAT sales; `N` = non-VAT sales. Dashboard sales-type split uses this |
| `VAT` (line) | **VAT rate %**, not baht amount | Confirmed | Typically `7.0` when `ISVAT=Y`; `0`/null when `ISVAT=N` |
| `ACCTNO` | **Customer (AR)** code — same as bill `ACCTNO` when filled | Confirmed | July 2026: when filled, always equals bill `ACCTNO`. Do **not** confuse with line `ACCT_NO` |
| `ACCT_NO` | **Supplier / source (AP-leaning)** code on the line | Confirmed | Joins `party.party_code` mostly as `SUPPLIER` (e.g. `7SSY`, `CRRK`). Never equals bill customer `ACCTNO`. **Not** for customer ranking |
| `PAID` | Paid flag on line | TBD | Seen `Y` |
| `STATUS` | Line/bill status | TBD | Seen `1.0`, `8.0` |
| `DONE` | Done flag | TBD | Mostly `N` |
| `CANCELED` | Canceled flag | Confirmed | `Y` / `N` |
| `IS_VALID` | Curated validity flag | Confirmed | `True` / `False` (text) |
| `INVALID_REASON` | Why invalid | Confirmed | e.g. `CANCELED`, `BAD_BCODE`, `BAD_AMOUNT`, `BAD_PRICE` (can combine with `\|`) |
| `ROW_ID` | Curated row id | Confirmed | |
| `LAST_PURCHASE_DATE` | Last purchase date for cost | Confirmed (name) | |
| `LAST_PURCHASE_COST` | Last purchase unit cost | Confirmed (name) | |
| `COST_STATUS` | Cost lookup status | Confirmed | `OK`, `UNKNOWN` |

### 4.3 Validity (line)

| `IS_VALID` | Typical reasons when false | Status |
|------------|----------------------------|--------|
| `True` | — | Confirmed (~529k rows) |
| `False` | `CANCELED`, `BAD_BCODE`, `BAD_AMOUNT`, `BAD_PRICE` | Confirmed |

**`MTP` usage (Confirmed — owner + samples)**

`PRICE` / `AMOUNT` are for the **sold unit** (`UI`: ลัง, โหล, กล่อง, คู่, …).  
`MTP` converts that pack to base pieces:

```text
base_qty              = QTY * MTP
unit_price_smallest   = PRICE / MTP
                      = AMOUNT / (QTY * MTP)   -- same when AMOUNT = QTY * PRICE
```

Examples: `UI=ลัง`, `MTP=20`, `PRICE=1350` → 67.5 per piece; `UI=คู่`, `MTP=2`, `PRICE=590` → 295 each.

**Do not** use `AMOUNT / MTP` alone when `QTY > 1` (that understates pieces).  
**Revenue still uses `AMOUNT` / net line amount** — `MTP` is for unit price and quantity-in-pieces analytics, not for changing sales revenue.

**Default BI filter for “good sales lines”** (see also §8 revenue filters):

```sql
WHERE "IS_VALID" = 'True'
  AND "CANCELED" = 'N'
  -- plus JOURMODE / BILLTYPE_STD rules at bill join
```

---

## 5. `fact_sales_bills_all` — bill headers

### 5.1 Purpose

One row per bill. Use for bill count, bill totals (before/after tax), payment status, customer, terms, salesman.

### 5.2 Column glossary

| Column | Meaning | Status | Notes |
|--------|---------|--------|-------|
| `_ingested_at` | Row load timestamp | Confirmed | |
| `_source_file` | Source file | Confirmed | |
| `BRANCH` | Branch code | Confirmed | `HQ`, `SYP` |
| `JOURMODE` | Journal mode | TBD | Seen `0`, `1`, `2` |
| `JOURTYPE` | Journal type | TBD | Mostly `SJ`; rare `AR` |
| `JOURDATE` / `JOURNO` / `JOURTIME` | Journal date/no/time | TBD | |
| `DEPTNO` / `BOOKNO` | Dept / book | TBD | |
| `BILLTYPE` | Raw bill type | TBD | Seen `0`, `1`, `2`, `R` |
| `BILLTYPE_STD` | Standardized bill type | TBD | Same family as lines |
| `BILLDATE` | Bill date | Confirmed | Text datetime-like |
| `BILLTIME` | Bill time | Confirmed | e.g. ` 1729` |
| `BILLNO` | Bill number | Confirmed | Join key with `BRANCH` |
| `LINES` | Number of lines on bill | Confirmed (name) | Text; can be `0` / null on orphans |
| `TAXIC` | How operator keyed amounts on the bill | Confirmed | Same as line `TAXIC` (incl vs excl VAT keying). Bill has no `ISVAT` column — VAT sales type lives on lines |
| `DISCOUNT` | Bill-level discount (baht) | Confirmed (rare) | Almost unused (~7 bills). **Not** in line `AMOUNT` — must allocate to lines for line↔bill match |
| `DEDUCT` | Bill-level deduction (baht) | Confirmed | Common (~11k bills, ~6.8M baht). **Not** in line `AMOUNT` — must allocate to lines. See [§6.7](#67-discount--deduct-line-vs-bill) |
| `BEFORETAX` | Bill total **excluding VAT** | Confirmed | Net of VAT |
| `VAT` (bill) | **VAT rate %** (not baht) | Confirmed | On `TAXIC=Y` bills almost always `7.0` |
| `TAX` | **VAT amount in baht** | Confirmed | On `TAXIC=Y`: `AFTERTAX - BEFORETAX` (= `BEFORETAX * 0.07`) |
| `AFTERTAX` | Bill total **including VAT** | Confirmed | Gross / tax-included total |
| `EXEMPT` | Tax exempt amount | TBD | |
| `SVCCHG` | Service charge | TBD | |
| `PAID` | Paid flag | TBD | `Y` / `N` |
| `CASHED` | Cashed / cash-received flag | TBD | `Y` / `N` |
| `CASHAMT` | Cash amount | TBD | |
| `CHKAMT` | Check / transfer amount? | TBD | Often used when paid non-cash-label |
| `DUEAMT` | Amount still due | TBD | |
| `PAYSTAT` | Payment status code | TBD | Seen: null, `$`, `=`, `%`, `&` |
| `ACCTNO` | **Customer (AR)** account code | Confirmed | Join key → `public.party.party_code`. Blank = walk-in / cash — **exclude from customer ranking** |
| `ACCTNAME` | Name keyed on the bill | Confirmed | Fallback display only. **`party.party_name` takes priority** when party exists. Often `เงินสด` on walk-in |
| `ADDR1` / `ADDR2` | Address | TBD | |
| `PO` | Context-dependent reference (not always a purchase order) | Confirmed (CN, TAD) | See [§6.8](#68-po-column-meanings) |
| `SALE` | Salesperson code | Confirmed (name) | e.g. `NUY`, `JEAB`, `NONG` |
| `RE` | ? | TBD | |
| `TERM` | Credit term (days?) | TBD | e.g. `30.0` |
| `DUEDATE` | Due date | TBD | |
| `NOTEDATE` / `NOTENO` | Note refs | TBD | |
| `VOUCDATE1` / `VOUCNO1` / `VOUCDATE2` / `VOUCNO2` | Voucher refs | TBD | |
| `POSTED1` / `POSTED2` | Posted flags | TBD | |
| `REMARKS` | Remarks | TBD | |
| `CANCELED` | Canceled flag | Confirmed | `Y` / `N` |
| `DONE` | Done flag | TBD | Mostly `N` |

**TBD — default BI filter for “good bills”:**

```sql
-- PROPOSED (not locked):
WHERE "CANCELED" = 'N'
```

---

## 6. Code tables & billing rules (fill as we confirm)

### 6.0 VAT / TAXIC / ISVAT rules (Confirmed)

Owner correction + data recheck (2026-07-25): **do not confuse these two flags**.

#### Meaning (two different jobs)

| Flag | Job | Values |
|------|-----|--------|
| **`ISVAT`** | **What kind of sale** (VAT vs non-VAT) | `Y` = VAT sale; `N` = non-VAT sale |
| **`TAXIC`** | **How the operator keyed the amount** (only meaningful when `ISVAT=Y`) | `Y` = keyed amount **includes** VAT; `N` = keyed amount **excludes** VAT |

`ISVAT` is the dashboard classifier for VAT vs non-VAT sales.  
`TAXIC` only matters for **VAT sales** (`ISVAT=Y`): whether you must strip VAT out of `AMOUNT`.

**Valid combinations**

| `ISVAT` | `TAXIC` | Valid? | Notes |
|---------|---------|--------|-------|
| `Y` | `Y` | Yes | VAT sale, keyed inclusive |
| `Y` | `N` | Yes | VAT sale, keyed exclusive (~12k lines / ~3.6k bills) |
| `N` | `N` | Yes | Non-VAT sale |
| `N` | `Y` | **No — ignore `TAXIC`** | Should not happen. ~160 lines / ~19 bills (often `TFV`); bill header is `TAXIC=N`, `BEFORETAX=AFTERTAX`, line `"VAT"=0`. Treat as non-VAT and **do not** `/1.07` |

#### Critical naming trap

| Field | What it actually stores |
|-------|-------------------------|
| Bill/line `"VAT"` | **Rate** (e.g. `7.0`), **not** baht |
| Bill `"TAX"` | **VAT amount in baht** |
| Bill `"BEFORETAX"` | Amount **before** VAT (= net revenue at bill level) |
| Bill `"AFTERTAX"` | Amount **after** / including VAT |
| Line `"AMOUNT"` / `"AMOUNT_NUM"` | As keyed: incl VAT if `TAXIC=Y`, excl VAT if `TAXIC=N` |

#### How line `AMOUNT` relates to bill totals

| `ISVAT` | `TAXIC` | Line `AMOUNT` means | Net revenue from line | Data check |
|---------|---------|---------------------|-----------------------|------------|
| `Y` | `Y` | **Includes** VAT | `AMOUNT / 1.07` | sum(lines) ≈ `AFTERTAX`; `/1.07` ≈ `BEFORETAX` |
| `Y` | `N` | **Excludes** VAT | `AMOUNT` as-is | sum(lines) ≈ `BEFORETAX`; `AMOUNT*1.07` ≈ `AFTERTAX` |
| `N` | `N` | No VAT | `AMOUNT` as-is | `BEFORETAX ≈ AFTERTAX ≈` sum(lines) |
| `N` | `Y` | **Ignore `TAXIC`** | `AMOUNT` as-is (same as non-VAT) | Bill side shows no VAT; stripping would understate revenue |

#### Bill identities when VAT applies (`ISVAT=Y` bills)

```text
AFTERTAX  = BEFORETAX + TAX
AFTERTAX  = BEFORETAX * 1.07     -- when 7% VAT
TAX       = BEFORETAX * 0.07
bill "VAT" = 7.0                 -- rate, not amount
```

#### Net line amount (for revenue)

```text
net_line_amount =
  CASE
    WHEN "ISVAT" = 'Y' AND "TAXIC" = 'Y'
      THEN "AMOUNT_NUM"::numeric / 1.07   -- VAT sale keyed inclusive → strip
    ELSE "AMOUNT_NUM"::numeric            -- VAT excl, or non-VAT (ignore bogus TAXIC)
  END
```

Only strip when **both** `ISVAT=Y` and `TAXIC=Y`. If `ISVAT=N`, ignore `TAXIC`.

Sales-type label:

```text
sales_type = CASE WHEN "ISVAT" = 'Y' THEN 'VAT' ELSE 'NON_VAT' END
```

#### BI implication (Confirmed — owner, 2026-07-25)

| Need | Prefer | Status |
|------|--------|--------|
| **Official sales revenue** | Always **net / before VAT** | Confirmed |
| Bill-level revenue | `BEFORETAX` | Confirmed |
| Line-level revenue | `/1.07` only when `ISVAT=Y` **and** `TAXIC=Y` | Confirmed |
| **VAT vs non-VAT split** | Use **`ISVAT`**, not `TAXIC` | Confirmed |
| `ISVAT=N` + `TAXIC=Y` | Invalid combo — ignore `TAXIC` | Confirmed |
| VAT baht (separate) | Bill `TAX` — not inside revenue | Confirmed |

### 6.7 Discount / Deduct (line vs bill)

Owner rule + data check (2026-07-25):

#### Line level — already in `AMOUNT` (OK as-is)

| Field | Role | Status |
|-------|------|--------|
| `DISCNT1` | **Percent** discount on the line | Confirmed — `AMOUNT ≈ QTY × PRICE × (1 − DISCNT1/100)` on ~2218/2219 rows |
| `DISCNT2–4` | Extra discount slots | Almost unused |
| `DED` | Line deduction | Sparse; treat as already reflected in `AMOUNT` per owner |

**Do not** subtract line `DISCNT*` / `DED` again when summing revenue from `AMOUNT_NUM`.

#### Bill level — NOT in line `AMOUNT` (must allocate)

| Field | Frequency | Role |
|-------|----------:|------|
| `DISCOUNT` | ~7 bills | Bill discount baht |
| `DEDUCT` | ~11,207 bills | Bill deduction baht (main case) |

These reduce the bill total **after** lines are summed. Example (`TAXIC=N`):

```text
sum(line AMOUNT) = 4494
DEDUCT           = 4
BEFORETAX        = 4490   (= 4494 - 4)
```

So for line-level BI to reconcile to bill `BEFORETAX` / `AFTERTAX`:

```text
sum(line_net_after_bill_alloc)  =  BEFORETAX
-- and after VAT rules:
-- TAXIC/ISVAT handling still applies on top of keyed amounts
```

Rough reconcile check on bills with `DEDUCT ≠ 0` and `TAXIC=N`:  
`sum(line AMOUNT) − DEDUCT − DISCOUNT ≈ BEFORETAX` on ~9.1k / ~10.5k bills.

#### Required curation rule (Confirmed)

**Confirmed:** bill-level `DISCOUNT` + `DEDUCT` must be **broken down onto lines** (when they actually reduce the bill vs line sum) so line totals match bill `BEFORETAX` / `AFTERTAX`.

##### Locked method

1. **Allocation weight:** proportional by line `"AMOUNT"` share within the bill  
2. **Credit notes:** same method — but only allocate the **real gap** (see below)  
3. **VAT basis of `DEDUCT`:** data-confirmed

| Bill `TAXIC` | What `DEDUCT`/`DISCOUNT` units are | Evidence |
|--------------|-------------------------------------|----------|
| `N` | Same as line `AMOUNT` / `BEFORETAX` / `AFTERTAX` | ~8.9k/8.9k positive bills: `sum(lines) − adj ≈ BEFORETAX` |
| `Y` | **Gross / VAT-inclusive** (same as keyed line `AMOUNT`) | All 20 positive `TAXIC=Y`+`DEDUCT` bills: `sum(lines) − DEDUCT = AFTERTAX`, then `/1.07 = BEFORETAX` |

Example (`TAXIC=Y`, `TAR6806-001`):

```text
sum(lines) = 11352.8
DEDUCT     = 2.8          -- gross baht
AFTERTAX   = 11350.0      -- 11352.8 - 2.8
BEFORETAX  = 10607.48     -- 11350 / 1.07
```

##### Robust allocate formula (prefer this over blind field subtract)

On credit notes / some `BILLTYPE=2` rows, `"DEDUCT"` is often **not** an extra haircut on lines:

- Lines already equal `AFTERTAX` / net `BEFORETAX`
- `"DEDUCT"` may equal `abs(BEFORETAX)` (VAT CN) or another reference amount
- Subtracting it again would **break** the reconcile

So allocate the **observed gap**, not raw `DEDUCT` blindly:

```text
line_gross_sum = sum(AMOUNT over bill)          -- as keyed

-- bill target in same basis as keyed lines:
bill_target_gross = AFTERTAX
  -- (for TAXIC=N, AFTERTAX ≈ BEFORETAX)

gap_gross = line_gross_sum - bill_target_gross
  -- normal sale with deduct: gap ≈ DISCOUNT + DEDUCT
  -- typical credit note:      gap ≈ 0  (even if DEDUCT field is large)

line_share = AMOUNT / nullif(line_gross_sum, 0)
line_gap_alloc_gross = gap_gross * line_share

line_amount_after_bill_adj_gross = AMOUNT - line_gap_alloc_gross

net_line_revenue =
  CASE
    WHEN ISVAT='Y' AND TAXIC='Y'
      THEN line_amount_after_bill_adj_gross / 1.07
    ELSE line_amount_after_bill_adj_gross
  END
```

CN check (negative `AFTERTAX`, `DEDUCT ≠ 0`):

| `TAXIC` | Lines already = bill total (no adj) | Blind `lines − DEDUCT` matches |
|---------|------------------------------------:|-------------------------------:|
| `Y` | 648 / 648 | 0 / 648 |
| `N` | ~1250–1360 / 1387 | ~28 / 1387 |

**Rule:** for CN/negative bills, usually **allocate nothing** (`gap≈0`); still use the same proportional machinery so odd cases with a real gap are handled.

Until this allocation is implemented in curated SQL/views, **bill `BEFORETAX` is safer for company totals**.

### 6.8 `PO` column meanings

`PO` is reused for different references by bill type (not a classic purchase-order field in these flows).

| Bill type | `PO` means | Fill rate | Status |
|-----------|------------|----------:|--------|
| **`CN`** | **Original bill number** being credited | 975/977 (99.8%) | Confirmed |
| **`TAD`** | **Original online transaction id** | 11,767/11,969 (98.3%); from 2025-01 onward | Confirmed |
| `TF` / `TFV` | Almost always literal `BRANCH` | ~97–99% | **Not meaningful** as a join key (branch-transfer marker only) |
| `TD` | Sometimes filled | ~51% | TBD |
| Others | Usually empty | — | — |

**CN → original bill**

- Example: `CNTAD6907-030`.`PO` = `TAD6907-460`
- Join: `cn.PO = original.BILLNO` (same branch) matches **963/975** (~98.8%)
- Use for: credit-note linkage, returns analysis, net revenue by original sale

**TAD → online txn id**

- Examples: `09052426866208`, `260725JNY055U6` (platform order/txn ids — not internal `BILLNO`)
- Use for: reconcile online channel orders to VAT invoices
- Present on recent TAD docs (through current month)

Case note: CN `PO` values occasionally differ in casing (`tfv6808-012` vs `TFV…`); prefer case-insensitive join when linking.

### 6.9 `ACCTNO` / `ACCT_NO` + customer / party (Confirmed)

Field names look alike (`ACCTNO`, `ACCT_NO`, sometimes spoken as “accno”) but **roles differ by table**. Owner rule for customer ranking: use **bill `ACCTNO` (AR)** only.

#### Field map

| Field | Table | Role | Joins `party.party_code` as | Use for customer ranking? |
|-------|-------|------|-----------------------------|---------------------------|
| `"ACCTNO"` | `fact_sales_bills_all` | **Customer (AR)** | Mostly `CUSTOMER` | **Yes** — primary key |
| `"ACCTNO"` | `fact_sales_all` | Same customer code as bill when filled | Same as bill | Redundant; prefer bill |
| `"ACCT_NO"` | `fact_sales_all` | **Supplier / source (AP-leaning)** on the line | Mostly `SUPPLIER` | **No** |
| `"ACCTNO"` | `raw_hq_pidet_purchase_lines` | **Supplier (AP)** on purchase | Mostly `SUPPLIER` / `BOTH` | **No** (AP) |
| `"ACCT_NO"` | `raw_hq_pidet_purchase_lines` | Mixed — often expense/GL-like codes (`5209` ค่าขนส่ง) or supplier | Sparse; not reliable customer | **No** |

**Mnemonic:** sales bill/line **`ACCTNO` = AR customer**; sales line **`ACCT_NO` = AP/supplier**; purchase **`ACCTNO` = AP supplier**.

July 2026 check (revenue filters): line `ACCTNO` equals bill `ACCTNO` whenever filled; line `ACCT_NO` equals bill `ACCTNO` **0** times.

#### Customer ranking rules (Confirmed — owner)

1. **Grain:** bill header · revenue = `BEFORETAX` · same filters as sales overview (`CANCELED=N`, `JOURMODE<>0`, `fn_bi_sales_bill_excluded_from_revenue`; reporting branch `ONLINE` for TAD/CNTAD).
2. **Exclude blank `ACCTNO`** — walk-in / random cash customers (often `ACCTNAME='เงินสด'`). Do not rank them.
3. **Join:** `bill.ACCTNO = public.party.party_code` (left join).
4. **Display name priority:** `party.party_name` → else ARMAS `"ACCTNAME"` (`raw_kcw.raw_hq_armas_receivable`) → else **blank**. Do **not** invent a name from bill `ACCTNAME` or `ACCTNO` when both masters are missing.
5. **Name source:** expose `name_source` = `party` | `armas` | `none` (and `in_armas`) so the UI can show where the name came from.
6. **Unmatched:** keep the `ACCTNO` when there is no `party` row; name may still come from ARMAS. UI may show the full unmatched list so operators can add/sync into party.
7. **Related party tables:** `party`, `party_tax_info`, `party_bank_info`, `party_contact` (`kind`: `CUSTOMER` / `SUPPLIER` / `BOTH`).
8. **KACC AR/AP masters:** `raw_hq_armas_receivable` / `raw_hq_apmas_payable` — see [kcw-ar-ap-data-dictionary.md](./kcw-ar-ap-data-dictionary.md). In those tables, **`MOBILE` is tax id**, not phone (`PHONE` is the phone field).

RPC: `public.fn_bi_customer_overview` · UI `/bi/customers`.

### 6.1 `BILLTYPE` (raw)

| Code | Meaning | Status |
|------|---------|--------|
| `0` | Often with `DN` | Inferred |
| `1` | Normal sales docs (majority) | Inferred |
| `2` | Credit-note family (`CN`) | Confirmed pattern |
| `R` | Orphan-like headers (`&…` bill nos) | Inferred — usually exclude |

### 6.2 `BILLTYPE_STD` (Confirmed — owner + data)

| Code | Meaning | Revenue? | Data check |
|------|---------|----------|------------|
| `UNKNOWN` | Mixed unmapped docs — see billno families below | **Include** (split VAT vs non-VAT by family / `TAXIC`/`ISVAT`) | K/C = non-VAT; legacy `IV…`/`TA…` = VAT |
| `TAD` | **Online sales** | **Include** as **`ONLINE` reporting branch** (not HQ) | Stored `BRANCH=HQ` in source, but BI must **remove from HQ** so store sales are not overstated. Mostly `TAXIC=Y`, `CASHED=N` |
| `TD` | **VAT credit sales** | **Include** | **100% `CASHED=N`** (2,557/2,557); usually `TERM≈30`, `DUEAMT>0` |
| `TR` | **VAT cash sales** | **Include** | **100% `CASHED=Y`** (1,255/1,255); `DUEAMT=0` |
| `DN` | Debit note | **Include** (sign +) | Confirmed name |
| `CN` | Credit note | **Include** (sign −) | Confirmed name; subtypes in billno: `CNTAD`, plain `CN…` |
| `CNTF` | Credit note against `TF` / `TFV` transfer | **Exclude** | Billno prefix `CNTF…` / `CNTFV…` (HQ); `3CNTF…` / `3CNTFV…` (SYP). Source `BILLTYPE_STD` stays `CN` until curated split. `PO` → original `TF`/`TFV` bill |
| `3CNTF` | SYP transfer credit note | **Exclude** | Same as `CNTF`; leading `3` = SYP branch doc (none in load as of 2026-08; rule is forward-looking) |
| `TF` | Transfer HQ ↔ SYP | **Exclude** | Non-VAT (`ISVAT` mostly N); not customer revenue |
| `TFV` | Transfer HQ ↔ SYP (VAT-tagged variant) | **Exclude** | Same — inter-branch transfer |
| `TAR` | Reopen non-VAT bill into VAT doc (no new economic sale) | **Exclude** | All on `JOURMODE=0`; almost all `TAXIC=Y` |
| `CNTAR` | Credit/reopen pair for TAR family | **Exclude** | Owner rule; exact `CNTAR…` billnos currently **0** in bills (may appear as other CN naming) |

**CN billno subtypes (when `BILLTYPE_STD = CN`)**

| Billno prefix | Meaning | Revenue? | Reporting branch |
|---------------|---------|----------|------------------|
| `CNTAD…` / `3CNTAD…` | Online sale credit | **Include** (sign −) | **`ONLINE`** |
| `CNTF…` / `CNTFV…` / `3CNTF…` / `3CNTFV…` | Transfer (`TF`/`TFV`) credit | **Exclude** | n/a (out of revenue set) |
| plain `CN…` | Counter / VAT credit | **Include** (sign −) | `HQ` or `SYP` by branch |

Detection (Confirmed — matches `public.fn_bi_sales_bill_excluded_from_revenue`):

```text
exclude when billno ~* '^(3)?CNTF'   -- catches CNTF, CNTFV, 3CNTF, 3CNTFV
```

**Curated `BILLTYPE_STD` split (kcw-analytics) — recommended, not required**

`CNTAD` is **not** a separate `BILLTYPE_STD` in curated today; BI splits it from `CN` by billno prefix. Use the **same pattern** for `CNTF` / `3CNTF`:

| Approach | Pros | Cons |
|----------|------|------|
| **Billno prefix only** (current BI) | No curated change; works now | Subtype logic duplicated in SQL |
| **Add `CNTF` / `3CNTF` to curated `BILLTYPE_STD`** | Cleaner typing in analytics notebooks | Requires kcw-analytics curated refresh; kcw-v2 helper already accepts these values when present |

If kcw-analytics adds curated types later, map:

- `CNTF…` / `CNTFV…` → `CNTF`
- `3CNTF…` / `3CNTFV…` → `3CNTF`

Until then, keep source `BILLTYPE_STD = CN` and rely on the billno prefix rule above.

**Billno conventions**

| Pattern | Meaning | Status |
|---------|---------|--------|
| Prefix `3…` on std types (`3TR`, `3TAR`, `3TF`, …) | **SYP** branch document | Confirmed |
| `6K…` / `8K…` / other `*K…` + `BILLTYPE_STD=UNKNOWN` | Non-VAT sales (cash-heavy) | Confirmed |
| `*C…` + `UNKNOWN` | Non-VAT credit-like | Inferred (`CASHED=N`) |
| `IV…` / `TA…` + `UNKNOWN` | Legacy VAT docs (pre-std `TR`/`TD`/`TAD` naming) | **Include as VAT revenue** (Confirmed). Not recent: `IV` max `2024-12-30`, `TA` max `2024-12-31` |

**Legacy / scripted docs (not in recent ops)**

| Family | In recent month (as of 2026-07)? | Note |
|--------|----------------------------------|------|
| `TAR` | No — max billdate `2026-02-28` | Script-generated reopen; still **exclude** from revenue |
| `CNTAR` | None found in bills | Script-side; exclude if/when present |
| `IV…` / `TA…` UNKNOWN | No — ended 2024-12 | Historical VAT; **keep & count as VAT** |

### 6.2.2 Reporting branch: ONLINE vs HQ (Confirmed)

Source data stores all `TAD` (and related `CNTAD…` credit notes) as `"BRANCH" = 'HQ'`, but economically they are **online channel sales**, not HQ counter/store sales.

| Source | BI `reporting_branch` | In HQ store total? |
|--------|----------------------|--------------------|
| `BILLTYPE_STD = 'TAD'` | **`ONLINE`** | **No** |
| `CN` with billno `CNTAD…` | **`ONLINE`** | **No** |
| Other included HQ bills | `HQ` | Yes |
| SYP bills | `SYP` | n/a |

```text
reporting_branch =
  CASE
    WHEN BILLTYPE_STD = 'TAD' THEN 'ONLINE'
    WHEN BILLTYPE_STD = 'CN' AND BILLNO ~* '^CNTAD' THEN 'ONLINE'
    ELSE BRANCH   -- HQ or SYP
  END
```

Dashboard branch filter / HQ vs SYP cards must use **`reporting_branch`**, not raw `"BRANCH"`.  
Company-wide total (All) still includes ONLINE + HQ + SYP.

### 6.2.1 Revenue include / exclude (Confirmed)

```text
EXCLUDE from sales revenue:
  - JOURMODE = '0'                  -- owner rule (see §6.3)
  - BILLTYPE_STD IN ('TF','TFV')    -- inter-branch transfers
  - BILLTYPE_STD IN ('TAR')         -- VAT reopen of non-VAT (no revenue impact)
  - CNTAR / TAR-reopen family       -- same economic reason
  - CNTF / 3CNTF transfer credits   -- billno ~* '^(3)?CNTF' (credit against TF/TFV)
  - BILLNO ~ '^(3)?SA'              -- stock-check adjustments (SA / 3SA), not sales
  - CANCELED = 'Y'
  - (lines) IS_VALID <> 'True' when using line grain

INCLUDE (net BEFORETAX / net line amount):
  - UNKNOWN K/C series (non-VAT counter/credit)
  - UNKNOWN IV/TA series (legacy VAT — count as VAT)
  - TAD (online)
  - TD (VAT credit), TR (VAT cash)
  - DN / CN (with natural sign; not TAR-reopen or CNTF family)
```

### 6.3 `JOURMODE`

Owner rule: **always exclude `JOURMODE = 0`**.

| Code | Inferred meaning | Typical contents | Status |
|------|------------------|------------------|--------|
| `0` | VAT reopen / non-economic tax journal | Almost all `TAR` (+ some `UNKNOWN`/`TAD`/`TR`); **99.9% `TAXIC=Y`**; ends 2026-02 in current load | **Exclude** (Confirmed) |
| `1` | VAT / formal tax documents | `TAD`, `TD`, `TR`, `TFV`, `CN`, `DN` | Keep (Inferred label) |
| `2` | Day-to-day sales journal (mostly non-VAT) | Vast `UNKNOWN` K-series + `TF` transfers | Keep but still exclude `TF` by billtype |

Line `JOURMODE` always matches bill `JOURMODE` in current data.

**Why JOURMODE 0 ↔ TAR fits:** excluding mode `0` removes the TAR reopen amounts so they don’t inflate VAT-era revenue after converting old non-VAT bills.

### 6.4 `JOURTYPE` (bills)

| Code | Meaning | Status |
|------|---------|--------|
| `SJ` | Sales journal? | Inferred |
| `AR` | Accounts receivable? | Inferred |

### 6.5 `PAYSTAT` (bills)

| Code | Meaning | Status |
|------|---------|--------|
| `null` | TBD (very common) | TBD |
| `$` | TBD | TBD |
| `=` | TBD (often with credit / due?) | Inferred from samples |
| `%` | TBD | TBD |
| `&` | TBD (rare) | TBD |

### 6.6 Line `STATUS`

| Code | Meaning | Status |
|------|---------|--------|
| `1.0` | TBD (majority) | TBD |
| `8.0` | TBD | TBD |

---

## 7. Gotchas & data quality

1. **Text numerics** — Always cast; do not sum text blindly in some tools.
2. **Quoted identifiers** — `"BRANCH"`, `"BILLNO"`, etc.
3. **`"VAT"` is the rate; `"TAX"` is baht** — easy to misuse in VAT reports.
4. **`ISVAT` ≠ `TAXIC`** — `ISVAT` = VAT sale type; `TAXIC` = keyed incl/excl (only if `ISVAT=Y`). Do not split sales by `TAXIC`.
5. **Only strip `/1.07` when `ISVAT=Y` and `TAXIC=Y`** — if `ISVAT=N`, ignore `TAXIC` (even if wrongly `Y`).
6. **`BILLTYPE_STD = UNKNOWN` is common** — do not treat “UNKNOWN” as rare dirty data without a rule.
7. **Bill orphans (29 HQ)** — headers with no lines: many `BILLTYPE = R` / `&…` numbers, or `LINES = 0` / null amounts. Decide whether to exclude from bill counts.
8. **`ACCTNO` vs `ACCT_NO`** — different roles (AR customer vs AP/supplier). See [§6.9](#69-acctno-acct_no--customer-party-confirmed).
9. **Walk-in / blank `ACCTNO`** — exclude from customer ranking; often `ACCTNAME = 'เงินสด'`.
10. **Cost gaps** — `COST_STATUS = UNKNOWN` (~13k lines); margin metrics need a policy.
11. **Staging tables** — do not report from `*_stg`.
12. **Bill has no `ISVAT`** — for bill-level VAT vs non-VAT split, derive from lines (e.g. any/all `ISVAT=Y`) or use a curated rule (TBD).
13. **Bill `DEDUCT`/`DISCOUNT` not in lines** — sum(line `AMOUNT`) can exceed `BEFORETAX`; allocate before product-level revenue.

---

## 8. Metric definitions (lock before dashboard build)

> Fill formulas here as we agree. Until marked **Confirmed**, do not treat as official KPIs.

### 8.0 Official sales principles (Confirmed)

1. **Revenue = before tax (net).** Never use `AFTERTAX` as the main sales KPI.
2. **Tax is separate.** VAT baht (`TAX`) may appear on a tax report / secondary card, not mixed into revenue.
3. **Two sales types must be visible:** VAT vs non-VAT, classified by **`ISVAT`** (not `TAXIC`).
4. **`TAXIC` only adjusts VAT-sale line math** (strip `/1.07` only when `ISVAT=Y` and keyed inclusive).
5. **If `ISVAT=N`, ignore `TAXIC`** (combo `ISVAT=N`+`TAXIC=Y` is invalid noise).

| Sales type | Classifier | Net revenue from line | Net revenue from bill |
|------------|------------|-----------------------|-----------------------|
| **VAT sales** | `ISVAT = 'Y'` | `AMOUNT/1.07` if `TAXIC=Y`, else `AMOUNT` | `BEFORETAX` (when bill is VAT) |
| **Non-VAT sales** | `ISVAT = 'N'` | `AMOUNT` (ignore `TAXIC`) | `BEFORETAX` (≈ `AFTERTAX`) |

Recommended dashboard cuts:

- Total net revenue
- Net revenue — VAT sales (`ISVAT=Y`)
- Net revenue — non-VAT sales (`ISVAT=N`)
- (Optional, separate) VAT collected = `sum(TAX)`

### 8.1 Revenue (line-based) — Confirmed net + split; filters TBD

```text
net_line_amount =
  CASE
    WHEN "ISVAT" = 'Y' AND "TAXIC" = 'Y' THEN "AMOUNT_NUM"::numeric / 1.07
    ELSE "AMOUNT_NUM"::numeric
  END

sales_type =
  CASE WHEN "ISVAT" = 'Y' THEN 'VAT' ELSE 'NON_VAT' END

revenue = sum(net_line_amount)
split by: sales_type   -- ISVAT, not TAXIC

Also subtract allocated bill DISCOUNT+DEDUCT (see §6.7) or line totals will not match bill BEFORETAX.
Filters (Confirmed core):
  IS_VALID = 'True', CANCELED = 'N',
  JOURMODE <> '0',
  NOT fn_bi_sales_bill_excluded_from_revenue(BILLNO, BILLTYPE_STD)
    -- TF/TFV/TAR billtypes + CNTF/3CNTF billno prefixes
Sign: CN negative amounts already in data; keep natural sign.
```

### 8.2 Revenue (bill-based) — Confirmed net + filters

```text
revenue = sum("BEFORETAX"::numeric)
  -- already net of bill DISCOUNT/DEDUCT

Filters (Confirmed):
  CANCELED = 'N',
  JOURMODE <> '0',
  NOT fn_bi_sales_bill_excluded_from_revenue(BILLNO, BILLTYPE_STD)

vat_collected (separate) = sum("TAX"::numeric) on VAT docs only
do NOT use "VAT" as money (it is the 7% rate)

VAT vs non-VAT split at bill level (dashboard v1 — Confirmed for overview RPC):
  - VAT: BILLTYPE_STD IN (TAD, TD, TR)
        OR CN/DN with bill TAX <> 0
        OR UNKNOWN billno ~* '^(IV|TA)'
  - NON_VAT: everything else in the revenue include set (mainly UNKNOWN K/C)

Reporting branch (dashboard v1 — Confirmed):
  - ONLINE: TAD, or CN with billno ~* '^CNTAD'  (even though source BRANCH=HQ)
  - HQ / SYP: raw BRANCH for everything else
  - Branch filter + by_branch splits use reporting_branch so HQ is not inflated

Channel (optional dual view):
  - ONLINE vs COUNTER (same ONLINE rule); COUNTER = HQ+SYP store docs

RPC: public.fn_bi_sales_overview(from, to, branch) — branch in (HQ, SYP, ONLINE); see docs/bi/sql/
```

### 8.3 Canonical revenue SQL for interactive dashboards

**Idea:** the “canonical” query is **not** one hardcoded grand total.  
It is a **base grain** (usually line-level) that already applies *invariant* business rules, and exposes dimensions the dashboard can toggle.

```text
Invariant rules (always applied in the base):
  - revenue = net / before tax
  - JOURMODE <> '0'
  - exclude TF, TFV, TAR, CNTF/3CNTF (fn_bi_sales_bill_excluded_from_revenue)
  - CANCELED = 'N' (+ IS_VALID on lines)
  - bill deduct/discount allocated (or documented gap handling)
  - /1.07 only when ISVAT='Y' AND TAXIC='Y'

Interactive filters (applied by the dashboard, NOT baked as one total):
  - sales_type: VAT | NON_VAT | both (no filter)
  - BRANCH, date range, BILLTYPE_STD, salesman, product, …
```

#### Recommended shape: curated view / CTE with dimensions + measure

```sql
-- Conceptual; implement later as curated_kcw.fact_sales_revenue_lines
SELECT
  l."BRANCH",
  l."BILLDATE"::date AS bill_date,
  l."BILLNO",
  b."BILLTYPE_STD",
  l."BCODE",
  l."ISVAT",
  CASE WHEN l."ISVAT" = 'Y' THEN 'VAT' ELSE 'NON_VAT' END AS sales_type,
  l."TAXIC",
  /* net line revenue after VAT strip + bill-gap allocation */
  net_line_amount AS revenue_net
FROM /* lines joined bills, filters, alloc… */ ;
```

#### How the VAT toggle works

| Dashboard control | SQL effect on the same base |
|-------------------|-----------------------------|
| **Both** | no filter on `sales_type` → `sum(revenue_net)` |
| **VAT only** | `WHERE sales_type = 'VAT'` |
| **Non-VAT only** | `WHERE sales_type = 'NON_VAT'` |
| Split chart | `GROUP BY sales_type` |

Same pattern for branch, month, product, online vs counter (`TAD` vs `UNKNOWN`), etc.

#### Why not three separate revenue definitions?

If you write `revenue_vat_sql`, `revenue_nonvat_sql`, `revenue_all_sql` separately, filters drift.  
One base + dimensions keeps:

- one definition of “net”
- one exclude list
- toggles as plain filters / group-bys

#### Bill-level vs line-level base

| Base grain | Best for | VAT toggle source |
|------------|----------|-------------------|
| **Line** (preferred for product dashboards) | product mix, margin later, `ISVAT` native | `sales_type` from line `ISVAT` |
| **Bill** | company totals, AR | derive `sales_type` from billtype/billno or from lines |

For an interactive BI app: materialize/filter the **line base**, then aggregate in the UI/API:

```text
GET /api/bi/sales/summary?from=&to=&branch=&sales_type=VAT|NON_VAT|ALL
→ SUM(revenue_net) WHERE … optional sales_type
```

### 8.4 Bill count — TBD

```text
count distinct (BRANCH, BILLNO) on the same filtered base as revenue
```

### 8.5 Gross margin — Confirmed

```text
revenue_net = line net after bill-gap alloc (§6.7) + VAT strip (ISVAT=Y & TAXIC=Y → /1.07)
cogs        = (QTY × coalesce(nullif(MTP,0), 1)) × LAST_PURCHASE_COST
gross       = revenue_net − cogs

Ignore XPRICE.
Blank / missing LAST_PURCHASE_COST → exclude line from income totals
  (still listed in blank-cost drilldown for cleanup).
Net income (approx) = gross − app opex only — see kcw-income-data-dictionary.md
RPC: public.fn_bi_income_overview → /bi/income
```

### 8.6 Paid vs credit — TBD

```text
TBD: rules using PAID, CASHED, DUEAMT, PAYSTAT, TERM, ACCTNAME
-- prefer bill grain or bill attributes joined onto the line base
```

### 8.7 Customer ranking — Confirmed

```text
Key: bill "ACCTNO"  (AR customer; NOT line "ACCT_NO", NOT purchase ACCTNO)
Exclude: blank / null / whitespace ACCTNO  (walk-in)

revenue_net = sum(BEFORETAX)  -- same bill filters as §8 sales overview
customer_count = count distinct ACCTNO
bill_count = count bills with ACCTNO
display_name = coalesce(party.party_name, armas.ACCTNAME)  -- blank if both missing
name_source  = party | armas | none

Unmatched (no party row): still ranked by ACCTNO; name may come from ARMAS; expose list for party sync.
Walk-in totals may be reported separately but are outside the ranking set.
```

---

## 9. Open questions (working list)

- [x] `TAXIC` = keyed incl/excl VAT; `ISVAT` = VAT vs non-VAT sale — Confirmed in §6.0
- [x] Official revenue KPI = **net / before tax**; split by **`ISVAT`** — Confirmed in §8.0
- [x] `BILLTYPE_STD` meanings + revenue include/exclude (TF/TFV/TAR/CNTF out; SA/3SA stock-check out; TAD/TD/TR/UNKNOWN/CN/DN in) — Confirmed §6.2
- [x] Always exclude `JOURMODE=0` — Confirmed; maps mainly to `TAR` reopen
- [x] `TD` = VAT credit (`CASHED=N`); `TR` = VAT cash (`CASHED=Y`) — Confirmed
- [ ] How to classify **bill-level** VAT vs non-VAT (no `ISVAT` on bills) — can use `BILLTYPE_STD`/`TAXIC`/`ISVAT` from lines
- [x] Legacy `UNKNOWN` `IV…`/`TA…` count as VAT revenue (historical; not recent)
- [x] `PO` on `CN` = original bill; `PO` on `TAD` = online transaction id
- [x] `MTP` = smallest-unit multiplier; unit price = `PRICE/MTP` or `AMOUNT/(QTY*MTP)`
- [x] `CNTF` / `3CNTF` transfer credit notes excluded from revenue (billno `^(3)?CNTF`; `fn_bi_sales_bill_excluded_from_revenue`) — Confirmed §6.2
- [x] `TAD` / `CNTAD` → BI reporting branch `ONLINE` (exclude from HQ store sales)
- [x] `ISVAT=N` + `TAXIC=Y` — invalid; ignore `TAXIC` (Confirmed)
- [x] Line discounts already in `AMOUNT`; bill `DEDUCT`/`DISCOUNT` must be allocated to lines (Confirmed need)
- [x] Allocation = proportional by line `AMOUNT`; `DEDUCT` on `TAXIC=Y` is **gross**; CN uses same method via **gap** (not blind `DEDUCT`)
- [ ] Credit note / debit note sign handling (`CN`, `DN`)
- [ ] `PAYSTAT` legend and AR aging rules
- [x] Margin COGS = qty×MTP×LAST_PURCHASE_COST; ignore XPRICE; blank cost lines excluded from totals (list kept) — Confirmed §8.5
- [x] Line `ACCTNO` = customer (AR, = bill); line `ACCT_NO` = supplier (AP-leaning) — Confirmed §6.9
- [x] Customer ranking key = bill `ACCTNO` → `party.party_code`; blank excluded; name = party → ARMAS → blank; expose `name_source` — Confirmed §6.9 / §8.7
- [ ] Whether `BILLTYPE = R` headers should appear in any dashboard
- [ ] Default timezone / business day cutoff for `BILLDATE`
- [ ] Richer customer dims from `party_tax_info` / `party_contact` (tax id, phone) on ranking UI

---

## 10. Changelog

| Date | Change | By |
|------|--------|----|
| 2026-07-25 | Initial dictionary from `fact_sales_all` + `fact_sales_bills_all` inspection | Cursor + owner |
| 2026-07-25 | Rechecked bills after upload fix: SYP headers present; join coverage complete for both branches | Cursor |
| 2026-07-25 | Confirmed VAT/TAXIC rules: `TAXIC=Y` ⇒ line `AMOUNT` is VAT-inclusive; bill `"VAT"` is rate, `"TAX"` is baht | Cursor + owner |
| 2026-07-25 | Confirmed dashboard revenue = before tax; split VAT vs non-VAT sales; tax reported separately | Owner |
| 2026-07-25 | Correction: sales type = `ISVAT`; `TAXIC` only means keyed incl/excl VAT (not the VAT-sales flag) | Owner |
| 2026-07-25 | Rule: if `ISVAT=N`, `TAXIC` must be `N` or ignored; never `/1.07` on non-VAT lines | Owner |
| 2026-07-25 | Bill `DEDUCT`/`DISCOUNT` not in line `AMOUNT`; must allocate to lines for reconcile | Owner |
| 2026-07-25 | Lock deduct alloc: proportional by `AMOUNT`; VAT-bill deduct is gross; CN allocate observed gap only | Owner + data |
| 2026-07-25 | Lock BILLTYPE_STD meanings, revenue include/exclude, JOURMODE=0 exclude; TD/TR vs CASHED confirmed | Owner + data |
| 2026-07-25 | Legacy IV/TA UNKNOWN = VAT revenue; TAR/CNTAR scripted & not recent | Owner + data |
| 2026-07-25 | PO meanings: CN→original bill; TAD→online txn id | Owner + data |
| 2026-07-25 | Clarify canonical revenue SQL as filterable base grain for VAT toggles | Cursor |
| 2026-07-25 | MTP = pack→smallest-unit multiplier; unit price = PRICE/MTP | Owner + data |
| 2026-07-25 | TAD/CNTAD reporting_branch=ONLINE; remove from HQ totals | Owner |
| 2026-07-25 | Ship sales overview dashboard + `fn_bi_sales_overview` (bill BEFORETAX; VAT/branch/channel splits) | Cursor |
| 2026-07-26 | Confirm ACCTNO (AR customer) vs ACCT_NO (AP/supplier); customer ranking rules + party master; ship `fn_bi_customer_overview` | Owner + Cursor |
| 2026-07-26 | Lock gross margin §8.5 (LAST_PURCHASE_COST; blank=0; ignore XPRICE) + income report net = gross − opex | Owner + Cursor |
| 2026-07-27 | Cross-link ARMAS/APMAS; `MOBILE` = tax id (see ar-ap dictionary) | Owner |
| 2026-08-08 | Exclude `CNTF`/`3CNTF` transfer credit notes from sales revenue; add `fn_bi_sales_bill_excluded_from_revenue`; document curated split guidance | Owner + Cursor |
| 2026-07-27 | Customer name fallback: party → ARMAS → blank; expose `name_source` | Owner + Cursor |

---

## 11. Scratch / owner notes

> Paste informal notes here during working sessions; promote into sections above when confirmed.

-
