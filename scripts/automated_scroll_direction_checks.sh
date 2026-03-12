#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_common.sh"

LOG_FILE="/tmp/dockmint-scroll-direction-checks.log"

run_test_preflight false
capture_dock_state

cleanup() {
  stop_dockmint
  ensure_no_dockmint
  restore_dock_state
}
trap cleanup EXIT

wait_for_log_line_after() {
  local needle="$1"
  local start_line="$2"
  local timeout_seconds="${3:-4}"
  local deadline=$((SECONDS + timeout_seconds))

  while (( SECONDS <= deadline )); do
    if sed -n "${start_line},\$p" "$LOG_FILE" | grep -Fq "$needle"; then
      return 0
    fi
    sleep 0.2
  done

  return 1
}

post_scroll_event() {
  local x="$1"
  local y="$2"
  local delta="$3"
  local continuous="$4"

  SCROLL_X="$x" SCROLL_Y="$y" SCROLL_DELTA="$delta" SCROLL_CONTINUOUS="$continuous" \
    xcrun swift -e '
import CoreGraphics
import Foundation

let env = ProcessInfo.processInfo.environment
let x = Double(env["SCROLL_X"] ?? "0") ?? 0
let y = Double(env["SCROLL_Y"] ?? "0") ?? 0
let delta = Int32(env["SCROLL_DELTA"] ?? "0") ?? 0
let isContinuous = Int64(env["SCROLL_CONTINUOUS"] ?? "0") ?? 0

guard let source = CGEventSource(stateID: .hidSystemState),
      let event = CGEvent(scrollWheelEvent2Source: source,
                          units: isContinuous == 0 ? .line : .pixel,
                          wheelCount: 1,
                          wheel1: delta,
                          wheel2: 0,
                          wheel3: 0) else {
    fputs("failed to construct CGEvent\n", stderr)
    exit(1)
}

event.location = CGPoint(x: x, y: y)
event.setIntegerValueField(.scrollWheelEventIsContinuous, value: isContinuous)
event.post(tap: .cghidEventTap)
'
}

assert_scroll_action() {
  local direction="$1"
  local context="$2"
  local start_line="$3"

  local expected="WORKFLOW: Executing scroll ${direction} action"
  if wait_for_log_line_after "$expected" "$start_line" 5; then
    echo "  PASS $context"
  else
    echo "  FAIL $context"
    echo "  expected log after line $start_line: $expected"
    print_log_tail "$LOG_FILE" 120
    exit 1
  fi
}

echo "== scroll direction gui checks =="
set_dock_autohide false
select_two_dock_test_apps

# Keep click paths quiet so scroll routing is isolated.
write_pref_string firstClickBehavior activateApp
write_pref_string clickAction none
write_pref_string scrollUpAction hideOthers
write_pref_string scrollDownAction hideApp

start_dockmint "$LOG_FILE"
assert_dockmint_alive "$LOG_FILE" "scroll checks startup"
set_process_visible "$TEST_PROCESS_A" true
set_process_visible "$TEST_PROCESS_B" true
activate_finder

point="$(dock_icon_center "$TEST_DOCK_ICON_A")"
x="${point%,*}"
y="${point#*,}"

echo "target icon: $TEST_DOCK_ICON_A ($TEST_BUNDLE_A) at $x,$y"

echo "[case1] discrete wheel negative should route down"
start_line=$(( $(wc -l < "$LOG_FILE") + 1 ))
post_scroll_event "$x" "$y" -3 0
assert_scroll_action "down" "discrete negative -> down" "$start_line"
sleep 0.8

echo "[case2] discrete wheel positive should route up"
start_line=$(( $(wc -l < "$LOG_FILE") + 1 ))
post_scroll_event "$x" "$y" 3 0
assert_scroll_action "up" "discrete positive -> up" "$start_line"
sleep 0.8

echo "[case3] continuous negative should route down"
start_line=$(( $(wc -l < "$LOG_FILE") + 1 ))
post_scroll_event "$x" "$y" -24 1
assert_scroll_action "down" "continuous negative -> down" "$start_line"
sleep 0.8

echo "[case4] continuous positive should route up"
start_line=$(( $(wc -l < "$LOG_FILE") + 1 ))
post_scroll_event "$x" "$y" 24 1
assert_scroll_action "up" "continuous positive -> up" "$start_line"

stop_dockmint

echo "== scroll direction gui checks passed =="
