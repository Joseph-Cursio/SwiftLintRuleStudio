#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$PROJECT_ROOT"

xcodebuild \
  -scheme SwiftLIntRuleStudio \
  -configuration Debug \
  test \
  ENABLE_THREAD_SANITIZER=NO \
  -parallel-testing-enabled NO
