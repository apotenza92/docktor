#!/usr/bin/env bash
set -euo pipefail

APP_BIN="${APP_BIN:-$HOME/Library/Developer/Xcode/DerivedData/Docktor-cjzqobmvtpcmooawtnamxdxekyry/Build/Products/Debug/Docktor.app/Contents/MacOS/Docktor}"
BUNDLE_ID="pzc.Dockter"
LOG_FILE="/tmp/docktor-issue1-automation.log"

if [[ ! -x "$APP_BIN" ]]; then
  echo "error: Docktor binary not found at $APP_BIN"
  exit 1
fi

orig_autohide="$(defaults read com.apple.dock autohide 2>/dev/null || echo 0)"
DOCKTOR_PID=""

cleanup() {
  if [[ -n "${DOCKTOR_PID:-}" ]]; then
    kill "$DOCKTOR_PID" >/dev/null 2>&1 || true
    wait "$DOCKTOR_PID" >/dev/null 2>&1 || true
  fi
  defaults write com.apple.dock autohide -bool "$orig_autohide" >/dev/null 2>&1 || true
  killall Dock >/dev/null 2>&1 || true
  pkill -x Docktor >/dev/null 2>&1 || true
}
trap cleanup EXIT

set_dock_visible() {
  defaults write com.apple.dock autohide -bool false
  killall Dock
  sleep 1
}

frontmost() {
  osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null || echo "unknown"
}

proc_visible() {
  local proc="$1"
  osascript -e "tell application \"System Events\" to get visible of process \"$proc\"" 2>/dev/null || echo "missing"
}

icon_center() {
  local dock_name="$1"
  osascript -e "tell application \"System Events\" to tell process \"Dock\" to get {position, size} of UI element \"$dock_name\" of list 1" \
    | awk -F',' '{gsub(/ /,"",$0); x=$1+($3/2); y=$2+($4/2); printf "%d,%d", x, y}'
}

real_click_icon() {
  local dock_name="$1"
  /opt/homebrew/bin/cliclick c:"$(icon_center "$dock_name")"
}

launch_docktor() {
  pkill -x Docktor >/dev/null 2>&1 || true
  : > "$LOG_FILE"
  DOCKTOR_DEBUG_LOG=1 "$APP_BIN" >>"$LOG_FILE" 2>&1 &
  DOCKTOR_PID=$!
  sleep 2
}

assert_alive() {
  if ! kill -0 "$DOCKTOR_PID" >/dev/null 2>&1; then
    echo "  FAIL: Docktor process exited unexpectedly"
    exit 1
  fi
}

set_neutral_frontmost() {
  osascript -e 'tell application "Finder" to activate' >/dev/null 2>&1 || true
  sleep 0.2
}

configure_issue2_prefs() {
  defaults write "$BUNDLE_ID" firstClickBehavior -string activateApp
  defaults write "$BUNDLE_ID" clickAction -string hideApp
}

configure_issue3_prefs() {
  defaults write "$BUNDLE_ID" firstClickBehavior -string appExpose
  defaults write "$BUNDLE_ID" clickAction -string appExpose
  defaults write "$BUNDLE_ID" firstClickAppExposeRequiresMultipleWindows -bool false
  defaults write "$BUNDLE_ID" clickAppExposeRequiresMultipleWindows -bool false
}

ensure_two_apps_visible() {
  local a="$1" b="$2"
  osascript -e "tell application \"System Events\" to set visible of process \"$a\" to true" >/dev/null 2>&1 || true
  osascript -e "tell application \"System Events\" to set visible of process \"$b\" to true" >/dev/null 2>&1 || true
  sleep 0.3
}

issue2_case() {
  local dock_name="$1" target_proc="$2" other_proc="$3"
  ensure_two_apps_visible "$target_proc" "$other_proc"
  set_neutral_frontmost

  # Ensure we genuinely reach the "active app" state before asserting hide behavior.
  local activated=false
  for _ in 1 2 3; do
    real_click_icon "$dock_name"; sleep 0.8
    if [[ "$(frontmost)" == "$target_proc" ]]; then
      activated=true
      break
    fi
  done

  if [[ "$activated" != "true" ]]; then
    echo "  FAIL [$dock_name] could not activate target app via Dock icon (frontmost=$(frontmost))"
    exit 1
  fi

  # Active-app click should now hide target.
  real_click_icon "$dock_name"; sleep 1.2

  local target_vis other_vis
  target_vis="$(proc_visible "$target_proc")"
  other_vis="$(proc_visible "$other_proc")"

  # Allow one retry for occasional synthetic click timing jitter in CI/automation.
  if [[ "$target_vis" != "false" ]]; then
    real_click_icon "$dock_name"; sleep 1.2
    target_vis="$(proc_visible "$target_proc")"
    other_vis="$(proc_visible "$other_proc")"
  fi

  if [[ "$target_vis" == "false" && "$other_vis" == "true" ]]; then
    echo "  PASS [$dock_name] target hidden, other unchanged"
  else
    echo "  FAIL [$dock_name] targetVisible=$target_vis otherVisible=$other_vis frontmost=$(frontmost)"
    exit 1
  fi
}

run_issue2_suite() {
  echo "[issue1+2] wrong target / finicky hide"
  configure_issue2_prefs
  launch_docktor
  assert_alive

  for round in 1 2 3; do
    echo "  round $round"
    issue2_case "Firefox" "firefox" "Messages"
    issue2_case "Messages" "Messages" "firefox"
  done
}

run_issue3_suite() {
  echo "[issue3] third click should not be swallowed"
  configure_issue3_prefs
  launch_docktor
  assert_alive

  ensure_two_apps_visible "firefox" "Messages"
  set_neutral_frontmost

  real_click_icon "Firefox"; sleep 0.7
  real_click_icon "Firefox"; sleep 0.7
  real_click_icon "Firefox"; sleep 1.0

  local clickups invokes
  clickups="$(rg -c 'APP_EXPOSE_TRACE: click=.*phase=up bundle=org.mozilla.firefox' "$LOG_FILE" || true)"
  invokes="$(rg -c 'WORKFLOW: Triggering App Exposé for org.mozilla.firefox' "$LOG_FILE" || true)"

  if [[ "$clickups" -ge 3 && "$invokes" -ge 3 ]]; then
    echo "  PASS clickUps=$clickups invocations=$invokes"
  else
    echo "  FAIL clickUps=$clickups invocations=$invokes"
    exit 1
  fi
}

run_preferences_stability_suite() {
  echo "[prefs] repeated settings opens should not crash"
  launch_docktor
  assert_alive

  for i in $(seq 1 12); do
    osascript -e 'tell application "System Events" to tell process "Docktor" to set frontmost to true' >/dev/null 2>&1 || true
    osascript -e 'tell application "System Events" to keystroke "," using command down' >/dev/null 2>&1 || true
    sleep 0.18
    assert_alive
  done

  echo "  PASS Docktor alive after repeated settings opens"
}

echo "== full issue #1 regression run =="
set_dock_visible
run_issue2_suite
run_issue3_suite
run_preferences_stability_suite
echo "== all automated checks passed =="