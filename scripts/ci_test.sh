#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$PROJECT_ROOT"

# Housekeeping only: SwiftPM leaks one $TMPDIR/TemporaryDirectory.* per resolved
# package on every package-graph load, and they accumulate without bound. This is
# not load-bearing for correctness -- the test flakiness that used to look related
# was a scratch-directory race, fixed in TestTempDirectory. See the script header.
"$PROJECT_ROOT/scripts/prune_leaked_tempdirs.sh"

# The Core layer is a separate SwiftPM package: `xcodebuild test` on the app scheme
# builds it but never runs its tests. Without this line CI silently skipped 594
# tests, the entire property-law suite among them. CLAUDE.md has always specified
# three targets in this order; the script only ran two.
swift test --package-path SwiftLintRuleStudioCore

# -parallel-testing-enabled NO is no longer required for correctness -- it predates
# the scratch-directory race fixed in TestTempDirectory. Measured after that fix,
# both settings pass consistently and the wall-clock difference is in the noise, so
# it stays off as the more predictable default.
xcodebuild \
  -scheme SwiftLintRuleStudio \
  -configuration Debug \
  -destination "platform=macOS" \
  test \
  ENABLE_THREAD_SANITIZER=NO \
  -parallel-testing-enabled NO

swiftlint lint
