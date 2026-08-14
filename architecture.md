# KCW architecture

Three repos, one business. Shared hosted **Supabase** (Postgres, Auth, Storage, RPCs) is the system of record after extract.

```
PARTS9 (HQ + SYP SQL Server)
        │  kcw-analytics BATs / CLI
        ▼
Google Drive (01_raw CSVs)
        │  upload / pipeline
        ▼
Supabase  raw_kcw → curated_kcw → public / ops / bank / stock
        │
        ├── kcw-v2  (Next.js UI + API routes + Edge Function import-bank-statement)
        └── kcw-api (LINE bot, Tiger Pay companion, PC workers)
```

## Data path

- **kcw-analytics** extracts PARTS9 on shop PCs, writes Drive, loads `raw_kcw`, runs TAR/VAT/bank Excel. Local SQL Server stays on HQ/SYP machines.
- **kcw-v2** reads `raw_kcw` / `curated_kcw` / app tables via service-role RPCs (`fn_bi_*`, PO, bank). It enqueues PC work on `ops.job_queue`; it does not run PARTS9.
- **kcw-api** workers on HQ-PC / SYP-PC poll `ops.job_queue` and run the same BATs/CLI as analytics. LINE and LIFF product-scan talk to this API.

## Auth and jobs

- v2 login is Supabase email/password + `kcw_user_roles` / page permissions.
- LINE access is `ops.line_access` in kcw-api; `/liff/*` in v2 is public to Supabase on purpose.
- Background PC work always goes through **`ops.job_queue`** and **`ops.worker_heartbeat`**. Bank Excel upload is an Edge Function, not a PC job.

## Dictionaries

Business meaning for shared tables lives in [dictionaries/](./dictionaries/README.md). Extract how-tos stay in kcw-analytics `docs/`; RPC SQL snapshots stay in kcw-v2 `docs/bi/sql/`.
