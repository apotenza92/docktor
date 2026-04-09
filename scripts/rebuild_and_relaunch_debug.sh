#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
cd "$REPO_ROOT"

source "$SCRIPT_DIR/lib/test_common.sh"

kill_matching_pids() {
  local signal="$1"
  shift

  local pids=()
  local pid
  for pid in "$@"; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    pids+=("$pid")
  done

  if [[ "${#pids[@]}" -eq 0 ]]; then
    return 0
  fi

  local unique_pids
  unique_pids="$(printf '%s\n' "${pids[@]}" | awk 'NF && !seen[$0]++')"
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    kill "-$signal" "$pid" >/dev/null 2>&1 || true
  done <<<"$unique_pids"
}

collect_dockmint_family_pids() {
  local -a bundle_ids=(
    "pzc.Dockmint.dev"
    "pzc.Dockmint"
    "pzc.Dockmint.beta"
    "pzc.Dockter"
    "pzc.Dockter.beta"
  )
  local -a app_names=(
    "Dockmint Dev"
    "Dockmint"
    "Dockmint Beta"
    "Docktor"
    "Docktor Beta"
    "Dockter"
    "DockActioner"
  )
  local -a executable_patterns=(
    "/Dockmint Dev.app/Contents/MacOS/Dockmint Dev"
    "/Dockmint.app/Contents/MacOS/Dockmint"
    "/Dockmint Beta.app/Contents/MacOS/Dockmint Beta"
    "/Docktor.app/Contents/MacOS/Docktor"
    "/Docktor Beta.app/Contents/MacOS/Docktor Beta"
    "/Dockter.app/Contents/MacOS/Dockter"
    "/DockActioner.app/Contents/MacOS/DockActioner"
  )

  local -a pids=()
  local bundle_id
  for bundle_id in "${bundle_ids[@]}"; do
    local raw_bundle_pids
    raw_bundle_pids="$(osascript -e "tell application \"System Events\" to get unix id of every process whose bundle identifier is \"$bundle_id\"" 2>/dev/null || true)"
    raw_bundle_pids="$(printf '%s' "$raw_bundle_pids" | tr ',' ' ')"
    local pid
    for pid in $raw_bundle_pids; do
      [[ "$pid" =~ ^[0-9]+$ ]] || continue
      pids+=("$pid")
    done
  done

  local app_name
  for app_name in "${app_names[@]}"; do
    local named_pids
    named_pids="$(pgrep -x "$app_name" 2>/dev/null || true)"
    if [[ -n "$named_pids" ]]; then
      while IFS= read -r pid; do
        [[ -n "$pid" ]] || continue
        pids+=("$pid")
      done <<<"$named_pids"
    fi
  done

  local pattern
  for pattern in "${executable_patterns[@]}"; do
    local matched_pids
    matched_pids="$(pgrep -f "$pattern" 2>/dev/null || true)"
    if [[ -n "$matched_pids" ]]; then
      while IFS= read -r pid; do
        [[ -n "$pid" ]] || continue
        pids+=("$pid")
      done <<<"$matched_pids"
    fi
  done

  if [[ "${#pids[@]}" -eq 0 ]]; then
    return 0
  fi

  printf '%s\n' "${pids[@]}" | awk 'NF && !seen[$0]++'
}

terminate_dockmint_family() {
  local pids
  pids="$(collect_dockmint_family_pids)"
  if [[ -z "$pids" ]]; then
    return 0
  fi

  local -a pid_array=()
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    pid_array+=("$pid")
  done <<<"$pids"

  echo "Stopping existing Dockmint-family processes: ${pid_array[*]}"
  kill_matching_pids TERM "${pid_array[@]}"

  local deadline=$((SECONDS + 5))
  local -a remaining=("${pid_array[@]}")
  while (( SECONDS < deadline )); do
    local -a still_running=()
    local pid
    for pid in "${remaining[@]}"; do
      if kill -0 "$pid" >/dev/null 2>&1; then
        still_running+=("$pid")
      fi
    done
    if [[ "${#still_running[@]}" -eq 0 ]]; then
      return 0
    fi
    remaining=("${still_running[@]}")
    sleep 0.2
  done

  echo "Force-killing stubborn Dockmint-family processes: ${remaining[*]}"
  kill_matching_pids KILL "${remaining[@]}"
  sleep 0.3
}

wait_for_no_dockmint_family() {
  local timeout_seconds="${1:-8}"
  local settle_seconds="${2:-1}"
  local deadline=$((SECONDS + timeout_seconds))

  while (( SECONDS < deadline )); do
    local remaining
    remaining="$(collect_dockmint_family_pids)"
    if [[ -z "$remaining" ]]; then
      sleep "$settle_seconds"
      remaining="$(collect_dockmint_family_pids)"
      if [[ -z "$remaining" ]]; then
        return 0
      fi
    fi
    sleep 0.2
  done

  echo "error: Dockmint-family processes were still present after waiting for shutdown" >&2
  collect_dockmint_family_pids >&2 || true
  return 1
}

running_app_pids() {
  require_app_bin

  ps -axww -o pid=,command= | awk -v app_bin="$APP_BIN" '
    index($0, app_bin) {
      pid = $1
      if (pid ~ /^[0-9]+$/) {
        print pid
      }
    }
  '
}

launch_debug_app() {
  require_app_bin

  local launch_log="${DOCKMINT_RELAUNCH_LOG:-/tmp/dockmint-relaunch.log}"
  local stability_seconds="${DOCKMINT_RELAUNCH_STABILITY_SECONDS:-10}"
  local previous_persistent_log
  : >"$launch_log"
  previous_persistent_log="$(latest_dockmint_persistent_log)"

  echo "Launching $APP_BUNDLE"
  DOCKMINT_DEBUG_LOG="${DOCKMINT_DEBUG_LOG:-1}" \
  DOCKTOR_DEBUG_LOG="${DOCKTOR_DEBUG_LOG:-1}" \
  open -na "$APP_BUNDLE" >>"$launch_log" 2>&1

  local launched_pid=""
  local pid_deadline=$((SECONDS + 8))
  while (( SECONDS < pid_deadline )); do
    launched_pid="$(running_app_pids | head -n 1 || true)"
    if [[ -n "$launched_pid" ]]; then
      break
    fi
    sleep 0.2
  done

  if [[ -z "$launched_pid" ]]; then
    echo "error: Dockmint did not appear in the process table after launch" >&2
    tail -n 80 "$launch_log" >&2 || true
    return 1
  fi

  local deadline=$((SECONDS + 8))
  local ready=false
  local active_persistent_log=""
  while (( SECONDS < deadline )); do
    active_persistent_log="$(latest_dockmint_persistent_log)"
    if [[ -n "$active_persistent_log" && "$active_persistent_log" != "$previous_persistent_log" ]] \
      && log_contains "$DOCKMINT_READY_LOG_MARKER" "$active_persistent_log"; then
      ready=true
      break
    fi
    if ! kill -0 "$launched_pid" >/dev/null 2>&1; then
      break
    fi
    sleep 0.2
  done

  if [[ "$ready" != "true" ]]; then
    echo "error: Dockmint did not reach readiness marker '$DOCKMINT_READY_LOG_MARKER'" >&2
    if [[ -n "$active_persistent_log" ]]; then
      tail -n 80 "$active_persistent_log" >&2 || true
    fi
    tail -n 80 "$launch_log" >&2 || true
    return 1
  fi

  local stability_deadline=$((SECONDS + stability_seconds))
  while (( SECONDS < stability_deadline )); do
    if ! kill -0 "$launched_pid" >/dev/null 2>&1; then
      echo "error: Dockmint exited during the post-launch stability window" >&2
      if [[ -n "$active_persistent_log" ]]; then
        tail -n 80 "$active_persistent_log" >&2 || true
      fi
      tail -n 80 "$launch_log" >&2 || true
      return 1
    fi
    if [[ -z "$(running_app_pids)" ]]; then
      echo "error: Dockmint reached startup but no running app process remained during the stability window" >&2
      if [[ -n "$active_persistent_log" ]]; then
        tail -n 80 "$active_persistent_log" >&2 || true
      fi
      tail -n 80 "$launch_log" >&2 || true
      return 1
    fi
    sleep 0.2
  done

  echo "Launched Dockmint PID $launched_pid"
  echo "Launch log: $launch_log"
}

echo "Building Dockmint Debug"
xcodebuild -project Dockmint.xcodeproj -scheme Dockmint -configuration Debug build

resolve_app_paths
terminate_dockmint_family
wait_for_no_dockmint_family
launch_debug_app
