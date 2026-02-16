#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE_SCRIPT="$ROOT_DIR/tools/probe_app_expose.swift"

ITERATIONS=12
TARGET_BUNDLE="com.apple.TextEdit"
STRATEGY="all"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --iterations)
      ITERATIONS="$2"
      shift 2
      ;;
    --target)
      TARGET_BUNDLE="$2"
      shift 2
      ;;
    --strategy)
      STRATEGY="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: test_app_expose.sh [--iterations N] [--target bundleId] [--strategy all|dockNotify|hotkey|fallback]" >&2
      exit 2
      ;;
  esac
done

if [[ ! -f "$PROBE_SCRIPT" ]]; then
  echo "Missing probe script: $PROBE_SCRIPT" >&2
  exit 1
fi

if [[ "$STRATEGY" == "all" ]]; then
  STRATEGIES=(dockNotify hotkey fallback)
else
  STRATEGIES=("$STRATEGY")
fi

OUT_DIR="$ROOT_DIR/tools/artifacts/app_expose-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT_DIR"
RESULTS_FILE="$OUT_DIR/results.ndjson"

echo "Running App Expose probe"
echo "target=$TARGET_BUNDLE iterations=$ITERATIONS strategies=${STRATEGIES[*]}"
echo "artifacts=$OUT_DIR"

for strategy in "${STRATEGIES[@]}"; do
  for ((i = 1; i <= ITERATIONS; i++)); do
    json="$(swift "$PROBE_SCRIPT" --strategy "$strategy" --target "$TARGET_BUNDLE")"
    echo "$json" >> "$RESULTS_FILE"

    python3 - "$json" "$strategy" "$i" "$ITERATIONS" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
strategy = sys.argv[2]
index = sys.argv[3]
total = sys.argv[4]

evidence = payload.get("evidence")
ratio = payload.get("diffChangedRatio")
delta = payload.get("dockSignatureDelta")
posted = payload.get("posted")

ratio_text = "n/a" if ratio is None else f"{ratio:.4f}"
print(f"[{strategy} {index}/{total}] posted={posted} evidence={evidence} diffRatio={ratio_text} dockDelta={delta}")
PY
  done
done

python3 - "$RESULTS_FILE" <<'PY'
import collections
import json
import statistics
import sys

path = sys.argv[1]
rows = []
with open(path, "r", encoding="utf-8") as handle:
    for line in handle:
        line = line.strip()
        if not line:
            continue
        rows.append(json.loads(line))

if not rows:
    print("No results captured")
    sys.exit(1)

by_strategy = collections.defaultdict(list)
for row in rows:
    by_strategy[row.get("strategy", "unknown")].append(row)

print("\nSummary")
for strategy, items in sorted(by_strategy.items()):
    total = len(items)
    evidence_count = sum(1 for item in items if item.get("evidence") is True)
    posted_count = sum(1 for item in items if item.get("posted") is True)
    ratios = [item["diffChangedRatio"] for item in items if isinstance(item.get("diffChangedRatio"), (int, float))]
    deltas = [item.get("dockSignatureDelta", 0) for item in items]

    pass_rate = (100.0 * evidence_count / total) if total else 0.0
    posted_rate = (100.0 * posted_count / total) if total else 0.0
    median_ratio = statistics.median(ratios) if ratios else 0.0
    max_delta = max(deltas) if deltas else 0

    print(
        f"- {strategy}: evidence={evidence_count}/{total} ({pass_rate:.1f}%), "
        f"posted={posted_count}/{total} ({posted_rate:.1f}%), "
        f"medianDiffRatio={median_ratio:.4f}, maxDockDelta={max_delta}"
    )

print(f"\nRaw results: {path}")
PY
