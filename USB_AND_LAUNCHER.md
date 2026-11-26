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

Moving your top 2–3 daily apps (e.g. YouTube, Netflix) back to **internal** keeps cold launches and updates fast, while leaving less-used apps and downloads on the USB pen drive.

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

## 5. Projectivy Launcher via ADB (Fire OS 7)

Because Fire OS 7 protects `com.amazon.tv.launcher`, Projectivy overrides the Home button safely using Android's **Accessibility Service**.

```bash
# Install Projectivy APK from your Mac
adb -s 192.168.1.50:5555 install -r ProjectivyLauncher.apk

# Enable Projectivy's Accessibility Service without hunting through Fire OS settings
adb -s 192.168.1.50:5555 shell settings put secure enabled_accessibility_services com.spocky.projengmenu/com.spocky.projengmenu.services.ProjectivyAccessibilityService
adb -s 192.168.1.50:5555 shell settings put secure accessibility_enabled 1
```

Then open **Projectivy Launcher → Settings → General → Override current launcher** and turn it **ON**.

---

## 6. Recommended Projectivy Layout & TV Bro Browser

- **Favorites row & sorting:** Under **Settings → Edit categories → Favorites**, use **Manage apps** to pin your favorite apps (e.g. `YouTube`, `Netflix`, `Prime Video`) and set **Sort → Alphabetically**.
- **Compact cards:** Under **Settings → Appearance → Cards → Cards size**, set to **50%** so all favorites fit cleanly on one row.
- **Dark purple tint:** Under **Settings → Appearance → Wallpaper**, pick **Dynamic colours** and adjust **Picture adjustment → Brightness** down a few notches for a deep dark-purple gradient.
- **TV Bro browser:** Install the lightweight `geckoExcluded` APK (`3.6 MB`, compatible with Fire TV Stick 4K Max `armeabi-v7a`) from `https://github.com/truefedex/tv-bro/releases`:
  ```bash
  adb -s 192.168.1.50:5555 install -r tvbro-3.0.7-generic-geckoExcluded.apk
  ```


