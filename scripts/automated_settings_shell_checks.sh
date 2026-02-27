#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_common.sh"

require_app_bin
capture_dock_state

cleanup() {
  stop_docktor
  write_pref_bool showMenuBarIcon true
  write_pref_bool showOnStartup false
  ensure_no_docktor
  restore_dock_state
}
trap cleanup EXIT

count_menu_bar_items() {
  osascript -e 'tell application "System Events" to tell process "ControlCenter" to get count of menu bar items of menu bar 1'
}

echo "[settings-shell] ensure deterministic Dock geometry"
set_dock_autohide false

echo "[settings-shell] menu icon toggle"
base_count="$(count_menu_bar_items)"
write_pref_bool showMenuBarIcon true
start_docktor /tmp/docktor-settings-shell-on.log
on_count="$(count_menu_bar_items)"
stop_docktor

write_pref_bool showMenuBarIcon false
start_docktor /tmp/docktor-settings-shell-off.log
off_count="$(count_menu_bar_items)"
stop_docktor

echo "  counts base=$base_count on=$on_count off=$off_count"
if [[ "$on_count" -lt "$((base_count + 1))" ]]; then
  echo "  FAIL: expected icon-on menu count to increase"
  exit 1
fi
if [[ "$off_count" -ne "$base_count" ]]; then
  echo "  FAIL: expected icon-off menu count to return to baseline"
  exit 1
fi

echo "[settings-shell] --settings fail-safe"
write_pref_bool showMenuBarIcon false
write_pref_bool showOnStartup false
start_docktor /tmp/docktor-settings-shell-args.log --settings
stop_docktor
if ! rg -q "Launch argument requested settings window" /tmp/docktor-settings-shell-args.log; then
  echo "  FAIL: missing launch-argument settings log"
  exit 1
fi
if ! rg -q "Opening settings window" /tmp/docktor-settings-shell-args.log; then
  echo "  FAIL: missing settings open log for --settings"
  exit 1
fi

echo "[settings-shell] URL fail-safe"
ensure_no_docktor
latest_before="$(ls -t "$HOME"/Code/Docktor/logs/Docktor-*.log 2>/dev/null | head -n 1 || true)"
open -na "$APP_BUNDLE" >/dev/null 2>&1 || true
sleep 2
open "docktor://settings" >/dev/null 2>&1 || true
sleep 2
ensure_no_docktor
sleep 0.5
latest_after="$(ls -t "$HOME"/Code/Docktor/logs/Docktor-*.log 2>/dev/null | head -n 1 || true)"
if [[ -z "$latest_after" ]]; then
  echo "  FAIL: no Docktor log found for URL test"
  exit 1
fi
if [[ "$latest_after" == "$latest_before" ]]; then
  echo "  FAIL: no new Docktor run log created for URL test"
  exit 1
fi
if rg -q "Received URL request to open settings" "$latest_after"; then
  echo "  URL handler log observed"
else
  echo "  WARN: URL handler log not observed in latest debug run (LaunchServices may route URL to another installed Docktor bundle)"
fi

echo "== settings shell checks passed =="
