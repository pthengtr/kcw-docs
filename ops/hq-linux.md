# Linux HQ-PC runbook

Living notes for the Ubuntu HQ box (`hqadmin`). Use this when setting up **another** machine. Update this file after every non-obvious setup choice.

**Reference machine (2026-08-14):** Ubuntu 26.04 LTS, GNOME 50 / Wayland, user `hqadmin`, Tailscale name `hq-ubuntu-server`.

Repos live as siblings under `~/projects/` (`kcw-api`, `kcw-v2`, `kcw-analytic`, `kcw-docs`).

---

## Best combination (use this)

| Layer | Choice | Why |
|-------|--------|-----|
| Network | **Tailscale** | No port-forward. All remotes stay on the tailnet. |
| Boot | **`multi-user.target`** (no GUI) | 24/7 box. GNOME costs RAM/GPU; GDM itself is tiny. |
| Desktop on demand | **`sudo systemctl start gdm`** | Autologin `hqadmin` creates the physical GNOME session. |
| Remote GUI | **NoMachine → physical desktop** | Windows NoMachine client was the stable path. `nxserver` already starts on `multi-user.target`. |
| Analytics | **kcw-analytic venv + rclone Shared Drive + ODBC 18** | See [kcw-analytics](#kcw-analytics-on-linux) below. |

Day to day after reboot:

```bash
# already headless; SSH / Tailscale / nxserver are up
sudo systemctl start gdm          # when you want a desktop
# wait ~30–60s for autologin / gnome-shell, then connect NoMachine
sudo systemctl stop gdm           # drop the local GUI; SSH + nxserver stay
```

Do **not** set `graphical.target` as the default just to make NoMachine work. That was a false lead: connecting too early looks like “NX needs graphical,” when GDM/autologin had not finished yet.

```bash
sudo systemctl set-default multi-user.target   # keep this
sudo systemctl disable gdm                     # start it yourself
```

GDM autologin is required for the **physical** NoMachine session:

```
# /etc/gdm3/custom.conf
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=hqadmin
```

`loginctl linger` for `hqadmin` is `yes` (systemd user services survive logout). Leave it.

---

## Remote access: what actually works

### Do use

1. **Tailscale** on the box and on the client. Connect to the MagicDNS / Tailscale IP, never expose RDP/NX to the public internet.
2. **NoMachine (physical desktop)** from a **Windows** client. Attach to the existing GNOME session after GDM is up.
3. **SSH** over Tailscale for everything that does not need a GUI (rclone, venv, pipeline).

NoMachine notes that matter on the next box:

- Unit: `nxserver.service` is `WantedBy=multi-user.target` — the daemon does **not** need `graphical.target`.
- Config is `physical-desktop`. `CreateDisplay` stays off. Without GDM there is nothing to shadow.
- Wayland + GNOME 50: set **`EnableEGLCapture 0`** and **`WaylandModes drm,compositor`** in `/usr/NX/etc/node.cfg`. EGL capture segfaulted `nxnode` (exit 11) and looked like “connection reset by host.”
- iPad NoMachine: prefer **TCP only** on port **4000**. UDP over Tailscale caused reconnect loops.
- White screen: restart `nxserver` (`sudo systemctl restart nxserver.service`), then reconnect. If still white, terminate the leftover NX session rather than reboot.

### Do not use (already tried)

| Attempt | Result | Do not repeat |
|---------|--------|----------------|
| **Jump Desktop → this Ubuntu box (RDP)** | Handshake fails. Jump iPad RDP speaks Windows NLA/NTLM; GNOME Remote Desktop rejects it (`invalid flags … 0x00000205`). Password was fine. | Do not debug credentials. Jump RDP is the wrong client for GNOME RDP. |
| **Jump Desktop Connect / Fluid on Linux** | Connect agent is **Mac/Windows only**. | Jump is still useful later for a **Mac mini**, not as the Ubuntu host. |
| **xrdp** | Ubuntu 26.04 is Wayland-only; GNOME 50 does not give xrdp a real desktop. | Skip. |
| **Software virtual monitor** (kernel `drm.edid_firmware` + `video=HDMI-A-1:D`, fake EDID, udev hotplug, `hq-display-watch`) | Unstable: layout fights, dummy stays after unplug, GNOME crash if **zero** real outputs. | **Never** re-add GRUB EDID dummy / watch scripts. |
| **GNOME RDP “extend” + iPad native 2388×1668** | Intel dummy would not take that mode; Windows App scaling made the pointer miss. | If you must use RDP, match client resolution to a mode the GPU actually lists (e.g. 1920×1200), not iPad panel size. |
| **Moonlight / Sunshine** | Not adopted. Fine for video, weak clipboard/files. | Not needed for HQ work. |

**Physical HDMI dummy dongle** is a different idea from the software dummy. We did not keep it. If a future box has no panel at all and you need a persistent GPU output, prefer a **cheap hardware dummy plug**, not kernel EDID hacks. On the reference box (2026-08-22) a dummy HDMI plug on `HDMI-A-3` is fine for headless GPU output while boot stays `multi-user.target`.

GNOME Remote Desktop (RDP, port 3389) may still be installed. **Microsoft Windows App** (formerly Remote Desktop) can talk to it; Jump cannot. Keep RDP off the public internet (UFW allow only `tailscale0`). For daily use, prefer NoMachine + GDM-on-demand rather than keeping a second RDP stack.

---

## UPS (Syndome Claire) + auto power-on

Goal: outage → clean OS shutdown → machine comes back when power returns, including the awkward case where mains returns **while the UPS is still feeding the PSU**.

### Hardware on the reference box (2026-08-22)

| Item | Detail |
|------|--------|
| UPS | **Syndome Claire** (line-interactive). Battery bank reports **24 V** → Claire ~1000 class (2×12 V), not 2000. |
| USB | Appears as **QinHeng CH340** (`1a86:7523`) → `/dev/ttyUSB0` (USB-serial), **not** a HID UPS. |
| Protocol | Megatec / Q1. Status works (`Q1`, `F`). |
| Software cut | **Does not work.** Every Megatec shutdown command returns `#-1` (`S.2`, `S01`, `shutdown.return`, etc.). USB is **monitor-only** on this unit. |

Other Syndome models (e.g. Hercules over real RS-232) may behave differently — re-probe before assuming killpower works.

### BIOS (Gigabyte B860M AORUS ELITE — key: **Del**)

| Setting | Value | Why |
|---------|-------|-----|
| **AC BACK / Restore AC Power Loss** | **Always On** | After a **real** power cut (UPS goes dark), PSU sees power return → board powers on. |
| **Resume by Alarm / Power On By RTC** | **Enabled** | Lets Linux `rtcwake` wake from soft-off. |
| Day / Hour / Min / Sec | Leave defaults (`0`) | This is a **fixed clock schedule**, **not** “N seconds after power off.” Day `0` + time `0:0:0` is usually inert. If Day is “Every day” at midnight, an always-on box ignores it while running. |

Confirm AC BACK with a safe test (no NUT): `shutdown -h now` → unplug **PC cord from UPS** → wait → plug back in → PC should power on alone.

### NUT install (Ubuntu)

```bash
sudo apt install nut nut-client nut-server
sudo usermod -aG dialout nut "$USER"   # then re-login for interactive serial tests
```

`/etc/nut/nut.conf`:

```
MODE=standalone
```

`/etc/nut/ups.conf` (example name `claire`):

```
maxretry = 3
pollinterval = 2

[claire]
	driver = blazer_ser
	port = /dev/ttyUSB0
	desc = "Syndome Claire"
	allow_killpower
	sdcommands = shutdown.return
```

`/etc/nut/upsd.users` — monitor user needs instant commands (even if this UPS rejects them):

```
[upsmon]
	password = <local-random>
	upsmon master
	actions = SET
	instcmds = ALL
```

Do not commit the password. Generate with `openssl rand -hex 12`.

`/etc/nut/upsmon.conf` (shape):

```
RUN_AS_USER nut
MONITOR claire@localhost 1 upsmon <password> master
MINSUPPLIES 1
SHUTDOWNCMD "/usr/local/sbin/nut-fsd-shutdown.sh"
POWERDOWNFLAG /etc/killpower
FINALDELAY 5
```

Enable services:

```bash
sudo systemctl enable --now nut-driver@claire nut-server nut-monitor
upsc claire@localhost    # expect ups.status OL or OB
```

Prefer systemd `nut-driver@<name>` over calling `upsdrvctl start` by hand (enumerator conflict).

### FSD shutdown script + RTC backup

Because this Claire **cannot** cut output, a mid-outage restore after soft-off leaves the PSU powered → **AC BACK never fires**. Backup: arm RTC wake before halt.

On the reference box: `/usr/local/sbin/nut-fsd-shutdown.sh`  
Optional override: `/etc/default/nut-fsd-shutdown` → `RTC_WAKE_SECS=1800` (30 minutes).  
Log: `/var/log/nut-fsd-shutdown.log`

Script outline:

1. Try `upscmd … shutdown.return` / `upsdrvctl shutdown` (expect fail / `#-1` on Claire).
2. `rtcwake -m no -s "$RTC_WAKE_SECS"` (set alarm only; do not suspend).
3. `shutdown -h now`.

Coverage:

| Situation | Who brings the box back |
|-----------|-------------------------|
| UPS actually goes dark, then mains returns | BIOS **AC BACK** |
| Soft-off, UPS still feeding, mains returns (power race) | **RTC wake** (~30 min) |
| Short outage, never FSD | Box never shut down |

Kernel should show `RTC can wake from S4`. `rtcwake -m no -s 120` must succeed (clear the test alarm afterward).

### Do not do

| Attempt | Result |
|---------|--------|
| Expect NUT killpower / `shutdown.return` to darken this Claire | Firmware rejects all `S*` / cut commands (`#-1`). |
| `POWEROFF_WAIT` in `nut.conf` | After halt, if PSU still live, `nutshutdown` **force-reboots** — looks like “FSD did nothing.” Leave it unset on this box. |
| Test killpower while UPS still on wall (`OL`) | Many units ignore cut or restore immediately. Test FSD only with `ups.status` = **`OB`**. |
| Soft-off only, then wait for AC BACK while UPS still on | No AC-loss edge → stuck off until button / RTC. |

### Useful commands

```bash
upsc claire@localhost ups.status battery.charge ups.load
# FSD test (will halt the machine — only when OB and you are ready):
sudo upsmon -c fsd
# After reboot, see whether RTC was armed / UPS cmds failed:
sudo cat /var/log/nut-fsd-shutdown.log
```

Rough runtime at light load (~6% reported): tens of minutes to ~1–2 h depending on Ah / age — not calibrated in NUT (`runtimecal` unset). Prefer a real drain test if you need a number.

---

## kcw-analytics on Linux

App how-tos stay in [kcw-analytics](https://github.com/pthengtr/kcw-analytics). This is only **what the Linux HQ box needs**.

### Layout

```
~/projects/kcw-analytic     # clone
  .venv                     # Python 3.12 (system python on Ubuntu 26.04 may be 3.14 — do not use that)
  .env                      # gitignored
  paths.yaml                # gitignored
~/mnt/gdrive/KCW-Data       # rclone mount of Shared drive KCW-Data
```

### 1. Clone and venv

```bash
mkdir -p ~/projects && cd ~/projects
git clone https://github.com/pthengtr/kcw-analytics.git kcw-analytic
cd kcw-analytic
# uv is what this box used; pin 3.12
uv python install 3.12
uv venv --python 3.12
.venv/bin/pip install -r requirements.txt
```

Confirm: `.venv/bin/python -V` is **3.12.x**, and `pyodbc` imports.

### 2. Google Shared Drive (rclone)

Do **not** use Google Drive for Desktop / DriveFS AppData cache paths.

```bash
# rclone in ~/.local/bin (v1.75.0 on the reference box)
rclone config    # remote name: kcw   (Google Drive, Shared drives)
sudo loginctl enable-linger "$USER"   # so the user unit starts without GDM
bash scripts/mount-kcw-drive.sh       # installs + starts rclone-kcw-data.service
```

The mount script copies [`scripts/rclone-kcw-data.service`](https://github.com/pthengtr/kcw-analytics/blob/main/scripts/rclone-kcw-data.service) into `~/.config/systemd/user/` and enables it. Do **not** use a one-shot `rclone mount --daemon` as the daily path — it dies on reboot.

Shared drive id `0AJ5BTDhgit7-Uk9PVA` (KCW-Data). First-time OAuth needs a browser (start GDM, or copy the `127.0.0.1` auth URL to another machine).

rclone still warns that the **shared Google client_id is retired during 2026**. Put your own Drive `client_id` / `client_secret` in `~/.config/rclone/rclone.conf` when you can; empty values keep using rclone’s default.

`paths.yaml` (gitignored):

```yaml
drive_root: "/home/hqadmin/mnt/gdrive"
analytics_root: "/home/hqadmin/mnt/gdrive/KCW-Data/kcw_analytics"
```

Smoke: `ls ~/mnt/gdrive/KCW-Data/kcw_analytics/01_raw` shows `raw_hq_*.csv`.

### 3. SQL Server ODBC (PARTS9 on KSS)

Ubuntu 26.04 has no official `msodbcsql18` repo yet — use the **24.04 amd64** package.

```bash
sudo bash scripts/install-mssql-odbc.sh
odbcinst -q -d    # expect: ODBC Driver 18 for SQL Server
```

Do **not** pin `KSS` in `/etc/hosts`. Extract and kcw-api probe a comma list in `PARTS9_HQ_SERVER` / `POS_MSSQL_SERVER`, first TCP 1433 win:

`KSS.local` (LAN mDNS) → `KSS` (NetBIOS/DNS) → `192.168.1.99` (last known HQ LAN IP)

Do **not** put Tailscale `kss-pc` on this list — that is the **SYP** shop PC (`KSS-PC`), a different PARTS9. HQ SQL Server’s Windows name is **KSS**. If HQ KSS joins Tailscale later, add that MagicDNS name (e.g. `kss`) to the comma list.

Windows trusted auth does **not** work from Linux. Use SQL auth (`PARTS9_HQ_USER=python_reader`).

### 4. `.env` (gitignored — copy keys, never commit values)

Minimum for extract / TAR / gap-check:

| Key | Notes |
|-----|--------|
| `KCW_ANALYTICS_PYTHON` | `.venv/bin/python` absolute path |
| `KCW_DRIVE_ROOT` | `/home/<user>/mnt/gdrive` |
| `KCW_ANALYTICS_DATA_ROOT` | `.../KCW-Data/kcw_analytics` |
| `MSSQL_ODBC_DRIVER` | `ODBC Driver 18 for SQL Server` |
| `PARTS9_HQ_SERVER` | `KSS.local,KSS,192.168.1.99` (first reachable :1433). Not `kss-pc` (SYP). |
| `PARTS9_HQ_DATABASE` | `PARTS9` |
| `PARTS9_HQ_USER` / `PARTS9_HQ_PASSWORD` | SQL login (`python_reader` is **SQL only**, not the Windows file share) |
| `PARTS9_SYP_SERVER` | Tailscale MagicDNS `kss-pc` (SYP `KSS-PC`). Not on the HQ host list. |
| `PARTS9_SYP_USER` / `PARTS9_SYP_PASSWORD` | Same SQL login as HQ (`python_reader`). Windows trusted auth does not work from Linux. |
| `SUPABASE_DB_URL` | Postgres DSN (pooler), **not** the `https://….supabase.co` API URL |
| `LEGACY_PRODUCT_IMAGE_DIR` | Linux: POSIX mount `~/mnt/kss/PARTS9/Picture`. Windows HQ-PC keeps `\\KSS\KAcc9\PARTS9\Picture` |
| `KSS_SMB_HOST` | Same list as `PARTS9_HQ_SERVER`. Probe **TCP 445**, do not pin one LAN IP in config |
| `KSS_SMB_SHARE` / `KSS_SMB_USER` / `KSS_SMB_PASSWORD` | Windows share login for `KAcc9` (gitignored `.env`). Also stored in rclone remote `kss` |

Copy from `.env.example` and from the existing HQ Windows `.env` (or the Drive backup zip if you still keep one). Do not paste secrets into this markdown.

### 5. PARTS9 Picture share (product images)

Windows HQ-PC uses UNC `\\KSS\KAcc9\PARTS9\Picture`. Linux cannot write that path (it would mkdir a fake local folder).

Same PC as HQ SQL (`KSS` at LAN, last-known `192.168.1.99`). Guest SMB is **disabled**. Need a Windows admin/share login, not `python_reader`.

```bash
rclone config create kss smb host KSS.local user <windows-user> pass <windows-pass> domain WORKGROUP
# Install user unit from kcw-analytic:
cp scripts/rclone-kss-picture.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now rclone-kss-picture.service
ls ~/mnt/kss/PARTS9/Picture | head
```

Mount wrapper [`scripts/rclone-kss-picture-mount.sh`](https://github.com/pthengtr/kcw-analytics/blob/main/scripts/rclone-kss-picture-mount.sh) calls [`scripts/pick_kss_host.py`](https://github.com/pthengtr/kcw-analytics/blob/main/scripts/pick_kss_host.py): first host in `KSS_SMB_HOST` with TCP **445** open (same idea as SQL on **1433**). rclone’s Go DNS cannot resolve `.local` / NetBIOS, so the wrapper passes the **system-resolved IP at mount time** via `--smb-host`. Do **not** hardcode `192.168.1.99` in `.env` or the unit file.

`sync_product_images.py` must see a real POSIX directory. `PRODUCT_IMAGE_DELETE_MODE=quarantine` writes `_deleted/` on that share — this is the live PARTS9 Picture folder.

### 6. Linux worker job scripts (not the queue yet)

Windows BATs in `worker_tasks/*.bat` stay on HQ-PC / Task Scheduler. This box has POSIX stand-ins in `worker_tasks/linux/` (HQ A/B including SYP extract over Tailscale, inventory, online sales, bank, PO-related, product images). Executed notebooks go to **local** `kcw-analytic/logs/`, not Drive FUSE.

This machine’s **gitignored** `kcw-api/.env`:

- `WORKER_NAME=HQ-UBUNTU-SERVER` — LINE/web still enqueue `HQ-PC`, so this process would not steal jobs even if started
- `WORKER_COMMAND_TIMEOUT_SECONDS=7200` (default **1800** = 30 minutes is too short for HQ B PDFs)
- `WORKER_JOB_*_COMMAND` points at `worker_tasks/linux/*.sh`

**Do not start** `python -m src.jobs.worker` until kcw-api / kcw-v2 enqueue is switched on purpose.

HQ B on this box is a **systemd user timer** at **21:00 Asia/Bangkok**, after HQ-PC’s daily HQ B (~19:00). Both write the same Drive/Supabase targets so we can compare; turn off HQ-PC Task Scheduler when this box is trusted.

Linux HQ A (`hq_raw.sh`, also the first step of HQ B) extracts **SYP then HQ** (`syp_raw.sh` → `extract --site hq` → `upload-daily-raw`). SYP PARTS9 is `kss-pc:1433` on the tailnet — do **not** wait for the shop PC’s Task Scheduler. If `kss-pc` is offline the step fails (same as a missed SYP BAT).

```bash
cp scripts/kcw-hq-full.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now kcw-hq-full.timer
systemctl --user list-timers kcw-hq-full.timer
# logs: ~/projects/kcw-analytic/logs/hq_full.systemd.log
```

`Persistent=false` — if the box is down at 21:00 it does **not** catch up on boot (avoids a surprise overwrite). Timeout 3 hours. Queue worker stays off during this dual-run.

Extra venv packages vs a thin Windows Anaconda install: `pytz`, `weasyprint`, `openpyxl`, `supabase` (in `requirements.txt`). Repo folder `kcw-analytic/supabase/` is SQL/functions — it shadows the PyPI client if you put the repo on `PYTHONPATH` / `sys.path[0]`.

### 7. What is ready vs not

| Need | Ready when |
|------|------------|
| Read Drive CSVs / notebooks | rclone mount + `paths.yaml` |
| PARTS9 extract | ODBC + HQ LAN 1433 + SYP Tailscale `kss-pc:1433` + SQL auth env |
| TAR / `gap-check` / upload | `SUPABASE_DB_URL` |
| Product image sync | rclone SMB `kss` + Picture mount + `LEGACY_PRODUCT_IMAGE_DIR` POSIX |
| Manual Linux job scripts | `worker_tasks/linux/*.sh` |
| Scheduled HQ B | user timer `kcw-hq-full.timer` at 21:00 Asia/Bangkok |
| Queue worker claiming LINE/web jobs | **Later** — change enqueue `worker_name` + start kcw-api worker |

Pipeline CLI is `python -m src.kcw.pipeline …` from repo root (see kcw-analytic README). Shop BATs stay on Windows Task Scheduler until this box is the worker.

---

## Checklist: new Ubuntu HQ-like box

1. Install Ubuntu 26.04 (or current LTS), user with sudo, SSH.
2. `sudo systemctl set-default multi-user.target` and `sudo systemctl disable gdm`. Keep GDM **installed**. Enable autologin for the work user.
3. Tailscale; enable linger: `sudo loginctl enable-linger <user>`.
4. NoMachine: physical desktop; `EnableEGLCapture 0`; `nxserver` enabled.
5. Clone `~/projects/{kcw-api,kcw-v2,kcw-analytic,kcw-docs}`.
6. Analytics: Python 3.12 venv, rclone Shared Drive, ODBC 18, `.env` / `paths.yaml`.
7. Picture share: rclone SMB remote `kss`, user unit `rclone-kss-picture.service`, POSIX `LEGACY_PRODUCT_IMAGE_DIR`.
8. Enable `kcw-hq-full.timer` (21:00 Asia/Bangkok) only if this box should run HQ B. Keep HQ-PC scheduler until Linux is trusted.
9. Confirm: `systemctl get-default` is `multi-user.target`; `start gdm` then NoMachine from Windows.
10. UPS: NUT + `blazer_ser` on `/dev/ttyUSB0` if CH340; BIOS AC BACK Always On + RTC wake Enabled; FSD script with `rtcwake` backup (see [UPS section](#ups-syndome-claire--auto-power-on)). Re-probe killpower — Claire cannot cut output.

---

## kcw-api services on this box

Not Docker. Four **systemd user** units (`Restart=always`, `RestartSec=5`), linger already on:

| Unit | Port | Command |
|------|------|---------|
| `kcw-worker.service` | — | `python -m src.jobs.worker` (`WORKER_NAME=HQ-UBUNTU-SERVER`) |
| `kcw-tiger-pay.service` | 8000 | uvicorn `app.main:app` |
| `kcw-stock-check.service` | 8787 | uvicorn `app.stock_check_app:app` |
| `kcw-parts9-explorer.service` | 8788 | uvicorn `app.parts9_explorer_app:app` |

Repo copies: `~/projects/kcw-api/scripts/systemd/`. Enable:

```bash
cp ~/projects/kcw-api/scripts/systemd/kcw-*.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now kcw-worker kcw-tiger-pay kcw-stock-check kcw-parts9-explorer
journalctl --user -u kcw-worker -f
```

kcw-api venv is Python **3.11** at `~/projects/kcw-api/.venv` (`WORKER_PYTHON` points here). Analytic jobs still use the 3.12 analytic venv.

HQ jobs: if this worker heartbeat is live, LINE/web assign `HQ-UBUNTU-SERVER`; else `HQ-PC`. Unassigned jobs can still be claimed here. Do not rename this process to `HQ-PC` while Windows is running.

LINE `เช็คสต็อก` and `ไทเกอร์` / `tiger pay` prefer this box’s URLs when the heartbeat is online. Companion on Linux requires the LINE token (`COMPANION_REQUIRE_LINE_AUTH=true`).

CI/CD: self-hosted GitHub runner labeled `self-hosted, linux, hq` on this machine. Workflows:

- kcw-api `.github/workflows/hq-linux-deploy.yml` → `scripts/hq-linux-deploy.sh` (pull, pip, restart tiger-pay + stock-check + parts9-explorer; worker left running unless `FORCE_WORKER_RESTART=1`)
- kcw-analytic `.github/workflows/hq-linux-deploy.yml` → `scripts/hq-linux-deploy.sh` (pull + pip only)

Register the runner in both GitHub repos (or the org, limited to these two). LINE still deploys on Railway from kcw-api `master`.

---

## Changelog

| Date | What we learned |
|------|-----------------|
| 2026-08-14 | Boot `multi-user.target`; GDM on demand; NoMachine physical after autologin. |
| 2026-08-14 | Jump RDP ≠ GNOME RDP (NLA). Jump Connect not on Linux. Keep Jump for Mac later. |
| 2026-08-14 | Software virtual HDMI/EDID/hotplug: remove and do not rebuild. |
| 2026-08-14 | NX iPad: EGL capture crash; TCP-only 4000. White screen → restart nxserver. |
| 2026-08-14 | kcw-analytic Linux: rclone KCW-Data, ODBC 18 from Ubuntu 24.04 package, KSS `192.168.1.99`, venv 3.12 not system 3.14. |
| 2026-08-15 | PARTS9 host is a probe list (`KSS.local`, `KSS`, last-known LAN IP). Tailscale `kss-pc` is SYP, not HQ. |
| 2026-08-15 | Product images: mount `KAcc9/PARTS9/Picture` via rclone SMB; probe TCP 445 with the same host list; do not pin LAN IP. `python_reader` cannot open the share. |
| 2026-08-15 | Linux job wrappers in `worker_tasks/linux/`. Default worker timeout 1800s is 30 min — too short for HQ B. Queue worker not started (`WORKER_NAME=HQ-UBUNTU-SERVER`). |
| 2026-08-15 | kcw-api user units: worker, tiger-pay :8000, stock-check :8787. HQ enqueue prefers `HQ-UBUNTU-SERVER` if live. LINE companion uses same HMAC token as stock-check. |
| 2026-08-15 | PARTS9 explorer :8788; worker heartbeat `explorer_public_base_url`; LINE `parts9` / `ค้นหา` / `สำรวจ`. Photos from Supabase `pictures/product`. |
| 2026-08-15 | Daily HQ A/B on this box extracts SYP over Tailscale (`kss-pc`) — no wait on SYP Task Scheduler. |
| 2026-08-22 | Syndome Claire USB = CH340 `/dev/ttyUSB0`, Megatec status OK, **no** software load-off (`#-1`). NUT FSD + BIOS AC BACK + RTC wake (`rtcwake -m no`) covers real cut and power-race. Do not use `POWEROFF_WAIT`. HDMI dummy on HDMI-A-3 OK with headless boot. |
