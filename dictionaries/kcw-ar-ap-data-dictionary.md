# KCW AR / AP master data dictionary

Naming for KACC AR/AP **account masters** in `raw_kcw` (ARMAS / APMAS).

Sources:

- `raw_kcw.raw_hq_armas_receivable` — AR / ลูกหนี้ (customer accounts)
- `raw_kcw.raw_hq_apmas_payable` — AP / เจ้าหนี้ (supplier accounts)

Status legend: **Confirmed** · **TBD** · **Inferred**

Last reviewed: 2026-07-27

---

## 1. Schema map

| Object | Grain | Role | Approx rows (2026-07-27) |
|--------|-------|------|-------------------------:|
| `raw_hq_armas_receivable` | 1 row ≈ 1 AR account (`ACCTNO`) | Customer master | ~2,325 |
| `raw_hq_apmas_payable` | 1 row ≈ 1 AP account (`ACCTNO`) | Supplier master | ~988 |

Join keys:

- Sales customer: bill/line `"ACCTNO"` → ARMAS `"ACCTNO"` (and/or `public.party.party_code`)
- Purchase supplier: PIDET `"ACCTNO"` → APMAS `"ACCTNO"`

These tables are **masters only** (name, address, terms, tax id). No open-balance / aging ledger tables in `raw_kcw` yet.

---

## 2. Critical rename: `MOBILE` = tax id (Confirmed)

| Column | Apparent name | Actual meaning | Status |
|--------|---------------|----------------|--------|
| **`MOBILE`** | Mobile phone | **Tax ID / เลขประจำตัวผู้เสียภาษี** | Confirmed |
| `PHONE` | Phone | Phone number(s) | Confirmed (name) |
| `FAX` | Fax | Fax | Confirmed (name) |

### Evidence / BI use

- Values are typically **13-digit** Thai tax ids (sometimes hyphenated / zero-padded placeholders like `0000000000000`).
- Real phone numbers live in **`PHONE`** (may contain multiple numbers comma-separated).
- Do **not** treat `MOBILE` as a contact phone in UI, CRM sync, or customer ranking.

```sql
tax_id = nullif(trim("MOBILE"), '')
-- optional normalize: regexp_replace(tax_id, '[^0-9]', '', 'g')
```

Examples (ARMAS/APMAS): company accounts with `MOBILE` = 13-digit tax id while `PHONE` holds `034-…` / `089-…`.

---

## 3. Other columns (queue)

| Field | Meaning | Status |
|-------|---------|--------|
| `ACCTNO` | Account code (AR customer / AP supplier) | Confirmed (role) |
| `ACCTNAME` | Account display name | Confirmed (name) |
| `JOURMODE` | `1` / `2` — often aligns with VAT vs non-VAT path (same pattern as sales/purchase) | Inferred |
| `ACCTTYPE` | Seen `0`, `1` | TBD |
| `ADDR1` / `ADDR2` | Address | Confirmed (name) |
| `CONTACT` / `EMAIL` | Contact / email | Confirmed (name) |
| `TERM` | Credit term (days) | Inferred |
| `ALLOW` | Credit limit? | TBD |
| `ATPRICE` | Price list / tier? | TBD |
| `MARKUP` | Markup | TBD |
| `BEGDATE` / `ENDDATE` | Active period | TBD |
| `REMARKS` | Free text / payment instructions / `@eom` style flags | TBD |
| `CANCELED` | Canceled flag | Confirmed (name) |

---

## 4. Open questions

- [x] `MOBILE` = tax id (not phone) — Confirmed §2
- [x] Prefer `public.party` as display master, then ARMAS `"ACCTNAME"`, else blank (customer ranking) — Confirmed
- [ ] Full `ACCTTYPE` / `JOURMODE` legend for masters
- [ ] Exact meaning of `ALLOW`, `ATPRICE`, `MARKUP`
- [ ] Ingest AR/AP **transaction** ledgers if needed for aging

---

## 5. Changelog

| Date | Change | By |
|------|--------|----|
| 2026-07-27 | Start AR/AP master dictionary; lock `MOBILE` = tax id | Owner |
| 2026-07-27 | Customer BI uses party first, then ARMAS name fallback | Owner + Cursor |
