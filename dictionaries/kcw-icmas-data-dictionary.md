# KCW ICMAS (product master) data dictionary

Naming and code meanings for product master data in `raw_kcw` ICMAS tables, used to enrich sales BI (join on `BCODE`).

Sources:

- `raw_kcw.raw_hq_icmas_products`
- `raw_kcw.raw_syp_icmas_products`
- Drive curated dims (reference): [kcw_analytics / 03_curated](https://drive.google.com/drive/folders/1zn_5KoMRFOOBQFDTj0STRPsR-TXpQIQe)

Status legend: **Confirmed** · **TBD** · **Inferred**

Last reviewed: 2026-08-29

---

## 1. Schema map (products)

| Object | Grain | Role |
|--------|-------|------|
| `raw_kcw.raw_hq_icmas_products` | 1 row ≈ 1 product (`BCODE`) at HQ | Product attributes, prices, costs, pack MTPs |
| `raw_kcw.raw_syp_icmas_products` | same for SYP | Branch product master |
| Drive `dim_product.csv` | curated product dim | `BCODE`, `DETAIL`, `UI`, `CATEGORY_CODE` |
| Drive `dim_category.csv` | category codes | `CATEGORY_CODE` = first 2 digits of `BCODE`; **names in §2.1** (KACC9) |

Join to sales lines: `fact_sales_all."BCODE" = icmas."BCODE"` (prefer HQ master unless SYP-only item).

---

## 2. `BCODE` structure (working)

| Part | Meaning | Status |
|------|---------|--------|
| Digits 1–2 | `CATEGORY_CODE` / หมวดสินค้า (KACC9) — aligns with ICMAS `MAIN` | Confirmed |
| Rest | Item identity within category | TBD detail |

Drive `dim_category.csv` has codes only; **names below are the business legend** (KACC9).

### 2.1 หมวดสินค้า / `CATEGORY_CODE` = `left(BCODE, 2)` (Confirmed)

| Code | หมวดสินค้า (KACC9) | Status |
|------|-------------------|--------|
| `01` | TX จิ๊ป แลนด์ | Confirmed |
| `02` | I/S JCM FV FXZ DECA TX บรรทุก 10 ล้อ | Confirmed |
| `03` | I/S KBZ TFR D-MAX กระบะ | Confirmed |
| `04` | I/S ELF-KS NPR NKR NQR บรรทุก 4-6 ล้อ | Confirmed |
| `05` | NISSAN (D/S) กระบะ เก๋ง | Confirmed |
| `06` | NISSAN UD CW CMA บรรทุก 6-10 ล้อ | Confirmed |
| `07` | MAZDA FORD กระบะ เก๋ง | Confirmed |
| `08` | TOYOTA กระบะ เก๋ง | Confirmed |
| `09` | HINO | Confirmed |
| `10` | FUSO | Confirmed |
| `11` | MITSUBISHI กระบะ เก๋ง | Confirmed |
| `12` | รถไถ FORD JOHNDEERE | Confirmed |
| `13` | ทั่วไป โช้คอัพ ไฟ ยาง | Confirmed |
| `14` | เครื่องเหล็ก เครื่องมือ | Confirmed |
| `15` | ลูกปืน | Confirmed |
| `16` | HONDA รถญี่ปุ่น เกาหลี ทั่วไป | Confirmed |
| `17` | สกรู MIC ดำ | Confirmed |
| `18` | สกรู NF ละเอียด | Confirmed |
| `19` | สกรู NC หยาบ | Confirmed |
| `20` | สกรู MIC ขาว | Confirmed |
| `21` | แบตเตอรี่ น้ำกรด น้ำกลั่น | Confirmed |
| `22` | น้ำมัน จารบี น้ำยา | Confirmed |
| `23` | รถยุโรป BENZ BMW | Confirmed |
| `24` | อะไหล่เก่า เชียงกง | Confirmed |
| `25` | ยางโอริง | Confirmed |
| `26` | สายอ่อน | Confirmed |
| `27` | บัส | Confirmed |
| `28` | พ่วง เทลเลอร์ ดั๊ม | Confirmed |
| `29` | ประดับยนต์ | Confirmed |
| `30` | รถไถ KUBOTA | Confirmed |
| `31` | รถไถ MASSEY (แมสซี่ย์) | Confirmed |
| `32` | แม็คโคร | Confirmed |
| `33` | อัดสายไฮดรอลิค | Confirmed |
| `34` | โฟคลิฟ รถยก | Confirmed |
| `35` | รถไถ ยันม่าร์ อิเซกิ ฮิโนโมโต้ แชมป์ | Confirmed |
| `40` | ค่าแรง | Confirmed |
| `70` | ค่าใช้จ่าย เทิร์นแบตเก่า | Confirmed |
| `91` | โปรโมชั่น / พิเศษ | Confirmed |

```sql
category_code = lpad(left("BCODE", 2), 2, '0')  -- or left(BCODE,2) when already zero-padded
-- label: join dim / CASE map above
```

Notes:

- Drive `dim_category.csv` also lists `88` (rare in ICMAS) — **name TBD** (not in KACC9 list above).
- Prefer labeling sales/product reports with this หมวด, not only raw `BCODE` prefix.

---

## 3. `CODE1` — part-type / item-class letter (Confirmed)

Owner-provided legend. Field: ICMAS `"CODE1"` (single letter on the product).

Use for: product-type filters/facets (seal, bearing, filter, …), separate from `BCODE` 2-digit category.

| CODE1 | Category (Thai) | Status | HQ row count (approx, non-canceled) |
|-------|-----------------|--------|-------------------------------------:|
| `A` | ถ่าน | Confirmed | ~424 |
| `C` | ซีล | Confirmed | ~3,044 |
| `D` | บู๊ช | Confirmed | ~860 |
| `E` | ลูกปืนเข็ม/กรงนก | Confirmed | ~356 |
| `F` | ไส้กรองอากาศ | Confirmed | ~669 |
| `G` | ยอยกากบาท | Confirmed | ~383 |
| `I` | ลูกปืนตลับ / ลูกปืน | Confirmed | ~2,281 |
| `K` | จานคลัช | Confirmed | ~1,010 |
| `L` | สายอ่อน | Confirmed | ~436 |
| `O` | โอริง | Confirmed | ~1,567 |
| `P` | ไส้กรองน้ำมันเครื่อง | Confirmed | ~546 |
| `Q` | ลูกหมาก | Confirmed | ~301 |
| `R` | ลูกยาง | Confirmed | ~49 |

### Notes / gotchas

1. **Most products have `CODE1` null** (~103k HQ rows) — letter class is only populated for some parts families; null ≠ “unknown category from BCODE”.
2. Dirty values exist (spaces, `C `, `CC`, Thai `จ`, `.`, `-`, digits). For BI, prefer:
   ```sql
   upper(trim("CODE1"))
   ```
   and only map letters in the table above; else `NULL` / `OTHER`.
3. **`CODE1` ≠ `CATEGORY_CODE`**  
   - `CATEGORY_CODE` / `left(BCODE,2)` / `MAIN` = broad catalog group  
   - `CODE1` = part-type letter (ซีล, ลูกปืน, …)

### Proposed label expression

```sql
CASE upper(trim("CODE1"))
  WHEN 'A' THEN 'ถ่าน'
  WHEN 'C' THEN 'ซีล'
  WHEN 'D' THEN 'บู๊ช'
  WHEN 'E' THEN 'ลูกปืนเข็ม/กรงนก'
  WHEN 'F' THEN 'ไส้กรองอากาศ'
  WHEN 'G' THEN 'ยอยกากบาท'
  WHEN 'I' THEN 'ลูกปืนตลับ / ลูกปืน'
  WHEN 'K' THEN 'จานคลัช'
  WHEN 'L' THEN 'สายอ่อน'
  WHEN 'O' THEN 'โอริง'
  WHEN 'P' THEN 'ไส้กรองน้ำมันเครื่อง'
  WHEN 'Q' THEN 'ลูกหมาก'
  WHEN 'R' THEN 'ลูกยาง'
  ELSE NULL
END AS code1_category
```

---

## 4. Part numbers: `PCODE` / `MCODE` (Confirmed)

| Field | Meaning | Status | Notes |
|-------|---------|--------|-------|
| `PCODE` | **เบอร์แท้** (genuine / OEM / maker part no.) | Confirmed | Often looks like OEM catalog no. (`203-07150B`, `1121210010`). Some dirty values exist (`ราคา 09/2008`, `69ซม.`) — treat as free text, not always a clean PN |
| `MCODE` | **เบอร์โรงงาน** (factory / internal supplier part no.) | Confirmed | Factory/cross-ref number (`HTC105-135-14`, `01A-BAD146-4B`) |

Examples (HQ ICMAS):

| BCODE | DESCR | PCODE (เบอร์แท้) | MCODE (เบอร์โรงงาน) |
|-------|-------|------------------|---------------------|
| 01010044 | ซีลข้อเหวี่ยง | MO-1484S | HTC105-135-14 |
| 01010045 | หม้อลมเบรค | 203-07150B | 01A-BAD146-4B |
| 01010080 | ซีลล้อหน้า | AAA077-AO | TAY75-115-20.5 |

**BI use:** search / match alternate part numbers; do not use as grain key (use `BCODE`).

---

## 4a. Short names: `ACODE` / `XCODE` (Confirmed)

| Field | Meaning | Status | Notes |
|-------|---------|--------|-------|
| **`ACODE`** | **ชื่อย่อ / staff short name** for search & POS | Confirmed | ~115k HQ rows populated. Thai (+ optional Latin brand suffix). Primary key for staff shorthand search in KCW Ask / LINE bot. |
| **`XCODE`** | Spec / grade code (often viscosity or pack spec) | Confirmed (role) | Examples: `15W-40`, `68-200`. Not the same as `ACODE`; searched as auxiliary text. |

### `ACODE` patterns (Confirmed examples)

| ACODE | DESCR (abbrev) | BRAND | Meaning |
|-------|----------------|-------|---------|
| `นมคPT` | น.ม.ค.PTT 15W-40 | PTT | Engine oil + PTT |
| `นมฮBC` | น.ม.ฮ.บางจาก | BC | Hydraulic + Bangchak |
| `นมกCT` | น.ม.ก.คาสตรอล | CT | Gear oil + Castrol |
| `ลป` / `ลปก` | ลูกปืน-related parts | … | Bearing family shorthand |
| `ยอร` | โอริง-related | … | O-ring family shorthand |

**Oil/fluid ACODE prefix (category `22` usually):**

| Prefix | Thai | Brand suffix (examples) |
|--------|------|---------------------------|
| `นมค` | น้ำมันเครื่อง | `PT`=PTT, `BC`=บางจาก, `CT`=Castrol, `SH`=Shell, … |
| `นมก` | น้ำมันเกียร์ | same pattern |
| `นมฮ` | น้ำมันไฮดรอลิค | same pattern |

`DESCR` often repeats dotted forms (`น.ม.ฮ.`, `นมก.`) — useful fallback when `ACODE` is blank.

**Search use:** match `ACODE` with prefix (`นมฮ%`) and brand suffix (`%PT%`); also search `DESCR`, `MODEL`, `BRAND`, `PCODE`, `MCODE`, `XCODE`. KCW Ask: `lib/icmas-short-names.mjs`.

```sql
-- example: hydraulic PTT
WHERE LTRIM(RTRIM(ACODE)) LIKE N'นมฮ%'
  AND (LTRIM(RTRIM(ACODE)) LIKE N'%PT%' OR BRAND LIKE N'%PTT%')
```

---

## 5. Units & prices: `UI*` / `MTP*` / `PRICE*` / `PRICEM*` (Confirmed)

Pack hierarchy on the product master:

| Field | Meaning | Status |
|-------|---------|--------|
| `UI1` | **Smallest unit** name (ชิ้น/ตัว/แผ่น/…) | Confirmed |
| `UI2` | **Large unit** name (กล่อง/ลัง/ถุง/…) | Confirmed |
| `MTP2` | How many **small units** in one **large unit** (`UI2`) | Confirmed |
| `PRICE1`…`PRICE5` (`PRICEx`) | Price for the **small unit** (`UI1`) | Confirmed (family) |
| `PRICEM1`…`PRICEM5` (`PRICEMx`) | Price for the **large unit** (`UI2`) | Confirmed (family) |

```text
1 × UI2  =  MTP2 × UI1
PRICEMx  ≈  price of one large pack
PRICEx   ≈  price of one small unit
```

Example: `UI1=ชุด`, `UI2=กล่อง`, `MTP2=10`, `PRICE1=25`, `PRICEM1=170`  
→ box of 10; small unit 25; box 170.

### Relation to sales fact `UI` / `MTP`

Sales line `"UI"` / `"MTP"` (see sales dictionary) are the **sold** pack on the bill.  
ICMAS `UI1`/`UI2`/`MTP2` are the **master** pack definition. They often align but are not guaranteed identical on every bill line.

### Still TBD in this family

| Field | Question |
|-------|----------|
| `UI3` / `UI4`, `MTP3` / `MTP4` | Extra pack levels? |
| Which of `PRICE1`…`PRICE5` is the “list” price vs tier | Price list levels |
| When `MTP2=0` or `PRICEM*=0` / null | Treat as unused large-pack slot |

---

## 6. On-hand stock: `QTYOH*` (Confirmed)

| Field | Meaning | Status | Notes |
|-------|---------|--------|-------|
| **`QTYOH2`** | **Remaining stock / คงเหลือ** in **smallest units** (`UI1`) | Confirmed | Sole field for on-hand inventory KPIs; covers both small- and large-unit movements |
| `QTYOH1` | Not used for remaining stock | Confirmed (do not use) | Populated on many HQ rows, but **not** the business remaining-stock quantity |
| `QTYOHA` / `QTYOHB` / `QTYOHC` | Unused for remaining stock | Confirmed (do not use) | Effectively empty / zero in HQ ICMAS |

```sql
on_hand_small_units = nullif(trim("QTYOH2"), '')::numeric   -- remaining stock only
-- do NOT sum/prefer QTYOH1, QTYOHA, QTYOHB, QTYOHC for คงเหลือ
```

**Unit rule (Confirmed):** `QTYOH2` is a single balance in **small units** (`UI1`). It already reflects sales/issues in either pack size:

| Sale / movement | Effect on `QTYOH2` |
|-----------------|--------------------|
| 1 × small unit (`UI1`) | −1 |
| 1 × large unit (`UI2`) | **−`MTP2`** (small units in one large pack) |

```text
1 × UI2 sold  →  QTYOH2 decreases by MTP2
1 × UI1 sold  →  QTYOH2 decreases by 1
```

Do **not** treat `QTYOH2` as a large-unit count, and do **not** divide by `MTP2` to get “pieces” — it is already in small-unit terms. Optional display: `QTYOH2 / MTP2` ≈ whole large packs on hand (when `MTP2 > 0`).

Notes:

- Stock is per ICMAS branch master: HQ rows → HQ on-hand; SYP rows → SYP on-hand. Do not mix without labeling branch.
- Related qty family: `QTYBEG*`, **`QTYMIN`**, `QTYMAX`, `QTYGET`, `QTYPUT`.
  - **`QTYMIN < 0` (usually `-1`)** — Confirmed operational convention: **do not restock / do not ICLOW**. Stock-check Take N excludes these from routine pools; **kcw-transfer** pick lists exclude them too. Risk pools may still include them. Not the same as `QTYOH2 < 0` (on-hand anomaly). See [ops/transfer.md](../ops/transfer.md).

---

## 7. `SIZE1` / `SIZE2` / `SIZE3` by `CODE1` (Confirmed)

Size columns are **dimension slots**; their meaning depends on `CODE1`.

| CODE1 | Category | SIZE1 | SIZE2 | SIZE3 | Status |
|-------|----------|-------|-------|-------|--------|
| `A` | ถ่าน | สูง | กว้าง | — | Confirmed |
| `C` | ซีล | ใน | นอก | หนา | Confirmed |
| `D` | บู๊ช | ใน | นอก | หนา | Confirmed |
| `E` | ลูกปืนเข็ม/กรงนก | ใน | นอก | หนา | Confirmed |
| `F` | ไส้กรองอากาศ | ใน | นอก | สูง | Confirmed |
| `G` | ยอยกากบาท | ปลอก | ยาว | — | Confirmed |
| `I` | ลูกปืนตลับ | ใน | นอก | หนา | Confirmed |
| `K` | จานคลัช | ยาว(นิ้ว) | ฟัน | ขนาดรูเฟือง | Confirmed |
| `L` | สายอ่อน | หัวสาย 1 | หัวสาย 2 | ยาว | Confirmed |
| `O` | โอริง | ใน | หนา | — | Confirmed |
| `P` | ไส้กรองน้ำมันเครื่อง | ใน | นอก | สูง | Confirmed |
| `Q` | ลูกหมาก | TBD | TBD | TBD | TBD |
| `R` | ลูกยาง | TBD | TBD | TBD | TBD |

`—` = slot not used for that part type.

**BI tip:** when showing sizes, label columns from `CODE1` (e.g. for `C`: `SIZE1`→ใน, `SIZE2`→นอก, `SIZE3`→หนา). Do not use one global “size1/2/3” label across all products.

Example (`CODE1=C` ซีล): `SIZE1=31`, `SIZE2=46`, `SIZE3=7` → ใน 31 / นอก 46 / หนา 7.

---

## 8. Other ICMAS codes (queue)

| Field | Meaning | Status |
|-------|---------|--------|
| `CODE2` / `CODE3` / `CODE4` | TBD | TBD |
| `XCODE` | Spec / grade code (viscosity, pack code) — see §4a | Confirmed |
| `ACODE` | Staff short name (ชื่อย่อ) — see §4a | Confirmed |
| `MAIN` / `SUB` / `PART` | Aligns with BCODE structure; names TBD | Inferred |
| `CATEGORY_CODE` / `left(BCODE,2)` | หมวดสินค้า KACC9 | Confirmed — full legend in §2.1 |
| `QTYOH2` | Remaining stock in small units (`UI1`); large sale −`MTP2` | Confirmed — §6 |
| `DESCR`, `BRAND`, `MODEL` | Description / brand / model | Confirmed (name) |

---

## 9. Open questions

- [x] `CODE1` letter meanings (A/C/D/E/F/G/I/K/L/O/P/Q/R) — Confirmed
- [x] `PCODE` = เบอร์แท้; `MCODE` = เบอร์โรงงาน — Confirmed
- [x] `UI1`/`UI2`/`MTP2` + `PRICEx`/`PRICEMx` pack & price rules — Confirmed
- [x] `SIZE1–3` meanings by `CODE1` (A/C/D/E/F/G/I/K/L/O/P) — Confirmed
- [x] หมวดสินค้า `CATEGORY_CODE` / first 2 digits of `BCODE` (KACC9) — Confirmed §2.1
- [x] Remaining stock = `QTYOH2` only — Confirmed §6
- [x] `QTYOH2` in small units (`UI1`); large-unit sale reduces by `MTP2` — Confirmed §6
- [ ] `SIZE*` meanings for `CODE1` = `Q`, `R`
- [ ] Name for rare code `88` (in Drive dim, not in KACC9 list)
- [ ] Meanings of `CODE2`–`CODE4`
- [x] `ACODE` = staff short name; `XCODE` = spec/grade code — Confirmed §4a
- [ ] `UI3`/`UI4`/`MTP3`/`MTP4` and price-tier roles of `PRICE1`…`PRICE5`
- [ ] Which master to prefer when HQ and SYP ICMAS disagree on the same `BCODE`
- [ ] Whether to curate `dim_code1` / size labels into Supabase `curated_kcw`

---

## 10. Changelog

| Date | Change | By |
|------|--------|----|
| 2026-07-26 | Start ICMAS dictionary; lock `CODE1` category letters | Owner |
| 2026-07-26 | Lock `PCODE`=เบอร์แท้, `MCODE`=เบอร์โรงงาน | Owner |
| 2026-07-26 | Lock UI/MTP/PRICE pack rules + SIZE1–3 meanings by CODE1 | Owner |
| 2026-07-26 | Lock KACC9 หมวดสินค้า names for BCODE first 2 digits | Owner |
| 2026-07-26 | Lock remaining stock = `QTYOH2` only | Owner |
| 2026-07-26 | Lock `QTYOH2` = small-unit balance; large sale −`MTP2` | Owner |
| 2026-08-29 | Lock `ACODE` = staff short name; `XCODE` = spec code — §4a | Owner |
