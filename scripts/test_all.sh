#!/usr/bin/env bash
# Runs the same checks as CI, locally. POSIX shell (Git Bash on Windows,
# or any Unix shell).
#
# Usage (from the repo root):
#   ./scripts/test_all.sh
set -e

echo "== dart format =="
dart format --output=none --set-exit-if-changed lib test

echo "== flutter analyze =="
flutter analyze

echo "== flutter test =="
flutter test

echo "== git diff --check =="
git diff --check

echo "All checks passed."
