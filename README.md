# Fire TV Stick 4K Max Cleaner (`firetv_cleaner.sh`)

Safe, reversible ADB optimization tool for the **Amazon Fire TV Stick 4K Max** (1st Gen Fire OS 7 and 2nd Gen Fire OS 8).

## What It Fixes

1. **Debloat & Performance (`--debloat`, `--performance`)**
   - Disables safe, non-essential Amazon bloatware (Shopping, Special Offers/lockscreen promos, Release Notes, Support/Tutorials, GameCircle, Amazon Photos/Music/News).
   - Leaves core launcher, Settings, Appstore, and Prime Video untouched so the stick cannot bootloop or lose remote/Wi-Fi access.
   - Speeds up UI responsiveness by setting animation scales to `0.5x`.
   - Optional `--debloat-extra` disables user-facing apps like Freevee, Silk Browser, Live TV, and Whisperplay if you do not use them.

2. **Free Up Storage (`--storage`)**
   - Trims accumulated app caches across the system (`pm trim-caches`).
   - Clears cached data from log, crash, release-note, and promo packages.
   - Lists large files (`> 20 MB`) in `/sdcard/Download` so you can spot leftover APKs or downloads without blindly deleting personal files.

3. **Privacy, Ads & OTA Updates (`--privacy`, `--ota`)**
   - Disables Amazon telemetry, crash-reporting, metrics, and ad-ID packages (and falls back to restricting background execution via `appops` if Fire OS protects a package).
   - Enables `limit_ad_tracking`, disables `send_action_app_error`, and opts out of `usage_metrics_enabled` / `usage_metrics_marketing_enabled`.
   - Clears cached OTA payloads and attempts to disable Amazon OTA update packages (and prints the exact domains to block on your router/Pi-hole/AdGuard if your Fire OS build protects OTA packages at the OS level).

4. **Automatic Backup & One-Command Restore (`--restore`)**
   - Every modifying run saves a snapshot under `backups/` before making changes so you can undo everything cleanly.

---

## Step 1: Enable ADB Debugging on Your Fire TV Stick 4K Max

1. On your Fire TV Home screen, go to **Settings** (gear icon) → **My Fire TV**.
2. Look for **Developer Options**.
   - If **Developer Options** is hidden: select **About**, highlight **Fire TV Stick 4K Max** (the first item), and press the **Select** (center) button **7 times** until it says *"No need, you are already a developer."*
   - Press **Back** once to see **Developer Options**.
3. Open **Developer Options** and turn **ADB Debugging** to **ON**.
4. Find your Fire TV's IP address under **Settings → My Fire TV → About → Network** (e.g. `192.168.1.50`).

---

## Step 2: Run the Cleaner from Your Mac

Make sure your Mac and Fire TV Stick 4K Max are on the **same Wi-Fi network**.

```bash
chmod +x firetv_cleaner.sh

# 1. Connect and inspect device, storage, and bloat (read-only)
./firetv_cleaner.sh --target 192.168.1.50 --inspect

# 2. Take a standalone restore backup before making any changes
./firetv_cleaner.sh --target 192.168.1.50 --backup
```

> **First-time connection:** Look at your TV screen and check **"Always allow from this computer"**, then select **Allow**. If the first `--inspect` fails as `unauthorized`, accept the prompt on your TV and run the command again.

```bash
# 3. Preview all changes without modifying anything
./firetv_cleaner.sh --target 192.168.1.50 --all --dry-run

# 4. Apply debloat + storage cleanup + privacy/OTA + performance tweaks (also auto-saves a backup)
./firetv_cleaner.sh --target 192.168.1.50 --all
```

### Undo / Restore

Every run writes a backup file in `backups/` and prints the exact restore command at the end:

```bash
./firetv_cleaner.sh --target 192.168.1.50 --restore backups/backup-<model>-<timestamp>.txt
```
