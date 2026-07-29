#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$PROJECT_ROOT"

# Housekeeping only: SwiftPM leaks one $TMPDIR/TemporaryDirectory.* per resolved
# package on every package-graph load, and they accumulate without bound. This is
# not load-bearing for correctness -- the test flakiness that used to look related
# was a scratch-directory race, fixed in TestTempDirectory. See the script header.
"$PROJECT_ROOT/scripts/prune_leaked_tempdirs.sh"

xcodebuild \
  -scheme SwiftLintRuleStudio \
  -configuration Debug \
  -destination "platform=macOS" \
  test \
  ENABLE_THREAD_SANITIZER=NO \
  -parallel-testing-enabled NO

swiftlint lint
