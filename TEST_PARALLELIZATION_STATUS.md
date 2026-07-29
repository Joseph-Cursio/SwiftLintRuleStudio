# Test Parallelization Status

> **Resolved 2026-07-29.** The full suite runs in parallel and passes. The
> previous revision of this document (2025-12-26) concluded that full-suite
> parallel execution was broken by "Swift Testing framework limitations." That
> diagnosis was wrong — the cause was a scratch-directory race in this
> repository's own test helper, fixed in `f3adb6b`. Everything below has been
> re-verified against the tree rather than carried forward.

## Current state

| Target | Command | Result |
|---|---|---|
| Core package | `swift test --package-path SwiftLintRuleStudioCore` | ✅ 594 tests in 90 suites |
| App unit | `xcodebuild test -only-testing:SwiftLintRuleStudioTests` | ✅ 650 tests in 112 suites |
| UI tests | `xcodebuild test -only-testing:SwiftLintRuleStudioUITests` | ✅ 9 tests (XCTest) |

Swift Testing's in-process parallelism is **on** (its default) for both unit
targets. Full-suite stability was measured across 15 consecutive runs after the
fix: **15 green, 0 failures.** Before the fix the app-unit target failed roughly
**one run in three**, with a different set of tests each time.

## What was actually wrong

`TestTempDirectory.root` was a `static let` whose initializer deleted
**everything** inside the shared `$TMPDIR/SwiftLintRuleStudioTests`. Its own
docstring claimed this was safe. Both premises were false:

1. **`static let` is lazy.** The initializer runs on first *access*, not at
   process start. Under parallel execution a lot has already happened by then, so
   "leftovers from previous runs" routinely meant "directories created seconds ago
   by tests that are still running."
2. **Not every helper routed through `make(_:)`**, as the docstring asserted.
   Twenty call sites across both test targets built the path by hand.

A live directory got deleted mid-test, and the victim's next atomic write failed
with `ENOENT`. That surfaced as *"Creating a temporary file via mktemp failed"*,
reported at the test's **declaration** line and usually taking a whole suite down
at once — which is exactly the "tests fail at 0.000 seconds, looks like a runner
crash" pattern the previous revision described and misattributed.

**Why the old evidence pointed the wrong way.** Every observation in the 2025
analysis was accurate; only the inference was wrong:

| Observation (2025) | Inferred then | Actually meant |
|---|---|---|
| Individual suites pass, full suite fails | framework can't scale | only concurrency exposes the race |
| Failures at ~0.000s, not assertion failures | runner crash | throw in the *setup* helper, before any test body |
| Widespread across unrelated suites | systemic runner bug | one shared directory, many victims |

**The fix** (`f3adb6b`): each process gets its own `run-<pid>-<uuid>` root, so one
run's cleanup and another run's live directories cannot overlap; stale cleanup is
age-gated at one hour, far longer than any run (~6s); and all twenty hand-built
paths now route through `make(_:)`, making the docstring true for the first time.

## `-parallel-testing-enabled`

`scripts/ci_test.sh` passes `NO`. That predates the fix and is **no longer
required for correctness**. Measured afterwards, 4 runs each:

| Setting | Result | Wall clock |
|---|---|---|
| `YES` | 4/4 pass | 20, 20, 21, 35 s |
| `NO` | 4/4 pass | 25, 26, 26, 27 s |

Both are stable; the difference is in the noise and `YES` has the wider spread.
It stays off as the more predictable default — but it is now a free choice rather
than a workaround.

> Note when measuring this yourself: with `-parallel-testing-enabled YES`,
> xcodebuild emits the legacy per-test-case format and **not** Swift Testing's
> `Test run with N tests …` summary line. Grepping for that line reports a false
> failure. Match `** TEST SUCCEEDED **` instead.

## CI coverage gap (fixed)

`ci_test.sh` ran `xcodebuild test` on the app scheme plus `swiftlint`. Because the
Core layer is a **separate SwiftPM package**, that builds it but never runs its
tests — CI was silently skipping **594 tests**, including all 47 property-law
tests. `CLAUDE.md` has always specified three targets; the script ran two. It now
runs `swift test --package-path SwiftLintRuleStudioCore` first.

## Isolation work that did hold up

The December 2025 dependency-injection work was sound and is still load-bearing.
Verified present:

| Component | Before | After | Status |
|-----------|--------|-------|--------|
| WorkspaceManager | Shared `UserDefaults.standard` | Injected, isolated suites | ✅ |
| CacheManager | Shared cache directory | `createForTesting()`, isolated dirs | ✅ |
| DependencyContainer | Default shared instances | `createForTesting()` | ✅ |
| FileTracker | Shared cache file | `createForTesting()`, isolated files | ✅ |
| ViolationStorage | Shared database | In-memory databases | ✅ |
| Scratch directories | Shared root, purged on first use | Per-process root, age-gated cleanup | ✅ `f3adb6b` |

Only the last row was wrong; the rest is why the race was the *sole* remaining
blocker rather than one of many.

## `.serialized`

Used in exactly one place — `URLConfigFetcherTests` — and that is appropriate.
The previous revision floated applying it broadly to work around the instability.
Don't: it would have masked the race rather than fixed it, at the cost of the
whole suite's parallelism.

## Guidance

- **Run the full suite.** The advice to run suites individually is obsolete.
- Use the three commands in the table above, Core first (matching `CLAUDE.md`), or
  just `scripts/ci_test.sh`, which now covers all three plus lint.
- **Reading a failure:** `Caught error: … mktemp failed` at a test's *declaration*
  line means a directory vanished underneath it — a real bug of the class fixed
  here, not flakiness to retry. `Expectation failed:` at an *assertion* line is an
  ordinary test failure.
- Unrelated and benign: SwiftPM leaks one `$TMPDIR/TemporaryDirectory.*` per
  resolved package per graph load. It never caused the failures above.
  `scripts/prune_leaked_tempdirs.sh` clears them as housekeeping.

## History

- **2026-07-29** — Race identified and fixed (`f3adb6b`); full-suite parallel
  execution verified green 15/15; CI's missing Core-test run fixed; this document
  rewritten.
- **2025-12-26** — Dependency-injection and isolation work landed (the table
  above). Full-suite parallel execution documented as broken and attributed to
  Swift Testing. The isolation work was right; the attribution was not.

> The previous revision linked to `SHARED_STATE_ANALYSIS.md`,
> `SERIALIZED_ANALYSIS.md` and `TEST_ISOLATION_PROGRESS.md`. None of the three
> exist anywhere in the repository, so the links are dropped rather than left
> dangling.
