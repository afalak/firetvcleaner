# USB OTG Storage & Projectivy Launcher Guide (Fire TV Stick 4K Max)

Reference commands for managing **Adopted (Internal) USB OTG storage**, keeping favorite apps on fast internal memory, and using **Projectivy Launcher** via ADB on Fire OS 7 (`AFTKA`).

---

## 1. Check Storage & Find Your USB Pen Drive UUID

```bash
# Check free space on internal (/data) and adopted USB (/mnt/expand/<UUID>)
adb -s 192.168.1.50:5555 shell df -h

# List storage volumes and find the UUID of private:<major>,<minor>
adb -s 192.168.1.50:5555 shell sm list-volumes all
```

Example UUID format: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`.

---

## 2. Move Specific Apps Between Internal Storage and USB

> **Important (Avoid App Stutter):** Keep your **launcher, active streaming apps (Netflix, Prime Video, YouTube, Apple TV, etc.), Home on Fire, and AdAway** on **fast internal memory (`/data`)**. Running active streaming apps or background services from an adopted **USB 2.0 OTG pen drive** causes UI and playback stutter. Use the USB pen drive mainly for `/sdcard` (downloads/shared media) and rarely used apps.

### Check where third-party apps are currently installed
```bash
adb -s 192.168.1.50:5555 shell 'for p in $(pm list packages -3 | cut -d: -f2); do echo "$p -> $(pm path "$p" | head -n 1)"; done'
```

- Paths starting with `/data/app/...` are on **internal memory**.
- Paths starting with `/mnt/expand/<UUID>/app/...` are on the **USB pen drive**.

### Move an app back to fast internal memory
```bash
adb -s 192.168.1.50:5555 shell pm move-package <package_name> internal
```

Common Fire TV package examples:
- **Prime Video:** `com.amazon.firebat`
- **YouTube:** `com.amazon.firetv.youtube`
- **Netflix:** `com.netflix.ninja`
- **Apple TV:** `com.apple.atve.amazon.appletv`
- **Amazon Appstore:** `com.amazon.venezia`
- **Projectivy Launcher:** `com.spocky.projengmenu`

### Move an app to the USB pen drive
```bash
adb -s 192.168.1.50:5555 shell pm move-package <package_name> <UUID>
```

---

## 3. Migrate `/sdcard` (Downloads & Shared Data)

```bash
# Move /sdcard to the adopted USB pen drive
adb -s 192.168.1.50:5555 shell pm move-primary-storage <UUID>

# Move /sdcard back to internal memory (for example, before swapping pen drives)
adb -s 192.168.1.50:5555 shell pm move-primary-storage internal
```

> **Tip:** Before unplugging or upgrading your USB OTG pen drive, move `/sdcard` and any USB-resident apps back to `internal` first (or check what's on the drive with `pm path`).

---

## 4. Recommended USB Drive Specs for Fire TV Stick 4K Max

- **Port bottleneck:** Micro-USB OTG on the stick is **USB 2.0** (~25–35 MB/s real-world ceiling).
- **What matters most:** High **random 4K read/write IOPS** and steady sustained write speed so app updates and thumbnail caches don't lag.
- **Recommended size:** **32 GB – 64 GB** (128 GB only if storing local media/ROMs).
- **Good models:** Samsung FIT Plus / BAR Plus (USB 3.1), SanDisk Extreme Go (USB 3.2), or a **U3 / A2 microSD card** in a compact USB 3.0 reader.

---

## 5. Projectivy Launcher & Home Button Remap via ADB (Fire OS 7)

Install Projectivy on **internal** storage and enable its Accessibility Service:

```bash
# Install Projectivy APK from your Mac
adb -s 192.168.1.50:5555 install -r ProjectivyLauncher.apk

# Enable Projectivy's Accessibility Service without hunting through Fire OS settings
adb -s 192.168.1.50:5555 shell settings put secure enabled_accessibility_services com.spocky.projengmenu/com.spocky.projengmenu.services.ProjectivyAccessibilityService
adb -s 192.168.1.50:5555 shell settings put secure accessibility_enabled 1
adb -s 192.168.1.50:5555 shell dumpsys deviceidle whitelist +com.spocky.projengmenu
```

### Fix the Home Button Reverting to Amazon Home (Fire OS 7 `STOP_APP_SWITCHES`)

On recent Fire OS 7 builds (such as `PS7713.5443N`), pressing **Home** launches `com.amazon.tv.launcher/.ui.HomeActivity_vNext` and activates Android 9's 5-second `STOP_APP_SWITCHES` cooldown, causing Projectivy's built-in **Override current launcher** call to be dropped (`Activity start request stopped`).

Use the open-source helper [**Home on Fire**](https://github.com/toolicious/home-on-fire/releases) (`io.github.toolicious.homeonfire`, zero `INTERNET` permission) to handle the redirect cleanly:

```bash
adb -s 192.168.1.50:5555 install -r home-on-fire.apk
adb -s 192.168.1.50:5555 shell pm grant io.github.toolicious.homeonfire android.permission.WRITE_SECURE_SETTINGS
adb -s 192.168.1.50:5555 shell dumpsys deviceidle whitelist +io.github.toolicious.homeonfire
adb -s 192.168.1.50:5555 shell am start -n io.github.toolicious.homeonfire/.MainActivity
```

1. In **Home on Fire**, pick **Projectivy Launcher** (`com.spocky.projengmenu`) under **Choose target app…** and turn **Accessibility service (required)** **ON** (leave **Launch on boot** **ON**).
2. In **Projectivy Launcher → Settings → General**, turn **Override current launcher** **OFF** so only Home on Fire manages the redirect.
3. **Controls:**
   - **Single-press Home** (from an app): waits out Fire OS 7's up-to-5s cooldown under a brief loading overlay, then opens Projectivy.
   - **Long-press Home** (or **double-press Home** ~1 s apart): escapes back to Amazon's stock Home screen when needed.
   - **Instant launch (optional):** Hold **Menu (`☰`)** to open Home on Fire and bind any spare remote button under **Map custom buttons → Launcher** to skip the 5s Home cooldown completely.

---

## 6. Recommended Projectivy Layout & TV Bro Browser

- **Favorites row & sorting:** Under **Settings → Edit categories → Favorites**, use **Manage apps** to pin your favorite apps (e.g. `YouTube`, `Netflix`, `Prime Video`) and set **Sort → Alphabetically**.
- **Compact cards:** Under **Settings → Appearance → Cards → Cards size**, set to **50%** so all favorites fit cleanly on one row.
- **Dark purple tint:** Under **Settings → Appearance → Wallpaper**, pick **Dynamic colours** and adjust **Picture adjustment → Brightness** down a few notches for a deep dark-purple gradient.
- **TV Bro browser:** Install the lightweight `geckoExcluded` APK (`3.6 MB`, compatible with Fire TV Stick 4K Max `armeabi-v7a`) from `https://github.com/truefedex/tv-bro/releases`:
  ```bash
  adb -s 192.168.1.50:5555 install -r tvbro-3.0.7-generic-geckoExcluded.apk
  ```


