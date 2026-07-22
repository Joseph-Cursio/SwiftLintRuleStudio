# Property-Based Testing Roadmap — SwiftLintRuleStudioCore

_Successor to the 2026-07 hardening backlog. The P0–P3 correctness / accessibility
/ robustness sweep is **complete** — see `git log` (search commit messages for
`P0`, `P1`, `P2`, `P3.x`, or the SHAs below) for the shipped fixes and their
regression tests. This file keeps only the **forward-looking** part: property
laws the codebase invites but that aren't written yet, plus the toolchain notes._

## Origin

`SwiftProjectLint --format pbt-seeds` over `SwiftLintRuleStudioCore` surfaced
**83 candidates** (61 pure functions + 22 extractable kernels), clustered where
refutable laws live. Densest hotspots:

- `RuleParameterParser` (11)
- YAML `Parsing` + `Serialization` (13 combined) — round-trip-shaped
- `ConfigurationHealthAnalyzer` (8)

Pipeline (per pbt-book Appendix C): `SwiftProjectLint` → `swift-infer discover`
→ `SwiftPropertyLaws` (run laws) → `SwiftIdempotency` (harden actor mutations).
Steps 1 and 2 are done; the laws below are the remaining `SwiftPropertyLaws` work.

## Shipped so far

- **7 kernel property laws** (`cf7036c`, `KernelPropertyLawTests`): `deindent`
  idempotence; `mergedWith` idempotence + completeness + existing-prefix;
  `levenshteinDistance` metric axioms; `isVersion` strict-weak-ordering.
- **3 `SwiftInferProperties` toolchain improvements** driven by this repo:
  recognize `(T?) -> T` idempotence (`628b3ae`); correct the stale
  "M3 prerequisite" generator message (`687ffd7`); ship a generator recipe for
  String-collection idempotence carriers (`4853341`). `swift-infer discover` now
  renders `mergedWith` as a Likely idempotence candidate with a runnable generator.

## Unrealized laws (the actual backlog)

| Kernel | Location | Candidate law | Notes |
|---|---|---|---|
| `layerChain` | `ResolvedConfigurationEngine.swift:56` | nested-config fold — associativity + identity | `mergedWith` idempotence is done; associativity of the fold is not |
| `generateDiff` / `diffBetween` | `YAMLConfigurationEngine.swift:220`, `ConfigVersionHistoryService.swift:151` | round-trip: `apply(diff(a,b), a) == b` | highest-value; guards the diff/apply engine |
| `parseParameters` / `parseRuleParameters` | `RuleParameterParser.swift:20`, `YAMLConfigurationEngine+Parsing.swift:261` | parse ↔ serialize round-trip | densest hotspot (11 + 13 seeds) |
| `orderedTopLevelPairs` / `orderedTopLevelKeys` | serialization | idempotence + permutation-stability of key ordering | |
| `findSafeRules` / `filterViolations` | `ImpactSimulator.swift:231`, `WorkspaceAnalyzer+Helpers.swift:150` | filter idempotence + subset invariant | |
| `mergedWith` (associativity) | `DefaultExclusions.swift:37,43` | `(a⊕b)⊕c == a⊕(b⊕c)` | idempotence shipped; associativity remains |

## Next actions

1. Stand up the two round-trip laws first (`generateDiff` apply-round-trip and
   `parseParameters` parse↔serialize) — they validate the toolchain against this
   repo *and* pin the diff/apply and parameter-parsing engines.
2. `SwiftIdempotency` pass on the actor mutations — `storeViolations`'s upsert
   (shipped in `9ea2e90`) is a natural `#assertIdempotent` target.
3. Regenerate the seed manifest with `SwiftProjectLint --format pbt-seeds` when
   Core grows; the original run's manifest was a session scratchpad artifact
   (`pbt-seeds.json`), not committed.
