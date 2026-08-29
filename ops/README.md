# Machine / ops notes

How we run the **Linux shop boxes**, not business dictionaries.

| Doc | What |
|-----|------|
| [hq-linux.md](./hq-linux.md) | Ubuntu HQ box (`hqadmin` / `hq-ubuntu-server`): remote access, GDM, UPS, rclone Drive + KSS Picture SMB, HQ B timer, kcw-api units as `HQ-UBUNTU-SERVER` |
| [syp-linux.md](./syp-linux.md) | Ubuntu SYP box (`sypadmin` / `syp-ubuntu-server`): replaces Windows SYP-PC; `WORKER_NAME=SYP-UBUNTU-SERVER`; no daily timer; no Tiger Pay; rclone + secrets blockers; kcw-api user units |
| [transfer.md](./transfer.md) | HQ↔SYP stock transfer (`kcw-transfer` `:8792`): operator flow, parallel `/po`, ICLOW stamp, writer flags on both boxes |

Do not put passwords, `.env` values, or RDP credentials here.
