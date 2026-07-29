#!/usr/bin/env bash
#
# Prune `TemporaryDirectory.*` entries leaked into $TMPDIR by the Swift toolchain.
#
# This is HOUSEKEEPING, not a fix for anything. Read the next section before
# assuming it solves a test failure -- it does not.
#
# WHAT IT CLEANS
#
# SwiftPM leaks exactly one `TemporaryDirectory.XXXXXX` per resolved package every
# time it loads a package graph. Measured on Xcode 26.5 / Darwin 25.5:
#
#   xcodebuild -list             -> +14   (15 resolved packages, no build at all)
#   xcodebuild build-for-testing -> +15   (no-op build, nothing to compile)
#   swift build --build-tests    -> +6    (Core's 6 resolved dependencies)
#   swift <file>.swift           -> +1    (per invocation)
#   swiftc <file>.swift          ->  0
#
# It is fixed overhead per invocation, not per test: running 3 tests and running
# 650 tests both leak 14. Nothing in this repository creates these directories.
# They are tiny, but they accumulate without bound across hundreds of builds.
#
# WHAT IT DOES *NOT* FIX
#
# The long-running app-unit flakiness -- suites dying with "Creating a temporary
# file via mktemp failed" -- was NOT caused by these. That error carries errno 2,
# ENOENT ("parent directory is gone"), not an exhaustion code. The real cause was
# TestTempDirectory purging the shared scratch root while parallel tests were still
# using it; see the comment on `TestTempDirectory` in TestIsolationHelpers.swift.
# That is fixed at the source. If you see mktemp failures again, they are a code
# bug, not a housekeeping problem -- do not reach for this script.
#
# USAGE
#
#   scripts/prune_leaked_tempdirs.sh [age_minutes]   # default 60
#
# Only entries older than `age_minutes` are removed, so a concurrent build or test
# run holding a fresh directory is never disturbed. Pass 0 to prune all of them
# (safe only when nothing else is building).

set -euo pipefail

AGE_MINUTES="${1:-60}"
TMP="${TMPDIR:-/tmp}"

if [[ ! -d "$TMP" ]]; then
    echo "prune_leaked_tempdirs: \$TMPDIR ($TMP) is not a directory; nothing to do."
    exit 0
fi

count_leaked() {
    find "$TMP" -maxdepth 1 -name 'TemporaryDirectory.*' 2>/dev/null | wc -l | tr -d ' '
}

before="$(count_leaked)"

# -maxdepth 1 and the literal name prefix keep this scoped to the toolchain's own
# droppings. $TMPDIR is per-user on macOS, so this cannot touch another user's files.
if [[ "$AGE_MINUTES" -gt 0 ]]; then
    find "$TMP" -maxdepth 1 -name 'TemporaryDirectory.*' -mmin "+${AGE_MINUTES}" \
        -exec rm -rf {} + 2>/dev/null || true
else
    find "$TMP" -maxdepth 1 -name 'TemporaryDirectory.*' \
        -exec rm -rf {} + 2>/dev/null || true
fi

after="$(count_leaked)"
removed=$((before - after))

echo "prune_leaked_tempdirs: removed ${removed} leaked temp dir(s), ${after} remaining (was ${before})."
