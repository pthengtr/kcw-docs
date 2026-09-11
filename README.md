# KCW docs

Shared knowledge for the three KCW apps. **Data dictionaries** are the contract for tables, grain, codes, and Confirmed vs TBD rules. Update them here, not in chat and not by copying between repos.

| App | Repo | Role |
|-----|------|------|
| API / LINE / PC workers | [kcw-api](https://github.com/pthengtr/kcw-api) | FastAPI, LINE webhook, HQ/SYP workers polling `ops.job_queue` |
| Web ERP / BI | [kcw-v2](https://github.com/pthengtr/kcw-v2) | Next.js back-office, BI RPCs, bank upload |
| Extract / TAR / reports | [kcw-analytics](https://github.com/pthengtr/kcw-analytics) | PARTS9 → Drive → Supabase, BATs, notebooks |

## Start here

- [Data dictionaries](./dictionaries/README.md) — shared business meaning (sales, ICMAS, PO, ICLOW, VAT, …)
- [Architecture](./architecture.md) — how the three repos share Supabase, Drive, LINE, and workers
- [What lives where](./repos.md)
- [Ops / Linux HQ-PC](./ops/hq-linux.md) — remote access, GDM on demand, UPS (NUT + AC BACK + RTC wake), kcw-analytics Linux setup, dead ends (Jump, virtual monitor)
- [Local Qwen3.6 delegation](./ops/local-qwen3.6-delegation.md) — DGX Spark vLLM worker: what agents can safely offload vs. verify

Local clone on this machine: `/home/hqadmin/projects/kcw-docs` (sibling of the three app repos).
