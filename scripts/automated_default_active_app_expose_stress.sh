#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_common.sh"

CYCLES="${1:-20}"

run_test_preflight true
init_artifact_dir docktor-e2e-default-active-app-expose-stress >/dev/null

LOG_FILE="$(artifact_path stress log)"
DOCKTOR_LOG_FILE="$(artifact_path docktor log)"
: >"$LOG_FILE"

cleanup() {
  stop_docktor
  ensure_no_docktor >/dev/null 2>&1 || true
  restore_dock_state >/dev/null 2>&1 || true
}
trap cleanup EXIT

set_dock_autohide false >>"$LOG_FILE" 2>&1 || true
select_two_dock_test_apps >>"$LOG_FILE" 2>&1

write_pref_string firstClickBehavior activateApp
write_pref_string clickAction appExpose
write_pref_bool firstClickAppExposeRequiresMultipleWindows true
write_pref_bool clickAppExposeRequiresMultipleWindows false
write_pref_bool firstLaunchCompleted true

start_docktor "$DOCKTOR_LOG_FILE" >>"$LOG_FILE" 2>&1
assert_docktor_alive "$DOCKTOR_LOG_FILE" "default active-app App Exposé stress" >>"$LOG_FILE" 2>&1

activate_finder
sleep 0.8

for iter in $(seq 1 "$CYCLES"); do
  echo "ITERATION $iter" >>"$LOG_FILE"
  before="$(grep -c "WORKFLOW: Triggering App Exposé for $TEST_BUNDLE_A" "$DOCKTOR_LOG_FILE" || true)"

  dock_click "$TEST_DOCK_ICON_A"
  sleep 1.0
  front_after_first="$(frontmost_bundle_id)"
  echo "front_after_first=$front_after_first" >>"$LOG_FILE"
  if [[ "$front_after_first" != "$TEST_BUNDLE_A" ]]; then
    capture_artifact_screenshot "iter-${iter}-activation-failure" >/dev/null
    capture_bundle_state_summary "$TEST_BUNDLE_A" "$TEST_PROCESS_A" "iter-${iter}-activation-bundle-state" >/dev/null
    echo "FAIL activation iteration=$iter artifact_dir=$TEST_ARTIFACT_DIR"
    exit 1
  fi

  dock_click "$TEST_DOCK_ICON_A"
  sleep 1.5
  after="$(grep -c "WORKFLOW: Triggering App Exposé for $TEST_BUNDLE_A" "$DOCKTOR_LOG_FILE" || true)"
  front_after_second="$(frontmost_bundle_id)"
  echo "front_after_second=$front_after_second triggers_before=$before triggers_after=$after" >>"$LOG_FILE"
  if [[ "$front_after_second" != "$TEST_BUNDLE_A" || $((after - before)) -ne 1 ]]; then
    capture_artifact_screenshot "iter-${iter}-failure" >/dev/null
    capture_dock_icon_snapshot "$TEST_DOCK_ICON_A" "iter-${iter}-icon" >/dev/null || true
    capture_bundle_state_summary "$TEST_BUNDLE_A" "$TEST_PROCESS_A" "iter-${iter}-bundle-state" >/dev/null
    echo "FAIL app_expose iteration=$iter artifact_dir=$TEST_ARTIFACT_DIR"
    exit 1
  fi

  activate_finder
  sleep 1.0
done

echo "PASS cycles=$CYCLES artifact_dir=$TEST_ARTIFACT_DIR"
