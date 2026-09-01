# HQ↔SYP stock transfer (โอนสินค้า)

Operator runbook for the **inventory** transfer workflow (not bank/cheque transfer). App code and service enablement: kcw-api [`docs/transfer.md`](https://github.com/pthengtr/kcw-api/blob/master/docs/transfer.md).

| Item | Value |
|------|--------|
| Service | `kcw-transfer` (`uvicorn app.transfer_app:app`) |
| Port | **8792** |
| LINE | `โอนสินค้า` · rich menu cell **โอนสินค้า** · `menu` / `เมนู` / `services` → services Flex card |
| Sites | **Both** HQ (`TRANSFER_SITE=HQ`) and SYP (`TRANSFER_SITE=SYP`) |
| Workflow DB | Supabase schema `transfer.*` |
| Stock writes | PARTS9 **SIMAS** (ship) + **PIMAS** (receive) — see four-leg table below |

---

## Bidirectional flow

Requester = branch that **needs** stock (`to_branch`). Shipper = branch that **sends** stock (`from_branch`).

| Direction | Submit at | Prepare (ship) | Receive |
|-----------|-----------|----------------|---------|
| **HQ → SYP** | SYP | HQ — **TF** SIMAS on `KSS` | SYP — **TF** PIMAS on `kss-pc` |
| **SYP → HQ** | HQ | SYP — **3TF** SIMAS on `kss-pc` | HQ — **3TF** PIMAS on `KSS` |

Thai shorthand: **ขอ → จัดออก → รับเข้า**. Same UI tabs on both boxes: แนะนำโอน · ขอโอน · รอจัด (ออก) · รอรับ (เข้า) · ประวัติ.

**Partial prepare:** one prepare click = one ship bill; request stays open until all lines are fully shipped.

---

## Parallel with legacy `/po`

The old path remains available:

| Path | What it uses | When |
|------|----------------|------|
| **kcw-transfer** (`:8792`) | Supabase `transfer.*` + optional ICLOW stamp | New three-step UI |
| **kcw-ops `/po`** | `POMAS`/`PODET` + ICLOW tabs | Legacy PO / ค้างรับ / prepare overlay |

When **`TRANSFER_ICLOW_STAMP_ENABLED=true`** on SYP and direction is **HQ→SYP** (`to_branch=SYP`), submit stamps open ICLOW rows (`ORDERED=Y`, `DOCNO=TRF-…`). SYP→HQ does not stamp SYP ICLOW.

See [ICLOW dictionary §8 — kcw-transfer stamp](./../dictionaries/kcw-iclow-pending-receive-data-dictionary.md#8-kcw-transfer-iclow-stamp-syp).

---

## Product rules (`ICMAS`)

| Rule | Meaning |
|------|---------|
| **`QTYMIN = -1`** (or `< 0`) | **Do not restock** — exclude from transfer pick lists and routine ICLOW. See [ICMAS dictionary §6](./../dictionaries/kcw-icmas-data-dictionary.md). |
| Branch | HQ `ICMAS` = HQ on-hand; SYP `ICMAS` = SYP on-hand — never mix without labeling site. |

---

## Where it runs

| Box | Unit | `TRANSFER_SITE` | PARTS9 SQL default | Writer flags |
|-----|------|-----------------|-------------------|--------------|
| `hq-ubuntu-server` | `kcw-transfer.service` | `HQ` | `KSS` (+ SYP via `PARTS9_SYP_SERVER=kss-pc`) | `TRANSFER_HQ_SHIP_WRITE_ENABLED`, `TRANSFER_HQ_RECEIVE_WRITE_ENABLED` |
| `syp-ubuntu-server` | `kcw-transfer.service` | `SYP` | `kss-pc` (HQ stock via peer `TRANSFER_PEER_BASE_URL`) | `TRANSFER_SYP_SHIP_WRITE_ENABLED`, `TRANSFER_SYP_RECEIVE_WRITE_ENABLED`, `TRANSFER_ICLOW_STAMP_ENABLED` |

**Not HQ-only** — unlike pay-notes (`:8791`), transfer runs on **both** Linux boxes.

Pay notes / Tiger Pay stay HQ-only; see [hq-linux.md](./hq-linux.md) and [syp-linux.md](./syp-linux.md).

**SYP box one-time install:** [syp-linux-transfer-setup.md](./syp-linux-transfer-setup.md) (`.env`, systemd, firewall). **kcw-api** (`master`) and **kcw-docs** (`main`) both auto-pull on SYP via GitHub Actions.

---

## Enable (summary)

Full env list: kcw-api `docs/transfer.md`. Minimum:

```env
TRANSFER_ENABLED=true
TRANSFER_SITE=HQ          # or SYP on syp box
TRANSFER_LISTEN_PORT=8792
STOCK_CHECK_TOKEN_SECRET=...
SUPABASE_URL=...
SUPABASE_SERVICE_ROLE_KEY=...
```

Writers stay **off** until live validation on KSS / kss-pc:

```env
TRANSFER_HQ_SHIP_WRITE_ENABLED=false
TRANSFER_SYP_SHIP_WRITE_ENABLED=false
TRANSFER_HQ_RECEIVE_WRITE_ENABLED=false
TRANSFER_SYP_RECEIVE_WRITE_ENABLED=false
TRANSFER_ICLOW_STAMP_ENABLED=false
POS_MSSQL_WRITER_USERNAME=...
POS_MSSQL_WRITER_PASSWORD=...
```

SQL grants: kcw-api `scripts/sql/grant_transfer_writer.sql` (SIMAS + PIMAS on both DBs).

```bash
systemctl --user enable --now kcw-transfer
curl -s http://127.0.0.1:8792/health
```

Supabase migrations: `20260829120000_transfer_schema.sql`, `20260830120000_transfer_direction.sql`.

---

## Deploy / CI

| Box | Workflow | Restart units |
|-----|----------|---------------|
| HQ | `hq-linux-deploy.yml` | includes `kcw-transfer` |
| SYP | `syp-linux-deploy.yml` | includes `kcw-transfer` |

SYP UFW: allow **8792/tcp** on shop LAN (`scripts/syp-linux-firewall.sh`).

---

## Changelog

| Date | Change |
|------|--------|
| 2026-09-01 | Dual stock: SYP peers HQ via `/transfer/api/local-icmas` when SQL hosts collide (`POS_MSSQL` = `PARTS9_SYP` = kss-pc). `TRANSFER_PEER_BASE_URL` + shared token secret. |
| 2026-08-30 | Bidirectional HQ↔SYP — direction fields, four-leg SIMAS/PIMAS writers, role-based UI tabs |
| 2026-08-30 | Initial runbook — kcw-transfer `:8792`, HQ+SYP, parallel `/po`, ICLOW stamp, writer flags |
