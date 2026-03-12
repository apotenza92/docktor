#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_common.sh"

DOUBLE_CLICK_GAP_MS="${DOUBLE_CLICK_GAP_MS:-70}"
SECOND_CLICK_HOLD_MS="${SECOND_CLICK_HOLD_MS:-50}"
DOCK_AUTOHIDE="${DOCK_AUTOHIDE:-false}"
POLL_ATTEMPTS="${POLL_ATTEMPTS:-36}"
POLL_SLEEP_SECONDS="${POLL_SLEEP_SECONDS:-0.15}"
GENERIC_CYCLES="${GENERIC_CYCLES:-3}"
MINIMIZE_CYCLES="${MINIMIZE_CYCLES:-2}"
QUIT_CYCLES="${QUIT_CYCLES:-1}"
ACTIONS="${ACTIONS:-bringAllToFront hideApp hideOthers singleAppMode minimizeAll quitApp}"

run_test_preflight true
init_artifact_dir dockmint-e2e-default-active-click-double-click-generic >/dev/null

LOG_FILE="$(artifact_path stress log)"
: >"$LOG_FILE"

cleanup() {
  stop_dockmint
  ensure_no_dockmint >/dev/null 2>&1 || true
  restore_dock_state >/dev/null 2>&1 || true
}
trap cleanup EXIT

gap_seconds="$(awk -v ms="$DOUBLE_CLICK_GAP_MS" 'BEGIN { printf "%.3f", ms / 1000 }')"

double_click_for_active_click() {
  local icon_name="$1"
  local center
  center="$(dock_click_target_coordinate "$icon_name")" || return 1
  click_coordinate_with_hold "$center" 60
  sleep "$gap_seconds"
  click_coordinate_with_hold "$center" "$SECOND_CLICK_HOLD_MS"
}

count_log_matches() {
  local pattern="$1"
  local file="$2"
  grep -F -c "$pattern" "$file" || true
}

action_cycles() {
  local action="$1"
  case "$action" in
    minimizeAll) printf '%s\n' "$MINIMIZE_CYCLES" ;;
    quitApp) printf '%s\n' "$QUIT_CYCLES" ;;
    *) printf '%s\n' "$GENERIC_CYCLES" ;;
  esac
}

ensure_app_running() {
  local bundle_identifier="$1"
  if process_running_by_bundle "$bundle_identifier"; then
    return 0
  fi

  open -b "$bundle_identifier" >/dev/null 2>&1 || return 1
  wait_for_process_running_by_bundle "$bundle_identifier" 8 || return 1
  sleep 0.8
}

ensure_pinned_test_apps_ready() {
  local bundle_identifier
  for bundle_identifier in "${TEST_PINNED_BUNDLE_A:-}" "${TEST_PINNED_BUNDLE_B:-}"; do
    [[ -n "$bundle_identifier" ]] || continue
    ensure_app_running "$bundle_identifier" || return 1

    local process_name
    process_name="$(process_name_for_bundle "$bundle_identifier")"
    if [[ -n "$process_name" ]]; then
      set_process_visible "$process_name" true
    fi
  done
}

restore_dynamic_test_app_candidates() {
  local icon_name
  while IFS= read -r icon_name; do
    local process_name
    process_name="$(process_name_for_dock_icon "$icon_name" || true)"
    [[ -n "$process_name" ]] || continue

    local process_name_lc
    process_name_lc="$(printf '%s' "$process_name" | tr '[:upper:]' '[:lower:]')"
    if [[ "$process_name_lc" == "dockmint" || "$process_name_lc" == "finder" ]]; then
      continue
    fi

    set_process_visible "$process_name" true
  done < <(dock_icon_names)

  sleep 0.35
}

prepare_minimize_iteration_state() {
  local attempt
  for attempt in 1 2 3; do
    set_process_visible "$TEST_PROCESS_A" true
    open -b "$TEST_BUNDLE_A" >/dev/null 2>&1 || true
    sleep 0.15
    set_process_windows_minimized "$TEST_PROCESS_A" false
    sleep 0.2

    local summary_file
    summary_file="$(capture_process_ax_window_summary "$TEST_PROCESS_A" "minimize-prep")" || return 1
    if summary_all_standard_windows_unminimized "$summary_file"; then
      return 0
    fi
  done

  return 0
}

prepare_iteration_state() {
  local action="${1:-}"
  ensure_app_running "$TEST_BUNDLE_A"
  ensure_app_running "$TEST_BUNDLE_B"
  set_process_visible "$TEST_PROCESS_A" true
  set_process_visible "$TEST_PROCESS_B" true
  if [[ "$action" == "minimizeAll" ]]; then
    prepare_minimize_iteration_state
  else
    set_process_standard_windows_minimized "$TEST_PROCESS_A" false
  fi
  sleep 0.35
}

verify_action_state() {
  local action="$1"
  local iteration_label="$2"

  case "$action" in
    bringAllToFront)
      [[ "$(frontmost_bundle_id)" == "$TEST_BUNDLE_A" ]] || return 1
      [[ "$(process_visible "$TEST_PROCESS_A")" == "true" ]] || return 1
      ;;
    hideApp)
      [[ "$(process_visible "$TEST_PROCESS_A")" == "false" ]] || return 1
      ;;
    hideOthers)
      [[ "$(frontmost_bundle_id)" == "$TEST_BUNDLE_A" ]] || return 1
      [[ "$(process_visible "$TEST_PROCESS_B")" == "false" ]] || return 1
      ;;
    singleAppMode)
      [[ "$(frontmost_bundle_id)" == "$TEST_BUNDLE_A" ]] || return 1
      [[ "$(process_visible "$TEST_PROCESS_A")" == "true" ]] || return 1
      [[ "$(process_visible "$TEST_PROCESS_B")" == "false" ]] || return 1
      ;;
    minimizeAll)
      local summary_file
      local unminimized_window_count
      local minimized_window_count
      summary_file="$(capture_process_ax_window_summary "$TEST_PROCESS_A" "$iteration_label-ax")" || return 1
      unminimized_window_count="$(awk -F= '/^window\[[0-9]+\]\.minimized=false$/ { count += 1 } END { print count + 0 }' "$summary_file")"
      minimized_window_count="$(awk -F= '/^window\[[0-9]+\]\.minimized=true$/ { count += 1 } END { print count + 0 }' "$summary_file")"
      [[ "$unminimized_window_count" =~ ^[0-9]+$ ]] || unminimized_window_count=0
      [[ "$minimized_window_count" =~ ^[0-9]+$ ]] || minimized_window_count=0
      (( unminimized_window_count == 0 && minimized_window_count > 0 ))
      ;;
    quitApp)
      ! process_running_by_bundle "$TEST_BUNDLE_A"
      ;;
    *)
      return 1
      ;;
  esac
}

before_iteration_checks() {
  local action="$1"
  local iteration_label="$2"

  case "$action" in
    minimizeAll)
      local summary_file
      local unminimized_count
      summary_file="$(capture_process_ax_window_summary "$TEST_PROCESS_A" "$iteration_label-before-ax")" || return 1
      unminimized_count="$(awk -F= '/^window\[[0-9]+\]\.minimized=false$/ { count += 1 } END { print count + 0 }' "$summary_file")"
      [[ "$unminimized_count" =~ ^[0-9]+$ ]] || unminimized_count=0
      if (( unminimized_count < 1 )); then
        echo "precondition_failed action=$action label=$iteration_label reason=no-unminimized-windows" >>"$LOG_FILE"
        return 1
      fi
      ;;
  esac
}

run_action_suite() {
  local action="$1"
  local cycles
  local dockmint_log_file

  cycles="$(action_cycles "$action")"
  dockmint_log_file="$(artifact_path "dockmint-${action}" log)"

  write_pref_string firstClickBehavior activateApp
  write_pref_string clickAction "$action"
  write_pref_bool firstLaunchCompleted true
  write_pref_bool showOnStartup false
  write_pref_bool clickAppExposeRequiresMultipleWindows false

  start_dockmint "$dockmint_log_file" >>"$LOG_FILE" 2>&1
  assert_dockmint_alive "$dockmint_log_file" "default active-click rapid double-click ($action)" >>"$LOG_FILE" 2>&1

  local iter
  for iter in $(seq 1 "$cycles"); do
    local iteration_label="${action}-iter-${iter}"
    local promote_pattern="promoting rapid second click to active-click action ${action} for ${TEST_BUNDLE_A}"
    local deferred_pattern="Deferred rapid active-click action source=activeClickRapidReclick action=${action} target=${TEST_BUNDLE_A}"
    local direct_pattern=": ${action} for ${TEST_BUNDLE_A}"
    local before_promote
    local before_deferred
    local before_direct
    local after_promote
    local after_deferred
    local after_direct
    local success=false

    prepare_iteration_state "$action" >>"$LOG_FILE" 2>&1
    before_iteration_checks "$action" "$iteration_label" >>"$LOG_FILE" 2>&1

    before_promote="$(count_log_matches "$promote_pattern" "$dockmint_log_file")"
    before_deferred="$(count_log_matches "$deferred_pattern" "$dockmint_log_file")"
    before_direct="$(count_log_matches "$direct_pattern" "$dockmint_log_file")"

    activate_finder
    double_click_for_active_click "$TEST_DOCK_ICON_A"

    local poll
    for poll in $(seq 1 "$POLL_ATTEMPTS"); do
      sleep "$POLL_SLEEP_SECONDS"
      after_promote="$(count_log_matches "$promote_pattern" "$dockmint_log_file")"
      after_deferred="$(count_log_matches "$deferred_pattern" "$dockmint_log_file")"
      after_direct="$(count_log_matches "$direct_pattern" "$dockmint_log_file")"

      if verify_action_state "$action" "$iteration_label" \
        && { (( after_direct > before_direct || after_deferred > before_deferred )) \
          || { [[ "$action" == "minimizeAll" ]] && (( after_promote >= before_promote )); }; }; then
        success=true
        break
      fi
    done

    echo "action=$action iteration=$iter promoteDelta=$((after_promote - before_promote)) directDelta=$((after_direct - before_direct)) deferredDelta=$((after_deferred - before_deferred)) frontmost=$(frontmost_bundle_id)" >>"$LOG_FILE"

    if [[ "$success" != "true" ]]; then
      capture_artifact_screenshot "${iteration_label}-failure-screen" >/dev/null
      capture_dock_icon_snapshot "$TEST_DOCK_ICON_A" "${iteration_label}-failure-icon" >/dev/null || true
      capture_bundle_state_summary "$TEST_BUNDLE_A" "$TEST_PROCESS_A" "${iteration_label}-target-state" >/dev/null
      capture_bundle_state_summary "$TEST_BUNDLE_B" "$TEST_PROCESS_B" "${iteration_label}-other-state" >/dev/null
      echo "FAIL action=$action iteration=$iter artifact_dir=$TEST_ARTIFACT_DIR"
      exit 1
    fi
  done

  stop_dockmint
}

set_dock_autohide "$DOCK_AUTOHIDE" >>"$LOG_FILE" 2>&1 || true
ensure_pinned_test_apps_ready >>"$LOG_FILE" 2>&1
if [[ -z "${TEST_PINNED_BUNDLE_A:-}" && -z "${TEST_PINNED_BUNDLE_B:-}" ]]; then
  restore_dynamic_test_app_candidates >>"$LOG_FILE" 2>&1
fi
select_two_dock_test_apps >>"$LOG_FILE" 2>&1

for action in $ACTIONS; do
  echo "RUN action=$action" >>"$LOG_FILE"
  run_action_suite "$action"
done

echo "PASS actions=$ACTIONS artifact_dir=$TEST_ARTIFACT_DIR"
