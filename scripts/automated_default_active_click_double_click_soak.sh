#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_common.sh"

SOAK_ACTIONS="${SOAK_ACTIONS:-bringAllToFront hideApp hideOthers singleAppMode minimizeAll quitApp}"
SOAK_TIMINGS="${SOAK_TIMINGS:-70:50 50:40 110:70}"
SOAK_AUTOHIDE_STATES="${SOAK_AUTOHIDE_STATES:-false true}"
SOAK_MAX_PAIRS="${SOAK_MAX_PAIRS:-3}"
SOAK_MIXED_GENERIC_CYCLES="${SOAK_MIXED_GENERIC_CYCLES:-1}"
SOAK_MIXED_MINIMIZE_CYCLES="${SOAK_MIXED_MINIMIZE_CYCLES:-1}"
SOAK_MIXED_QUIT_CYCLES="${SOAK_MIXED_QUIT_CYCLES:-1}"
SOAK_LONG_GENERIC_CYCLES="${SOAK_LONG_GENERIC_CYCLES:-6}"
SOAK_LONG_MINIMIZE_CYCLES="${SOAK_LONG_MINIMIZE_CYCLES:-3}"
SOAK_LONG_QUIT_CYCLES="${SOAK_LONG_QUIT_CYCLES:-1}"
SOAK_PREFERRED_BUNDLES="${SOAK_PREFERRED_BUNDLES:-com.apple.iCal com.apple.mail com.apple.MobileSMS org.whispersystems.signal-desktop net.whatsapp.WhatsApp com.brave.Browser}"

run_test_preflight true
init_artifact_dir dockmint-e2e-default-active-click-double-click-soak >/dev/null

LOG_FILE="$(artifact_path soak log)"
SUMMARY_FILE="$(artifact_path summary txt)"
: >"$LOG_FILE"
: >"$SUMMARY_FILE"

cleanup() {
  restore_dock_state >/dev/null 2>&1 || true
}
trap cleanup EXIT

declare -a CANDIDATE_ICONS=()
declare -a CANDIDATE_PROCESSES=()
declare -a CANDIDATE_BUNDLES=()
declare -a PAIR_INDEXES=()
FAILURES=0

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr ' /:' '---' | tr -cd '[:alnum:]-_'
}

ensure_bundle_running() {
  local bundle_identifier="$1"
  if process_running_by_bundle "$bundle_identifier"; then
    return 0
  fi

  open -b "$bundle_identifier" >/dev/null 2>&1 || return 1
  wait_for_process_running_by_bundle "$bundle_identifier" 8 || return 1
  sleep 0.8
}

ensure_bundle_visible() {
  local bundle_identifier="$1"
  local process_name
  process_name="$(process_name_for_bundle "$bundle_identifier")"
  [[ -n "$process_name" ]] || return 1
  set_process_visible "$process_name" true
}

seed_preferred_apps() {
  local bundle_identifier
  for bundle_identifier in $SOAK_PREFERRED_BUNDLES; do
    open -b "$bundle_identifier" >/dev/null 2>&1 || true
  done
  sleep 1
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

bundle_is_preferred() {
  local bundle_identifier="$1"
  local preferred_bundle
  for preferred_bundle in $SOAK_PREFERRED_BUNDLES; do
    if [[ "$preferred_bundle" == "$bundle_identifier" ]]; then
      return 0
    fi
  done
  return 1
}

collect_candidate_records() {
  local -a seen_bundles=()
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

    local visible
    visible="$(process_visible "$process_name")"
    [[ "$visible" == "true" ]] || continue

    local window_count
    window_count="$(process_window_count "$process_name")"
    [[ "$window_count" =~ ^[0-9]+$ ]] || window_count=0
    (( window_count > 0 )) || continue

    local bundle_identifier
    bundle_identifier="$(process_bundle_id "$process_name")"
    [[ -n "$bundle_identifier" && "$bundle_identifier" != "missing value" ]] || continue

    local seen_bundle=false
    local existing_bundle
    if (( ${#seen_bundles[@]} > 0 )); then
      for existing_bundle in "${seen_bundles[@]}"; do
        if [[ "$existing_bundle" == "$bundle_identifier" ]]; then
          seen_bundle=true
          break
        fi
      done
    fi
    [[ "$seen_bundle" == "false" ]] || continue

    seen_bundles+=("$bundle_identifier")
    printf '%s|%s|%s\n' "$icon_name" "$process_name" "$bundle_identifier"
  done < <(dock_icon_names)
}

populate_candidates() {
  CANDIDATE_ICONS=()
  CANDIDATE_PROCESSES=()
  CANDIDATE_BUNDLES=()

  restore_dynamic_test_app_candidates

  local record
  local -a fallback_icons=()
  local -a fallback_processes=()
  local -a fallback_bundles=()
  while IFS= read -r record; do
    IFS='|' read -r icon_name process_name bundle_identifier <<<"$record"
    fallback_icons+=("$icon_name")
    fallback_processes+=("$process_name")
    fallback_bundles+=("$bundle_identifier")

    if bundle_is_preferred "$bundle_identifier"; then
      CANDIDATE_ICONS+=("$icon_name")
      CANDIDATE_PROCESSES+=("$process_name")
      CANDIDATE_BUNDLES+=("$bundle_identifier")
    fi
  done < <(collect_candidate_records)

  if (( ${#CANDIDATE_BUNDLES[@]} < 2 )); then
    CANDIDATE_ICONS=()
    CANDIDATE_PROCESSES=()
    CANDIDATE_BUNDLES=()

    if (( ${#fallback_bundles[@]} > 0 )); then
      CANDIDATE_ICONS=("${fallback_icons[@]}")
      CANDIDATE_PROCESSES=("${fallback_processes[@]}")
      CANDIDATE_BUNDLES=("${fallback_bundles[@]}")
    fi
  fi

  if (( ${#CANDIDATE_BUNDLES[@]} < 2 )); then
    echo "error: soak runner could not discover at least two Dock app candidates" >&2
    return 1
  fi
}

add_pair_index() {
  local index_a="$1"
  local index_b="$2"
  local pair_key="${index_a}:${index_b}"
  local existing
  if (( ${#PAIR_INDEXES[@]} > 0 )); then
    for existing in "${PAIR_INDEXES[@]}"; do
      [[ "$existing" == "$pair_key" ]] && return 0
    done
  fi
  PAIR_INDEXES+=("$pair_key")
}

build_pair_indexes() {
  PAIR_INDEXES=()

  local count="${#CANDIDATE_BUNDLES[@]}"
  add_pair_index 0 1

  if (( count >= 4 )); then
    local mid_right=$((count / 2))
    local mid_left=$((mid_right - 1))
    add_pair_index "$mid_left" "$mid_right"
  fi

  if (( count >= 3 )); then
    add_pair_index "$((count - 2))" "$((count - 1))"
  fi

  if (( ${#PAIR_INDEXES[@]} > SOAK_MAX_PAIRS )); then
    PAIR_INDEXES=("${PAIR_INDEXES[@]:0:SOAK_MAX_PAIRS}")
  fi
}

pair_label() {
  local pair_indexes="$1"
  local index_a="${pair_indexes%%:*}"
  local index_b="${pair_indexes##*:}"
  printf '%s-%s' "${CANDIDATE_ICONS[$index_a]}" "${CANDIDATE_ICONS[$index_b]}"
}

ensure_pair_ready() {
  local pair_indexes="$1"
  local index_a="${pair_indexes%%:*}"
  local index_b="${pair_indexes##*:}"
  local bundle_a="${CANDIDATE_BUNDLES[$index_a]}"
  local bundle_b="${CANDIDATE_BUNDLES[$index_b]}"
  local process_a="${CANDIDATE_PROCESSES[$index_a]}"
  local process_b="${CANDIDATE_PROCESSES[$index_b]}"

  ensure_bundle_running "$bundle_a" || return 1
  ensure_bundle_running "$bundle_b" || return 1
  set_process_visible "$process_a" true
  set_process_visible "$process_b" true
  set_process_windows_minimized "$process_a" false
  set_process_windows_minimized "$process_b" false
  sleep 0.5
}

relaunch_pair() {
  local pair_indexes="$1"
  local index_a="${pair_indexes%%:*}"
  local index_b="${pair_indexes##*:}"
  local bundle_identifier

  for bundle_identifier in "${CANDIDATE_BUNDLES[$index_a]}" "${CANDIDATE_BUNDLES[$index_b]}"; do
    osascript -e "tell application id \"$bundle_identifier\" to quit" >/dev/null 2>&1 || true
    wait_for_process_terminated_by_bundle "$bundle_identifier" 6 || true
    open -b "$bundle_identifier" >/dev/null 2>&1 || true
    wait_for_process_running_by_bundle "$bundle_identifier" 8 || true
  done

  sleep 1
  ensure_pair_ready "$pair_indexes"
}

run_case() {
  local scenario_name="$1"
  local pair_indexes="$2"
  local actions="$3"
  local generic_cycles="$4"
  local minimize_cycles="$5"
  local quit_cycles="$6"
  local gap_ms="$7"
  local hold_ms="$8"
  local dock_autohide="$9"

  local index_a="${pair_indexes%%:*}"
  local index_b="${pair_indexes##*:}"
  local bundle_a="${CANDIDATE_BUNDLES[$index_a]}"
  local bundle_b="${CANDIDATE_BUNDLES[$index_b]}"
  local scenario_slug
  scenario_slug="$(slugify "$scenario_name")"
  local scenario_log
  scenario_log="$(artifact_path "$scenario_slug" log)"

  ensure_pair_ready "$pair_indexes" || {
    printf 'result=FAIL scenario=%s bundleA=%s bundleB=%s reason=pair_setup_failed\n' \
      "$scenario_name" "$bundle_a" "$bundle_b" | tee -a "$SUMMARY_FILE"
    FAILURES=$((FAILURES + 1))
    return 0
  }

  local output
  local status
  set +e
  output="$(
    TEST_PINNED_BUNDLE_A="$bundle_a" \
    TEST_PINNED_BUNDLE_B="$bundle_b" \
    ACTIONS="$actions" \
    GENERIC_CYCLES="$generic_cycles" \
    MINIMIZE_CYCLES="$minimize_cycles" \
    QUIT_CYCLES="$quit_cycles" \
    DOUBLE_CLICK_GAP_MS="$gap_ms" \
    SECOND_CLICK_HOLD_MS="$hold_ms" \
    DOCK_AUTOHIDE="$dock_autohide" \
    "$SCRIPT_DIR/automated_default_active_click_double_click_generic.sh" 2>&1
  )"
  status=$?
  set -e

  printf '%s\n' "$output" >"$scenario_log"

  local child_artifact_dir
  child_artifact_dir="$(printf '%s\n' "$output" | sed -n 's/.*artifact_dir=//p' | tail -n 1)"
  local result="PASS"
  if (( status != 0 )); then
    result="FAIL"
    FAILURES=$((FAILURES + 1))
  fi

  printf 'result=%s scenario=%s bundleA=%s bundleB=%s actions=%s gapMs=%s holdMs=%s autohide=%s artifact=%s log=%s\n' \
    "$result" "$scenario_name" "$bundle_a" "$bundle_b" "$actions" "$gap_ms" "$hold_ms" "$dock_autohide" \
    "${child_artifact_dir:-missing}" "$scenario_log" | tee -a "$SUMMARY_FILE"
}

seed_preferred_apps >>"$LOG_FILE" 2>&1
populate_candidates >>"$LOG_FILE" 2>&1
build_pair_indexes

printf 'candidates=%s\n' "${#CANDIDATE_BUNDLES[@]}" >>"$LOG_FILE"

stable_pair="${PAIR_INDEXES[0]}"
relaunch_pair "$stable_pair" >>"$LOG_FILE" 2>&1
run_case "relaunch-recovery-$(pair_label "$stable_pair")" \
  "$stable_pair" "$SOAK_ACTIONS" \
  "$SOAK_MIXED_GENERIC_CYCLES" "$SOAK_MIXED_MINIMIZE_CYCLES" "$SOAK_MIXED_QUIT_CYCLES" \
  70 50 false

for timing in $SOAK_TIMINGS; do
  gap_ms="${timing%%:*}"
  hold_ms="${timing##*:}"
  for dock_autohide in $SOAK_AUTOHIDE_STATES; do
    run_case "timing-${gap_ms}-${hold_ms}-autohide-${dock_autohide}-$(pair_label "$stable_pair")" \
      "$stable_pair" "$SOAK_ACTIONS" \
      "$SOAK_MIXED_GENERIC_CYCLES" "$SOAK_MIXED_MINIMIZE_CYCLES" "$SOAK_MIXED_QUIT_CYCLES" \
      "$gap_ms" "$hold_ms" "$dock_autohide"
  done
done

if (( ${#PAIR_INDEXES[@]} > 0 )); then
  for pair_indexes in "${PAIR_INDEXES[@]}"; do
    run_case "pair-$(pair_label "$pair_indexes")" \
      "$pair_indexes" "$SOAK_ACTIONS" \
      "$SOAK_MIXED_GENERIC_CYCLES" "$SOAK_MIXED_MINIMIZE_CYCLES" "$SOAK_MIXED_QUIT_CYCLES" \
      70 50 false
  done
fi

run_case "long-cycle-$(pair_label "$stable_pair")" \
  "$stable_pair" "$SOAK_ACTIONS" \
  "$SOAK_LONG_GENERIC_CYCLES" "$SOAK_LONG_MINIMIZE_CYCLES" "$SOAK_LONG_QUIT_CYCLES" \
  70 50 false

if (( FAILURES > 0 )); then
  printf 'SOAK_FAIL failures=%s summary=%s artifact_dir=%s\n' "$FAILURES" "$SUMMARY_FILE" "$TEST_ARTIFACT_DIR"
  exit 1
fi

printf 'SOAK_PASS summary=%s artifact_dir=%s\n' "$SUMMARY_FILE" "$TEST_ARTIFACT_DIR"
