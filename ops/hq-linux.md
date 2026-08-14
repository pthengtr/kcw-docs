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

**Physical HDMI dummy dongle** is a different idea from the software dummy. We did not keep it. If a future box has no panel at all and you need a persistent GPU output, prefer a **cheap hardware dummy plug**, not kernel EDID hacks.

GNOME Remote Desktop (RDP, port 3389) may still be installed. **Microsoft Windows App** (formerly Remote Desktop) can talk to it; Jump cannot. Keep RDP off the public internet (UFW allow only `tailscale0`). For daily use, prefer NoMachine + GDM-on-demand rather than keeping a second RDP stack.

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
| `PARTS9_HQ_USER` / `PARTS9_HQ_PASSWORD` | SQL login |
| `SUPABASE_DB_URL` | Postgres DSN (pooler), **not** the `https://….supabase.co` API URL |

Copy from `.env.example` and from the existing HQ Windows `.env` (or the Drive backup zip if you still keep one). Do not paste secrets into this markdown.

### 5. What is ready vs not

| Need | Ready when |
|------|------------|
| Read Drive CSVs / notebooks | rclone mount + `paths.yaml` |
| PARTS9 extract | ODBC + LAN 1433 + SQL auth env |
| TAR / `gap-check` / upload | `SUPABASE_DB_URL` |

Pipeline CLI is `python -m src.kcw.pipeline …` from repo root (see kcw-analytic README). Shop BATs stay on Windows Task Scheduler until this box is the worker.

---

## Checklist: new Ubuntu HQ-like box

1. Install Ubuntu 26.04 (or current LTS), user with sudo, SSH.
2. `sudo systemctl set-default multi-user.target` and `sudo systemctl disable gdm`. Keep GDM **installed**. Enable autologin for the work user.
3. Tailscale; enable linger: `sudo loginctl enable-linger <user>`.
4. NoMachine: physical desktop; `EnableEGLCapture 0`; `nxserver` enabled.
5. Clone `~/projects/{kcw-api,kcw-v2,kcw-analytic,kcw-docs}`.
6. Analytics: Python 3.12 venv, rclone Shared Drive, ODBC 18, `.env` / `paths.yaml`.
7. Confirm: `systemctl get-default` is `multi-user.target`; `start gdm` then NoMachine from Windows.

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
