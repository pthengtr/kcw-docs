# What lives where

## This repo (`kcw-docs`)

- Data dictionaries (canonical)
- Cross-repo architecture and the map of the three apps

Do not put `.env` examples, SQL migrations, or “how to run npm/python” here.

## [kcw-api](https://github.com/pthengtr/kcw-api)

- FastAPI app, LINE webhook, Tiger Pay companion, stock-check LAN UI
- PC worker process that polls `ops.job_queue`
- Cloud/agent runbooks: `AGENTS.md`, `docs/cloud-environment.md`

Use dictionaries for ICMAS / product codes when LINE or scan features touch `BCODE`.

## [kcw-v2](https://github.com/pthengtr/kcw-v2)

- Next.js ERP/BI UI and API routes
- RPC SQL snapshots under `docs/bi/sql/`
- App-only docs: worker jobs, bank-statement upload, LIFF, stock-audit, product-image KPI

Dictionaries used to live in `docs/bi/*-data-dictionary.md`. Those paths are now stubs that point here.

## [kcw-analytics](https://github.com/pthengtr/kcw-analytics)

- PARTS9 extract, Drive layers, TAR, VAT Excel, bank import BATs/CLI
- Extract validation notes (`docs/parts9_*.md`) — keep those; they link to dictionaries for the contract
