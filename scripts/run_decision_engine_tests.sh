#!/usr/bin/env bash
set -euo pipefail

BIN="/tmp/docktor-decision-engine-tests"

swiftc Docktor/DockDecisionEngine.swift tools/decision_engine_tests.swift -o "$BIN"
"$BIN"
