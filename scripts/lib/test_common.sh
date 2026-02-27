#!/usr/bin/env bash

: "${APP_BIN:=$HOME/Library/Developer/Xcode/DerivedData/Docktor-cjzqobmvtpcmooawtnamxdxekyry/Build/Products/Debug/Docktor.app/Contents/MacOS/Docktor}"
: "${APP_BUNDLE:=$HOME/Library/Developer/Xcode/DerivedData/Docktor-cjzqobmvtpcmooawtnamxdxekyry/Build/Products/Debug/Docktor.app}"
: "${BUNDLE_ID:=pzc.Dockter}"

APP_PID=""
TEST_ORIG_AUTOHIDE=""

require_app_bin() {
  if [[ ! -x "$APP_BIN" ]]; then
    echo "error: app binary missing at $APP_BIN"
    exit 1
  fi
}

capture_dock_state() {
  TEST_ORIG_AUTOHIDE="$(defaults read com.apple.dock autohide 2>/dev/null || echo 1)"
}

restore_dock_state() {
  if [[ -n "${TEST_ORIG_AUTOHIDE:-}" ]]; then
    defaults write com.apple.dock autohide -bool "$TEST_ORIG_AUTOHIDE" >/dev/null 2>&1 || true
    killall Dock >/dev/null 2>&1 || true
  fi
}

set_dock_autohide() {
  local enabled="$1"
  defaults write com.apple.dock autohide -bool "$enabled"
  killall Dock
  sleep 1
  ensure_dock_ready
}

ensure_dock_ready() {
  for _ in $(seq 1 30); do
    if osascript -e 'tell application "System Events" to exists process "Dock"' 2>/dev/null | grep -qi true; then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

ensure_no_docktor() {
  pkill -x Docktor >/dev/null 2>&1 || true
}

start_docktor() {
  local log_file="$1"
  shift
  ensure_no_docktor
  : > "$log_file"
  DOCKTOR_DEBUG_LOG=1 "$APP_BIN" "$@" >>"$log_file" 2>&1 &
  APP_PID=$!
  sleep 2
}

stop_docktor() {
  if [[ -n "${APP_PID:-}" ]]; then
    kill "$APP_PID" >/dev/null 2>&1 || true
    wait "$APP_PID" >/dev/null 2>&1 || true
    APP_PID=""
  fi
}

frontmost_process() {
  osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null || echo "unknown"
}

process_visible() {
  local process_name="$1"
  osascript -e "tell application \"System Events\" to get visible of process \"$process_name\"" 2>/dev/null || echo "missing"
}

set_process_visible() {
  local process_name="$1"
  local visible="$2"
  osascript -e "tell application \"System Events\" to set visible of process \"$process_name\" to $visible" >/dev/null 2>&1 || true
}

activate_finder() {
  osascript -e 'tell application "Finder" to activate' >/dev/null 2>&1 || true
  sleep 0.25
}

dock_icon_names() {
  ensure_dock_ready || { echo "error: Dock process not ready" >&2; return 1; }
  osascript -e 'tell application "System Events" to tell process "Dock" to get name of every UI element of list 1' \
    | tr ',' '\n' \
    | sed 's/^ *//; s/ *$//' \
    | awk 'NF && $0 != "missing value" && $0 != "Applications" && $0 != "Downloads" && $0 != "Bin"'
}

user_process_names() {
  osascript -e 'tell application "System Events" to get name of every process whose background only is false' \
    | tr ',' '\n' \
    | sed 's/^ *//; s/ *$//' \
    | awk 'NF'
}

process_name_for_dock_icon() {
  local icon_name="$1"
  local icon_lc
  icon_lc="$(printf '%s' "$icon_name" | tr '[:upper:]' '[:lower:]')"
  while IFS= read -r proc; do
    local proc_lc
    proc_lc="$(printf '%s' "$proc" | tr '[:upper:]' '[:lower:]')"
    if [[ "$proc_lc" == "$icon_lc" ]]; then
      printf '%s\n' "$proc"
      return 0
    fi
  done < <(user_process_names)
  return 1
}

process_bundle_id() {
  local process_name="$1"
  osascript -e "tell application \"System Events\" to get bundle identifier of process \"$process_name\"" 2>/dev/null || true
}

process_window_count() {
  local process_name="$1"
  osascript -e "tell application \"System Events\" to tell process \"$process_name\" to get count of windows" 2>/dev/null || echo 0
}

select_two_dock_test_apps() {
  local mode="${TEST_SELECTION_MODE:-random}"
  local -a candidate_icons=()
  local -a candidate_procs=()
  local -a candidate_bundles=()

  TEST_DOCK_ICON_A=""
  TEST_PROCESS_A=""
  TEST_BUNDLE_A=""
  TEST_DOCK_ICON_B=""
  TEST_PROCESS_B=""
  TEST_BUNDLE_B=""

  while IFS= read -r icon; do
    local proc
    proc="$(process_name_for_dock_icon "$icon" || true)"
    [[ -n "$proc" ]] || continue

    local proc_lc
    proc_lc="$(printf '%s' "$proc" | tr '[:upper:]' '[:lower:]')"
    [[ "$proc_lc" == "docktor" ]] && continue
    [[ "$proc_lc" == "finder" ]] && continue

    local visible
    visible="$(process_visible "$proc")"
    [[ "$visible" == "true" ]] || continue

    local windows
    windows="$(process_window_count "$proc")"
    [[ "$windows" =~ ^[0-9]+$ ]] || windows=0
    (( windows >= 1 )) || continue

    local bundle
    bundle="$(process_bundle_id "$proc")"
    [[ -n "$bundle" && "$bundle" != "missing value" ]] || continue

    candidate_icons+=("$icon")
    candidate_procs+=("$proc")
    candidate_bundles+=("$bundle")
  done < <(dock_icon_names)

  local count="${#candidate_icons[@]}"
  if (( count < 2 )); then
    echo "error: unable to discover two suitable Dock test apps dynamically"
    return 1
  fi

  if [[ -n "${TEST_SELECTION_SEED:-}" ]]; then
    RANDOM="$TEST_SELECTION_SEED"
  fi

  local idx_a=0
  local idx_b=-1

  if [[ "$mode" == "random" ]]; then
    idx_a=$((RANDOM % count))
    local proc_a_lc
    proc_a_lc="$(printf '%s' "${candidate_procs[$idx_a]}" | tr '[:upper:]' '[:lower:]')"

    local -a eligible=()
    local i
    for ((i = 0; i < count; i++)); do
      local proc_i_lc
      proc_i_lc="$(printf '%s' "${candidate_procs[$i]}" | tr '[:upper:]' '[:lower:]')"
      [[ "$proc_i_lc" == "$proc_a_lc" ]] && continue
      eligible+=("$i")
    done

    if (( ${#eligible[@]} == 0 )); then
      echo "error: discovered apps map to one process only"
      return 1
    fi

    idx_b="${eligible[$((RANDOM % ${#eligible[@]}))]}"
  else
    local proc_a_lc
    proc_a_lc="$(printf '%s' "${candidate_procs[$idx_a]}" | tr '[:upper:]' '[:lower:]')"
    local i
    for ((i = 1; i < count; i++)); do
      local proc_i_lc
      proc_i_lc="$(printf '%s' "${candidate_procs[$i]}" | tr '[:upper:]' '[:lower:]')"
      if [[ "$proc_i_lc" != "$proc_a_lc" ]]; then
        idx_b="$i"
        break
      fi
    done

    if (( idx_b < 0 )); then
      echo "error: discovered apps map to one process only"
      return 1
    fi
  fi

  TEST_DOCK_ICON_A="${candidate_icons[$idx_a]}"
  TEST_PROCESS_A="${candidate_procs[$idx_a]}"
  TEST_BUNDLE_A="${candidate_bundles[$idx_a]}"
  TEST_DOCK_ICON_B="${candidate_icons[$idx_b]}"
  TEST_PROCESS_B="${candidate_procs[$idx_b]}"
  TEST_BUNDLE_B="${candidate_bundles[$idx_b]}"

  echo "selected apps ($mode, candidates=$count): A='$TEST_DOCK_ICON_A'($TEST_PROCESS_A) B='$TEST_DOCK_ICON_B'($TEST_PROCESS_B)"
}

dock_icon_center() {
  local icon_name="$1"
  ensure_dock_ready || { echo "error: Dock process not ready" >&2; return 1; }
  osascript -e "tell application \"System Events\" to tell process \"Dock\" to get {position, size} of UI element \"$icon_name\" of list 1" \
    | awk -F',' '{gsub(/ /,""); printf "%d,%d", int($1+$3/2), int($2+$4/2)}'
}

dock_click() {
  local icon_name="$1"
  /opt/homebrew/bin/cliclick c:"$(dock_icon_center "$icon_name")"
}

write_pref_string() {
  local key="$1"
  local value="$2"
  defaults write "$BUNDLE_ID" "$key" -string "$value"
}

write_pref_bool() {
  local key="$1"
  local value="$2"
  defaults write "$BUNDLE_ID" "$key" -bool "$value"
}
