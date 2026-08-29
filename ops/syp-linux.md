# Linux SYP box runbook

Living notes for the Ubuntu SYP box (`sypadmin` / Tailscale `syp-ubuntu-server`). This machine **replaces Windows SYP-PC** for kcw-api worker + LAN services. Update after every non-obvious setup choice.

Sibling of the HQ Linux notes: [hq-linux.md](./hq-linux.md). Shared ideas (rclone Shared Drive, ODBC 18, linger, systemd user units) apply; site-specific values differ.

**Reference machine (2026-08-26):** Ubuntu, user `sypadmin`, Tailscale `syp-ubuntu-server`, repos under `~/projects/`.

---

## Goal

| Role | Name / value |
|------|----------------|
| Queue worker | `WORKER_NAME=SYP-UBUNTU-SERVER` |
| Stock-check / ops / explorer site | `SYP` |
| PARTS9 SQL (this box) | Tailscale **`kss-pc`** (shop `KSS-PC`) |
| HQ PARTS9 | Windows name **`KSS`** — HQ LAN only, **not on Tailscale** |
| Drive | rclone Shared drive **KCW-Data** → `~/mnt/gdrive/KCW-Data` |
| Daily schedules | **None on this box** — do not enable `kcw-hq-full.timer` (HQ B lives on `hq-ubuntu-server`) |
| Tiger Pay | **Not on this box** — companion / `:8000` stays on HQ (Windows HQ-PC or `hq-ubuntu-server`) |
| Pay notes / ชำระเจ้าหนี้ (`:8791`) | **Not on this box** — HQ-only (`kcw-pay-notes` on `hq-ubuntu-server`) |
| Transfer / โอนสินค้า (`:8792`) | **On this box** — `TRANSFER_SITE=SYP` (submit + receive); HQ box prepares TF bills |

Do **not** run this box as `HQ-UBUNTU-SERVER`, enable HQ daily timers, start `kcw-tiger-pay` or `kcw-pay-notes`, or point stock-check / inventory at HQ `KSS`.

### SQL hosts (easy to mix up)

| Name | Machine | Reachability | Use on SYP Ubuntu |
|------|---------|--------------|-------------------|
| `kss-pc` | SYP shop PARTS9 (`KSS-PC`) | Tailscale MagicDNS | **Default** — stock-check, inventory, SYP extract/sync |
| `KSS` / `KSS.local` | HQ PARTS9 | HQ LAN only (no Tailscale) | Not for inventory/stock-check here |

`POS_MSSQL_SERVER` and `PARTS9_SYP_SERVER` on this box: `kss-pc,KSS-PC`.  
Analytic inventory: `BRANCH=SYP` / `KCW_BRANCH=SYP` so notebook 50 calls `mssql_engine("syp")`.

### Wake-on-LAN (kss-pc / KSS-PC)

Same shop Windows box as PARTS9 SQL. MAC learned from ARP on this LAN (2026-08-27):

| Field | Value |
|-------|--------|
| Host | `kss-pc` / `KSS-PC` |
| LAN IP | `192.168.1.189` |
| **MAC** | **`6c:0b:5e:47:06:d1`** |
| Tailscale | `100.68.177.59` |
| Broadcast | `192.168.1.255` |
| Send from | `enp3s0` on this box |

When the shop PC is asleep/off and WoL is enabled in BIOS + NIC:

```bash
bash ~/projects/kcw-api/scripts/wol-kss-pc.sh
# or manually:
sudo apt install -y wakeonlan   # once
wakeonlan -i 192.168.1.255 -p 9 6c:0b:5e:47:06:d1
```

WoL only works on **LAN** (this box → broadcast). Tailscale cannot carry magic packets. If ARP is empty after long downtime, use the MAC above — do not rely on `ip neigh` alone.

---

## Blockers (fill before enable --now)

As of 2026-08-26 on this box:

1. **Secrets** — filled from `~/Downloads/credential-*.zip` (`.env_api` / `.env_analytic`), keeping SYP hosts (`kss-pc`) and `WORKER_NAME=SYP-UBUNTU-SERVER`. Do not commit `.env`.

2. **Deploy code** — merge PRs that add `SYP-UBUNTU-SERVER` preference (kcw-api Railway + kcw-v2 Supabase RPC). Until merged, enqueue may still target `SYP-PC`.

**Drive (2026-08-26):** OAuth as `admin@kcw.app` (org-internal client). Mount unit enabled; linger already on.

**Services (2026-08-27):** four kcw-api user units enabled and running on this box. Add **`kcw-transfer`** (`:8792`) after merge — five units total.

---

## GitHub Actions auto-deploy

Self-hosted runner label: **`self-hosted, linux, syp`**. Workflow: `kcw-api/.github/workflows/syp-linux-deploy.yml` → `scripts/syp-linux-deploy.sh` (pull `master`, pip install, restart stock-check + explorer + ops + transfer; worker left running unless `FORCE_WORKER_RESTART=1`).

---

## Firewall (UFW)

Inbound is **deny by default**. Allowed:

| What | Port / rule |
|------|-------------|
| SSH | 22/tcp |
| Tailscale | 41641/udp + all traffic on `tailscale0` |
| NoMachine | 4000/tcp + 4000/udp |
| KCW LAN UIs | 8787, 8788, 8790, **8792**/tcp on **`enp3s0` only** |

KCW on Tailscale (`100.94.98.18:8787` etc.) is reached via the **`tailscale0`** rule, not a separate port rule.

Apply or re-apply (idempotent):

```bash
bash ~/projects/kcw-api/scripts/syp-linux-firewall.sh
sudo ufw status verbose
```

Override LAN interface: `SYP_LAN_IF=wlp2s0 bash …/syp-linux-firewall.sh`.

---

## UPS (Syndome Claire) + auto power-on

Same hardware pattern as [HQ Linux](./hq-linux.md#ups-syndome-claire--auto-power-on): **Syndome Claire** over USB-serial (**QinHeng CH340** → `/dev/ttyUSB0`, Megatec/Q1). USB is **monitor-only** — firmware rejects software load-off (`#-1`).

**BIOS (before relying on auto power-on):**

| Setting | Value |
|---------|-------|
| **AC BACK / Restore AC Power Loss** | **Always On** |
| **Power On By RTC** | **Enabled** |

Install / re-apply NUT (idempotent):

```bash
bash ~/projects/kcw-api/scripts/syp-linux-ups-setup.sh
upsc claire@localhost ups.status battery.charge ups.load
systemctl is-active nut-driver@claire nut-server nut-monitor
```

On outage, `nut-monitor` runs `/usr/local/sbin/nut-fsd-shutdown.sh` (from repo): tries UPS cut commands (expect fail), arms **RTC wake** (~30 min via `/etc/default/nut-fsd-shutdown`), then `shutdown -h now`. Real mains cut → BIOS AC BACK; power-race while UPS still feeding → RTC.

**Do not** set `POWEROFF_WAIT` in `/etc/nut/nut.conf` on this box.

Log after FSD test: `sudo cat /var/log/nut-fsd-shutdown.log`

---

## kcw-api systemd user units

Not Docker. **Five** units on this box after transfer ships (`Restart=always`, `RestartSec=5`), linger on:

| Unit | Port | Command |
|------|------|---------|
| `kcw-worker.service` | — | `python -m src.jobs.worker` (`WORKER_NAME=SYP-UBUNTU-SERVER`) |
| `kcw-stock-check.service` | 8787 | uvicorn `app.stock_check_app:app` |
| `kcw-parts9-explorer.service` | 8788 | uvicorn `app.parts9_explorer_app:app` |
| `kcw-ops.service` | 8790 | uvicorn `app.ops_app:app` |
| `kcw-transfer.service` | 8792 | uvicorn `app.transfer_app:app` (`TRANSFER_SITE=SYP`) — see [transfer.md](./transfer.md) |

**Do not** install or enable `kcw-tiger-pay.service` or `kcw-pay-notes.service` here (Tiger Pay `:8000` and ชำระเจ้าหนี้ `:8791` are **HQ-only**).

```bash
cp ~/projects/kcw-api/scripts/systemd/kcw-{worker,stock-check,parts9-explorer,ops,transfer}.service ~/.config/systemd/user/
# Optional: Description=… (SYP-UBUNTU-SERVER) on kcw-worker.service
systemctl --user daemon-reload
# Only after secrets + Drive:
systemctl --user enable --now \
  kcw-worker kcw-stock-check kcw-parts9-explorer kcw-ops kcw-transfer
journalctl --user -u kcw-worker -f
```

kcw-api venv: Python **3.11** at `~/projects/kcw-api/.venv`. Analytic jobs use kcw-analytic **3.12** venv via `WORKER_JOB_*_COMMAND`.

`STOCK_CHECK_ENABLED=true` only after `STOCK_CHECK_TOKEN_SECRET` is set. Site keys: `STOCK_CHECK_BRANCH=SYP`, `PARTS9_EXPLORER_SITE=SYP`, `KCW_OPS_SITE=SYP`.

With `STOCK_CHECK_BRANCH=SYP`, stock-check refuses HQ-like `POS_MSSQL_SERVER` defaults (`KSS` / `KSS.local`) and falls back to `PARTS9_SYP_SERVER` or `kss-pc,KSS-PC`.

---

## No daily task on this box

HQ A/B timer (`kcw-hq-full.timer` at 21:00) belongs on **hq-ubuntu-server** only. On SYP Ubuntu:

```bash
systemctl --user disable --now kcw-hq-full.timer   # keep off
systemctl --user list-timers --all | grep kcw || true
```

Queue jobs (LINE / web → `ops.job_queue`) are on-demand via `kcw-worker`, not a local cron/timer.

---

## Worker job commands (Linux)

Point at `kcw-analytic/worker_tasks/linux/` (SYP site scripts). Example keys already sketched in this box’s `.env`:

- `WORKER_JOB_SYP_RAW_COMMAND` → `…/syp_raw.sh`
- `WORKER_JOB_SYNC_*` → `sync_syp_iclow.sh`, `sync_syp_icmas.sh`, `sync_syp_pomas_podet.sh`, `sync_syp_po_related.sh`
- `WORKER_JOB_SYNC_INVENTORY_COMMAND` / `SYNC_PRODUCT_IMAGES` → shared linux wrappers

`WORKER_JOB_*_CWD` = `~/projects/kcw-analytic`. Timeout on this box: `WORKER_COMMAND_TIMEOUT_SECONDS=7200`.

Do **not** enable `kcw-hq-full.timer` here (that is HQ B on the HQ Ubuntu box).

---

## Drive + analytic

Same rclone remote name `kcw`, Shared drive id `0AJ5BTDhgit7-Uk9PVA`. Mount unit: `rclone-kcw-data.service` → `~/mnt/gdrive/KCW-Data`.

**Survives reboot** via user systemd (not a special rclone env):

```bash
sudo loginctl enable-linger "$USER"   # already yes on this box — user units start at boot without login
systemctl --user enable --now rclone-kcw-data.service
```

Token lives in `~/.config/rclone/rclone.conf` (OAuth as `admin@kcw.app`). Do **not** use one-shot `rclone mount --daemon` as the daily path — it dies on reboot.

```bash
bash ~/projects/kcw-analytic/scripts/mount-kcw-drive.sh   # installs/enables the user unit if needed
ls ~/mnt/gdrive/KCW-Data/kcw_analytics
```

Analytic `.env`: `BRANCH=SYP`, `KCW_BRANCH=SYP`, `PARTS9_SYP_SERVER=kss-pc,…`, `KCW_DRIVE_ROOT=/home/sypadmin/mnt/gdrive`, Python 3.12 venv. Inventory notebook 50 follows `BRANCH` → `mssql_engine("syp")` → **kss-pc**, not HQ `KSS`.

Picture SMB for product images is HQ-oriented (`rclone-kss-picture` → HQ `KAcc9`). SYP may not need it for queue jobs that only touch SYP SQL + Drive; revisit if `sync_product_images` must run here.

---

## Checklist: bring SYP Ubuntu online

1. `rclone config reconnect kcw:` and confirm `ls ~/mnt/gdrive/KCW-Data/kcw_analytics`.
2. Copy secrets into `kcw-api/.env` and `kcw-analytic/.env` from Drive / Windows SYP-PC (never commit).
3. Set `STOCK_CHECK_ENABLED=true` once token secret is present.
4. `systemctl --user enable --now` the five kcw-api units above (**not** tiger-pay or pay-notes); confirm `Restart=always` in each unit.
5. Heartbeat row `SYP-UBUNTU-SERVER` appears in `ops.worker_heartbeat`.
6. Ship enqueue preference for `SYP-UBUNTU-SERVER` over `SYP-PC` (kcw-api + kcw-v2 / RPCs), then retire Windows SYP-PC worker.
7. UFW: `bash ~/projects/kcw-api/scripts/syp-linux-firewall.sh`
8. UPS: BIOS AC BACK + RTC wake; `bash ~/projects/kcw-api/scripts/syp-linux-ups-setup.sh`; `upsc claire@localhost` shows `OL`.

---

## Changelog

| Date | What |
|------|------|
| 2026-08-27 | UFW hardening, NUT/Claire UPS on `/dev/ttyUSB0`, WoL MAC for `kss-pc`, GitHub Actions deploy verified. |
| 2026-08-27 | Documented: do **not** run `kcw-pay-notes` / ชำระเจ้าหนี้ (`:8791`) here — HQ-only. |
| 2026-08-30 | `kcw-transfer` `:8792` (โอนสินค้า) on SYP (`TRANSFER_SITE=SYP`); UFW + deploy include `:8792`. Runbook [transfer.md](./transfer.md). |
| 2026-08-26 | Box hostname/Tailscale `syp-ubuntu-server`; `WORKER_NAME=SYP-UBUNTU-SERVER`; units installed but not started — empty rclone token + placeholder secrets. Linux SYP sync scripts under `worker_tasks/linux/sync_syp_*.sh`. **No** `kcw-hq-full.timer`. **No** `kcw-tiger-pay`. Inventory/stock-check default SQL = **kss-pc** (not HQ `KSS`). |
