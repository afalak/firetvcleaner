# Fire TV Stick 4K Max Complete Optimization Guide (STEM Step-by-Step)

This guide explains **everything** we did to turn a slow, nearly full **Amazon Fire TV Stick 4K Max** (`AFTKA`, Fire OS 7 / Android 9) into a clean, fast, ad-minimized streaming device using **ADB (Android Debug Bridge)** — written so anyone comfortable with a terminal can follow along, understand *why* each command works, and safely undo changes at any time.

---

## Big Picture: What We Accomplished

| Metric | Before | After |
| --- | --- | --- |
| Main internal storage (`/data`, 4.9 GB) | **4.0 GB used (83% full, 870 MB free)** | **~2.0 GB used (~43% used, ~2.7 GB free)** |
| USB OTG pen drive (7.3 GB Adopted Storage) | **17 MB used (1% used, 7.2 GB free)** | **Used for `/sdcard` & secondary apps** |
| Home screen & Home button | Amazon ad-heavy launcher | **Projectivy Launcher v4.74** + **Home on Fire** |
| Bloatware & telemetry | 29 bloat/tracking/OTA packages active | Disabled or background-restricted via `appops` |
| Unwanted sideloaded/unused apps | 9 unused apps taking space | Uninstalled |
| System-wide DNS ad & OTA blocking | None | **AdAway** (local VPN mode, blocklists + OTA domains) |
| TV web browser | Amazon Silk only | **TV Bro v3.0.7** (`3.6 MB`, built-in ad blocker) + Silk |

---

## Concepts You Will Use (The "Why")

1. **ADB (Android Debug Bridge):** A developer tool (`adb`) that lets your Mac talk to Android/Fire OS devices over Wi-Fi (port `5555`) or USB.
2. **RSA Authorization:** The first time your Mac connects, the Fire TV shows an *"Allow USB debugging?"* popup with a cryptographic fingerprint so random devices on your Wi-Fi can't control your TV.
3. **Why `/sdcard` isn't an SD card:** On Android/Fire OS, `/sdcard` is a **symlink** (shortcut) pointing to `/storage/self/primary` → internal `/data/media`. That's why downloaded movies and APKs eat up your main internal storage!
4. **Adopted Storage (`private` volume):** When you format a USB pen drive as Internal/Adopted Storage on Fire TV, Android encrypts it with ext4 and assigns it a **UUID** (mounted at `/mnt/expand/<UUID>`). Because it's encrypted and managed by Android's `PackageManager`, you move data to it using `pm move-primary-storage` and `pm move-package` instead of plain `mv`.
5. **OS-Protected Packages & `appops`:** On newer Fire OS builds (like `PS7713.5443N`), Amazon marks certain apps (e.g., OTA updates and log managers) as **protected**, causing `pm disable-user` to fail with `SecurityException`. When that happens, we use Android's **AppOps** (`cmd appops set <pkg> RUN_IN_BACKGROUND ignore`) to stop them from running in the background anyway.
6. **Home Button Redirect (`Home on Fire`):** Fire OS 7 blocks disabling `com.amazon.tv.launcher` directly, and pressing **Home** activates Android 9's ~5-second `STOP_APP_SWITCHES` cooldown (which drops Projectivy's single-shot launcher override). **Home on Fire** waits out that brief lock under a clean loading overlay (plus lets you long-press/double-press Home to escape to Amazon Home, or map any spare remote button for instant launch).

---

## Step 0: Prerequisites on Your Mac

Install Android Platform Tools (gives you `adb`) if you don't already have it:

```bash
brew install android-platform-tools
adb version
```

Clone this repository and make the script executable:

```bash
git clone https://github.com/afalak/firetvcleaner.git
cd firetvcleaner
chmod +x firetv_cleaner.sh
```

---

## Step 1: Turn On ADB & Connect Over Wi-Fi

### On the Fire TV
1. Go to **Settings** (gear icon) → **My Fire TV**.
2. If **Developer Options** isn't visible:
   - Open **About** → highlight **Fire TV Stick 4K Max** → press the **Select** (center) button **7 times** until it says *"No need, you are already a developer."*
   - Press **Back** once.
3. Open **Developer Options** → turn **ADB Debugging** to **ON**.
4. Find your Fire TV's IP address under **Settings → My Fire TV → About → Network** (for example, `192.168.1.50`).

### On Your Mac
Replace `192.168.1.50` with your Fire TV's IP address:

```bash
adb kill-server
adb start-server
adb connect 192.168.1.50:5555
```

Look at your TV screen, check **"Always allow from this computer"**, and click **Allow**. Then verify the connection:

```bash
adb devices -l
```

You should see `device` (not `unauthorized` or `offline`), e.g. `model:AFTKA`.

---

## Step 2: Inspect & Take a Full Restore Backup (Safety First!)

Before changing *anything*, inspect your device and save a snapshot so you can undo everything in one command if needed:

```bash
# Read-only health check (model, Fire OS build, storage, bloat count, large downloads)
./firetv_cleaner.sh --target 192.168.1.50 --inspect

# Save a complete snapshot of enabled/disabled packages and settings into backups/
./firetv_cleaner.sh --target 192.168.1.50 --backup
```

### How to Undo Everything Later
Every backup file saved in `backups/` can be restored anytime:

```bash
./firetv_cleaner.sh --target 192.168.1.50 --restore backups/backup-AFTKA-<timestamp>.txt
```

---

## Step 3: Debloat, Free Caches, Block Telemetry & Speed Up UI

First run a **dry-run** (prints every planned change without touching the Fire TV):

```bash
./firetv_cleaner.sh --target 192.168.1.50 --all --dry-run
```

Then apply it:

```bash
./firetv_cleaner.sh --target 192.168.1.50 --all
```

### What `--all` Does Behind the Scenes
- **`--debloat`:** Disables non-essential Amazon bloat/promos (`com.amazon.kso.blackbird`, `com.amazon.shoptv.client`, `com.amazon.device.sale.service`, `com.amazon.tv.releasenotes`, `com.amazon.tv.support`, `com.amazon.bueller.photos`, `com.amazon.bueller.music`, `com.amazon.hedwig`, `com.amazon.ods.kindleconnect`). Core packages like Launcher, Settings, Appstore, and Prime Video are **hard-protected** in the script so you can never bootloop the stick.
- **`--storage`:** Runs `pm trim-caches 999999999999`, clears bloat/OTA/release-note caches, and lists files `> 20 MB` in `/sdcard/Download` for manual review.
- **`--privacy`:** Disables or background-restricts Amazon telemetry/crash/metric packages and sets:
  - `limit_ad_tracking = 1`
  - `send_action_app_error = 0`
  - `usage_metrics_enabled = 0`
  - `usage_metrics_marketing_enabled = 0`
- **`--ota`:** Clears and disables `com.amazon.tv.forcedotaupdater.v2`, and restricts background activity for OS-protected `com.amazon.device.software.ota` and `com.amazon.device.software.ota.override`.
- **`--performance`:** Sets `window_animation_scale`, `transition_animation_scale`, and `animator_duration_scale` to `0.5` (twice as snappy as default `1.0`).

---

## Step 4: Extra Hardening for OTA Updates (Optional but Recommended)

Because Fire OS 7 (`PS7713.5443N`) blocks uninstalling or disabling the main two OTA packages without root, we also restricted their wake locks and foreground services via `appops`:

```bash
adb -s 192.168.1.50:5555 shell '
for p in com.amazon.device.software.ota com.amazon.device.software.ota.override; do
  cmd appops set "$p" WAKE_LOCK ignore
  cmd appops set "$p" START_FOREGROUND ignore
  am force-stop "$p"
done
'
```

To block OTA update downloads at the **DNS / network** level too, install **AdAway** (VPN mode) on internal storage, whitelist it from Doze (`dumpsys deviceidle whitelist +org.adaway`), enable **Start on boot** in AdAway Preferences, and add these 5 domains to **AdAway → Your Lists → Blocked** (or your Wi-Fi router / Pi-hole / AdGuard):
- `softwareupdates.amazon.com`
- `updates.amazon.com`
- `d1s31zyz7dcc2d.cloudfront.net`
- `amzdigital-a.akamaihd.net`
- `amzdigitaldownloads.edgesuite.net`

---

## Step 5: Move `/sdcard` and Apps to the USB OTG Pen Drive

> **Note:** Make sure your USB pen drive is connected via an OTG Y-splitter cable and formatted as Internal/Adopted Storage in Fire TV Settings.

### 5.1 Find Your Storage Usage and USB Volume UUID

```bash
adb -s 192.168.1.50:5555 shell df -h
adb -s 192.168.1.50:5555 shell sm list-volumes all
```

Look for the line like `private:8,2 mounted xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`. That long string is your `<UUID>`.

### 5.2 Migrate `/sdcard` (Downloads & Shared Files) to the Pen Drive

```bash
adb -s 192.168.1.50:5555 shell pm move-primary-storage <UUID>
```

*(Expect ~3–5 minutes for ~600 MB on a USB 2.0 drive. Reversible anytime with `pm move-primary-storage internal`.)*

### 5.3 Move Third-Party Apps to the Pen Drive

Check where all user-installed apps currently live:

```bash
adb -s 192.168.1.50:5555 shell 'for p in $(pm list packages -3 | cut -d: -f2); do echo "$p -> $(pm path "$p" | head -n 1)"; done'
```

Move non-overlay third-party apps to the USB drive:

```bash
adb -s 192.168.1.50:5555 shell '
for p in $(pm list packages -3 | cut -d: -f2); do
  case "$p" in *.overlay.*) continue ;; esac
  echo "$p -> $(pm move-package "$p" <UUID> 2>&1)"
done
'
```

> **Important (Avoid App Stutter):** Keep your **launcher, active streaming apps (YouTube, Netflix, Prime Video, Apple TV, etc.), Home on Fire, and AdAway** on **fast internal memory (`/data`)**. Running active streaming apps or background VPN/launcher services from an adopted **USB 2.0 OTG pen drive** causes UI and playback stutter (`~25–35 MB/s` USB 2.0 OTG ceiling). Use the USB pen drive mainly for `/sdcard` and rarely used apps:
> ```bash
> adb -s 192.168.1.50:5555 shell pm move-package <package_name> internal
> ```

---

## Step 6: Uninstall Unwanted Third-Party Apps

If you spot unused apps in the `pm list packages -3` list, remove them cleanly with:

```bash
adb -s 192.168.1.50:5555 uninstall <package_name>
```

*(For example, any unused third-party streaming or sideloaded apps such as `com.example.unusedapp`.)*

---

## Step 7: Install & Enable Projectivy Launcher (Ad-Free Home Screen)

1. Download the latest official APK from the developer's GitHub releases (`https://github.com/spocky/miproja1/releases`):
   ```bash
   curl -fL -o /tmp/ProjectivyLauncher.apk <APK_DOWNLOAD_URL>
   ```
2. Install it on the Fire TV (keep it on fast internal storage):
   ```bash
   adb -s 192.168.1.50:5555 install -r /tmp/ProjectivyLauncher.apk
   rm -f /tmp/ProjectivyLauncher.apk
   ```
3. Enable Projectivy's Accessibility Service via ADB (so you don't have to hunt for hidden Fire OS menus):
   ```bash
   adb -s 192.168.1.50:5555 shell settings put secure enabled_accessibility_services com.spocky.projengmenu/com.spocky.projengmenu.services.ProjectivyAccessibilityService
   adb -s 192.168.1.50:5555 shell settings put secure accessibility_enabled 1
   ```
4. Launch Projectivy on your TV:
   ```bash
   adb -s 192.168.1.50:5555 shell monkey -p com.spocky.projengmenu -c android.intent.category.LAUNCHER 1
   ```
5. **Configure Projectivy on your TV:**
   - **Favorites & sort:** **Settings → Edit categories → Favorites → Manage apps** to pin your favorite apps (for example, `YouTube`, `Netflix`, `Prime Video`, `Appstore`), and set **Sort → Alphabetically**.
   - **Compact cards & dark purple tint:** **Settings → Appearance → Cards → Cards size → 50%**, and **Settings → Appearance → Wallpaper → Dynamic colours** with **Picture adjustment → Brightness** dimmed slightly.
   - **Watch Next & Alexa Search note:** Fire OS 7 apps like Prime Video/Netflix don't feed Android TV's `Watch Next` row (only apps using Android TV's Watch Next/Channels API appear there). Pressing the remote's **Alexa Voice** button still searches across supported apps unless you disable `com.amazon.vizzini`.

6. **Remap the Remote Home Button with Home on Fire (Fire OS 7 Fix):**
   On Fire OS 7 (`PS7713.5443N`), pressing **Home** launches `com.amazon.tv.launcher/.ui.HomeActivity_vNext` and activates Android 9's ~5-second `STOP_APP_SWITCHES` cooldown, causing Projectivy's own **Override current launcher** hook to be dropped. Install [**Home on Fire**](https://github.com/toolicious/home-on-fire/releases) (`io.github.toolicious.homeonfire`, zero `INTERNET` permission) onto internal storage:
   ```bash
   curl -fL -o /tmp/home-on-fire.apk https://github.com/toolicious/home-on-fire/releases/latest/download/home-on-fire.apk
   adb -s 192.168.1.50:5555 install -r /tmp/home-on-fire.apk
   rm -f /tmp/home-on-fire.apk
   adb -s 192.168.1.50:5555 shell pm grant io.github.toolicious.homeonfire android.permission.WRITE_SECURE_SETTINGS
   adb -s 192.168.1.50:5555 shell dumpsys deviceidle whitelist +io.github.toolicious.homeonfire
   adb -s 192.168.1.50:5555 shell am start -n io.github.toolicious.homeonfire/.MainActivity
   ```
   - In **Home on Fire**, pick **Projectivy Launcher** under **Choose target app…** and turn **Accessibility service (required)** **ON** (leave **Launch on boot** **ON**).
   - In **Projectivy Settings → General**, turn **Override current launcher** **OFF** so only Home on Fire handles the redirect cleanly.
   - **Long-press Home** (or **double-press Home** ~1 s apart) escapes to Amazon Home anytime; **long-press Menu (`☰`)** opens Home on Fire settings where you can optionally map a spare remote button for an instant 0-second Projectivy shortcut.

---

## Step 8: Install a TV-Friendly Browser (TV Bro)

Download the lightweight `geckoExcluded` APK (`3.6 MB`, compatible with Fire TV Stick 4K Max `armeabi-v7a`) from `https://github.com/truefedex/tv-bro/releases` and install over ADB:

```bash
curl -fL -o /tmp/tvbro.apk https://github.com/truefedex/tv-bro/releases/download/v3.0.7/tvbro-3.0.7-generic-geckoExcluded.apk
adb -s 192.168.1.50:5555 install -r /tmp/tvbro.apk
rm -f /tmp/tvbro.apk
```

---

## Step 9: Final Verification Checklist

Run these two commands to verify your storage and clean state:

```bash
adb -s 192.168.1.50:5555 shell df -h /data /mnt/expand/<UUID>
adb -s 192.168.1.50:5555 shell settings get secure enabled_accessibility_services
```

And if you ever upgrade to a faster **32 GB / 64 GB USB 3.1+ drive** (like a Samsung FIT Plus / BAR Plus or a U3/A2 microSD card in a USB 3.0 reader), move `/sdcard` and your apps back to `internal` first before unplugging the old drive!

