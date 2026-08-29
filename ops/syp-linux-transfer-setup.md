# SYP Ubuntu — kcw-transfer setup (`syp-ubuntu-server`)

One-time checklist for **`sypadmin`** on the SYP Linux box after [kcw-transfer](https://github.com/pthengtr/kcw-api/pull/101) merges to `kcw-api` `master`.

Operator runbook: [transfer.md](./transfer.md). Service env reference: kcw-api [`docs/transfer.md`](https://github.com/pthengtr/kcw-api/blob/master/docs/transfer.md).

---

## What runs automatically (GitHub Actions)

**kcw-docs** — same pattern: push to `main` auto-pulls on this box via GitHub Actions (`.github/workflows/syp-linux-deploy.yml`). Manual pull only if the runner is down.

| Repo | Trigger | Runner on this box | Script |
|------|---------|-------------------|--------|
| **kcw-api** | push to `master` | `self-hosted, linux, syp` | `scripts/syp-linux-deploy.sh` |
| **kcw-docs** | push to `main` | `self-hosted, linux, syp` | `git reset --hard origin/main` in `~/projects/kcw-docs` |

Each deploy:

1. `git fetch` + `git reset --hard origin/master` in `~/projects/kcw-api`
2. `pip install -r requirements.txt` (venv)
3. Restart `kcw-stock-check`, `kcw-parts9-explorer`, `kcw-ops`, and **`kcw-transfer`** (if the unit is already installed)
4. Start/restart `kcw-worker` only if it was stopped (or when `FORCE_WORKER_RESTART=1`)

**You must do the steps below once** before the first post-merge deploy can start `kcw-transfer`. After that, routine code updates are automatic on `master` push.

---

## One-time setup (run on SYP box)

SSH or NoMachine to **`syp-ubuntu-server`** as `sypadmin`.

### 0. Supabase migrations (once per project — usually HQ first)

Apply kcw-api migrations **before** the app can use `transfer.*`:

- `supabase/migrations/20260829120000_transfer_schema.sql`
- `supabase/migrations/20260829121000_transfer_grants.sql`

Run from a machine with Supabase access (often **HQ**), not necessarily on SYP:

```bash
cd ~/projects/kcw-api
# if you use Supabase CLI linked to the project:
supabase db push
# or apply the two SQL files via Supabase dashboard / SQL editor
```

SYP only needs `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` in `.env` (same as other kcw-api services).

---

### 1. Pull kcw-api (if merge already landed)

Either wait for GitHub Actions after merge, or pull manually:

```bash
cd ~/projects/kcw-api
git fetch origin
git checkout master
git pull origin master
```

---

### 2. Add to `~/projects/kcw-api/.env`

Append (do **not** commit `.env`):

```env
# kcw-transfer — SYP site (submit + receive)
TRANSFER_ENABLED=true
TRANSFER_SITE=SYP
TRANSFER_LISTEN_PORT=8792

# Writers OFF until validated on kss-pc (see §4)
TRANSFER_HQ_WRITE_ENABLED=false
TRANSFER_SYP_RECEIVE_ENABLED=false
TRANSFER_ICLOW_STAMP_ENABLED=false
```

**Already required** by other services on this box (reuse, do not duplicate):

- `STOCK_CHECK_TOKEN_SECRET` — LINE / HMAC auth (transfer falls back to this)
- `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`
- `POS_MSSQL_SERVER` / `PARTS9_SYP_SERVER` → `kss-pc,KSS-PC` (SYP PARTS9)
- `WORKER_NAME=SYP-UBUNTU-SERVER`

**Optional** — public URLs for LINE links (worker heartbeat):

```env
TRANSFER_PUBLIC_BASE_URL=http://<shop-lan-ip>:8792
TRANSFER_TAILSCALE_BASE_URL=http://100.94.98.18:8792
```

Use this box’s real LAN IP and Tailscale IP. If omitted, worker may still resolve URLs from heartbeat/env on HQ.

---

### 3. Install and start systemd unit

```bash
mkdir -p ~/.config/systemd/user
cp ~/projects/kcw-api/scripts/systemd/kcw-transfer.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now kcw-transfer
```

Check:

```bash
systemctl --user status kcw-transfer --no-pager
curl -s http://127.0.0.1:8792/health
journalctl --user -u kcw-transfer -n 40 --no-pager
```

---

### 4. Firewall (allow `:8792` on shop LAN)

Re-run the idempotent script (includes 8787, 8788, 8790, **8792**):

```bash
bash ~/projects/kcw-api/scripts/syp-linux-firewall.sh
sudo ufw status verbose | grep 8792
```

Tailscale access uses the existing `tailscale0` rule (no extra port rule needed).

---

### 5. kcw-docs (automatic after merge)

On push to `kcw-docs` `main`, GitHub Actions pulls `~/projects/kcw-docs` on this box. After the docs PR merges, the next push (or re-run the workflow) updates the tree.

Manual fallback:

```bash
cd ~/projects/kcw-docs && git fetch origin && git reset --hard origin/main
```

Or: `bash ~/projects/kcw-docs/scripts/syp-linux-deploy.sh`

Read on this box:

- [ops/transfer.md](./transfer.md) — operator flow
- [ops/syp-linux.md](./syp-linux.md) — full SYP runbook

---

### 6. Smoke test

```bash
# Service up
curl -s http://127.0.0.1:8792/health

# Worker heartbeat should include transfer URLs after next heartbeat tick
# (check Supabase ops.worker_heartbeat for SYP-UBUNTU-SERVER)

# From shop LAN or Tailscale browser (with valid LINE token / tailnet):
# http://<this-box>:8792/transfer/
```

LINE: `โอนสินค้า` or rich menu **โอนสินค้า** (rich menu image deploy is separate — see HQ).

---

## Later: enable PARTS9 writers (after live test)

Only on **kss-pc** (`PARTS9` SYP DB), after SQL grants:

```bash
# On kss-pc / via WinRM+sqlcmd — run as admin:
# ~/projects/kcw-api/scripts/sql/grant_transfer_writer.sql
```

Then on SYP `.env`:

```env
POS_MSSQL_WRITER_USERNAME=python_writer
POS_MSSQL_WRITER_PASSWORD=...
TRANSFER_ICLOW_STAMP_ENABLED=true    # stamp ICLOW on submit
TRANSFER_SYP_RECEIVE_ENABLED=true    # receive TF on kss-pc
```

```bash
systemctl --user restart kcw-transfer
```

HQ prepares TF bills (`TRANSFER_HQ_WRITE_ENABLED=true` on **hq-ubuntu-server** only).

---

## Troubleshooting

| Symptom | Check |
|---------|--------|
| GitHub Action deploy failed on `kcw-transfer` | Unit not installed yet — complete **§3** above |
| `health` fails / connection refused | `systemctl --user status kcw-transfer`; port clash on 8792 |
| UI 401 / no LINE link | `STOCK_CHECK_TOKEN_SECRET` set; token in URL `?t=` |
| Empty transfer list / DB errors | Supabase migrations applied? (`transfer.*` schema) |
| Cannot reach from shop phone | UFW **§4**; use LAN IP on `enp3s0` |
| Writer errors | Grants on kss-pc; flags still `false` until validated |

Force worker restart after env change (optional):

```bash
FORCE_WORKER_RESTART=1 bash ~/projects/kcw-api/scripts/syp-linux-deploy.sh
```

Or manually: `systemctl --user restart kcw-worker kcw-transfer`

---

## Changelog

| Date | Change |
|------|--------|
| 2026-08-30 | Initial SYP one-time setup for kcw-transfer `:8792` |
| 2026-08-30 | kcw-docs auto-deploy on `main` (GitHub Actions, same SYP runner as kcw-api) |
