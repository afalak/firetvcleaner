#!/usr/bin/env bash
#
# firetv_cleaner.sh — Safe, reversible ADB cleaner, debloater, privacy, and
# performance optimizer for Amazon Fire TV Stick 4K Max (Fire OS 7 & Fire OS 8).
#
# Usage:
#   ./firetv_cleaner.sh --inspect [--target IP[:PORT]|SERIAL]
#   ./firetv_cleaner.sh --all [--dry-run] [--target IP[:PORT]|SERIAL]
#   ./firetv_cleaner.sh --debloat --storage --privacy --ota --performance
#   ./firetv_cleaner.sh --restore backups/backup-....txt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/backups"

TARGET=""
DRY_RUN=0
DO_INSPECT=0
DO_BACKUP=0
DO_DEBLOAT=0
DO_DEBLOAT_EXTRA=0
DO_STORAGE=0
DO_PRIVACY=0
DO_OTA=0
DO_PERFORMANCE=0
RESTORE_FILE=""
ANIM_SCALE="0.5"
YES=0

# --- Package Lists -----------------------------------------------------------

# Critical packages that must NEVER be disabled or uninstalled.
PROTECTED_CORE_PACKAGES=(
  "com.amazon.tv.launcher"
  "com.amazon.tv.settings"
  "com.amazon.tv.settings.v2"
  "com.amazon.device.settings"
  "com.amazon.venezia"
  "com.amazon.imp"
  "com.amazon.tv.oobe"
  "com.amazon.firehomestarter"
  "com.amazon.tv.inputsettings"
  "com.amazon.device.controllermanager"
  "com.amazon.tv.keyguard"
  "com.amazon.avod"
  "com.android.settings"
  "com.android.systemui"
  "com.android.webview"
  "com.android.packageinstaller"
  "com.android.shell"
  "com.android.bluetooth"
)

# Safe Amazon bloat/promo/support packages (non-essential).
DEBLOAT_PACKAGES=(
  "com.amazon.kso.blackbird"          # Special Offers / lockscreen ads
  "com.amazon.shoptv.client"          # Shop on TV
  "com.amazon.shopping"               # Amazon Shopping
  "com.amazon.device.sale.service"    # Device Sale / Promo service
  "com.amazon.ags.app"                # Amazon GameCircle
  "com.amazon.tv.releasenotes"        # Release Notes
  "com.amazon.tv.csapp"               # Customer Support app
  "com.amazon.tv.support"             # Help / Support
  "com.amazon.tv.alexa.tutorials"     # Alexa Tutorials
  "com.amazon.bueller.photos"         # Amazon Photos
  "com.amazon.bueller.music"          # Amazon Music
  "com.amazon.hedwig"                 # Amazon News
  "com.amazon.diode"                  # Promotional video/shop widget
  "com.amazon.ods.kindleconnect"      # Kindle Connect
)

# Optional user-facing Amazon apps (only disabled with --debloat-extra).
DEBLOAT_EXTRA_PACKAGES=(
  "com.amazon.tahoe"                  # Amazon Freevee
  "com.amazon.imdb.tv.android.app"    # IMDb TV / Freevee legacy
  "com.amazon.cloud9"                 # Silk Browser
  "com.amazon.tv.livetv"              # Live TV guide
  "com.amazon.whisperplay.contracts"  # Whisperplay / Second Screen
  "com.amazon.whisperlink.core.android"
  "com.amazon.whisperplay.service.install"
)

# Telemetry, crash reporting, diagnostics, and ad-tracking packages.
PRIVACY_PACKAGES=(
  "com.amazon.advertisingidsettings"
  "com.amazon.device.logmanager"
  "com.amazon.device.crashmanager"
  "com.amazon.device.metrics"
  "com.amazon.client.metrics"
  "com.amazon.minerva.client"
  "com.amazon.dcp"
  "com.amazon.tcomm"
  "com.amazon.tcomm.client"
  "com.amazon.communication.discovery"
  "com.amazon.dp.logger"
  "com.amazon.tv.arc"
  "com.amazon.aria"
  "com.amazon.aca"
  "com.amazon.recess"
  "com.amazon.securitysyncclient"
  "com.amazon.sync.service"
  "com.amazon.sync.provider.ipc"
)

# Over-the-Air (OTA) OS update packages.
OTA_PACKAGES=(
  "com.amazon.device.software.ota"
  "com.amazon.device.software.ota.override"
  "com.amazon.tv.forcedotaupdater.v2"
)

# --- Helpers -----------------------------------------------------------------

log_info()  { printf '[INFO]  %s\n' "$*"; }
log_ok()    { printf '[OK]    %s\n' "$*"; }
log_warn()  { printf '[WARN]  %s\n' "$*"; }
log_err()   { printf '[ERROR] %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Fire TV Stick 4K Max Cleaner & Optimizer (ADB)

Usage:
  firetv_cleaner.sh [OPTIONS]

Target Selection:
  -t, --target <IP[:PORT]|SERIAL>  Connect to IP (default port 5555) or use ADB serial

Actions:
  --inspect        Read-only report: model, Fire OS, storage, top space users, bloat count
  --backup         Save a full restore backup (package states & settings) without changing anything
  --all            Run --debloat, --storage, --privacy, --ota, and --performance
  --debloat        Disable safe non-essential Amazon bloat/promo/support apps
  --debloat-extra  Also disable optional apps (Freevee, Silk, Live TV, Whisperplay)
  --storage        Trim app caches, clear bloat/OTA caches, list large /sdcard files
  --privacy        Disable Amazon telemetry/ad packages & opt-out metrics settings
  --ota            Attempt to disable OTA update packages & clear cached update data
  --performance    Set snappy animations (0.5x) & restrict background runs on bloat
  --anim-scale <N> Animation scale for --performance (default: 0.5; use 0 to disable)
  --restore <FILE> Restore packages and settings from a backup file

Safety & Execution:
  --dry-run        Print what would be changed without modifying the device
  -y, --yes        Skip confirmation prompt before applying changes
  -h, --help       Show this help message

Examples:
  ./firetv_cleaner.sh --target 192.168.1.50 --inspect
  ./firetv_cleaner.sh --target 192.168.1.50 --all --dry-run
  ./firetv_cleaner.sh --target 192.168.1.50 --all -y
  ./firetv_cleaner.sh --target 192.168.1.50 --restore backups/backup-....txt
EOF
}

require_adb() {
  if ! command -v adb >/dev/null 2>&1; then
    log_err "adb not found in PATH. Install Android Platform Tools (e.g., brew install android-platform-tools)."
    exit 1
  fi
}

ADB_SERIAL=""
INSTALLED_PACKAGES=""
BACKUP_FILE=""

adb_cmd() {
  if [[ -n "$ADB_SERIAL" ]]; then
    adb -s "$ADB_SERIAL" "$@"
  else
    adb "$@"
  fi
}

adb_shell() {
  adb_cmd shell "$@" </dev/null
}

connect_and_select_device() {
  if [[ -n "$TARGET" ]]; then
    # If target looks like IPv4 without port, append :5555
    if [[ "$TARGET" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      TARGET="${TARGET}:5555"
    fi
    if [[ "$TARGET" == *:* ]]; then
      log_info "Connecting to ${TARGET}..."
      local out
      out="$(adb connect "$TARGET" 2>&1 || true)"
      printf '%s\n' "$out"
    fi
    ADB_SERIAL="$TARGET"
  else
    local devices
    devices="$(adb devices | awk 'NR>1 && $2=="device" {print $1}')"
    local count
    count="$(printf '%s\n' "$devices" | awk 'NF' | wc -l | tr -d ' ')"
    if [[ "$count" -eq 0 ]]; then
      log_err "No authorized ADB devices found."
      log_err "Connect first via: adb connect <FIRE_TV_IP>:5555 (or pass --target <IP>)"
      log_err "Make sure to accept the 'Allow USB debugging' prompt on your TV screen."
      exit 1
    elif [[ "$count" -gt 1 ]]; then
      log_err "Multiple ADB devices connected. Specify one with --target:"
      printf '%s\n' "$devices" >&2
      exit 1
    fi
    ADB_SERIAL="$(printf '%s\n' "$devices" | head -n 1)"
  fi

  local state
  state="$(adb_cmd get-state 2>/dev/null | tr -d '\r' || true)"
  if [[ "$state" != "device" ]]; then
    log_err "Device '${ADB_SERIAL}' is not ready (state: '${state:-offline/unauthorized}')."
    log_err "If unauthorized, check your TV screen to allow the RSA fingerprint."
    exit 1
  fi
}

load_installed_packages() {
  INSTALLED_PACKAGES="$(adb_shell pm list packages | tr -d '\r' | sed 's/^package://')"
}

is_installed() {
  local pkg="$1"
  printf '%s\n' "$INSTALLED_PACKAGES" | grep -qxF "$pkg"
}

is_protected_core() {
  local pkg="$1"
  local core
  for core in "${PROTECTED_CORE_PACKAGES[@]}"; do
    if [[ "$pkg" == "$core" ]]; then
      return 0
    fi
  done
  return 1
}

get_setting() {
  local ns="$1"
  local key="$2"
  adb_shell settings get "$ns" "$key" 2>/dev/null | tr -d '\r' || true
}

set_setting() {
  local ns="$1"
  local key="$2"
  local val="$3"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "[DRY-RUN] settings put ${ns} ${key} ${val}"
    return 0
  fi
  if adb_shell settings put "$ns" "$key" "$val" >/dev/null 2>&1; then
    log_ok "Set ${ns}.${key} = ${val}"
  else
    log_warn "Could not set ${ns}.${key} = ${val}"
  fi
}

print_device_info() {
  local model manufacturer android_ver build_id
  model="$(adb_shell getprop ro.product.model | tr -d '\r' || true)"
  manufacturer="$(adb_shell getprop ro.product.manufacturer | tr -d '\r' || true)"
  android_ver="$(adb_shell getprop ro.build.version.release | tr -d '\r' || true)"
  build_id="$(adb_shell getprop ro.build.display.id | tr -d '\r' || true)"

  log_info "Device: ${manufacturer} ${model} (Android ${android_ver}, ${build_id})"
}

print_storage_summary() {
  log_info "Storage (/data):"
  adb_shell df -h /data 2>/dev/null | tr -d '\r' | sed 's/^/  /' || true
}

create_backup() {
  mkdir -p "$BACKUP_DIR"
  local model_slug ts
  model_slug="$(adb_shell getprop ro.product.model | tr -d '\r' | tr ' ' '_' | tr -cd '[:alnum:]_-' || echo "firetv")"
  ts="$(date '+%Y%m%d-%H%M%S')"
  BACKUP_FILE="${BACKUP_DIR}/backup-${model_slug:-firetv}-${ts}.txt"

  {
    printf '# Fire TV Cleaner Backup (%s)\n' "$ts"
    printf '# Serial: %s\n' "$ADB_SERIAL"
    printf 'SETTING|global|window_animation_scale|%s\n' "$(get_setting global window_animation_scale)"
    printf 'SETTING|global|transition_animation_scale|%s\n' "$(get_setting global transition_animation_scale)"
    printf 'SETTING|global|animator_duration_scale|%s\n' "$(get_setting global animator_duration_scale)"
    printf 'SETTING|global|send_action_app_error|%s\n' "$(get_setting global send_action_app_error)"
    printf 'SETTING|secure|limit_ad_tracking|%s\n' "$(get_setting secure limit_ad_tracking)"
    printf 'SETTING|secure|usage_metrics_enabled|%s\n' "$(get_setting secure usage_metrics_enabled)"
    printf 'SETTING|secure|usage_metrics_marketing_enabled|%s\n' "$(get_setting secure usage_metrics_marketing_enabled)"
  } > "$BACKUP_FILE"

  # Snapshot full enabled/disabled package state so --backup alone is restorable
  adb_shell pm list packages -e | tr -d '\r' | sed 's/^package:/ENABLED_PKG|/' >> "$BACKUP_FILE" || true
  adb_shell pm list packages -d | tr -d '\r' | sed 's/^package:/WAS_DISABLED_PKG|/' >> "$BACKUP_FILE" || true

  log_ok "Backup saved: ${BACKUP_FILE}"
}

record_disabled_package() {
  local pkg="$1"
  if [[ -n "$BACKUP_FILE" ]]; then
    printf 'DISABLED_PKG|%s\n' "$pkg" >> "$BACKUP_FILE"
  fi
}

record_appops_package() {
  local pkg="$1"
  if [[ -n "$BACKUP_FILE" ]]; then
    printf 'APPOPS_PKG|%s\n' "$pkg" >> "$BACKUP_FILE"
  fi
}

disable_package() {
  local pkg="$1"

  if is_protected_core "$pkg"; then
    log_warn "Refusing to disable core system package: ${pkg}"
    return 0
  fi

  if ! is_installed "$pkg"; then
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "[DRY-RUN] Would disable ${pkg}"
    return 0
  fi

  local out
  if out="$(adb_shell pm disable-user --user 0 "$pkg" 2>&1 | tr -d '\r')"; then
    if printf '%s' "$out" | grep -qiE 'new state: disabled|disabled-user'; then
      log_ok "Disabled ${pkg}"
      record_disabled_package "$pkg"
      adb_shell am force-stop "$pkg" >/dev/null 2>&1 || true
      return 0
    fi
  fi

  # Fallback: restrict background execution via appops when Fire OS protects the package
  if adb_shell cmd appops set "$pkg" RUN_IN_BACKGROUND ignore >/dev/null 2>&1 ||
     adb_shell appops set "$pkg" RUN_IN_BACKGROUND ignore >/dev/null 2>&1; then
    adb_shell cmd appops set "$pkg" RUN_ANY_IN_BACKGROUND ignore >/dev/null 2>&1 || true
    record_appops_package "$pkg"
    log_warn "OS-protected package (${pkg}) could not be disabled; restricted background run via appops instead"
  else
    log_warn "Skipped protected package ${pkg}: ${out:-permission denied}"
  fi
}

run_inspect() {
  print_device_info
  print_storage_summary

  local total_pkgs disabled_pkgs
  total_pkgs="$(printf '%s\n' "$INSTALLED_PACKAGES" | awk 'NF' | wc -l | tr -d ' ')"
  disabled_pkgs="$(adb_shell pm list packages -d | tr -d '\r' | awk 'NF' | wc -l | tr -d ' ')"
  log_info "Packages installed: ${total_pkgs} (currently disabled: ${disabled_pkgs})"

  local match_count=0
  local pkg
  for pkg in "${DEBLOAT_PACKAGES[@]}" "${PRIVACY_PACKAGES[@]}" "${OTA_PACKAGES[@]}"; do
    if is_installed "$pkg"; then
      match_count=$((match_count + 1))
    fi
  done
  log_info "Known bloat/privacy/OTA packages present: ${match_count}"

  log_info "Animation scales: window=$(get_setting global window_animation_scale), transition=$(get_setting global transition_animation_scale), animator=$(get_setting global animator_duration_scale)"

  log_info "Files > 20MB on /sdcard (if any):"
  adb_shell find /sdcard -type f -size +20M 2>/dev/null | tr -d '\r' | head -n 15 | sed 's/^/  /' || true
}

run_debloat() {
  log_info "=== Debloating non-essential Amazon bloatware ==="
  local pkg
  for pkg in "${DEBLOAT_PACKAGES[@]}"; do
    disable_package "$pkg"
  done

  if [[ "$DO_DEBLOAT_EXTRA" -eq 1 ]]; then
    log_info "=== Disabling optional Amazon apps (--debloat-extra) ==="
    for pkg in "${DEBLOAT_EXTRA_PACKAGES[@]}"; do
      disable_package "$pkg"
    done
  fi
}

run_storage() {
  log_info "=== Freeing storage space ==="
  print_storage_summary

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "[DRY-RUN] Would run: pm trim-caches 999999999999"
    log_info "[DRY-RUN] Would clear data/cache for log, crash, and release-note packages"
  else
    if adb_shell pm trim-caches 999999999999 >/dev/null 2>&1; then
      log_ok "Trimmed system/app caches (pm trim-caches)"
    else
      log_warn "pm trim-caches reported an error"
    fi

    local clear_pkgs=(
      "com.amazon.device.logmanager"
      "com.amazon.device.crashmanager"
      "com.amazon.tv.releasenotes"
      "com.amazon.kso.blackbird"
    )
    local pkg
    for pkg in "${clear_pkgs[@]}"; do
      if is_installed "$pkg"; then
        if adb_shell pm clear "$pkg" >/dev/null 2>&1; then
          log_ok "Cleared cached data for ${pkg}"
        fi
      fi
    done
  fi

  log_info "Large files (> 20MB) in /sdcard/Download (review manually if unneeded):"
  adb_shell find /sdcard/Download -type f -size +20M 2>/dev/null | tr -d '\r' | head -n 15 | sed 's/^/  /' || true

  if [[ "$DRY_RUN" -eq 0 ]]; then
    log_info "Storage after cleanup:"
    print_storage_summary
  fi
}

run_privacy() {
  log_info "=== Disabling Amazon telemetry, crash logs & ad tracking ==="
  local pkg
  for pkg in "${PRIVACY_PACKAGES[@]}"; do
    disable_package "$pkg"
  done

  set_setting secure limit_ad_tracking 1
  set_setting global send_action_app_error 0
  set_setting secure usage_metrics_enabled 0
  set_setting secure usage_metrics_marketing_enabled 0
}

run_ota() {
  log_info "=== Blocking Fire OS OTA updates (where allowed by firmware) ==="
  local pkg blocked_any=0
  for pkg in "${OTA_PACKAGES[@]}"; do
    if is_installed "$pkg"; then
      if [[ "$DRY_RUN" -eq 0 ]]; then
        adb_shell pm clear "$pkg" >/dev/null 2>&1 && log_ok "Cleared cached OTA data for ${pkg}" || true
      fi
      disable_package "$pkg"
      blocked_any=1
    fi
  done

  if [[ "$blocked_any" -eq 1 ]]; then
    log_info "Note: On newer Fire OS 7/8 builds, Amazon protects OTA packages at OS level."
    log_info "If marked OS-protected above, also block these domains on your router/Pi-hole/AdGuard:"
    log_info "  - softwareupdates.amazon.com"
    log_info "  - updates.amazon.com"
    log_info "  - d1s31zyz7dcc2d.cloudfront.net"
    log_info "  - amzdigital-a.akamaihd.net"
    log_info "  - amzdigitaldownloads.edgesuite.net"
  fi
}

run_performance() {
  log_info "=== Applying UI & background performance tweaks ==="
  set_setting global window_animation_scale "$ANIM_SCALE"
  set_setting global transition_animation_scale "$ANIM_SCALE"
  set_setting global animator_duration_scale "$ANIM_SCALE"
}

run_restore() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    log_err "Backup file not found: ${file}"
    exit 1
  fi

  local current_disabled
  current_disabled="$(adb_shell pm list packages -d | tr -d '\r' | sed 's/^package://')"

  log_info "=== Restoring from ${file} ==="
  while IFS='|' read -r kind a b c; do
    [[ -z "$kind" || "$kind" == \#* ]] && continue
    case "$kind" in
      DISABLED_PKG)
        if [[ "$DRY_RUN" -eq 1 ]]; then
          log_info "[DRY-RUN] Would re-enable ${a}"
        else
          if adb_shell pm enable "$a" >/dev/null 2>&1; then
            adb_shell cmd appops reset "$a" >/dev/null 2>&1 || true
            log_ok "Re-enabled ${a}"
          else
            log_warn "Could not re-enable ${a}"
          fi
        fi
        ;;
      ENABLED_PKG)
        if printf '%s\n' "$current_disabled" | grep -qxF "$a"; then
          if [[ "$DRY_RUN" -eq 1 ]]; then
            log_info "[DRY-RUN] Would re-enable ${a} (was enabled in snapshot)"
          else
            if adb_shell pm enable "$a" >/dev/null 2>&1; then
              adb_shell cmd appops reset "$a" >/dev/null 2>&1 || true
              log_ok "Re-enabled ${a} (from snapshot)"
            else
              log_warn "Could not re-enable ${a}"
            fi
          fi
        fi
        ;;
      APPOPS_PKG)
        if [[ "$DRY_RUN" -eq 1 ]]; then
          log_info "[DRY-RUN] Would reset appops for ${a}"
        else
          if adb_shell cmd appops reset "$a" >/dev/null 2>&1 ||
             adb_shell appops reset "$a" >/dev/null 2>&1; then
            log_ok "Reset appops background permissions for ${a}"
          else
            log_warn "Could not reset appops for ${a}"
          fi
        fi
        ;;
      SETTING)
        # a=namespace, b=key, c=value
        if [[ -n "$c" && "$c" != "null" ]]; then
          set_setting "$a" "$b" "$c"
        elif [[ "$DRY_RUN" -eq 1 ]]; then
          log_info "[DRY-RUN] settings delete ${a} ${b}"
        else
          adb_shell settings delete "$a" "$b" >/dev/null 2>&1 || true
          log_ok "Restored default (deleted) ${a}.${b}"
        fi
        ;;
    esac
  done < "$file"
}

# --- Argument Parsing --------------------------------------------------------

if [[ $# -eq 0 ]]; then
  usage
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target)
      [[ $# -lt 2 ]] && { log_err "Missing value for $1"; exit 1; }
      TARGET="$2"
      shift 2
      ;;
    --inspect)
      DO_INSPECT=1
      shift
      ;;
    --backup)
      DO_BACKUP=1
      shift
      ;;
    --all)
      DO_DEBLOAT=1
      DO_STORAGE=1
      DO_PRIVACY=1
      DO_OTA=1
      DO_PERFORMANCE=1
      shift
      ;;
    --debloat)
      DO_DEBLOAT=1
      shift
      ;;
    --debloat-extra)
      DO_DEBLOAT=1
      DO_DEBLOAT_EXTRA=1
      shift
      ;;
    --storage)
      DO_STORAGE=1
      shift
      ;;
    --privacy)
      DO_PRIVACY=1
      shift
      ;;
    --ota)
      DO_OTA=1
      shift
      ;;
    --performance)
      DO_PERFORMANCE=1
      shift
      ;;
    --anim-scale)
      [[ $# -lt 2 ]] && { log_err "Missing value for $1"; exit 1; }
      ANIM_SCALE="$2"
      shift 2
      ;;
    --restore)
      [[ $# -lt 2 ]] && { log_err "Missing value for $1"; exit 1; }
      RESTORE_FILE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -y|--yes)
      YES=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log_err "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

# --- Main --------------------------------------------------------------------

require_adb
connect_and_select_device
load_installed_packages

if [[ -n "$RESTORE_FILE" ]]; then
  run_restore "$RESTORE_FILE"
  exit 0
fi

if [[ "$DO_INSPECT" -eq 1 ]]; then
  run_inspect
fi

if [[ "$DO_DEBLOAT" -eq 0 && "$DO_STORAGE" -eq 0 && "$DO_PRIVACY" -eq 0 && "$DO_OTA" -eq 0 && "$DO_PERFORMANCE" -eq 0 ]]; then
  if [[ "$DO_BACKUP" -eq 1 ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log_info "[DRY-RUN] Would save a full restore backup in ${BACKUP_DIR}"
    else
      create_backup
      log_info "To restore from this snapshot later: $0 --target ${ADB_SERIAL} --restore ${BACKUP_FILE}"
    fi
    exit 0
  fi
  if [[ "$DO_INSPECT" -eq 1 ]]; then
    exit 0
  fi
  log_err "No action specified. Use --inspect, --backup, --all, or specific flags."
  usage
  exit 1
fi

print_device_info

if [[ "$DRY_RUN" -eq 0 && "$YES" -eq 0 ]]; then
  printf 'Apply selected changes to %s? A backup will be saved first. [y/N] ' "$ADB_SERIAL"
  read -r reply
  if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    log_info "Cancelled by user."
    exit 0
  fi
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
  create_backup
fi

[[ "$DO_DEBLOAT" -eq 1 ]] && run_debloat
[[ "$DO_STORAGE" -eq 1 ]] && run_storage
[[ "$DO_PRIVACY" -eq 1 ]] && run_privacy
[[ "$DO_OTA" -eq 1 ]] && run_ota
[[ "$DO_PERFORMANCE" -eq 1 ]] && run_performance

log_ok "Done!"
if [[ "$DRY_RUN" -eq 0 && -n "$BACKUP_FILE" ]]; then
  log_info "To undo all changes: $0 --target ${ADB_SERIAL} --restore ${BACKUP_FILE}"
fi
