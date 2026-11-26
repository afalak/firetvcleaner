#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLEANER="${REPO_DIR}/firetv_cleaner.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

MOCK_BIN="${TMP_DIR}/bin"
MOCK_LOG="${TMP_DIR}/adb_calls.log"
mkdir -p "$MOCK_BIN"

cat > "${MOCK_BIN}/adb" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${MOCK_ADB_LOG:?}"
echo "$*" >> "$LOG_FILE"

if [[ "${1:-}" == "-s" ]]; then
  shift 2
fi

cmd="${1:-}"
shift || true

case "$cmd" in
  connect)
    echo "connected to ${1:-192.168.1.50:5555}"
    ;;
  devices)
    echo "List of devices attached"
    echo "192.168.1.50:5555	device"
    ;;
  get-state)
    echo "device"
    ;;
  shell)
    sub="${1:-}"
    shift || true
    case "$sub" in
      getprop)
        case "${1:-}" in
          ro.product.model) echo "AFTKA" ;;
          ro.product.manufacturer) echo "Amazon" ;;
          ro.build.version.release) echo "11" ;;
          ro.build.display.id) echo "RS8116.2923N" ;;
          *) echo "" ;;
        esac
        ;;
      df)
        echo "Filesystem      Size  Used Avail Use% Mounted on"
        echo "/dev/block/dm-0  12G  6.1G  5.9G  51% /data"
        ;;
      pm)
        pm_sub="${1:-}"
        shift || true
        case "$pm_sub" in
          list)
            if [[ "${1:-}" == "packages" && "${2:-}" == "-d" ]]; then
              if [[ -n "${MOCK_DISABLED_FILE:-}" && -f "$MOCK_DISABLED_FILE" ]]; then
                sed 's/^/package:/' "$MOCK_DISABLED_FILE"
              else
                echo "package:com.amazon.kso.blackbird"
              fi
            elif [[ "${1:-}" == "packages" && "${2:-}" == "-e" ]]; then
              cat <<'PKGS'
package:com.amazon.tv.launcher
package:com.amazon.tv.settings.v2
package:com.amazon.avod
package:com.amazon.shoptv.client
package:com.amazon.device.logmanager
package:com.amazon.device.software.ota
package:com.amazon.tahoe
PKGS
            else
              cat <<'PKGS'
package:com.amazon.tv.launcher
package:com.amazon.tv.settings.v2
package:com.amazon.avod
package:com.amazon.kso.blackbird
package:com.amazon.shoptv.client
package:com.amazon.device.logmanager
package:com.amazon.device.software.ota
package:com.amazon.tahoe
PKGS
            fi
            ;;
          disable-user)
            pkg="${3:-}"
            if [[ "$pkg" == "com.amazon.device.software.ota" ]]; then
              echo "Error: java.lang.SecurityException: Cannot disable protected package $pkg" >&2
              exit 1
            fi
            echo "Package $pkg new state: disabled-user"
            ;;
          enable)
            echo "Package ${1:-} new state: enabled"
            ;;
          clear)
            echo "Success"
            ;;
          trim-caches)
            echo "Trimmed caches"
            ;;
        esac
        ;;
      cmd)
        if [[ "${1:-}" == "appops" ]]; then
          echo "OK"
        fi
        ;;
      appops)
        echo "OK"
        ;;
      settings)
        if [[ "${1:-}" == "get" ]]; then
          case "${3:-}" in
            window_animation_scale|transition_animation_scale|animator_duration_scale) echo "1.0" ;;
            send_action_app_error) echo "1" ;;
            *) echo "null" ;;
          esac
        fi
        ;;
      am)
        echo "Stopping ${2:-}"
        ;;
      find)
        echo "/sdcard/Download/old_installer.apk"
        ;;
    esac
    ;;
esac
EOF
chmod +x "${MOCK_BIN}/adb"

export PATH="${MOCK_BIN}:${PATH}"
export MOCK_ADB_LOG="$MOCK_LOG"

# Isolate backups into TMP_DIR by copying script into TMP_DIR/work
WORK_DIR="${TMP_DIR}/work"
mkdir -p "$WORK_DIR"
cp "$CLEANER" "${WORK_DIR}/firetv_cleaner.sh"
chmod +x "${WORK_DIR}/firetv_cleaner.sh"

# Test 1: --inspect
inspect_out="$("${WORK_DIR}/firetv_cleaner.sh" --target 192.168.1.50 --inspect)"
printf '%s\n' "$inspect_out" | grep -q "Amazon AFTKA (Android 11"
printf '%s\n' "$inspect_out" | grep -q "Known bloat/privacy/OTA packages present: 4"

# Test 2: --all --dry-run creates no backup and does not disable packages
: > "$MOCK_LOG"
dry_out="$("${WORK_DIR}/firetv_cleaner.sh" --target 192.168.1.50 --all --dry-run)"
printf '%s\n' "$dry_out" | grep -q "\[DRY-RUN\] Would disable com.amazon.kso.blackbird"
if [[ -d "${WORK_DIR}/backups" ]]; then
  echo "FAIL: dry-run created backups directory" >&2
  exit 1
fi
if grep -q "disable-user" "$MOCK_LOG"; then
  echo "FAIL: dry-run invoked pm disable-user" >&2
  exit 1
fi

# Test 3: --all -y disables bloat/privacy, falls back to appops on protected OTA, sets settings, creates backup
: > "$MOCK_LOG"
run_out="$("${WORK_DIR}/firetv_cleaner.sh" --target 192.168.1.50 --all -y)"
printf '%s\n' "$run_out" | grep -q "\[OK\]    Disabled com.amazon.kso.blackbird"
printf '%s\n' "$run_out" | grep -q "restricted background run via appops instead"
printf '%s\n' "$run_out" | grep -q "\[OK\]    Set global.window_animation_scale = 0.5"
if printf '%s\n' "$run_out" | grep -q "com.amazon.tv.launcher"; then
  echo "FAIL: core launcher should never be touched" >&2
  exit 1
fi

backup_file="$(find "${WORK_DIR}/backups" -type f -name 'backup-*.txt' | head -n 1)"
[[ -f "$backup_file" ]]
grep -q '^DISABLED_PKG|com.amazon.kso.blackbird$' "$backup_file"
grep -q '^APPOPS_PKG|com.amazon.device.software.ota$' "$backup_file"
grep -q '^SETTING|global|window_animation_scale|1.0$' "$backup_file"

# Test 4: --restore re-enables packages, resets appops, and restores settings
: > "$MOCK_LOG"
restore_out="$("${WORK_DIR}/firetv_cleaner.sh" --target 192.168.1.50 --restore "$backup_file")"
printf '%s\n' "$restore_out" | grep -q "\[OK\]    Re-enabled com.amazon.kso.blackbird"
printf '%s\n' "$restore_out" | grep -q "\[OK\]    Reset appops background permissions for com.amazon.device.software.ota"
printf '%s\n' "$restore_out" | grep -q "\[OK\]    Set global.window_animation_scale = 1.0"
grep -q "settings delete secure limit_ad_tracking" "$MOCK_LOG"

# Test 5: standalone --backup and snapshot --restore
: > "$MOCK_LOG"
standalone_out="$("${WORK_DIR}/firetv_cleaner.sh" --target 192.168.1.50 --backup)"
printf '%s\n' "$standalone_out" | grep -q "Backup saved:"
snap_file="$(printf '%s\n' "$standalone_out" | sed -n 's/.*Backup saved: //p' | head -n 1)"
[[ -f "$snap_file" ]]
grep -q '^ENABLED_PKG|com.amazon.shoptv.client$' "$snap_file"
grep -q '^WAS_DISABLED_PKG|com.amazon.kso.blackbird$' "$snap_file"

MOCK_DISABLED_FILE="${TMP_DIR}/disabled_now.txt"
printf 'com.amazon.shoptv.client\n' > "$MOCK_DISABLED_FILE"
export MOCK_DISABLED_FILE
snap_restore_out="$("${WORK_DIR}/firetv_cleaner.sh" --target 192.168.1.50 --restore "$snap_file")"
printf '%s\n' "$snap_restore_out" | grep -q "Re-enabled com.amazon.shoptv.client (from snapshot)"

echo "ALL TESTS PASSED"
