#!/usr/bin/env bash
set -euo pipefail

BIN="/tmp/dockmint-decision-engine-tests"

swiftc Dockmint/DockDecisionEngine.swift tools/decision_engine_tests.swift -o "$BIN"
"$BIN"
