#!/usr/bin/env bash
set -euo pipefail

xcodebuild -project Docktor.xcodeproj -scheme Docktor -configuration Debug test -quiet
./scripts/run_decision_engine_tests.sh
./scripts/automated_app_expose_checks.sh
./scripts/automated_settings_shell_checks.sh
./scripts/automated_issue1_checks.sh
